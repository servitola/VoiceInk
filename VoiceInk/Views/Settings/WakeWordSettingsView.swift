import SwiftUI
import SwiftData

struct WakeWordSettingsView: View {
    @EnvironmentObject private var voiceInkEngine: VoiceInkEngine
    @AppStorage("isWakeWordEnabled") private var isWakeWordEnabled = false
    @AppStorage("wakeWord") private var wakeWord = "лошадка"
    @AppStorage("wakeWordLanguage") private var wakeWordLanguage = "ru-RU"
    @AppStorage("removeWakeWordFromTranscription") private var removeWakeWordFromTranscription = true
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
                languageSection
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

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Options")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 12) {
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

    private func handleWakeWordToggle(enabled: Bool) {
        Task {
            if enabled {
                // Request speech recognition permissions first
                let hasPermission = await voiceInkEngine.requestWakeWordPermissions()
                if hasPermission {
                    await voiceInkEngine.startWakeWordListening()
                } else {
                    // Permission denied, revert toggle
                    await MainActor.run {
                        isWakeWordEnabled = false
                    }
                }
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
