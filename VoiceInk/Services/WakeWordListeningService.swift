import AVFoundation
import CoreAudio
import Foundation
import Speech
import os

/// Service for continuous wake word detection using Apple Speech Recognition
@MainActor
class WakeWordListeningService: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published var isListening = false {
        didSet { if oldValue != isListening { onStateChanged?() } }
    }
    @Published var lastRecognizedText = ""
    @Published var permissionStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    /// True when the explicitly configured microphone is not currently connected.
    /// Listening stays paused in that case instead of falling back to another device.
    @Published var microphoneUnavailable = false {
        didSet { if oldValue != microphoneUnavailable { onStateChanged?() } }
    }
    /// Name of the device the audio engine is actually bound to, for UI feedback.
    @Published var boundDeviceName: String? {
        didSet { if oldValue != boundDeviceName { onStateChanged?() } }
    }

    /// Called whenever the observable state above changes, including from the
    /// service's own rolling restarts and device-change handling.
    var onStateChanged: (() -> Void)?

    // MARK: - Private Properties

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "WakeWordListeningService")

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var boundDeviceID: AudioDeviceID?
    private var deviceChangeObserver: NSObjectProtocol?

    /// Invalidation token. Every start/stop bumps it, and every asynchronous
    /// continuation (recognition callback, scheduled restart, engine spin-up)
    /// checks it before touching shared state, so overlapping restarts cannot
    /// stomp each other's engine and leave the microphone held open.
    private var generation = 0
    private var pendingRestartTask: Task<Void, Never>?
    private var restartBackoffSeconds: UInt64 = 1

    private var wakeWord: String = "лошадка"
    private var language: String = "ru-RU"
    /// UID of the microphone to listen on. Empty = follow the app's recording device selection.
    private var microphoneUID: String = ""
    /// Stable identity of that microphone — USB UIDs embed the port location ID
    /// and change between ports, the model UID does not.
    private var microphoneModelUID: String?
    private var onWakeWordDetected: (() -> Void)?

    /// Set by the engine. The detector must not take the microphone while a
    /// recording or transcription is in flight.
    var canStartListening: (() -> Bool)?

    // Circular buffer to keep last N seconds of recognized text
    private var recognizedTextBuffer: [String] = []
    private let bufferSize = 10

    /// A single speech recognition request is capped at roughly a minute, so an
    /// always-on listener has to cycle proactively rather than wait for the error.
    private let rollingRestartRange: ClosedRange<UInt64> = 47...53
    private let maxRestartBackoffSeconds: UInt64 = 30

    // MARK: - Initialization

    override init() {
        super.init()
        loadSettings()
        checkPermissions()
        setupDeviceChangeObserver()
    }

    // MARK: - Settings Management

    private func loadSettings() {
        wakeWord = UserDefaults.standard.string(forKey: "wakeWord") ?? "лошадка"
        language = UserDefaults.standard.string(forKey: "wakeWordLanguage") ?? "ru-RU"
        microphoneUID = UserDefaults.standard.wakeWordMicrophoneUID ?? ""
        microphoneModelUID = UserDefaults.standard.wakeWordMicrophoneModelUID

        logger.notice("Wake word settings loaded: '\(self.wakeWord)', language: \(self.language)")
    }

    /// Select the microphone the wake word detector listens on.
    /// Pass an empty UID to follow the app's recording device selection.
    func configureMicrophone(uid: String, modelUID: String?) {
        self.microphoneUID = uid
        self.microphoneModelUID = uid.isEmpty ? nil : modelUID

        UserDefaults.standard.wakeWordMicrophoneUID = uid
        UserDefaults.standard.wakeWordMicrophoneModelUID = self.microphoneModelUID

        logger.notice("Wake word microphone configured: '\(uid.isEmpty ? "app default" : uid)'")

        // Restart listening if already active so the new device takes effect
        if isListening {
            Task {
                await stopListening()
                await startListening()
            }
        }
    }

    /// Resolves the input device the detector should listen on, together with its name.
    ///
    /// When a device was chosen explicitly this is strict: if that device is not
    /// connected it returns nil rather than picking another one, because falling
    /// back would grab the built-in or headset microphone the user deliberately
    /// excluded. Only "Same as Recording" follows the app's own device selection.
    private func resolveInputDevice() -> (id: AudioDeviceID, name: String)? {
        let manager = AudioDeviceManager.shared

        guard microphoneUID.isEmpty else {
            guard let device = manager.findAvailableDevice(uid: microphoneUID, modelUID: microphoneModelUID) else {
                return nil
            }

            // The device may have come back on another USB port under a new UID.
            // Re-pin the saved identity so the settings picker keeps resolving it.
            if device.uid != microphoneUID {
                logger.notice("Wake word microphone reappeared under a new UID - re-pinning")
                microphoneUID = device.uid
                UserDefaults.standard.wakeWordMicrophoneUID = device.uid
            }
            if microphoneModelUID == nil {
                microphoneModelUID = manager.getDeviceModelUID(deviceID: device.id)
                UserDefaults.standard.wakeWordMicrophoneModelUID = microphoneModelUID
            }

            return (device.id, device.name)
        }

        let current = manager.getCurrentDevice()
        guard current != 0 else { return nil }
        let name = manager.availableDevices.first(where: { $0.id == current })?.name ?? "Unknown"
        return (current, name)
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

        generation &+= 1
        let myGeneration = generation

        do {
            try await startRecognition(generation: myGeneration)

            // A newer start/stop superseded this one while the engine was spinning up.
            guard myGeneration == generation else { return }

            isListening = true
            restartBackoffSeconds = 1
            logger.notice(
                "✅ Wake word listening started for '\(self.wakeWord)' on '\(self.boundDeviceName ?? "unknown", privacy: .public)'"
            )
        } catch {
            logger.error("Failed to start wake word listening: \(error.localizedDescription)")
        }
    }

    /// Tears everything down. Deliberately unconditional - a listening flag left
    /// stale by a losing race must never be able to skip the teardown and leave
    /// the audio engine running with the microphone open.
    func stopListening() async {
        generation &+= 1

        pendingRestartTask?.cancel()
        pendingRestartTask = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognizedTextBuffer.removeAll()
        boundDeviceID = nil
        boundDeviceName = nil

        if isListening {
            isListening = false
            logger.notice("Wake word listening stopped")
        }
    }

    // MARK: - Speech Recognition

    private func startRecognition(generation myGeneration: Int) async throws {
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

        guard let device = resolveInputDevice() else {
            microphoneUnavailable = !microphoneUID.isEmpty
            boundDeviceName = nil
            logger.error("Wake word microphone is not connected - staying idle instead of falling back")
            throw WakeWordError.microphoneUnavailable
        }

        // Create audio engine
        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode

        // Bind to the selected microphone instead of the system default one.
        // Must happen before querying the format / installing the tap.
        // On macOS the input and output nodes share one AUHAL, so this also moves
        // system output if anything is ever connected to audioEngine.outputNode -
        // keep this engine input-only.
        do {
            try inputNode.auAudioUnit.setDeviceID(device.id)
        } catch {
            logger.error("Failed to set wake word input device: \(error.localizedDescription)")
            microphoneUnavailable = true
            boundDeviceName = nil
            throw WakeWordError.audioEngineFailure
        }

        // Read the format only after the device is bound - it describes that device.
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.channelCount > 0, recordingFormat.sampleRate > 0 else {
            // installTap raises an uncatchable exception on a degenerate format.
            logger.error("Invalid input format for wake word device \(device.id, privacy: .public)")
            throw WakeWordError.audioEngineFailure
        }

        // Create recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Server-side recognition caps a single request at about a minute and is
        // rate limited, which an always-on listener hits constantly - and it would
        // stream the room to Apple around the clock. Stay on device when possible.
        request.requiresOnDeviceRecognition = speechRecognizer.supportsOnDeviceRecognition

        // The tap runs on a realtime audio thread, so it captures the request
        // directly and never touches actor-isolated state.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        // Start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw error
        }

        guard myGeneration == generation else {
            inputNode.removeTap(onBus: 0)
            audioEngine.stop()
            request.endAudio()
            return
        }

        self.audioEngine = audioEngine
        self.recognitionRequest = request
        self.boundDeviceID = device.id
        self.boundDeviceName = device.name
        self.microphoneUnavailable = false

        logger.notice(
            "Wake word listening on device \(device.id, privacy: .public) '\(device.name, privacy: .public)', onDevice recognition: \(speechRecognizer.supportsOnDeviceRecognition, privacy: .public)"
        )

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self = self, myGeneration == self.generation else { return }

                if let error = error {
                    self.logger.error("Recognition error: \(error.localizedDescription)")

                    let delay = self.restartBackoffSeconds
                    self.restartBackoffSeconds = min(delay * 2, self.maxRestartBackoffSeconds)
                    self.scheduleRestart(after: delay, reason: "recognition error")
                    return
                }

                if let result = result {
                    self.handleRecognitionResult(result)
                }
            }
        }

        scheduleRestart(after: UInt64.random(in: rollingRestartRange), reason: "rolling restart")
    }

    /// Schedules a stop/start cycle. Replaces any previously scheduled one, so a
    /// recognition error supersedes the pending rolling restart rather than
    /// racing it.
    private func scheduleRestart(after seconds: UInt64, reason: String) {
        let myGeneration = generation

        pendingRestartTask?.cancel()
        pendingRestartTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)

            guard !Task.isCancelled, let self = self else { return }
            guard myGeneration == self.generation else { return }
            guard UserDefaults.standard.bool(forKey: "isWakeWordEnabled") else { return }
            guard self.canStartListening?() ?? true else { return }

            // Clear first - stopListening() cancels this field, which is this task.
            self.pendingRestartTask = nil
            self.logger.notice("Restarting wake word listening (\(reason, privacy: .public))")

            await self.stopListening()
            await self.startListening()
        }
    }

    // MARK: - Device Changes

    private func setupDeviceChangeObserver() {
        deviceChangeObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("AudioDeviceChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handleDeviceListChanged()
            }
        }
    }

    /// Rebinds the engine when the configured microphone is unplugged, comes back,
    /// or reappears on a different port under a new AudioDeviceID.
    private func handleDeviceListChanged() async {
        guard UserDefaults.standard.bool(forKey: "isWakeWordEnabled") else { return }
        guard canStartListening?() ?? true else { return }

        guard let resolved = resolveInputDevice() else {
            if isListening {
                logger.notice("Wake word microphone disappeared - pausing until it returns")
                await stopListening()
            }
            microphoneUnavailable = !microphoneUID.isEmpty
            return
        }

        guard isListening else {
            microphoneUnavailable = false
            await startListening()
            return
        }

        if resolved.id != boundDeviceID {
            logger.notice("Wake word microphone moved to device \(resolved.id, privacy: .public) - rebinding")
            await stopListening()
            await startListening()
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

        if Self.detectWakeWord(wakeWord, in: recentText) {
            logger.notice("🎯 Wake word detected: '\(self.wakeWord)'")
            handleWakeWordDetection()
        }
    }

    nonisolated static func detectWakeWord(_ wakeWord: String, in text: String) -> Bool {
        let normalizedText = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let normalizedWakeWord = wakeWord.lowercased()
        guard !normalizedWakeWord.isEmpty else { return false }

        // Direct match
        if normalizedText.contains(normalizedWakeWord) {
            return true
        }

        // Fuzzy match for potential recognition errors
        let words = normalizedText.components(separatedBy: .whitespaces)
        for word in words where !word.isEmpty {
            if levenshteinDistance(word, normalizedWakeWord) <= 2 {
                return true
            }
        }

        return false
    }

    // Simple Levenshtein distance for fuzzy matching
    nonisolated static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let s1Count = s1Array.count
        let s2Count = s2Array.count

        guard s1Count > 0 else { return s2Count }
        guard s2Count > 0 else { return s1Count }

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
        pendingRestartTask?.cancel()
        recognitionTask?.cancel()
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        recognitionRequest?.endAudio()
        if let observer = deviceChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

// MARK: - Error Types

enum WakeWordError: LocalizedError {
    case recognizerNotAvailable
    case audioEngineFailure
    case permissionDenied
    case microphoneUnavailable

    var errorDescription: String? {
        switch self {
        case .recognizerNotAvailable:
            return "Speech recognizer is not available for the selected language"
        case .audioEngineFailure:
            return "Failed to start audio engine"
        case .permissionDenied:
            return "Speech recognition permission denied"
        case .microphoneUnavailable:
            return "The selected wake word microphone is not connected"
        }
    }
}
