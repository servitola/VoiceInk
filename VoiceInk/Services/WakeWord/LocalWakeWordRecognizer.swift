import Foundation
import os

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

    var errorDescription: String? {
        switch self {
        case .noLocalModelSelected:
            return String(localized: "No local model is selected for wake word detection")
        case .modelNotDownloaded(let name):
            return String(format: String(localized: "The model %@ is not downloaded"), name)
        case .unsupportedModel(let name):
            return String(
                format: String(localized: "%@ cannot be used for wake word detection yet"), name)
        }
    }
}

#if canImport(FluidAudio)
import FluidAudio

/// Wake word recognition that never leaves the machine.
///
/// A transcription model is far too expensive to run on every second of silence,
/// so Silero VAD acts as the gate: it is tiny, runs on the Neural Engine, and
/// only when it reports speech does the recognizer collect a segment and hand it
/// to the model. Long utterances are transcribed incrementally so "лошадка,
/// сделай X" triggers on the first word instead of after the whole sentence.
///
/// Samples arrive already downmixed to 16 kHz mono from `CoreAudioRecorder`'s
/// processing queue - never from the realtime render thread, and never through a
/// protocol existential. The reverted first attempt at this feature did both,
/// and the app died with heap corruption surfacing in unrelated SwiftData views
/// (see AGENTS.md). Keep this boundary: `append` is the only entry point from
/// outside, it takes plain samples, and everything else is actor-isolated.
///
/// An actor, deliberately: `start`/`stop` arrive from the main actor while the
/// processing task appends to the very same buffers on another thread, and
/// concurrently mutating a Swift array corrupts the heap.
actor LocalWakeWordRecognizer {

    // MARK: - Tuning

    /// Silero's model is optimised for this chunk length (256 ms at 16 kHz).
    private static let vadChunkSamples = 4_096
    /// Audio kept before a speech start, so the beginning of the word survives
    /// the VAD's reaction time.
    private static let preRollSamples = 8_000
    /// Ignore blips too short to contain a wake word.
    private static let minSegmentSamples = 4_000
    /// Transcribe an ongoing utterance once it reaches this length...
    private static let firstPartialSamples = 32_000
    /// ...and again every this many samples while the speaker keeps going.
    private static let partialStrideSamples = 24_000
    /// Hard cap on one segment, so a monologue cannot grow the buffer forever.
    private static let maxSegmentSamples = 160_000

    // MARK: - Dependencies

    private let transcriber: FluidAudioTranscriptionService
    private let modelName: String
    private let languages: [String]
    private let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink", category: "LocalWakeWordRecognizer")

    // MARK: - State

    private var vad: VadManager?
    private var vadState = VadStreamState.initial()

    /// Written on start/stop, read from the capture queue, so it cannot live in
    /// the actor's isolated state.
    private nonisolated let continuationBox = OSAllocatedUnfairLock<
        AsyncStream<[Float]>.Continuation?
    >(initialState: nil)
    private var processingTask: Task<Void, Never>?
    private var isRunning = false

    private var onTranscript: ((String) -> Void)?
    private var onFailure: ((Error) -> Void)?

    private var pending: [Float] = []
    private var preRoll: [Float] = []
    private var segment: [Float] = []
    private var isInSpeech = false
    private var nextPartialAt = 0

    init(transcriber: FluidAudioTranscriptionService, modelName: String, languages: [String]) {
        self.transcriber = transcriber
        self.modelName = modelName
        self.languages = languages
    }

    func start(
        onTranscript: @escaping (String) -> Void,
        onFailure: @escaping (Error) -> Void
    ) async throws {
        self.onTranscript = onTranscript
        self.onFailure = onFailure

        // Load the speech model up front. Doing it lazily on the first speech
        // segment would swallow the very utterance that triggered it.
        try await transcriber.prepareForWakeWord(modelName: modelName)

        let vad = try await VadManager(config: VadConfig(defaultThreshold: 0.6))
        self.vad = vad
        self.vadState = VadStreamState.initial()

        pending.removeAll()
        preRoll.removeAll()
        segment.removeAll()
        isInSpeech = false

        let (stream, continuation) = AsyncStream<[Float]>.makeStream(
            bufferingPolicy: .bufferingNewest(96))
        continuationBox.withLock { $0 = continuation }
        isRunning = true

        processingTask = Task { [weak self] in
            for await samples in stream {
                guard let self, !Task.isCancelled else { return }
                await self.consume(samples)
            }
        }

        logger.notice(
            "Local wake word recognizer started on '\(self.modelName, privacy: .public)'"
        )
    }

    /// Hands over 16 kHz mono samples. Called from the capture queue.
    nonisolated func append(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        let continuation = continuationBox.withLock { $0 }
        continuation?.yield(samples)
    }

    func stop() async {
        isRunning = false

        let continuation = continuationBox.withLock { current -> AsyncStream<[Float]>.Continuation? in
            let existing = current
            current = nil
            return existing
        }
        continuation?.finish()

        processingTask?.cancel()
        processingTask = nil

        vad = nil
        onTranscript = nil
        onFailure = nil
        pending.removeAll()
        preRoll.removeAll()
        segment.removeAll()
        isInSpeech = false
    }

    // MARK: - Processing

    private func consume(_ samples: [Float]) async {
        guard isRunning else { return }
        pending.append(contentsOf: samples)

        while isRunning, pending.count >= Self.vadChunkSamples {
            let chunk = Array(pending.prefix(Self.vadChunkSamples))
            pending.removeFirst(Self.vadChunkSamples)
            await process(chunk: chunk)
            if Task.isCancelled { return }
        }
    }

    private func process(chunk: [Float]) async {
        guard isRunning, let vad else { return }

        let result: VadStreamResult
        do {
            result = try await vad.processStreamingChunk(chunk, state: vadState)
        } catch {
            logger.error("VAD failed: \(error.localizedDescription, privacy: .public)")
            onFailure?(error)
            return
        }

        // stop() may have run while the VAD was busy.
        guard isRunning else { return }
        vadState = result.state

        if isInSpeech {
            segment.append(contentsOf: chunk)
        } else {
            preRoll.append(contentsOf: chunk)
            if preRoll.count > Self.preRollSamples {
                preRoll.removeFirst(preRoll.count - Self.preRollSamples)
            }
        }

        switch result.event?.kind {
        case .speechStart:
            isInSpeech = true
            segment = preRoll
            segment.append(contentsOf: chunk)
            preRoll.removeAll()
            nextPartialAt = Self.firstPartialSamples

        case .speechEnd:
            isInSpeech = false
            let finished = segment
            segment.removeAll()
            nextPartialAt = Self.firstPartialSamples
            if finished.count >= Self.minSegmentSamples {
                await transcribeAndReport(finished)
            }

        case .none:
            guard isInSpeech else { return }

            if segment.count >= Self.maxSegmentSamples {
                let finished = segment
                // Keep a tail so a word straddling the cut is still recognisable.
                segment = Array(finished.suffix(Self.preRollSamples))
                nextPartialAt = Self.firstPartialSamples
                await transcribeAndReport(finished)
                return
            }

            if segment.count >= nextPartialAt {
                nextPartialAt = segment.count + Self.partialStrideSamples
                await transcribeAndReport(segment)
            }
        }
    }

    private func transcribeAndReport(_ samples: [Float]) async {
        do {
            let text = try await transcriber.transcribeForWakeWord(
                samples, modelName: modelName, languages: languages)
            guard isRunning else { return }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            onTranscript?(text)
        } catch {
            logger.error(
                "Local wake word transcription failed: \(error.localizedDescription, privacy: .public)"
            )
            onFailure?(error)
        }
    }
}

#else

/// Intel stub - FluidAudio is not linked there, see FluidAudioTranscriptionService.
actor LocalWakeWordRecognizer {
    init(transcriber: FluidAudioTranscriptionService, modelName: String, languages: [String]) {}

    func start(
        onTranscript: @escaping (String) -> Void,
        onFailure: @escaping (Error) -> Void
    ) async throws {
        throw FluidAudioUnavailableError.notSupportedOnIntel
    }

    nonisolated func append(_ samples: [Float]) {}
    func stop() async {}
}

#endif
