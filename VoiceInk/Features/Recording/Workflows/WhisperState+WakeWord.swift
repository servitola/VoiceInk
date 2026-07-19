import Foundation
import os

// MARK: - Wake Word Detection Extension
extension VoiceInkEngine {

    // MARK: - Wake Word Management

    /// Initialize wake word service and start listening if enabled
    func initializeWakeWordService() {
        let service = WakeWordListeningService()
        service.setWakeWordDetectedCallback { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleWakeWordDetected()
            }
        }
        self.wakeWordService = service

        // Auto-start if enabled in settings
        if UserDefaults.standard.bool(forKey: "isWakeWordEnabled") {
            Task {
                await startWakeWordListening()
            }
        }
    }

    /// Start listening for wake word in the background
    func startWakeWordListening() async {
        guard let service = wakeWordService else {
            logger.error("Wake word service not initialized")
            return
        }

        // Don't start if already recording or processing
        guard recordingState == .idle else {
            logger.notice("Cannot start wake word listening: recorder is busy")
            return
        }

        await service.startListening()
        await MainActor.run {
            isWakeWordListening = service.isListening
        }

        if service.isListening {
            logger.notice("🎤 Wake word listening started")
        }
    }

    /// Stop listening for wake word
    func stopWakeWordListening() async {
        guard let service = wakeWordService else { return }

        await service.stopListening()
        await MainActor.run {
            isWakeWordListening = false
        }

        logger.notice("🎤 Wake word listening stopped")
    }

    /// Handle wake word detection - trigger recording
    @MainActor
    func handleWakeWordDetected() async {
        logger.notice("🎯 Wake word detected - starting recording")

        // Stop wake word listening temporarily
        isWakeWordListening = false

        // Show the recorder panel and start recording via the standard path.
        // toggleRecorderPanel plays the start sound, reveals the panel, and toggles
        // recording — with the panel hidden and the engine idle it starts a new session.
        NotificationCenter.default.post(name: .toggleRecorderPanel, object: nil)

        // Wake word listening will resume after recording completes
    }

    /// Resume wake word listening after recording completes
    func resumeWakeWordListeningIfEnabled() async {
        let isEnabled = UserDefaults.standard.bool(forKey: "isWakeWordEnabled")

        guard isEnabled else { return }
        guard recordingState == .idle else { return }

        // Small delay before resuming
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        await startWakeWordListening()
    }

    /// Configure wake word settings
    func configureWakeWord(word: String, language: String) {
        guard let service = wakeWordService else {
            logger.error("Wake word service not initialized")
            return
        }

        service.configureWakeWord(word, language: language)
        logger.notice("Wake word configured: '\(word)', language: \(language)")
    }

    /// Configure which microphone the wake word detector listens on.
    /// Pass an empty UID to follow the app's recording device selection.
    func configureWakeWordMicrophone(uid: String) {
        guard let service = wakeWordService else {
            logger.error("Wake word service not initialized")
            return
        }

        service.configureMicrophone(uid: uid)
    }

    /// Toggle wake word listening on/off
    func toggleWakeWordListening() async {
        if isWakeWordListening {
            await stopWakeWordListening()
        } else {
            await startWakeWordListening()
        }
    }

    /// Request speech recognition permissions
    func requestWakeWordPermissions() async -> Bool {
        guard let service = wakeWordService else {
            logger.error("Wake word service not initialized")
            return false
        }

        return await service.requestPermissions()
    }
}
