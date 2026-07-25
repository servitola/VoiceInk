import SwiftUI
import SwiftData

struct WakeWordSettingsView: View {
    @EnvironmentObject private var voiceInkEngine: VoiceInkEngine
    @ObservedObject private var audioDeviceManager = AudioDeviceManager.shared
    @AppStorage("isWakeWordEnabled") private var isWakeWordEnabled = false
    @AppStorage("wakeWord") private var wakeWord = "лошадка"
    @AppStorage("wakeWordLanguage") private var wakeWordLanguage = "ru-RU"
    @AppStorage("wakeWordMicrophoneUID") private var wakeWordMicrophoneUID = ""
    @AppStorage("wakeWordEngine") private var wakeWordEngine = WakeWordEngineKind.localModel.rawValue
    @AppStorage("wakeWordModelName") private var wakeWordModelName = ""
    @AppStorage("removeWakeWordFromTranscription") private var removeWakeWordFromTranscription = true
    @AppStorage("wakeWordStopsRecording") private var wakeWordStopsRecording = true
    @Environment(\.colorScheme) private var colorScheme

    @State private var tempWakeWord: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroSection
                mainContent
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            tempWakeWord = wakeWord
        }
    }

    private var mainContent: some View {
        VStack(spacing: 40) {
            enableSection

            if isWakeWordEnabled {
                wakeWordConfigSection
                engineSection
                languageSection
                microphoneSection
                optionsSection
                statusSection
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 40)
    }

    private var heroSection: some View {
        CompactHeroSection(
            icon: "waveform.badge.mic",
            title: "Wake Word Detection",
            description: "Activate recording with a voice command"
        )
    }

    private var enableSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enable Wake Word Mode")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("VoiceInk will continuously listen for your wake word in the background")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Toggle("", isOn: $isWakeWordEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: isWakeWordEnabled) { _, newValue in
                        handleWakeWordToggle(enabled: newValue)
                    }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            )
        }
    }

    private var wakeWordConfigSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Wake Word")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "text.quote")
                        .foregroundColor(.secondary)

                    TextField("Enter wake word...", text: $tempWakeWord)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            updateWakeWord()
                        }

                    if tempWakeWord != wakeWord {
                        Button("Save") {
                            updateWakeWord()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Text("Example: Say \"\(wakeWord), write an email\" to start recording")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 28)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            )
        }
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Recognition Language")
                .font(.title2)
                .fontWeight(.semibold)

            HStack {
                Image(systemName: "globe")
                    .foregroundColor(.secondary)

                Picker("Language", selection: $wakeWordLanguage) {
                    Text("Russian (Русский)").tag("ru-RU")
                    Text("English (US)").tag("en-US")
                    Text("English (UK)").tag("en-GB")
                    Text("Spanish (Español)").tag("es-ES")
                    Text("French (Français)").tag("fr-FR")
                    Text("German (Deutsch)").tag("de-DE")
                    Text("Italian (Italiano)").tag("it-IT")
                    Text("Portuguese (Português)").tag("pt-BR")
                    Text("Chinese (中文)").tag("zh-CN")
                    Text("Japanese (日本語)").tag("ja-JP")
                    Text("Korean (한국어)").tag("ko-KR")
                }
                .labelsHidden()
                .onChange(of: wakeWordLanguage) { _, newValue in
                    voiceInkEngine.configureWakeWord(word: wakeWord, language: newValue)
                }

                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            )
        }
    }

    private var microphoneSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Microphone")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "mic")
                        .foregroundColor(.secondary)

                    Picker("Microphone", selection: $wakeWordMicrophoneUID) {
                        Text("Same as Recording").tag("")

                        ForEach(audioDeviceManager.availableDevices, id: \.uid) { device in
                            Text(device.name).tag(device.uid)
                        }

                        // Keep the saved choice selectable while it is unplugged,
                        // otherwise the picker renders blank and looks unset.
                        if isSavedMicrophoneDisconnected {
                            Text(
                                String(
                                    format: String(localized: "%@ (not connected)"),
                                    savedMicrophoneName
                                )
                            )
                            .tag(wakeWordMicrophoneUID)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: wakeWordMicrophoneUID) { _, newValue in
                        voiceInkEngine.configureWakeWordMicrophone(uid: newValue)
                    }

                    Spacer()

                    Button {
                        audioDeviceManager.loadAvailableDevices()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh Microphones")
                }

                Text("Choose which microphone listens for the wake word. \"Same as Recording\" follows your main audio input selection.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 28)

                if voiceInkEngine.wakeWordMicrophoneUnavailable {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)

                        Text("The selected microphone is not connected. Wake word detection is paused — it will not switch to another microphone on its own.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 28)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            )
        }
    }

    private var engineSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Recognition Engine")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "cpu")
                        .foregroundColor(.secondary)

                    Picker("Engine", selection: $wakeWordEngine) {
                        ForEach(WakeWordEngineKind.allCases) { kind in
                            Text(kind.displayName).tag(kind.rawValue)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: wakeWordEngine) { _, newValue in
                        guard let kind = WakeWordEngineKind(rawValue: newValue) else { return }
                        voiceInkEngine.configureWakeWordEngine(kind)
                    }

                    Spacer()
                }

                if wakeWordEngine == WakeWordEngineKind.localModel.rawValue {
                    HStack {
                        Image(systemName: "shippingbox")
                            .foregroundColor(.secondary)

                        Picker("Model", selection: $wakeWordModelName) {
                            ForEach(localWakeWordModels, id: \.name) { model in
                                Text(model.displayName).tag(model.name)
                            }
                        }
                        .labelsHidden()
                        .disabled(localWakeWordModels.isEmpty)
                        .onChange(of: wakeWordModelName) { _, newValue in
                            guard !newValue.isEmpty else { return }
                            voiceInkEngine.configureWakeWordModel(named: newValue)
                        }

                        Spacer()
                    }

                    if localWakeWordModels.isEmpty {
                        Text("No local model is downloaded. Download a Parakeet model on the AI Models page.")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.leading, 28)
                    } else {
                        Text("Runs entirely on this Mac. Speech detection gates the model, so it only transcribes when someone is actually talking.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 28)
                    }
                } else {
                    Text("Apple Speech runs on device only when macOS Dictation is enabled. Without it, audio is sent to Apple's servers the whole time it listens.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 28)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            )
        }
        .onAppear {
            // Default the picker to whatever is actually downloaded, so an
            // untouched setting still starts the engine.
            if wakeWordModelName.isEmpty, let first = localWakeWordModels.first {
                wakeWordModelName = first.name
                voiceInkEngine.configureWakeWordModel(named: first.name)
            }
        }
    }

    private var localWakeWordModels: [any TranscriptionModel] {
        voiceInkEngine.transcriptionModelManager.usableModels.filter {
            $0.provider == .fluidAudio && $0.name.hasPrefix("parakeet-tdt")
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Options")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Say it again to finish")
                            .font(.system(size: 14, weight: .medium))

                        Text("The wake word ends dictation too, exactly as pressing the shortcut a second time does. The detector keeps the microphone while recording so it can hear you.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Toggle("", isOn: $wakeWordStopsRecording)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .padding()

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Remove wake word from transcription")
                            .font(.system(size: 14, weight: .medium))

                        Text("The wake word will not appear in the final text")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $removeWakeWordFromTranscription)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .padding()
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            )
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Status")
                .font(.title2)
                .fontWeight(.semibold)

            HStack {
                HStack(spacing: 12) {
                    Circle()
                        .fill(voiceInkEngine.isWakeWordListening ? Color.green : Color.gray)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(voiceInkEngine.isWakeWordListening ? Color.green.opacity(0.3) : Color.clear, lineWidth: 4)
                                .scaleEffect(voiceInkEngine.isWakeWordListening ? 1.5 : 1.0)
                                .opacity(voiceInkEngine.isWakeWordListening ? 0 : 1)
                                .animation(
                                    voiceInkEngine.isWakeWordListening ?
                                        .easeOut(duration: 1.5).repeatForever(autoreverses: false) : .default,
                                    value: voiceInkEngine.isWakeWordListening
                                )
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(voiceInkEngine.isWakeWordListening ? "Listening" : "Inactive")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(voiceInkEngine.isWakeWordListening ? .green : .secondary)

                        Text(voiceInkEngine.isWakeWordListening ?
                             "Waiting for \"\(wakeWord)\"..." :
                             "Wake word detection is currently inactive"
                        )
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // The device actually bound by the audio engine, which is
                        // the only way to tell the picker took effect.
                        if voiceInkEngine.isWakeWordListening, let device = voiceInkEngine.wakeWordBoundDeviceName {
                            Text(String(format: String(localized: "Listening on: %@"), device))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // What the recogniser last produced. Without this the only
                        // symptom of a broken detector is silence, which looks
                        // identical whether the microphone, the recogniser or the
                        // word matching is at fault.
                        if voiceInkEngine.isWakeWordListening {
                            Text(voiceInkEngine.wakeWordLastRecognizedText.isEmpty
                                 ? String(localized: "Heard: nothing yet")
                                 : String(format: String(localized: "Heard: %@"), voiceInkEngine.wakeWordLastRecognizedText))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .truncationMode(.head)
                        }

                        if let failure = voiceInkEngine.wakeWordFailureMessage {
                            Text(failure)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }

                        if voiceInkEngine.wakeWordUsingServerRecognition {
                            Text("On-device recognition is unavailable, so audio is sent to Apple's servers while listening. Turn on System Settings → Keyboard → Dictation to keep it offline.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            )
        }
    }

    // MARK: - Helper Methods

    private var isSavedMicrophoneDisconnected: Bool {
        !wakeWordMicrophoneUID.isEmpty
            && !audioDeviceManager.availableDevices.contains(where: { $0.uid == wakeWordMicrophoneUID })
    }

    private var savedMicrophoneName: String {
        UserDefaults.standard.wakeWordMicrophoneName ?? String(localized: "Saved microphone")
    }

    private func handleWakeWordToggle(enabled: Bool) {
        Task {
            if enabled {
                // Speech Recognition authorization is Apple's recognizer only.
                // The local engine never touches the Speech framework, so asking
                // for it there would block offline detection on an unused grant.
                if wakeWordEngine == WakeWordEngineKind.appleSpeech.rawValue,
                    await !voiceInkEngine.requestWakeWordPermissions()
                {
                    await MainActor.run { isWakeWordEnabled = false }
                    return
                }
                await voiceInkEngine.startWakeWordListening()
            } else {
                await voiceInkEngine.stopWakeWordListening()
            }
        }
    }

    private func updateWakeWord() {
        let trimmed = tempWakeWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        wakeWord = trimmed
        tempWakeWord = trimmed
        voiceInkEngine.configureWakeWord(word: trimmed, language: wakeWordLanguage)
    }
}

// Preview requires a full VoiceInkEngine setup — omitted for brevity.
