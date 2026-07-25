import AVFoundation
import Accelerate
import Atomics
import CoreAudio
import Foundation
import Speech
import os

/// Service for continuous wake word detection using Apple Speech Recognition
@MainActor
class WakeWordListeningService: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published var isListening = false {
        didSet { if oldValue != isListening { onStateChanged?() } }
    }
    /// The most recent transcription the recogniser produced. Surfaced in the
    /// wake word settings so "it never fires" can be told apart from "it never
    /// hears anything" without attaching a debugger.
    @Published var lastRecognizedText = "" {
        didSet { if oldValue != lastRecognizedText { onStateChanged?() } }
    }
    @Published var permissionStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    /// True when the explicitly configured microphone is not currently connected.
    /// Listening stays paused in that case instead of falling back to another device.
    @Published var microphoneUnavailable = false {
        didSet { if oldValue != microphoneUnavailable { onStateChanged?() } }
    }
    /// Name of the device the audio engine is actually bound to, for UI feedback.
    @Published var boundDeviceName: String? {
        didSet { if oldValue != boundDeviceName { onStateChanged?() } }
    }
    /// Why the detector gave up, when it did. Surfaced in settings instead of
    /// letting it restart in a loop that just blinks the microphone indicator.
    @Published var failureMessage: String? {
        didSet { if oldValue != failureMessage { onStateChanged?() } }
    }
    /// True while recognition runs on Apple's servers rather than on device.
    /// Worth showing: an always-on listener then streams the room continuously.
    @Published var usingServerRecognition = false {
        didSet { if oldValue != usingServerRecognition { onStateChanged?() } }
    }

    /// Called whenever the observable state above changes, including from the
    /// service's own rolling restarts and device-change handling.
    var onStateChanged: (() -> Void)?

    // MARK: - Private Properties

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "WakeWordListeningService")

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var capture: CoreAudioRecorder?
    private var localRecognizer: LocalWakeWordRecognizer?
    private var boundDeviceID: AudioDeviceID?
    private var deviceChangeObserver: NSObjectProtocol?

    /// Invalidation token. Every start/stop bumps it, and every asynchronous
    /// continuation (recognition callback, scheduled restart, engine spin-up)
    /// checks it before touching shared state, so overlapping restarts cannot
    /// stomp each other's engine and leave the microphone held open.
    private var generation = 0
    private var pendingRestartTask: Task<Void, Never>?
    private var restartBackoffSeconds: UInt64 = 1
    /// Chains concurrent `startListening()` calls so they run one after another.
    private var startTask: Task<Void, Never>?
    /// Reports microphone health while a session runs. The Apple backend logs it
    /// on every rolling restart, but a local model has no session to end, so
    /// without this the counters would never be printed at all.
    private var levelReportTask: Task<Void, Never>?

    /// When the current recognition session started, and how it was configured.
    /// A session that dies within seconds of starting is a configuration failure,
    /// not the ordinary end-of-request - restarting it on a short timer just
    /// reopens the microphone over and over.
    private var sessionStartedAt: Date?
    private var sessionUsedOnDeviceRecognition = false
    private var consecutiveImmediateFailures = 0
    /// Set once on-device recognition proves unusable for the chosen language,
    /// so the next attempt goes through the server instead of failing forever.
    private var onDeviceRecognitionDisabled = false
    private let immediateFailureThreshold: TimeInterval = 15

    /// Loudest sample the tap has seen since the current session started, held as
    /// a `Float` bit pattern. Written from the realtime audio thread, so it is
    /// lock-free rather than actor-isolated, and read once per teardown. A
    /// session that ends with a peak of zero means the microphone delivered
    /// silence, which is a completely different fault from a recogniser that
    /// returns nothing.
    private let sessionInputPeakBits = ManagedAtomic<UInt32>(Float(0).bitPattern)
    /// Frames the tap actually delivered this session. Zero peak with zero frames
    /// is a dead audio graph; zero peak with millions of frames is a muted or
    /// permission-denied microphone. The two have completely different fixes.
    private let sessionInputFrames = ManagedAtomic<UInt64>(0)

    private var wakeWord: String = "лошадка"
    private var language: String = "ru-RU"
    /// Which backend turns audio into text. Defaults to the local model - an
    /// always-on listener on Apple's servers streams the room continuously.
    private var engineKind: WakeWordEngineKind = .localModel
    /// Transcription model for the local engine.
    private var localModelName: String?

    /// When the detector last fired. The recognisers report a growing utterance
    /// incrementally ("лошадка", then "лошадка сделай..."), and the wake word
    /// stays in every one of those, so without a cooldown a single spoken word
    /// triggers over and over - which matters much more now that a second
    /// trigger ends the dictation the first one started.
    private var lastDetectionAt: Date?
    private let detectionCooldown: TimeInterval = 2.5

    /// The wake word also finishes dictation, so the detector keeps listening
    /// while the recorder runs instead of handing the microphone over.
    private var stopsRecording: Bool {
        UserDefaults.standard.object(forKey: "wakeWordStopsRecording") as? Bool ?? true
    }
    /// UID of the microphone to listen on. Empty = follow the app's recording device selection.
    private var microphoneUID: String = ""
    /// Stable identity of that microphone — USB UIDs embed the port location ID
    /// and change between ports, the model UID does not.
    private var microphoneModelUID: String?
    private var onWakeWordDetected: (() -> Void)?

    /// Set by the engine. The detector must not take the microphone while a
    /// recording or transcription is in flight.
    var canStartListening: (() -> Bool)?

    /// Supplies the app's shared FluidAudio service, so the local engine reuses
    /// the model dictation already loaded instead of holding a second copy.
    var transcriberProvider: (() -> FluidAudioTranscriptionService?)?
    /// Names of downloaded models usable by the local engine, newest first.
    var availableLocalModels: (() -> [String])?

    // Circular buffer to keep last N seconds of recognized text
    private var recognizedTextBuffer: [String] = []
    private let bufferSize = 10

    /// A single speech recognition request is capped at roughly a minute, so an
    /// always-on listener has to cycle proactively rather than wait for the error.
    private let rollingRestartRange: ClosedRange<UInt64> = 47...53
    private let maxRestartBackoffSeconds: UInt64 = 30

    // MARK: - Initialization

    override init() {
        super.init()
        loadSettings()
        checkPermissions()
        setupDeviceChangeObserver()
    }

    // MARK: - Settings Management

    private func loadSettings() {
        wakeWord = UserDefaults.standard.string(forKey: "wakeWord") ?? "лошадка"
        language = UserDefaults.standard.string(forKey: "wakeWordLanguage") ?? "ru-RU"
        microphoneUID = UserDefaults.standard.wakeWordMicrophoneUID ?? ""
        microphoneModelUID = UserDefaults.standard.wakeWordMicrophoneModelUID
        engineKind =
            UserDefaults.standard.wakeWordEngine.flatMap(WakeWordEngineKind.init(rawValue:))
            ?? .localModel
        localModelName = UserDefaults.standard.wakeWordModelName

        logger.notice(
            "Wake word settings loaded: '\(self.wakeWord)', language: \(self.language), engine: \(self.engineKind.rawValue, privacy: .public)"
        )
    }

    /// Select the microphone the wake word detector listens on.
    /// Pass an empty UID to follow the app's recording device selection.
    func configureMicrophone(uid: String, modelUID: String?) {
        self.microphoneUID = uid
        self.microphoneModelUID = uid.isEmpty ? nil : modelUID

        UserDefaults.standard.wakeWordMicrophoneUID = uid
        UserDefaults.standard.wakeWordMicrophoneModelUID = self.microphoneModelUID

        logger.notice("Wake word microphone configured: '\(uid.isEmpty ? "app default" : uid)'")

        // An explicit settings change deserves a clean slate.
        consecutiveImmediateFailures = 0
        restartBackoffSeconds = 1

        // Restart listening if already active so the new device takes effect
        if isListening {
            Task {
                await stopListening()
                await startListening()
            }
        }
    }

    /// Resolves the input device the detector should listen on, together with its name.
    ///
    /// When a device was chosen explicitly this is strict: if that device is not
    /// connected it returns nil rather than picking another one, because falling
    /// back would grab the built-in or headset microphone the user deliberately
    /// excluded. Only "Same as Recording" follows the app's own device selection.
    private func resolveInputDevice() -> (id: AudioDeviceID, name: String)? {
        let manager = AudioDeviceManager.shared

        guard microphoneUID.isEmpty else {
            guard let device = manager.findAvailableDevice(uid: microphoneUID, modelUID: microphoneModelUID) else {
                return nil
            }

            // The device may have come back on another USB port under a new UID.
            // Re-pin the saved identity so the settings picker keeps resolving it.
            if device.uid != microphoneUID {
                logger.notice("Wake word microphone reappeared under a new UID - re-pinning")
                microphoneUID = device.uid
                UserDefaults.standard.wakeWordMicrophoneUID = device.uid
            }
            if microphoneModelUID == nil {
                microphoneModelUID = manager.getDeviceModelUID(deviceID: device.id)
                UserDefaults.standard.wakeWordMicrophoneModelUID = microphoneModelUID
            }

            return (device.id, device.name)
        }

        let current = manager.getCurrentDevice()
        guard current != 0 else { return nil }
        let name = manager.availableDevices.first(where: { $0.id == current })?.name ?? "Unknown"
        return (current, name)
    }

    func configureWakeWord(_ word: String, language: String = "ru-RU") {
        self.wakeWord = word.lowercased()
        self.language = language

        UserDefaults.standard.set(word, forKey: "wakeWord")
        UserDefaults.standard.set(language, forKey: "wakeWordLanguage")

        logger.notice("Wake word configured: '\(word)', language: \(language)")

        // Restart listening if already active
        if isListening {
            Task {
                await stopListening()
                await startListening()
            }
        }
    }

    func setWakeWordDetectedCallback(_ callback: @escaping () -> Void) {
        self.onWakeWordDetected = callback
    }

    // MARK: - Permission Management

    private func checkPermissions() {
        permissionStatus = SFSpeechRecognizer.authorizationStatus()
        logger.notice("Speech recognition permission status: \(String(describing: self.permissionStatus.rawValue))")
    }

    func requestPermissions() async -> Bool {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    self.permissionStatus = status
                    self.logger.notice("Speech recognition permission: \(String(describing: status.rawValue))")
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }

    // MARK: - Listening Control

    func startListening() async {
        // Serialise starts. Bringing a local model up takes hundreds of
        // milliseconds, and three callers race here at launch - the auto-start,
        // the device-list arrival and the idle-state hook. Each got past the
        // `isListening` check while the others were still awaiting, so two
        // models were loaded and two capture sessions opened before the
        // generation token discarded all but the last. Measured in the log as
        // two "Local wake word recognizer started" lines for one start.
        let previous = startTask
        let task = Task { [weak self] in
            _ = await previous?.value
            await self?.performStart()
        }
        startTask = task
        await task.value
    }

    private func performStart() async {
        guard !isListening else {
            logger.notice("Already listening, ignoring start request")
            return
        }

        // Only Apple's recognizer needs Speech Recognition authorization. The
        // local engine never talks to the Speech framework, so demanding it
        // there would block offline detection on a permission it does not use.
        if engineKind == .appleSpeech, permissionStatus != .authorized {
            logger.error("Cannot start listening: Speech recognition not authorized")
            let authorized = await requestPermissions()
            if !authorized {
                logger.error("Permission request denied")
                return
            }
        }

        generation &+= 1
        let myGeneration = generation
        // Note: consecutiveImmediateFailures deliberately survives a restart -
        // every restart goes through here, so resetting it would keep the counter
        // at zero and the failure loop would never be detected.
        failureMessage = nil

        do {
            try await startRecognition(generation: myGeneration)

            // A newer start/stop superseded this one while the engine was spinning up.
            guard myGeneration == generation else { return }

            isListening = true
            logger.notice(
                "✅ Wake word listening started for '\(self.wakeWord)' on '\(self.boundDeviceName ?? "unknown", privacy: .public)'"
            )
        } catch {
            logger.error("Failed to start wake word listening: \(error.localizedDescription)")
        }
    }

    /// Tears everything down. Deliberately unconditional - a listening flag left
    /// stale by a losing race must never be able to skip the teardown and leave
    /// the audio engine running with the microphone open.
    func stopListening() async {
        generation &+= 1

        pendingRestartTask?.cancel()
        pendingRestartTask = nil

        levelReportTask?.cancel()
        levelReportTask = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        if let capture {
            // Drop the callback first: teardown drains the processing queue, and
            // a chunk delivered after the backend is gone is wasted work at best.
            capture.onAudioChunk = nil
            capture.teardown()
        }
        capture = nil

        if let localRecognizer {
            await localRecognizer.stop()
        }
        localRecognizer = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if let started = sessionStartedAt {
            let lifetime = Date().timeIntervalSince(started)
            reportInputLevel(reason: "session ended after \(String(format: "%.1f", lifetime))s")
        }

        recognizedTextBuffer.removeAll()
        boundDeviceID = nil
        boundDeviceName = nil
        sessionStartedAt = nil

        if isListening {
            isListening = false
            logger.notice("Wake word listening stopped")
        }
    }

    /// Format the capture path delivers: 16 kHz mono, which is also what the
    /// local wake word models expect.
    nonisolated private static let captureFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )

    /// Logs how much audio the microphone actually delivered, once a minute.
    ///
    /// A peak of zero here means the tap saw pure digital silence, which is a
    /// microphone or permission fault rather than a recognition one - the two
    /// look identical from the outside, and telling them apart is what found
    /// the AVAudioEngine bug this capture path replaced.
    private func startLevelReporting() {
        levelReportTask?.cancel()
        let myGeneration = generation

        levelReportTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled, let self else { return }
                guard myGeneration == self.generation else { return }
                self.reportInputLevel(reason: "still listening")
            }
        }
    }

    private func reportInputLevel(reason: String) {
        let peak = Float(bitPattern: sessionInputPeakBits.exchange(Float(0).bitPattern, ordering: .relaxed))
        let frames = sessionInputFrames.exchange(0, ordering: .relaxed)
        logger.notice(
            "Wake word input (\(reason, privacy: .public)): \(frames, privacy: .public) frames, peak \(String(format: "%.4f", peak), privacy: .public)"
        )
    }

    /// Converts a 16 kHz mono Int16 chunk to normalised floats, the form both
    /// backends want.
    nonisolated private static func floatSamples(fromInt16 data: Data) -> [Float]? {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        guard sampleCount > 0 else { return nil }

        var samples = [Float](repeating: 0, count: sampleCount)
        data.withUnsafeBytes { raw in
            guard let source = raw.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
            // vDSP converts the whole chunk in one pass instead of per-sample Swift.
            vDSP_vflt16(source, 1, &samples, 1, vDSP_Length(sampleCount))
            var scale: Float = 1.0 / 32768.0
            vDSP_vsmul(samples, 1, &scale, &samples, 1, vDSP_Length(sampleCount))
        }
        return samples
    }

    /// Wraps 16 kHz mono samples for Apple's recognizer.
    nonisolated private static func makeFloatBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard let format = captureFormat,
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
            let destination = buffer.floatChannelData?[0]
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            destination.update(from: base, count: samples.count)
        }
        return buffer
    }

    /// Records the diagnostic counters for one chunk.
    nonisolated private static func recordLevel(
        of samples: [Float], peak: ManagedAtomic<UInt32>, frames: ManagedAtomic<UInt64>
    ) {
        frames.wrappingIncrement(by: UInt64(samples.count), ordering: .relaxed)
        var value: Float = 0
        vDSP_maxmgv(samples, 1, &value, vDSP_Length(samples.count))
        recordPeak(value, into: peak)
    }

    /// Raises `storage` to `value` if `value` is larger. Called from the audio
    /// thread, so it is `nonisolated` and does no allocation.
    nonisolated private static func recordPeak(_ value: Float, into storage: ManagedAtomic<UInt32>) {
        var current = storage.load(ordering: .relaxed)
        while Float(bitPattern: current) < value {
            let (exchanged, seen) = storage.compareExchange(
                expected: current,
                desired: value.bitPattern,
                ordering: .relaxed
            )
            if exchanged { return }
            current = seen
        }
    }

    // MARK: - Local engine

    /// Builds the offline backend, or explains why it cannot run.
    private func makeLocalRecognizer() throws -> LocalWakeWordRecognizer {
        guard let transcriber = transcriberProvider?() else {
            throw WakeWordRecognizerError.noLocalModelSelected
        }

        let downloaded = availableLocalModels?() ?? []
        // A saved model that has since been deleted must not silently pick
        // another one behind the user's back, but an unset preference should
        // still work out of the box.
        let chosen: String
        if let localModelName, !localModelName.isEmpty {
            guard downloaded.contains(localModelName) else {
                throw WakeWordRecognizerError.modelNotDownloaded(localModelName)
            }
            chosen = localModelName
        } else {
            guard let first = downloaded.first else {
                throw WakeWordRecognizerError.noLocalModelSelected
            }
            chosen = first
        }

        return LocalWakeWordRecognizer(
            transcriber: transcriber,
            modelName: chosen,
            languages: [String(language.prefix(2))]
        )
    }

    /// Selects the recognition backend.
    func configureEngine(_ kind: WakeWordEngineKind) {
        guard kind != engineKind else { return }
        engineKind = kind
        UserDefaults.standard.wakeWordEngine = kind.rawValue
        logger.notice("Wake word engine set to \(kind.rawValue, privacy: .public)")
        restartIfListening()
    }

    /// Selects the transcription model for the local backend.
    func configureLocalModel(named modelName: String) {
        guard modelName != localModelName else { return }
        localModelName = modelName
        UserDefaults.standard.wakeWordModelName = modelName
        logger.notice("Wake word local model set to \(modelName, privacy: .public)")
        restartIfListening()
    }

    /// Applies a settings change that only takes effect on a fresh session.
    private func restartIfListening() {
        consecutiveImmediateFailures = 0
        restartBackoffSeconds = 1
        failureMessage = nil

        guard isListening else { return }
        Task {
            await stopListening()
            await startListening()
        }
    }

    // MARK: - Speech Recognition

    private func startRecognition(generation myGeneration: Int) async throws {
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        guard let device = resolveInputDevice() else {
            microphoneUnavailable = !microphoneUID.isEmpty
            boundDeviceName = nil
            logger.error("Wake word microphone is not connected - staying idle instead of falling back")
            throw WakeWordError.microphoneUnavailable
        }

        // Capture through the same AUHAL recorder the main dictation path uses.
        //
        // This was an AVAudioEngine input tap until it was measured delivering
        // zero frames for a whole session against a USB microphone bound with
        // `auAudioUnit.setDeviceID` - the engine started without error and the
        // tap was simply never called, so the detector heard literal digital
        // silence and could never fire. CoreAudioRecorder drives the device
        // directly, is what records every dictation on this machine, and already
        // hands 16 kHz mono PCM off the realtime thread through its own
        // lock-free queue.
        let capture = CoreAudioRecorder()

        // Chunks arrive on the recorder's processing queue, already downmixed to
        // 16 kHz mono - not on the realtime render thread - so allocating here is
        // fine. Nothing actor-isolated is touched, and the backend is reached
        // through a concrete type rather than a protocol existential: the
        // reverted first attempt at a swappable backend called through
        // `any WakeWordRecognizer` from the realtime thread and the app died
        // with heap corruption (AGENTS.md, commits 6a27634 / c61cdc7).
        let peakBits = sessionInputPeakBits
        let frameCount = sessionInputFrames
        peakBits.store(Float(0).bitPattern, ordering: .relaxed)
        frameCount.store(0, ordering: .relaxed)

        let useOnDevice: Bool
        switch engineKind {
        case .localModel:
            let recognizer = try makeLocalRecognizer()
            try await recognizer.start(
                onTranscript: { [weak self] text in
                    Task { @MainActor [weak self] in
                        guard let self, myGeneration == self.generation else { return }
                        self.handleRecognizedText(text)
                    }
                },
                onFailure: { [weak self] error in
                    Task { @MainActor [weak self] in
                        guard let self, myGeneration == self.generation else { return }
                        self.handleRecognitionFailure(error)
                    }
                }
            )

            guard myGeneration == generation else {
                await recognizer.stop()
                return
            }
            localRecognizer = recognizer

            capture.onAudioChunk = { data in
                guard let samples = Self.floatSamples(fromInt16: data) else { return }
                Self.recordLevel(of: samples, peak: peakBits, frames: frameCount)
                recognizer.append(samples)
            }
            // Nothing leaves the machine, and there is no session to expire.
            useOnDevice = true

        case .appleSpeech:
            let locale = Locale(identifier: language)
            speechRecognizer = SFSpeechRecognizer(locale: locale)

            guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
                logger.error("Speech recognizer not available for language: \(self.language)")
                throw WakeWordError.recognizerNotAvailable
            }

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            // Server-side recognition caps a single request at about a minute and is
            // rate limited, which an always-on listener hits constantly - and it would
            // stream the room to Apple around the clock. Stay on device when possible.
            // supportsOnDeviceRecognition can still report true while the language
            // asset is missing, so this falls back to the server after repeated
            // immediate failures.
            useOnDevice = speechRecognizer.supportsOnDeviceRecognition && !onDeviceRecognitionDisabled
            request.requiresOnDeviceRecognition = useOnDevice
            recognitionRequest = request

            capture.onAudioChunk = { data in
                guard let samples = Self.floatSamples(fromInt16: data) else { return }
                Self.recordLevel(of: samples, peak: peakBits, frames: frameCount)
                guard let buffer = Self.makeFloatBuffer(from: samples) else { return }
                request.append(buffer)
            }
        }

        do {
            try capture.startCapture(deviceID: device.id)
        } catch {
            logger.error("Failed to capture from wake word device \(device.id, privacy: .public): \(error.localizedDescription)")
            capture.onAudioChunk = nil
            capture.teardown()
            microphoneUnavailable = true
            boundDeviceName = nil
            throw WakeWordError.audioEngineFailure
        }

        guard myGeneration == generation else {
            capture.onAudioChunk = nil
            capture.teardown()
            recognitionRequest?.endAudio()
            recognitionRequest = nil
            if let localRecognizer {
                await localRecognizer.stop()
                self.localRecognizer = nil
            }
            return
        }

        self.capture = capture
        self.boundDeviceID = device.id
        self.boundDeviceName = device.name
        self.microphoneUnavailable = false
        self.sessionStartedAt = Date()
        self.sessionUsedOnDeviceRecognition = useOnDevice
        self.usingServerRecognition = !useOnDevice

        logger.notice(
            "Wake word listening on device \(device.id, privacy: .public) '\(device.name, privacy: .public)', engine: \(self.engineKind.rawValue, privacy: .public), onDevice recognition: \(useOnDevice, privacy: .public)"
        )

        startLevelReporting()

        // Only Apple's recogniser needs a task and a rolling restart: its request
        // is capped at roughly a minute, while a local model has no session that
        // expires and cycling it would just reload the model for nothing.
        if let speechRecognizer, let request = recognitionRequest {
            recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self = self, myGeneration == self.generation else { return }

                    if let error = error {
                        self.handleRecognitionFailure(error)
                        return
                    }

                    if let result = result {
                        self.handleRecognizedText(result.bestTranscription.formattedString)
                    }
                }
            }

            scheduleRestart(after: UInt64.random(in: rollingRestartRange), reason: "rolling restart")
        }
    }

    /// Decides what to do about a failed recognition session.
    ///
    /// An ordinary session ends after its time limit and simply restarts. One
    /// that dies within seconds of starting is a configuration problem: retrying
    /// it on a one-second timer produces nothing but a blinking microphone
    /// indicator. So repeated immediate failures first drop on-device
    /// recognition, and then stop the detector outright with a message.
    private func handleRecognitionFailure(_ error: Error) {
        let nsError = error as NSError
        let lifetime = sessionStartedAt.map { Date().timeIntervalSince($0) } ?? 0

        logger.error(
            "Recognition error after \(String(format: "%.2f", lifetime), privacy: .public)s: \(error.localizedDescription, privacy: .public) [\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)]"
        )

        guard lifetime < immediateFailureThreshold else {
            // Lived long enough to be doing its job - this is a normal cycle.
            consecutiveImmediateFailures = 0
            restartBackoffSeconds = 1
            scheduleRestart(after: 1, reason: "recognition ended")
            return
        }

        consecutiveImmediateFailures += 1

        // The on-device-to-server fallback belongs to Apple's recognizer only.
        // A local model has no server to fall back to, and pretending otherwise
        // would just relabel the session while it kept failing the same way.
        if consecutiveImmediateFailures >= 3, engineKind == .appleSpeech, sessionUsedOnDeviceRecognition {
            logger.error("On-device recognition is unusable for \(self.language, privacy: .public) - falling back to server recognition")
            onDeviceRecognitionDisabled = true
            consecutiveImmediateFailures = 0
            restartBackoffSeconds = 1
            scheduleRestart(after: 1, reason: "on-device fallback")
            return
        }

        if consecutiveImmediateFailures >= 3 {
            logger.error("Wake word recognition keeps failing immediately - stopping")
            let message = error.localizedDescription
            Task { [weak self] in
                await self?.stopListening()
                self?.failureMessage = message
            }
            return
        }

        let delay = restartBackoffSeconds
        restartBackoffSeconds = min(delay * 2, maxRestartBackoffSeconds)
        scheduleRestart(after: delay, reason: "recognition error")
    }

    /// Schedules a stop/start cycle. Replaces any previously scheduled one, so a
    /// recognition error supersedes the pending rolling restart rather than
    /// racing it.
    private func scheduleRestart(after seconds: UInt64, reason: String) {
        let myGeneration = generation

        pendingRestartTask?.cancel()
        pendingRestartTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)

            guard !Task.isCancelled, let self = self else { return }
            guard myGeneration == self.generation else { return }
            guard UserDefaults.standard.bool(forKey: "isWakeWordEnabled") else { return }
            guard self.canStartListening?() ?? true else { return }

            // Clear first - stopListening() cancels this field, which is this task.
            self.pendingRestartTask = nil
            self.logger.notice("Restarting wake word listening (\(reason, privacy: .public))")

            await self.stopListening()
            await self.startListening()
        }
    }

    // MARK: - Device Changes

    private func setupDeviceChangeObserver() {
        deviceChangeObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("AudioDeviceChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handleDeviceListChanged()
            }
        }
    }

    /// Rebinds the engine when the configured microphone is unplugged, comes back,
    /// or reappears on a different port under a new AudioDeviceID.
    private func handleDeviceListChanged() async {
        guard UserDefaults.standard.bool(forKey: "isWakeWordEnabled") else { return }
        guard canStartListening?() ?? true else { return }

        guard let resolved = resolveInputDevice() else {
            if isListening {
                logger.notice("Wake word microphone disappeared - pausing until it returns")
                await stopListening()
            }
            microphoneUnavailable = !microphoneUID.isEmpty
            return
        }

        guard isListening else {
            microphoneUnavailable = false
            await startListening()
            return
        }

        if resolved.id != boundDeviceID {
            logger.notice("Wake word microphone moved to device \(resolved.id, privacy: .public) - rebinding")
            await stopListening()
            await startListening()
        }
    }

    /// Handles one transcription from whichever backend is running.
    private func handleRecognizedText(_ text: String) {
        // Recognition is demonstrably working - forget earlier failures.
        consecutiveImmediateFailures = 0
        restartBackoffSeconds = 1

        let transcription = text.lowercased()
        guard !transcription.isEmpty else { return }
        lastRecognizedText = transcription
        // Debug level, so it costs nothing until someone runs `log stream`.
        logger.debug("heard: \(transcription, privacy: .public)")

        // Add to buffer
        recognizedTextBuffer.append(transcription)
        if recognizedTextBuffer.count > bufferSize {
            recognizedTextBuffer.removeFirst()
        }

        // Check for wake word in the most recent transcriptions
        let recentText = recognizedTextBuffer.suffix(3).joined(separator: " ")

        if let lastDetectionAt, Date().timeIntervalSince(lastDetectionAt) < detectionCooldown {
            return
        }

        if Self.detectWakeWord(wakeWord, in: recentText) {
            logger.notice("🎯 Wake word detected: '\(self.wakeWord)'")
            handleWakeWordDetection()
        }
    }

    nonisolated static func detectWakeWord(_ wakeWord: String, in text: String) -> Bool {
        let normalizedText = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let normalizedWakeWord = wakeWord.lowercased()
        guard !normalizedWakeWord.isEmpty else { return false }

        // Direct match
        if normalizedText.contains(normalizedWakeWord) {
            return true
        }

        // Fuzzy match for potential recognition errors
        let words = normalizedText.components(separatedBy: .whitespaces)
        for word in words where !word.isEmpty {
            if levenshteinDistance(word, normalizedWakeWord) <= 2 {
                return true
            }
        }

        return false
    }

    // Simple Levenshtein distance for fuzzy matching
    nonisolated static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let s1Count = s1Array.count
        let s2Count = s2Array.count

        guard s1Count > 0 else { return s2Count }
        guard s2Count > 0 else { return s1Count }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: s2Count + 1), count: s1Count + 1)

        for i in 0...s1Count {
            matrix[i][0] = i
        }
        for j in 0...s2Count {
            matrix[0][j] = j
        }

        for i in 1...s1Count {
            for j in 1...s2Count {
                let cost = s1Array[i-1] == s2Array[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,
                    matrix[i][j-1] + 1,
                    matrix[i-1][j-1] + cost
                )
            }
        }

        return matrix[s1Count][s2Count]
    }

    private func handleWakeWordDetection() {
        // Clear buffer to prevent immediate re-triggering
        recognizedTextBuffer.removeAll()
        lastDetectionAt = Date()
        lastRecognizedText = ""

        // When the word also ends dictation, the detector has to keep the
        // microphone through the recording - stopping here is what makes the
        // second "лошадка" impossible to hear.
        guard !stopsRecording else {
            // Forget the audio and the transcript that triggered this, or the
            // word keeps reappearing in every later result and stops the
            // dictation it just started. Clearing `recognizedTextBuffer` above
            // is not enough: both backends keep reporting a growing utterance
            // from its beginning, so the word comes straight back.
            if let localRecognizer {
                Task { await localRecognizer.consumeSegment() }
            }
            if recognitionRequest != nil {
                // Apple's request accumulates one transcript for the whole
                // ~50 s session, and there is no way to truncate it - only a
                // fresh session forgets the word.
                scheduleRestart(after: 1, reason: "wake word consumed")
            }
            onWakeWordDetected?()
            return
        }

        // Stop listening temporarily
        Task {
            await stopListening()

            // Trigger callback
            onWakeWordDetected?()
        }
    }

    // MARK: - Cleanup

    deinit {
        pendingRestartTask?.cancel()
        levelReportTask?.cancel()
        startTask?.cancel()
        recognitionTask?.cancel()
        if let capture {
            capture.onAudioChunk = nil
            capture.teardown()
        }
        if let localRecognizer {
            Task { await localRecognizer.stop() }
        }
        recognitionRequest?.endAudio()
        if let observer = deviceChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

// MARK: - Error Types

enum WakeWordError: LocalizedError {
    case recognizerNotAvailable
    case audioEngineFailure
    case permissionDenied
    case microphoneUnavailable

    var errorDescription: String? {
        switch self {
        case .recognizerNotAvailable:
            return "Speech recognizer is not available for the selected language"
        case .audioEngineFailure:
            return "Failed to start audio engine"
        case .permissionDenied:
            return "Speech recognition permission denied"
        case .microphoneUnavailable:
            return "The selected wake word microphone is not connected"
        }
    }
}
