import Foundation
import AppKit
import AVFoundation
import SwiftData
import os

/// IPC bridge that lets the `voiceink` CLI ask the running app to transcribe an audio
/// file and return the resulting text. Uses `DistributedNotificationCenter` because
/// VoiceInk is not sandboxed and the CLI is a separate process.
///
/// Protocol:
///   * Request:  name `com.prakashjoshipax.VoiceInk.cli.transcribe.request`
///               userInfo: `id` (String), `audioPath` (String)
///   * Safe request: name `com.prakashjoshipax.VoiceInk.cli.transcribe.ephemeral-local.v1`
///               The distinct versioned name is fail-closed with older VoiceInk builds.
///   * Response: name `com.prakashjoshipax.VoiceInk.cli.transcribe.response.<id>`
///               userInfo on success: `ok=true`, `text`, `enhancedText?`, `modelName`
///               userInfo on failure: `ok=false`, `error`
///   * Ready ping: name `com.prakashjoshipax.VoiceInk.cli.ready` posted on bridge start
///                 so a waiting CLI can stop polling.
@MainActor
final class CLIBridgeService {
    static let shared = CLIBridgeService()

    static let requestName = Notification.Name("com.prakashjoshipax.VoiceInk.cli.transcribe.request")
    static let ephemeralLocalRequestName = Notification.Name(
        "com.prakashjoshipax.VoiceInk.cli.transcribe.ephemeral-local.v1")
    static let readyName = Notification.Name("com.prakashjoshipax.VoiceInk.cli.ready")
    static let responseNamePrefix = "com.prakashjoshipax.VoiceInk.cli.transcribe.response."

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "CLIBridgeService")
    private weak var engine: VoiceInkEngine?
    private var modelContext: ModelContext?
    private var ephemeralRegistry: TranscriptionServiceRegistry?
    private var ephemeralInFlight = false
    private var inFlight: Set<String> = []
    private var observers: [NSObjectProtocol] = []

    private init() {}

    func start(engine: VoiceInkEngine, modelContext: ModelContext) {
        guard observers.isEmpty else { return }
        self.engine = engine
        self.modelContext = modelContext
        self.ephemeralRegistry = TranscriptionServiceRegistry(
            modelProvider: engine.whisperModelManager,
            modelsDirectory: engine.whisperModelManager.modelsDirectory,
            modelContext: modelContext,
            reuseLoadedWhisperContext: false
        )

        let center = DistributedNotificationCenter.default()
        for name in [Self.requestName, Self.ephemeralLocalRequestName] {
            observers.append(center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] note in
                self?.handleRequest(note)
            })
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
        let ephemeralLocal = notification.name == Self.ephemeralLocalRequestName
        if ephemeralLocal && ephemeralInFlight {
            sendResponse(id: id, result: .failure(.busy))
            inFlight.remove(id)
            return
        }
        if ephemeralLocal {
            ephemeralInFlight = true
        }

        Task { @MainActor in
            let result = await self.transcribe(audioURL: url, ephemeralLocal: ephemeralLocal)
            self.sendResponse(id: id, result: result)
            self.inFlight.remove(id)
            if ephemeralLocal {
                self.ephemeralInFlight = false
            }
        }
    }

    private func transcribe(audioURL: URL, ephemeralLocal: Bool) async -> Result<Payload, BridgeError> {
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
        if ephemeralLocal && model.provider != .whisper && model.provider != .fluidAudio {
            return .failure(.localModelRequired(model.displayName))
        }
        if ephemeralLocal {
            do {
                let values = try audioURL.resourceValues(forKeys: [.fileSizeKey])
                if let size = values.fileSize, size > 64 * 1024 * 1024 {
                    return .failure(.inputTooLarge)
                }
                let duration = try await AVURLAsset(url: audioURL).load(.duration).seconds
                if !duration.isFinite || duration > 15 * 60 {
                    return .failure(.durationTooLong)
                }
            } catch {
                return .failure(.transcriptionFailed(
                    "Could not inspect media: \(error.localizedDescription)"))
            }
        }

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

        do {
            if ephemeralLocal {
                let mode = runtimeConfiguration.mode
                let languages = TranscriptionLanguageSupport.validLanguagesOrFallback(
                    mode.selectedLanguages,
                    for: model,
                    realtimeEnabled: mode.isRealtimeTranscriptionEnabled
                )
                let language = TranscriptionLanguageSupport.singleLanguage(
                    from: languages,
                    for: model,
                    realtimeEnabled: mode.isRealtimeTranscriptionEnabled
                )
                let context = TranscriptionRequestContext(
                    languages: languages,
                    language: language,
                    prompt: model.provider == .whisper ? WhisperPrompt.combinedPrompt(for: languages) : nil
                )
                guard let ephemeralRegistry else {
                    return .failure(.engineNotReady)
                }
                var text = try await ephemeralRegistry.transcribe(
                    audioURL: tempWAV,
                    model: model,
                    context: context
                )
                text = TranscriptionOutputFilter.filter(text)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let formatting = ModeRuntimeResolver.transcriptionFormattingConfiguration(mode: mode)
                if formatting.isTextFormattingEnabled {
                    text = ParagraphFormatter.format(text)
                }
                text = WordReplacementService.shared.applyReplacements(to: text, using: modelContext)
                return .success(Payload(
                    text: text,
                    enhancedText: nil,
                    modelName: model.displayName
                ))
            }

            let service = AudioTranscriptionService(
                modelContext: modelContext,
                serviceRegistry: engine.serviceRegistry,
                enhancementService: engine.enhancementService
            )
            let transcription = try await service.retranscribeAudio(
                from: tempWAV, using: model, mode: runtimeConfiguration.mode).transcription
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
        case busy
        case localModelRequired(String)
        case inputTooLarge
        case durationTooLong
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
            case .busy:
                return "Another ephemeral transcription is already running"
            case .localModelRequired(let modelName):
                return "Ephemeral transcription requires a local Whisper or Parakeet model; selected: \(modelName)"
            case .inputTooLarge:
                return "Ephemeral transcription input exceeds 64 MiB"
            case .durationTooLong:
                return "Ephemeral transcription is limited to 15 minutes"
            case .transcriptionFailed(let message):
                return "Transcription failed: \(message)"
            }
        }
    }
}
