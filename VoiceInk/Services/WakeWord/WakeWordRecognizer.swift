import AVFoundation
import Foundation

/// A backend that turns live microphone audio into text for wake word spotting.
///
/// `WakeWordListeningService` owns the audio engine, the device binding and the
/// restart lifecycle; a recognizer only has to answer "what was said". Buffers
/// arrive on a realtime audio thread, so `append` must not block.
protocol WakeWordRecognizer: AnyObject {
    /// Human-readable name for the settings UI.
    var displayName: String { get }
    /// True when audio leaves the machine. Wake word listening is always-on, so
    /// this is worth surfacing rather than hiding.
    var usesServerRecognition: Bool { get }
    /// True when the session has a time limit and has to be cycled periodically.
    var needsRollingRestart: Bool { get }

    func start(
        inputFormat: AVAudioFormat,
        onTranscript: @escaping (String) -> Void,
        onFailure: @escaping (Error) -> Void
    ) async throws

    /// Called from the audio tap. Must return quickly and must not allocate
    /// anything expensive or take locks that the main thread can hold.
    func append(_ buffer: AVAudioPCMBuffer)

    func stop() async
}

/// How the wake word detector recognises speech.
enum WakeWordEngineKind: String, CaseIterable, Identifiable {
    /// A transcription model that runs on this Mac. Nothing is sent anywhere.
    case localModel
    /// Apple's speech recognition. Runs on device only when macOS Dictation is
    /// enabled, otherwise it falls back to Apple's servers.
    case appleSpeech

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .localModel:
            return String(localized: "Local model (offline)")
        case .appleSpeech:
            return String(localized: "Apple Speech")
        }
    }
}

enum WakeWordRecognizerError: LocalizedError {
    case noLocalModelSelected
    case modelNotDownloaded(String)
    case unsupportedModel(String)
    case audioConversionFailed

    var errorDescription: String? {
        switch self {
        case .noLocalModelSelected:
            return String(localized: "No local model is selected for wake word detection")
        case .modelNotDownloaded(let name):
            return String(format: String(localized: "The model %@ is not downloaded"), name)
        case .unsupportedModel(let name):
            return String(
                format: String(localized: "%@ cannot be used for wake word detection yet"), name)
        case .audioConversionFailed:
            return String(localized: "Could not convert microphone audio for the wake word model")
        }
    }
}
