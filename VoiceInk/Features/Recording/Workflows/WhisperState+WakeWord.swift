import Foundation
import os

// MARK: - Wake Word Detection Extension
extension VoiceInkEngine {

    /// True when *some* spoken word can end a running dictation - either the
    /// primary word saying it again, or the separate send word. Both cases mean
    /// the detector has to hold the microphone for the length of the recording
    /// instead of handing it to the recorder.
    static var voiceCanFinishDictation: Bool {
        UserDefaults.standard.wakeWordStopsRecording
            || !UserDefaults.standard.wakeWordSend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Wake Word Management

    /// Initialize wake word service and start listening if enabled
    func initializeWakeWordService() {
        let service = WakeWordListeningService()
        service.setWakeWordDetectedCallback { [weak self] trigger in
            Task { @MainActor [weak self] in
                await self?.handleWakeWordDetected(trigger: trigger)
            }
        }
        service.canStartListening = { [weak self] in
            guard let self else { return false }
            // While a spoken word also ends dictation, listening through an
            // active recording is the whole point. Transcription and enhancement
            // still take the detector down: there is nothing to stop by then,
            // and the model would compete with the one doing the real work.
            if Self.voiceCanFinishDictation, self.recordingState == .recording {
                return true
            }
            return self.recordingState == .idle
        }
        service.isRecordingActive = { [weak self] in
            self?.recordingState == .recording
        }
        // The local engine reuses the app's shared FluidAudio service, so the
        // Parakeet model is loaded once for both dictation and wake word.
        service.transcriberProvider = { [weak self] in
            self?.serviceRegistry.fluidAudioTranscriptionService
        }
        service.availableLocalModels = { [weak self] in
            guard let self else { return [] }
            return self.transcriptionModelManager.usableModels
                .filter { $0.provider == .fluidAudio && $0.name.hasPrefix("parakeet-tdt") }
                .map(\.name)
        }
        service.onStateChanged = { [weak self, weak service] in
            guard let self, let service else { return }
            self.syncWakeWordState(from: service)
        }
        self.wakeWordService = service

        // Auto-start if enabled in settings
        if UserDefaults.standard.bool(forKey: "isWakeWordEnabled") {
            Task {
                // AudioDeviceManager publishes its device list asynchronously.
                // Starting before it lands resolves no device and binds the engine
                // to the system default microphone instead of the chosen one.
                if AudioDeviceManager.shared.availableDevices.isEmpty {
                    await withCheckedContinuation { continuation in
                        AudioDeviceManager.shared.loadAvailableDevices {
                            continuation.resume()
                        }
                    }
                }
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
            syncWakeWordState(from: service)
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
            syncWakeWordState(from: service)
        }

        logger.notice("🎤 Wake word listening stopped")
    }

    /// Mirror the service's state onto the engine so views can observe it.
    @MainActor
    func syncWakeWordState(from service: WakeWordListeningService) {
        isWakeWordListening = service.isListening
        wakeWordMicrophoneUnavailable = service.microphoneUnavailable
        wakeWordBoundDeviceName = service.boundDeviceName
        wakeWordFailureMessage = service.failureMessage
        wakeWordUsingServerRecognition = service.usingServerRecognition
        wakeWordLastRecognizedText = service.lastRecognizedText
    }

    /// Handle wake word detection - start recording, or finish the one running.
    @MainActor
    func handleWakeWordDetected(trigger: WakeWordTrigger) async {
        if trigger == .send {
            // The send word only ever finishes. The detector already refuses to
            // report it while idle; this is the second lock on the same door,
            // because arming the override without a recording to spend it on is
            // exactly how a stray Return ends up in the next dictation.
            guard recordingState == .recording else {
                logger.notice("🎯 Send wake word ignored - nothing is recording")
                return
            }

            pendingAutoSendOverride = UserDefaults.standard.wakeWordSendKey
            logger.notice(
                "🎯 Send wake word detected - finishing recording and pressing \(UserDefaults.standard.wakeWordSendKey.rawValue, privacy: .public)"
            )
            NotificationCenter.default.post(name: .toggleRecorderPanel, object: nil)
            return
        }

        // The same notification does both: `toggleRecorderPanel` starts a session
        // when the engine is idle and finishes it - transcribe, then paste - when
        // one is running, which is exactly what pressing the shortcut twice does.
        if recordingState == .recording {
            logger.notice("🎯 Wake word detected - finishing recording")
        } else {
            logger.notice("🎯 Wake word detected - starting recording")
            // Listening resumes once the pipeline returns to idle, unless the
            // detector kept the microphone to hear a closing word.
            if !Self.voiceCanFinishDictation {
                isWakeWordListening = false
            }
        }

        NotificationCenter.default.post(name: .toggleRecorderPanel, object: nil)
    }

    /// Resume wake word listening after recording completes
    func resumeWakeWordListeningIfEnabled() async {
        let isEnabled = UserDefaults.standard.bool(forKey: "isWakeWordEnabled")

        guard isEnabled else { return }
        guard recordingState == .idle else { return }
        guard !isWakeWordListening else { return }

        // Small delay before resuming
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // The state can move again during the delay (a new recording started).
        guard recordingState == .idle else { return }

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

    /// Configure the second word, the one that finishes dictation and sends it.
    /// Pass an empty string to turn it off.
    func configureSendWakeWord(_ word: String) {
        guard let service = wakeWordService else {
            logger.error("Wake word service not initialized")
            return
        }

        service.configureSendWakeWord(word)
    }

    /// Set the command word and the mode it routes a dictation to.
    ///
    /// The word is stored as that mode's trigger word, not as a setting of its
    /// own, because the transcript side already works that way:
    /// `ModeTriggerWordDetectionService` is what recognises the word mid
    /// dictation, selects the mode and strips the word out of the text. Keeping
    /// one copy is what stops the spoken word and the stripped word from
    /// drifting apart and leaving the command wedged in its own text.
    ///
    /// Deliberately nothing here touches `wakeWordService`: the command word is
    /// not a wake word and the detector must never answer to it.
    @MainActor
    func configureCommandWord(_ words: [String], modeId: UUID?) {
        UserDefaults.standard.wakeWordCommandModeId = modeId

        guard let modeId,
            var mode = ModeManager.shared.getConfiguration(with: modeId)
        else { return }

        mode.triggerWords = ModeConfig.normalizedTriggerWords(words)
        ModeManager.shared.updateConfiguration(mode)
        logger.notice(
            "Command word configured: \(mode.triggerWords.isEmpty ? "off" : mode.triggerWords.joined(separator: ", "), privacy: .public) → mode '\(mode.name, privacy: .public)'"
        )
    }

    /// Configure which microphone the wake word detector listens on.
    /// Pass an empty UID to follow the app's recording device selection.
    func configureWakeWordMicrophone(uid: String) {
        guard let service = wakeWordService else {
            logger.error("Wake word service not initialized")
            return
        }

        // Capture the stable model UID now, while the device is connected - the
        // UID alone changes whenever a USB device moves to another port.
        let device = AudioDeviceManager.shared.availableDevices.first(where: { $0.uid == uid })
        let modelUID = device.flatMap { AudioDeviceManager.shared.getDeviceModelUID(deviceID: $0.id) }
        UserDefaults.standard.wakeWordMicrophoneName = uid.isEmpty ? nil : device?.name

        service.configureMicrophone(uid: uid, modelUID: modelUID)
    }

    /// Select which backend recognises the wake word.
    func configureWakeWordEngine(_ kind: WakeWordEngineKind) {
        guard let service = wakeWordService else {
            logger.error("Wake word service not initialized")
            return
        }
        service.configureEngine(kind)
    }

    /// Select the transcription model used by the local wake word engine.
    func configureWakeWordModel(named modelName: String) {
        guard let service = wakeWordService else {
            logger.error("Wake word service not initialized")
            return
        }
        service.configureLocalModel(named: modelName)
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
