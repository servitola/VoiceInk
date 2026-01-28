import Foundation
import AVFoundation
import Speech
import os

/// Service for continuous wake word detection using Apple Speech Recognition
@MainActor
class WakeWordListeningService: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published var isListening = false
    @Published var lastRecognizedText = ""
    @Published var permissionStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    // MARK: - Private Properties

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "WakeWordListeningService")

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?

    private var wakeWord: String = "лошадка"
    private var language: String = "ru-RU"
    private var onWakeWordDetected: (() -> Void)?

    // Circular buffer to keep last N seconds of recognized text
    private var recognizedTextBuffer: [String] = []
    private let bufferSize = 10

    // MARK: - Initialization

    override init() {
        super.init()
        loadSettings()
        checkPermissions()
    }

    // MARK: - Settings Management

    private func loadSettings() {
        wakeWord = UserDefaults.standard.string(forKey: "wakeWord") ?? "лошадка"
        language = UserDefaults.standard.string(forKey: "wakeWordLanguage") ?? "ru-RU"

        logger.notice("Wake word settings loaded: '\(self.wakeWord)', language: \(self.language)")
    }

    func configureWakeWord(_ word: String, language: String = "ru-RU") {
        self.wakeWord = word.lowercased()
        self.language = language

        UserDefaults.standard.set(word, forKey: "wakeWord")
        UserDefaults.standard.set(language, forKey: "wakeWordLanguage")

        logger.notice("Wake word configured: '\(word)', language: \(language)")

        // Restart listening if already active
        if isListening {
            Task {
                await stopListening()
                try? await Task.sleep(nanoseconds: 500_000_000)
                await startListening()
            }
        }
    }

    func setWakeWordDetectedCallback(_ callback: @escaping () -> Void) {
        self.onWakeWordDetected = callback
    }

    // MARK: - Permission Management

    private func checkPermissions() {
        permissionStatus = SFSpeechRecognizer.authorizationStatus()
        logger.notice("Speech recognition permission status: \(String(describing: self.permissionStatus.rawValue))")
    }

    func requestPermissions() async -> Bool {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    self.permissionStatus = status
                    self.logger.notice("Speech recognition permission: \(String(describing: status.rawValue))")
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }

    // MARK: - Listening Control

    func startListening() async {
        guard !isListening else {
            logger.notice("Already listening, ignoring start request")
            return
        }

        if permissionStatus != .authorized {
            logger.error("Cannot start listening: Speech recognition not authorized")
            let authorized = await requestPermissions()
            if !authorized {
                logger.error("Permission request denied")
                return
            }
        }

        do {
            try await startRecognition()
            isListening = true
            logger.notice("✅ Wake word listening started for '\(self.wakeWord)'")
        } catch {
            logger.error("Failed to start wake word listening: \(error.localizedDescription)")
        }
    }

    func stopListening() async {
        guard isListening else { return }

        recognitionTask?.cancel()
        recognitionTask = nil

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognizedTextBuffer.removeAll()

        isListening = false
        logger.notice("Wake word listening stopped")
    }

    // MARK: - Speech Recognition

    private func startRecognition() async throws {
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Create speech recognizer for the configured language
        let locale = Locale(identifier: language)
        speechRecognizer = SFSpeechRecognizer(locale: locale)

        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            logger.error("Speech recognizer not available for language: \(self.language)")
            throw WakeWordError.recognizerNotAvailable
        }

        // Create audio engine
        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Create recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false // Allow cloud for better accuracy
        self.recognitionRequest = request

        // Install tap on audio input
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        // Start audio engine
        audioEngine.prepare()
        try audioEngine.start()

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if let error = error {
                    self.logger.error("Recognition error: \(error.localizedDescription)")

                    // Restart on error
                    Task {
                        await self.stopListening()
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        if UserDefaults.standard.bool(forKey: "isWakeWordEnabled") {
                            await self.startListening()
                        }
                    }
                    return
                }

                if let result = result {
                    self.handleRecognitionResult(result)
                }
            }
        }
    }

    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult) {
        let transcription = result.bestTranscription.formattedString.lowercased()
        lastRecognizedText = transcription

        // Add to buffer
        recognizedTextBuffer.append(transcription)
        if recognizedTextBuffer.count > bufferSize {
            recognizedTextBuffer.removeFirst()
        }

        // Check for wake word in the most recent transcriptions
        let recentText = recognizedTextBuffer.suffix(3).joined(separator: " ")

        if detectWakeWord(in: recentText) {
            logger.notice("🎯 Wake word detected: '\(self.wakeWord)'")
            handleWakeWordDetection()
        }
    }

    private func detectWakeWord(in text: String) -> Bool {
        let normalizedText = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let normalizedWakeWord = wakeWord.lowercased()

        // Direct match
        if normalizedText.contains(normalizedWakeWord) {
            return true
        }

        // Fuzzy match for potential recognition errors
        let words = normalizedText.components(separatedBy: .whitespaces)
        for word in words {
            if levenshteinDistance(word, normalizedWakeWord) <= 2 {
                return true
            }
        }

        return false
    }

    // Simple Levenshtein distance for fuzzy matching
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let s1Count = s1Array.count
        let s2Count = s2Array.count

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: s2Count + 1), count: s1Count + 1)

        for i in 0...s1Count {
            matrix[i][0] = i
        }
        for j in 0...s2Count {
            matrix[0][j] = j
        }

        for i in 1...s1Count {
            for j in 1...s2Count {
                let cost = s1Array[i-1] == s2Array[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,
                    matrix[i][j-1] + 1,
                    matrix[i-1][j-1] + cost
                )
            }
        }

        return matrix[s1Count][s2Count]
    }

    private func handleWakeWordDetection() {
        // Clear buffer to prevent immediate re-triggering
        recognizedTextBuffer.removeAll()

        // Stop listening temporarily
        Task {
            await stopListening()

            // Trigger callback
            onWakeWordDetected?()
        }
    }

    // MARK: - Cleanup

    deinit {
        Task {
            await stopListening()
        }
    }
}

// MARK: - Error Types

enum WakeWordError: LocalizedError {
    case recognizerNotAvailable
    case audioEngineFailure
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .recognizerNotAvailable:
            return "Speech recognizer is not available for the selected language"
        case .audioEngineFailure:
            return "Failed to start audio engine"
        case .permissionDenied:
            return "Speech recognition permission denied"
        }
    }
}
