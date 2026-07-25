import AVFoundation
import Foundation
import os

#if canImport(FluidAudio)
import FluidAudio

/// Wake word recognition that never leaves the machine.
///
/// A transcription model is far too expensive to run on every second of silence,
/// so Silero VAD acts as the gate: it is tiny, runs on the Neural Engine, and
/// only when it reports speech does the recognizer collect a segment and hand it
/// to the model. Long utterances are transcribed incrementally so "лошадка,
/// сделай X" triggers on the first word instead of after the whole sentence.
final class LocalWakeWordRecognizer: WakeWordRecognizer {

    // MARK: - Tuning

    private static let targetSampleRate: Double = 16_000
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

    private var audioContinuation: AsyncStream<[Float]>.Continuation?
    private var processingTask: Task<Void, Never>?

    private var onTranscript: ((String) -> Void)?
    private var onFailure: ((Error) -> Void)?

    /// Resampling carry-over, kept across buffers so chunk boundaries do not click.
    private var resampleRatio: Double = 1
    private var resamplePosition: Double = 0
    private var resampleTail: Float = 0
    private var hasResampleTail = false

    private var pending: [Float] = []
    private var preRoll: [Float] = []
    private var segment: [Float] = []
    private var isInSpeech = false
    private var nextPartialAt = 0

    // MARK: - WakeWordRecognizer

    let displayName = String(localized: "Local model (offline)")
    let usesServerRecognition = false
    /// A local model has no session that expires, so nothing has to be cycled.
    let needsRollingRestart = false

    init(transcriber: FluidAudioTranscriptionService, modelName: String, languages: [String]) {
        self.transcriber = transcriber
        self.modelName = modelName
        self.languages = languages
    }

    func start(
        inputFormat: AVAudioFormat,
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

        resampleRatio = inputFormat.sampleRate / Self.targetSampleRate
        resamplePosition = 0
        hasResampleTail = false
        pending.removeAll()
        preRoll.removeAll()
        segment.removeAll()
        isInSpeech = false

        let (stream, continuation) = AsyncStream<[Float]>.makeStream(
            bufferingPolicy: .bufferingNewest(96))
        audioContinuation = continuation

        processingTask = Task { [weak self] in
            for await samples in stream {
                guard let self, !Task.isCancelled else { return }
                await self.consume(samples)
            }
        }

        logger.notice(
            "Local wake word recognizer started on '\(self.modelName, privacy: .public)' at \(inputFormat.sampleRate, privacy: .public) Hz"
        )
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let continuation = audioContinuation else { return }
        guard let mono = Self.monoSamples(from: buffer), !mono.isEmpty else { return }
        continuation.yield(mono)
    }

    func stop() async {
        audioContinuation?.finish()
        audioContinuation = nil

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

    // MARK: - Audio conversion

    /// Downmixes to mono on the audio thread. Deliberately the only work done
    /// there - resampling, VAD and the model all run on the consumer task.
    private static func monoSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return nil }

        if let channels = buffer.floatChannelData {
            let channelCount = Int(buffer.format.channelCount)
            if channelCount == 1 {
                return Array(UnsafeBufferPointer(start: channels[0], count: frameCount))
            }
            var mono = [Float](repeating: 0, count: frameCount)
            for channel in 0..<channelCount {
                let data = channels[channel]
                for frame in 0..<frameCount {
                    mono[frame] += data[frame]
                }
            }
            let scale = 1 / Float(channelCount)
            for frame in 0..<frameCount {
                mono[frame] *= scale
            }
            return mono
        }

        if let channels = buffer.int16ChannelData {
            let channelCount = Int(buffer.format.channelCount)
            var mono = [Float](repeating: 0, count: frameCount)
            for channel in 0..<channelCount {
                let data = channels[channel]
                for frame in 0..<frameCount {
                    mono[frame] += Float(data[frame]) / 32_768
                }
            }
            let scale = 1 / Float(channelCount)
            for frame in 0..<frameCount {
                mono[frame] *= scale
            }
            return mono
        }

        return nil
    }

    /// Linear resampling to 16 kHz, matching what `CoreAudioRecorder` does for
    /// the recording path.
    private func resample(_ input: [Float]) -> [Float] {
        guard resampleRatio != 1 else { return input }

        var output: [Float] = []
        output.reserveCapacity(Int(Double(input.count) / resampleRatio) + 2)

        // Index -1 refers to the last sample of the previous buffer.
        var position = resamplePosition
        while true {
            let base = Int(position.rounded(.down))
            if base >= input.count { break }

            let fraction = Float(position - Double(base))
            let current: Float
            let next: Float

            if base < 0 {
                guard hasResampleTail else {
                    position += resampleRatio
                    continue
                }
                current = resampleTail
                next = input[0]
            } else {
                current = input[base]
                next = base + 1 < input.count ? input[base + 1] : input[base]
            }

            output.append(current + (next - current) * fraction)
            position += resampleRatio
        }

        resamplePosition = position - Double(input.count)
        resampleTail = input[input.count - 1]
        hasResampleTail = true
        return output
    }

    // MARK: - Processing

    private func consume(_ nativeSamples: [Float]) async {
        pending.append(contentsOf: resample(nativeSamples))

        while pending.count >= Self.vadChunkSamples {
            let chunk = Array(pending.prefix(Self.vadChunkSamples))
            pending.removeFirst(Self.vadChunkSamples)
            await process(chunk: chunk)
            if Task.isCancelled { return }
        }
    }

    private func process(chunk: [Float]) async {
        guard let vad else { return }

        let result: VadStreamResult
        do {
            result = try await vad.processStreamingChunk(chunk, state: vadState)
        } catch {
            logger.error("VAD failed: \(error.localizedDescription, privacy: .public)")
            onFailure?(error)
            return
        }
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
final class LocalWakeWordRecognizer: WakeWordRecognizer {
    let displayName = String(localized: "Local model (offline)")
    let usesServerRecognition = false
    let needsRollingRestart = false

    init(transcriber: FluidAudioTranscriptionService, modelName: String, languages: [String]) {}

    func start(
        inputFormat: AVAudioFormat,
        onTranscript: @escaping (String) -> Void,
        onFailure: @escaping (Error) -> Void
    ) async throws {
        throw FluidAudioUnavailableError.notSupportedOnIntel
    }

    func append(_ buffer: AVAudioPCMBuffer) {}
    func stop() async {}
}

#endif
