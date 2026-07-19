#if canImport(FluidAudio)
import FluidAudio
import Foundation
import os

/// Streams audio through FluidAudio's Unified manager.
@MainActor
final class FluidAudioUnifiedStreamingProvider: StreamingTranscriptionProvider {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "FluidAudioUnifiedStreaming")
    private let models: UnifiedModelCache<StreamingUnifiedAsrManager>
    private let processing = UnifiedModelAccess()
    private var manager: StreamingUnifiedAsrManager?
    private var isDisconnected = false
    private var eventsContinuation: AsyncStream<StreamingTranscriptionEvent>.Continuation?

    nonisolated let transcriptionEvents: AsyncStream<StreamingTranscriptionEvent>

    init(fluidAudioService: FluidAudioTranscriptionService) {
        self.models = fluidAudioService.unifiedStreamingModels
        var continuation: AsyncStream<StreamingTranscriptionEvent>.Continuation!
        transcriptionEvents = AsyncStream { continuation = $0 }
        eventsContinuation = continuation
    }

    deinit {
        eventsContinuation?.finish()
        guard let manager else { return }
        let models = models
        Task { @MainActor in
            await manager.setPartialTranscriptCallback { _ in }
            await models.release(manager)
        }
    }

    func connect(model: any TranscriptionModel, language: String?) async throws {
        let manager = try await models.acquire()
        do {
            let continuation = eventsContinuation
            await manager.setPartialTranscriptCallback { continuation?.yield(.partial(text: $0)) }
            try Task.checkCancellation()
            guard !isDisconnected else { throw CancellationError() }
            self.manager = manager
        } catch {
            await manager.setPartialTranscriptCallback { _ in }
            await models.release(manager)
            throw error
        }
        eventsContinuation?.yield(.sessionStarted)
        logger.notice("Parakeet Unified streaming started for \(model.displayName, privacy: .public)")
    }

    func sendAudioChunk(_ data: Data) async throws {
        guard !data.isEmpty else { return }
        guard let buffer = PCMAudioConverter.pcmBuffer(fromPCM16Data: data) else {
            throw StreamingTranscriptionError.audioConversionFailed
        }
        _ = try await process { manager in
            try await manager.appendAudio(buffer)
            try await manager.processBufferedAudio()
            return ""
        }
    }

    func commit() async throws {
        let finalText = try await process { manager in try await manager.finish() }
        let text = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        eventsContinuation?.yield(.committed(text: text))
    }

    func disconnect() async {
        isDisconnected = true
        if let manager {
            self.manager = nil
            await processing.lock()
            await manager.setPartialTranscriptCallback { _ in }
            await models.release(manager)
            processing.unlock()
        }
        eventsContinuation?.finish()
        logger.notice("Parakeet Unified streaming disconnected")
    }

    private func process<Result>(
        _ operation: (StreamingUnifiedAsrManager) async throws -> Result
    ) async throws -> Result {
        await processing.lock()
        defer { processing.unlock() }
        try Task.checkCancellation()
        guard !isDisconnected else { throw CancellationError() }
        guard let manager else { throw StreamingTranscriptionError.notConnected }
        let result = try await operation(manager)
        try Task.checkCancellation()
        guard !isDisconnected else { throw CancellationError() }
        return result
    }
}
#endif
