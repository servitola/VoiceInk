import Foundation
import AppKit
import SwiftData
import os

/// IPC bridge that lets the `voiceink` CLI ask the running app to transcribe an audio
/// file and return the resulting text. Uses `DistributedNotificationCenter` because
/// VoiceInk is not sandboxed and the CLI is a separate process.
///
/// Protocol:
///   * Request:  name `com.prakashjoshipax.VoiceInk.cli.transcribe.request`
///               userInfo: `id` (String), `audioPath` (String)
///   * Response: name `com.prakashjoshipax.VoiceInk.cli.transcribe.response.<id>`
///               userInfo on success: `ok=true`, `text`, `enhancedText?`, `modelName`
///               userInfo on failure: `ok=false`, `error`
///   * Ready ping: name `com.prakashjoshipax.VoiceInk.cli.ready` posted on bridge start
///                 so a waiting CLI can stop polling.
@MainActor
final class CLIBridgeService {
    static let shared = CLIBridgeService()

    static let requestName = Notification.Name("com.prakashjoshipax.VoiceInk.cli.transcribe.request")
    static let readyName = Notification.Name("com.prakashjoshipax.VoiceInk.cli.ready")
    static let responseNamePrefix = "com.prakashjoshipax.VoiceInk.cli.transcribe.response."

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "CLIBridgeService")
    private weak var engine: VoiceInkEngine?
    private var modelContext: ModelContext?
    private var inFlight: Set<String> = []
    private var observer: NSObjectProtocol?

    private init() {}

    func start(engine: VoiceInkEngine, modelContext: ModelContext) {
        guard observer == nil else { return }
        self.engine = engine
        self.modelContext = modelContext

        let center = DistributedNotificationCenter.default()
        observer = center.addObserver(
            forName: Self.requestName,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleRequest(note)
        }

        center.postNotificationName(Self.readyName, object: nil, userInfo: nil, deliverImmediately: true)
        logger.notice("CLI bridge started")
    }

    private func handleRequest(_ notification: Notification) {
        guard let info = notification.userInfo as? [String: Any],
              let id = info["id"] as? String,
              let audioPath = info["audioPath"] as? String else {
            logger.error("CLI bridge: malformed request")
            return
        }

        if inFlight.contains(id) { return }
        inFlight.insert(id)

        let resolved = (audioPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: resolved)

        Task { @MainActor in
            let result = await self.transcribe(audioURL: url)
            self.sendResponse(id: id, result: result)
            self.inFlight.remove(id)
        }
    }

    private func transcribe(audioURL: URL) async -> Result<Payload, BridgeError> {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            return .failure(.fileNotFound(audioURL.path))
        }
        guard SupportedMedia.isSupported(url: audioURL) else {
            return .failure(.unsupportedFormat(audioURL.pathExtension))
        }
        guard let engine = engine, let modelContext = modelContext else {
            return .failure(.engineNotReady)
        }
        // Resolve the transcription model exactly like live dictation does: use the
        // current mode's selected model, falling back to the first usable model.
        // This keeps the CLI in sync with the model chosen for dictation instead of
        // relying on the separate `currentTranscriptionModel` global, which becomes
        // nil after the previously-selected model is deleted.
        guard let runtimeConfiguration = ModeRuntimeResolver.transcriptionConfiguration(
            transcriptionModelManager: engine.transcriptionModelManager
        ) else {
            return .failure(.noModelSelected)
        }
        let model = runtimeConfiguration.model

        // The downstream WhisperTranscriptionService.readAudioSamples reads the
        // file as raw 16-bit PCM after a 44-byte WAV header; it does not decode
        // compressed formats. Preprocess every input through AudioProcessor so
        // we hand whisper a proper 16 kHz mono PCM WAV regardless of source
        // codec (ogg/opus, mp3, m4a, mp4, etc).
        let processor = AudioProcessor()
        let tempWAV = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("voiceink-cli-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tempWAV) }

        do {
            let samples = try await processor.processAudioToSamples(audioURL)
            try processor.saveSamplesAsWav(samples: samples, to: tempWAV)
        } catch {
            return .failure(.transcriptionFailed("Audio decode failed: \(error.localizedDescription)"))
        }

        let service = AudioTranscriptionService(
            modelContext: modelContext,
            serviceRegistry: engine.serviceRegistry,
            enhancementService: engine.enhancementService
        )

        do {
            let transcription = try await service.retranscribeAudio(
                from: tempWAV, using: model, mode: runtimeConfiguration.mode)
            return .success(Payload(
                text: transcription.text,
                enhancedText: transcription.enhancedText,
                modelName: transcription.transcriptionModelName ?? model.displayName
            ))
        } catch {
            return .failure(.transcriptionFailed(error.localizedDescription))
        }
    }

    private func sendResponse(id: String, result: Result<Payload, BridgeError>) {
        var userInfo: [String: Any] = [:]
        switch result {
        case .success(let payload):
            userInfo["ok"] = true
            userInfo["text"] = payload.text
            if let enhanced = payload.enhancedText, !enhanced.isEmpty {
                userInfo["enhancedText"] = enhanced
            }
            userInfo["modelName"] = payload.modelName
        case .failure(let error):
            userInfo["ok"] = false
            userInfo["error"] = error.errorDescription ?? "Unknown error"
        }

        let name = Notification.Name(Self.responseNamePrefix + id)
        DistributedNotificationCenter.default().postNotificationName(
            name,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }

    private struct Payload {
        let text: String
        let enhancedText: String?
        let modelName: String
    }

    enum BridgeError: LocalizedError {
        case fileNotFound(String)
        case unsupportedFormat(String)
        case engineNotReady
        case noModelSelected
        case transcriptionFailed(String)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let path):
                return "Audio file not found: \(path)"
            case .unsupportedFormat(let ext):
                return "Unsupported audio format: .\(ext)"
            case .engineNotReady:
                return "VoiceInk engine is not ready yet"
            case .noModelSelected:
                return "No transcription model is selected in VoiceInk"
            case .transcriptionFailed(let message):
                return "Transcription failed: \(message)"
            }
        }
    }
}
