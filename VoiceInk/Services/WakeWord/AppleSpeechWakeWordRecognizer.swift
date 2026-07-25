import AVFoundation
import Foundation
import Speech
import os

/// Wake word recognition through Apple's speech recognizer.
///
/// Runs on device only when macOS Dictation is enabled - otherwise the request
/// fails with `kLSRErrorDomain 201` and the only way to get any recognition at
/// all is Apple's servers, which for an always-on listener means streaming the
/// room continuously. `usesServerRecognition` reports which one is in effect.
final class AppleSpeechWakeWordRecognizer: WakeWordRecognizer {

    private let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink", category: "AppleSpeechWakeWordRecognizer")

    private let language: String
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    /// Read from the realtime audio thread, written on start/stop. The unfair
    /// lock has priority inheritance, so the audio thread cannot be blocked by a
    /// lower-priority writer.
    private let requestLock = OSAllocatedUnfairLock<SFSpeechAudioBufferRecognitionRequest?>(
        initialState: nil)

    private(set) var usesServerRecognition = false
    let displayName = String(localized: "Apple Speech")
    /// A recognition request is capped at roughly a minute, so the session has
    /// to be cycled by the owner.
    let needsRollingRestart = true

    /// Set once on-device recognition proves unusable for this language, so the
    /// next attempt goes through the server rather than failing forever.
    var onDeviceDisabled = false

    init(language: String) {
        self.language = language
    }

    func start(
        inputFormat: AVAudioFormat,
        onTranscript: @escaping (String) -> Void,
        onFailure: @escaping (Error) -> Void
    ) async throws {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language))
        guard let recognizer, recognizer.isAvailable else {
            logger.error("Speech recognizer not available for language: \(self.language, privacy: .public)")
            throw WakeWordError.recognizerNotAvailable
        }
        speechRecognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // supportsOnDeviceRecognition can report true while the language asset
        // is missing, so the owner flips onDeviceDisabled after repeated
        // immediate failures.
        let useOnDevice = recognizer.supportsOnDeviceRecognition && !onDeviceDisabled
        request.requiresOnDeviceRecognition = useOnDevice
        usesServerRecognition = !useOnDevice
        requestLock.withLock { $0 = request }

        recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            if let error {
                onFailure(error)
                return
            }
            if let result {
                onTranscript(result.bestTranscription.formattedString)
            }
        }

        logger.notice("Apple speech wake word session started, onDevice: \(useOnDevice, privacy: .public)")
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        let request = requestLock.withLock { $0 }
        request?.append(buffer)
    }

    func stop() async {
        recognitionTask?.cancel()
        recognitionTask = nil

        let request = requestLock.withLock { current -> SFSpeechAudioBufferRecognitionRequest? in
            let existing = current
            current = nil
            return existing
        }
        request?.endAudio()

        speechRecognizer = nil
    }
}
