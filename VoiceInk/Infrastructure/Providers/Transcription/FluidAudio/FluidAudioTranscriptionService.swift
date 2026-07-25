import Foundation
import os.log

#if canImport(FluidAudio)
import FluidAudio

class FluidAudioTranscriptionService: TranscriptionService {
    private var asrManager: AsrManager?
    private var unifiedAsrManager: UnifiedAsrManager?
    private var nemotronAsrManager: StreamingNemotronMultilingualAsrManager?
    private var activeVersion: AsrModelVersion?
    private var activeNemotronModelName: String?
    private var cachedModels: AsrModels?
    private var loadingTask: (version: AsrModelVersion, task: Task<AsrModels, Error>)?
    private let audioConverter = AudioConverter()
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "FluidAudioTranscriptionService")

    private func version(for model: any TranscriptionModel) -> AsrModelVersion {
        FluidAudioModelManager.asrVersion(for: model.name)
    }

    static func languageHint(from selectedLanguages: [String], model: any TranscriptionModel) -> Language? {
        guard model.provider == .fluidAudio else {
            return nil
        }
        return FluidAudioModelManager.languageHint(from: selectedLanguages, for: model.name)
    }

    private func cleanupLoadedManagers() async {
        await unifiedAsrManager?.cleanup()
        await nemotronAsrManager?.cleanup()
        await asrManager?.cleanup()

        unifiedAsrManager = nil
        nemotronAsrManager = nil
        asrManager = nil
        activeVersion = nil
        activeNemotronModelName = nil
    }

    private func ensureModelsLoaded(for version: AsrModelVersion) async throws {
        if asrManager != nil, activeVersion == version {
            return
        }

        // Clean up existing manager but preserve cachedModels for reuse
        await cleanupLoadedManagers()

        let models = try await getOrLoadModels(for: version)

        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.asrManager = manager
        self.activeVersion = version
    }

    private func ensureUnifiedModelsLoaded() async throws {
        if unifiedAsrManager != nil {
            return
        }

        await cleanupLoadedManagers()

        let manager = UnifiedAsrManager(encoderPrecision: FluidAudioModelManager.parakeetUnifiedPrecision)
        try await manager.loadModels(from: FluidAudioModelManager.parakeetUnifiedCacheDirectory())
        self.unifiedAsrManager = manager
    }

    private func ensureNemotronModelsLoaded(named modelName: String) async throws {
        if nemotronAsrManager != nil, activeNemotronModelName == modelName {
            return
        }

        await cleanupLoadedManagers()

        let manager = StreamingNemotronMultilingualAsrManager()
        try await manager.loadModels(from: FluidAudioModelManager.nemotronCacheDirectory(for: modelName))
        self.nemotronAsrManager = manager
        self.activeNemotronModelName = modelName
    }

    // Returns cached models or loads from disk; deduplicates concurrent loads
    func getOrLoadModels(for version: AsrModelVersion) async throws -> AsrModels {
        if let cached = cachedModels, cached.version == version {
            return cached
        }

        // Deduplicate concurrent loads for the same version
        if let (existingVersion, existingTask) = loadingTask, existingVersion == version {
            return try await existingTask.value
        }

        let task = Task {
            let cacheDirectory = AsrModels.defaultCacheDirectory(for: version)
            guard AsrModels.modelsExist(at: cacheDirectory, version: version) else {
                throw AsrModelsError.loadingFailed(
                    "Parakeet model files are incomplete. Download the model from AI Models."
                )
            }
            return try await AsrModels.load(
                from: cacheDirectory,
                configuration: nil,
                version: version,
                encoderPrecision: .int8
            )
        }
        loadingTask = (version, task)

        do {
            let models = try await task.value
            self.cachedModels = models
            // Only clear if we're still the current loading task
            if loadingTask?.version == version {
                self.loadingTask = nil
            }
            return models
        } catch {
            // Only clear if we're still the current loading task
            if loadingTask?.version == version {
                self.loadingTask = nil
            }
            throw error
        }
    }

    func loadModel(for model: FluidAudioModel) async throws {
        if FluidAudioModelManager.isNemotronModel(named: model.name) {
            // Realtime Nemotron uses a dedicated streaming manager; batch loads lazily in transcribe().
            return
        }

        if FluidAudioModelManager.isParakeetUnifiedModel(named: model.name) {
            try await ensureUnifiedModelsLoaded()
            return
        }

        try await ensureModelsLoaded(for: version(for: model))
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext) async throws
        -> String
    {
        if FluidAudioModelManager.isParakeetUnifiedModel(named: model.name) {
            try await ensureUnifiedModelsLoaded()
            guard let unifiedAsrManager else {
                throw ASRError.notInitialized
            }

            let speechAudio = try loadAudioSamples(from: audioURL)
            let text = try await unifiedAsrManager.transcribe(speechAudio)
            return text
        }

        if FluidAudioModelManager.isNemotronModel(named: model.name) {
            try await ensureNemotronModelsLoaded(named: model.name)
            guard let nemotronAsrManager else {
                throw ASRError.notInitialized
            }

            // Nemotron's streaming manager takes one locale, so a multi-language pick degrades
            // to auto-detect.
            let compatibleLanguage = TranscriptionLanguageSupport.singleLanguage(
                from: context.languages,
                for: model
            )
            let languageHint = FluidAudioModelManager.nemotronLanguageHint(from: compatibleLanguage)
            await nemotronAsrManager.setLanguage(languageHint)
            await nemotronAsrManager.reset()

            var speechAudio = try loadAudioSamples(from: audioURL)
            let trailingSilenceSamples = 16_000
            let maxSingleChunkSamples = 240_000
            if speechAudio.count + trailingSilenceSamples <= maxSingleChunkSamples {
                speechAudio += [Float](repeating: 0, count: trailingSilenceSamples)
            }

            _ = try await nemotronAsrManager.process(samples: speechAudio)
            let text = try await nemotronAsrManager.finish()
            return text
        }

        let targetVersion = version(for: model)
        try await ensureModelsLoaded(for: targetVersion)

        guard let asrManager = asrManager else {
            throw ASRError.notInitialized
        }

        // nil when the selection spans more than one script — see languageHint(from:for:).
        let languageHint = Self.languageHint(
            from: context.languages,
            model: model
        )
        var decoderState = TdtDecoderState.make(decoderLayers: await asrManager.decoderLayerCount)
        let result = try await asrManager.transcribe(
            audioURL,
            decoderState: &decoderState,
            language: languageHint
        )

        return result.text
    }

    private func loadAudioSamples(from audioURL: URL) throws -> [Float] {
        try audioConverter.resampleAudioFile(audioURL)
    }

    // MARK: - Wake word

    /// Loads the model ahead of time so the first speech segment is not lost
    /// while the Neural Engine warms up.
    func prepareForWakeWord(modelName: String) async throws {
        try await ensureModelsLoaded(for: FluidAudioModelManager.asrVersion(for: modelName))
    }

    /// One-shot transcription of a short in-memory segment.
    ///
    /// The wake word detector hands over independent snippets of speech, so the
    /// decoder state is fresh every call - unlike the streaming managers, which
    /// carry state between chunks of one continuous utterance.
    func transcribeForWakeWord(_ samples: [Float], modelName: String, languages: [String]) async throws
        -> String
    {
        guard !FluidAudioModelManager.isParakeetUnifiedModel(named: modelName),
            !FluidAudioModelManager.isNemotronModel(named: modelName)
        else {
            throw WakeWordRecognizerError.unsupportedModel(modelName)
        }

        try await ensureModelsLoaded(for: FluidAudioModelManager.asrVersion(for: modelName))

        guard let asrManager = asrManager else {
            throw ASRError.notInitialized
        }

        let languageHint = FluidAudioModelManager.languageHint(from: languages, for: modelName)
        var decoderState = TdtDecoderState.make(decoderLayers: await asrManager.decoderLayerCount)
        let result = try await asrManager.transcribe(
            samples,
            decoderState: &decoderState,
            language: languageHint
        )

        return result.text
    }

    // Releases ASR resources but preserves cached models for reuse
    func cleanup() async {
        await cleanupLoadedManagers()
    }

}

#else

// Intel (x86_64) stub. FluidAudio/Parakeet relies on the Apple Neural Engine and the Float16
// type, neither of which is available on Intel Macs, so the dependency is not linked there. This
// stub keeps the type available so the rest of the app compiles; any attempt to use a Parakeet
// model on Intel throws a clear error. Use a Whisper model instead.
enum FluidAudioUnavailableError: LocalizedError {
    case notSupportedOnIntel
    var errorDescription: String? {
        "Parakeet (FluidAudio) is not supported on Intel Macs. Use a Whisper model instead."
    }
}

class FluidAudioTranscriptionService: TranscriptionService {
    func loadModel(for model: FluidAudioModel) async throws {
        throw FluidAudioUnavailableError.notSupportedOnIntel
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext) async throws
        -> String
    {
        throw FluidAudioUnavailableError.notSupportedOnIntel
    }

    func prepareForWakeWord(modelName: String) async throws {
        throw FluidAudioUnavailableError.notSupportedOnIntel
    }

    func transcribeForWakeWord(_ samples: [Float], modelName: String, languages: [String]) async throws
        -> String
    {
        throw FluidAudioUnavailableError.notSupportedOnIntel
    }

    func cleanup() async {}
}

#endif
