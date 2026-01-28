import SwiftUI
import Cocoa
import KeyboardShortcuts
import LaunchAtLogin
import AVFoundation

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var updaterViewModel: UpdaterViewModel
    @EnvironmentObject private var menuBarManager: MenuBarManager
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @EnvironmentObject private var recorderUIManager: RecorderUIManager
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @StateObject private var deviceManager = AudioDeviceManager.shared
    @ObservedObject private var soundManager = SoundManager.shared
    @ObservedObject private var mediaController = MediaController.shared
    @ObservedObject private var playbackController = PlaybackController.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @AppStorage("autoUpdateCheck") private var autoUpdateCheck = true
    @AppStorage("enableAnnouncements") private var enableAnnouncements = true
    @AppStorage("restoreClipboardAfterPaste") private var restoreClipboardAfterPaste = true
    @AppStorage("clipboardRestoreDelay") private var clipboardRestoreDelay = 2.0
    @AppStorage("useAppleScriptPaste") private var useAppleScriptPaste = false
    @State private var showResetOnboardingAlert = false
    @State private var currentShortcut = KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder)
    @State private var isCustomCancelEnabled = KeyboardShortcuts.getShortcut(for: .cancelRecorder) != nil

    // Expansion states - all collapsed by default
    @State private var isCustomCancelExpanded = false
    @State private var isMiddleClickExpanded = false
    @State private var isSoundFeedbackExpanded = false
    @State private var isMuteSystemExpanded = false
    @State private var isRestoreClipboardExpanded = false

    var body: some View {
        Form {
            // MARK: - Shortcuts
            Section {
                LabeledContent("Shortcut 1") {
                    HStack(spacing: 8) {
                        Spacer()
                        if hotkeyManager.selectedHotkey1 != .none {
                            hotkeyModePicker(binding: $hotkeyManager.hotkeyMode1)
                        }
                        hotkeyPicker(binding: $hotkeyManager.selectedHotkey1)
                        if hotkeyManager.selectedHotkey1 == .custom {
                            KeyboardShortcuts.Recorder(for: .toggleMiniRecorder)
                                .controlSize(.small)
                        }
                    }
                }

                if hotkeyManager.selectedHotkey2 != .none {
                    LabeledContent("Shortcut 2") {
                        HStack(spacing: 8) {
                            Spacer()
                            hotkeyModePicker(binding: $hotkeyManager.hotkeyMode2)
                            hotkeyPicker(binding: $hotkeyManager.selectedHotkey2)
                            if hotkeyManager.selectedHotkey2 == .custom {
                                KeyboardShortcuts.Recorder(for: .toggleMiniRecorder2)
                                    .controlSize(.small)
                            }
                        }
                        .onChange(of: isCustomCancelEnabled) { _, newValue in
                            if !newValue {
                                KeyboardShortcuts.setShortcut(nil, for: .cancelRecorder)
                            }
                        }

                        Divider()

                        ExpandableToggleSection(
                            section: .middleClick,
                            title: "Enable Middle-Click Toggle",
                            helpText: "Use middle mouse button to toggle VoiceInk recording.",
                            isEnabled: $hotkeyManager.isMiddleClickToggleEnabled,
                            expandedSections: $expandedSections
                        ) {
                            HStack(spacing: 8) {
                                Text("Activation Delay")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)

                                TextField("", value: $hotkeyManager.middleClickActivationDelay, formatter: {
                                    let formatter = NumberFormatter()
                                    formatter.numberStyle = .none
                                    formatter.minimum = 0
                                    return formatter
                                }())
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6))
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(5)
                                .frame(width: 70)

                                Text("ms")
                                    .foregroundColor(.secondary)

                                Spacer()
                            }
                        }
                    }
                }

                SettingsSection(
                    icon: "speaker.wave.2.bubble.left.fill",
                    title: "Recording Feedback",
                    subtitle: "Customize app & system feedback"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        ExpandableToggleSection(
                            section: .soundFeedback,
                            title: "Sound feedback",
                            helpText: "Play sounds when recording starts and stops",
                            isEnabled: $soundManager.isEnabled,
                            expandedSections: $expandedSections
                        ) {
                            CustomSoundSettingsView()
                        }

                        Divider()

                        ExpandableToggleSection(
                            section: .systemMute,
                            title: "Mute system audio during recording",
                            helpText: "Automatically mute system audio when recording starts and restore when recording stops",
                            isEnabled: $mediaController.isSystemMuteEnabled,
                            expandedSections: $expandedSections
                        ) {
                            HStack(spacing: 8) {
                                Text("Resume Delay")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)

                                Picker("", selection: $mediaController.audioResumptionDelay) {
                                    Text("0s").tag(0.0)
                                    Text("1s").tag(1.0)
                                    Text("2s").tag(2.0)
                                    Text("3s").tag(3.0)
                                    Text("4s").tag(4.0)
                                    Text("5s").tag(5.0)
                                }
                                .pickerStyle(.menu)
                                .frame(width: 80)

                                InfoTip(
                                    title: "Audio Resume Delay",
                                    message: "Delay before unmuting system audio after recording stops. Useful for Bluetooth headphones that need time to switch from microphone mode back to high-quality audio mode. Recommended: 2s for AirPods/Bluetooth headphones, 0s for wired headphones."
                                )

                                Spacer()
                            }
                        }

                        Divider()

                        ExpandableToggleSection(
                            section: .clipboardRestore,
                            title: "Restore clipboard after paste",
                            helpText: "When enabled, VoiceInk will restore your original clipboard content after pasting the transcription.",
                            isEnabled: $restoreClipboardAfterPaste,
                            expandedSections: $expandedSections
                        ) {
                            HStack(spacing: 8) {
                                Text("Restore Delay")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)

                                Picker("", selection: $clipboardRestoreDelay) {
                                    Text("1s").tag(1.0)
                                    Text("2s").tag(2.0)
                                    Text("3s").tag(3.0)
                                    Text("4s").tag(4.0)
                                    Text("5s").tag(5.0)
                                }
                                .pickerStyle(.menu)
                                .frame(width: 80)

                                Spacer()
                            }
                        }

                    }
                }

                SettingsSection(
                    icon: "waveform.badge.mic",
                    title: "Wake Word Detection",
                    subtitle: "Activate recording with a voice command"
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Enable continuous listening for a wake word to start recording hands-free.")
                            .settingsDescription()

                        NavigationLink(destination: WakeWordSettingsView()) {
                            Text("Configure Wake Word")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                PowerModeSettingsSection()

                ExperimentalFeaturesSection()

                SettingsSection(
                    icon: "doc.on.clipboard",
                    title: "Paste Method",
                    subtitle: "Choose how text is pasted"
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select the method used to paste text. Use AppleScript if you have a non-standard keyboard layout.")
                            .settingsDescription()

                        Toggle("Use AppleScript Paste Method", isOn: Binding(
                            get: { UserDefaults.standard.bool(forKey: "UseAppleScriptPaste") },
                            set: { UserDefaults.standard.set($0, forKey: "UseAppleScriptPaste") }
                        ))
                        .toggleStyle(.switch)
                    }
                }

                SettingsSection(
                    icon: "gear",
                    title: "General",
                    subtitle: "Appearance, startup, and updates"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Hide Dock Icon (Menu Bar Only)", isOn: $menuBarManager.isMenuBarOnly)
                            .toggleStyle(.switch)
                        
                        LaunchAtLogin.Toggle()
                            .toggleStyle(.switch)

                        Toggle("Enable automatic update checks", isOn: $autoUpdateCheck)
                            .toggleStyle(.switch)
                            .onChange(of: autoUpdateCheck) { _, newValue in
                                updaterViewModel.toggleAutoUpdates(newValue)
                            }
                        
                        Toggle("Show app announcements", isOn: $enableAnnouncements)
                            .toggleStyle(.switch)
                            .onChange(of: enableAnnouncements) { _, newValue in
                                if newValue {
                                    AnnouncementsService.shared.start()
                                } else {
                                    AnnouncementsService.shared.stop()
                                }
                            }
                        
                        Button("Check for Updates Now") {
                            updaterViewModel.checkForUpdates()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(!updaterViewModel.canCheckForUpdates)
                        
                        Divider()

                        Button("Reset Onboarding") {
                            showResetOnboardingAlert = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }

                SettingsSection(
                    icon: "lock.shield",
                    title: "Data & Privacy",
                    subtitle: "Control transcript history and storage"
                ) {
                    AudioCleanupSettingsView()
                }
                
                SettingsSection(
                    icon: "arrow.up.arrow.down.circle",
                    title: "Data Management",
                    subtitle: "Import or export your settings"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Export your custom prompts, power modes, word replacements, keyboard shortcuts, and app preferences to a backup file. API keys are not included in the export.")
                            .settingsDescription()

                        HStack(spacing: 12) {
                            Button {
                                withAnimation { hotkeyManager.selectedHotkey2 = .none }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if hotkeyManager.selectedHotkey1 != .none && hotkeyManager.selectedHotkey2 == .none {
                    Button("Add Second Shortcut") {
                        withAnimation { hotkeyManager.selectedHotkey2 = .rightOption }
                    }
                }
            } header: {
                Text("Shortcuts")
            }

            // MARK: - Additional Shortcuts
            Section("Additional Shortcuts") {
                LabeledContent("Paste Last Transcription (Original)") {
                    KeyboardShortcuts.Recorder(for: .pasteLastTranscription)
                        .controlSize(.small)
                }

                LabeledContent("Paste Last Transcription (Enhanced)") {
                    KeyboardShortcuts.Recorder(for: .pasteLastEnhancement)
                        .controlSize(.small)
                }

                LabeledContent("Retry Last Transcription") {
                    KeyboardShortcuts.Recorder(for: .retryLastTranscription)
                        .controlSize(.small)
                }

                // Custom Cancel - hierarchical
                ExpandableSettingsRow(
                    isExpanded: $isCustomCancelExpanded,
                    isEnabled: $isCustomCancelEnabled,
                    label: "Custom Cancel Shortcut"
                ) {
                    LabeledContent("Shortcut") {
                        KeyboardShortcuts.Recorder(for: .cancelRecorder)
                            .controlSize(.small)
                    }
                }
                .onChange(of: isCustomCancelEnabled) { _, newValue in
                    if !newValue {
                        KeyboardShortcuts.setShortcut(nil, for: .cancelRecorder)
                        isCustomCancelExpanded = false
                    }
                }

                // Middle-Click
                ExpandableSettingsRow(
                    isExpanded: $isMiddleClickExpanded,
                    isEnabled: $hotkeyManager.isMiddleClickToggleEnabled,
                    label: "Middle-Click Recording"
                ) {
                    LabeledContent("Activation Delay") {
                        HStack {
                            TextField("", value: $hotkeyManager.middleClickActivationDelay, formatter: {
                                let formatter = NumberFormatter()
                                formatter.minimum = 0
                                return formatter
                            }())
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                            Text("ms")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // MARK: - Recording Feedback
            Section("Recording Feedback") {
                // Sound Feedback
                ExpandableSettingsRow(
                    isExpanded: $isSoundFeedbackExpanded,
                    isEnabled: $soundManager.isEnabled,
                    label: "Sound Feedback"
                ) {
                    CustomSoundSettingsView()
                }

                // Mute System Audio
                ExpandableSettingsRow(
                    isExpanded: $isMuteSystemExpanded,
                    isEnabled: $mediaController.isSystemMuteEnabled,
                    label: "Mute Audio While Recording"
                ) {
                    Picker("Resume Delay", selection: $mediaController.audioResumptionDelay) {
                        Text("0s").tag(0.0)
                        Text("1s").tag(1.0)
                        Text("2s").tag(2.0)
                        Text("3s").tag(3.0)
                        Text("4s").tag(4.0)
                        Text("5s").tag(5.0)
                    }
                }

                // Restore Clipboard
                ExpandableSettingsRow(
                    isExpanded: $isRestoreClipboardExpanded,
                    isEnabled: $restoreClipboardAfterPaste,
                    label: "Restore Clipboard After Paste"
                ) {
                    Picker("Restore Delay", selection: $clipboardRestoreDelay) {
                        Text("250ms").tag(0.25)
                        Text("500ms").tag(0.5)
                        Text("1s").tag(1.0)
                        Text("2s").tag(2.0)
                        Text("3s").tag(3.0)
                        Text("4s").tag(4.0)
                        Text("5s").tag(5.0)
                    }
                }

                // AppleScript Paste
                Toggle(isOn: $useAppleScriptPaste) {
                    HStack(spacing: 4) {
                        Text("Use AppleScript Paste")
                        InfoTip("Enable this if pasting doesn't work with your keyboard layout (e.g. Neo2). Uses AppleScript instead of simulated key events.")
                    }
                }
            }

            // MARK: - Power Mode
            PowerModeSection()

            // MARK: - Interface
            Section("Interface") {
                Picker("Recorder Style", selection: $recorderUIManager.recorderType) {
                    Text("Notch").tag("notch")
                    Text("Mini").tag("mini")
                }
                .pickerStyle(.segmented)

            }

            // MARK: - Experimental
            ExperimentalSection()

            // MARK: - General
            Section("General") {
                Toggle("Hide Dock Icon", isOn: $menuBarManager.isMenuBarOnly)

                LaunchAtLogin.Toggle("Launch at Login")

                Toggle("Auto-check Updates", isOn: $autoUpdateCheck)
                    .onChange(of: autoUpdateCheck) { _, newValue in
                        updaterViewModel.toggleAutoUpdates(newValue)
                    }

                Toggle("Show Announcements", isOn: $enableAnnouncements)
                    .onChange(of: enableAnnouncements) { _, newValue in
                        if newValue {
                            AnnouncementsService.shared.start()
                        } else {
                            AnnouncementsService.shared.stop()
                        }
                    }

                HStack {
                    Button("Check for Updates") {
                        updaterViewModel.checkForUpdates()
                    }
                    .disabled(!updaterViewModel.canCheckForUpdates)

                    Button("Reset Onboarding") {
                        showResetOnboardingAlert = true
                    }
                }
            }

            // MARK: - Privacy
            Section {
                AudioCleanupSettingsView()
            } header: {
                Text("Privacy")
            } footer: {
                Text("Control how VoiceInk handles your transcription data and audio recordings.")
            }

            // MARK: - Backup
            Section {
                LabeledContent("Export Settings") {
                    Button("Export") {
                        ImportExportService.shared.exportSettings(
                            enhancementService: enhancementService,
                            whisperPrompt: WhisperPrompt(),
                            hotkeyManager: hotkeyManager,
                            menuBarManager: menuBarManager,
                            mediaController: mediaController,
                            playbackController: playbackController,
                            soundManager: soundManager,
                            recorderUIManager: recorderUIManager,
                            modelContext: modelContext
                        )
                    }
                }

                LabeledContent("Import Settings") {
                    Button("Import") {
                        ImportExportService.shared.importSettings(
                            enhancementService: enhancementService,
                            whisperPrompt: WhisperPrompt(),
                            hotkeyManager: hotkeyManager,
                            menuBarManager: menuBarManager,
                            mediaController: mediaController,
                            playbackController: playbackController,
                            soundManager: soundManager,
                            recorderUIManager: recorderUIManager,
                            modelContext: modelContext,
                            transcriptionModelManager: transcriptionModelManager
                        )
                    }
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("Export or import all your settings, prompts, power modes, dictionary, and custom models.")
            }

            // MARK: - Diagnostics
            Section("Diagnostics") {
                DiagnosticsSettingsView()
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(NSColor.controlBackgroundColor))
        .alert("Reset Onboarding", isPresented: $showResetOnboardingAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                DispatchQueue.main.async {
                    hasCompletedOnboarding = false
                }
            }
        } message: {
            Text("You'll see the introduction screens again the next time you launch the app.")
        }
    }

    @ViewBuilder
    private func hotkeyPicker(binding: Binding<HotkeyManager.HotkeyOption>) -> some View {
        Picker("", selection: binding) {
            ForEach(HotkeyManager.HotkeyOption.allCases, id: \.self) { option in
                Text(option.displayName).tag(option)
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    @ViewBuilder
    private func hotkeyModePicker(binding: Binding<HotkeyManager.HotkeyMode>) -> some View {
        Picker("", selection: binding) {
            ForEach(HotkeyManager.HotkeyMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .labelsHidden()
        .fixedSize()
    }
}

// MARK: - Expandable Settings Row (entire row clickable)

struct ExpandableSettingsRow<Content: View>: View {
    @Binding var isExpanded: Bool
    @Binding var isEnabled: Bool
    let label: String
    var infoMessage: String? = nil
    var infoURL: String? = nil
    @ViewBuilder let content: () -> Content

    @State private var isHandlingToggleChange = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row - entire area is tappable
            HStack {
                Toggle(isOn: $isEnabled) {
                    HStack(spacing: 4) {
                        Text(label)
                        if let message = infoMessage {
                            if let url = infoURL {
                                InfoTip(message, learnMoreURL: url)
                            } else {
                                InfoTip(message)
                            }
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isEnabled && isExpanded ? 90 : 0))
                    .opacity(isEnabled ? 1 : 0.4)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isHandlingToggleChange else { return }
                if isEnabled {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
            }

            // Expanded content with proper spacing
            if isEnabled && isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    content()
                }
                .padding(.top, 12)
                .padding(.leading, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .onChange(of: isEnabled) { _, newValue in
            isHandlingToggleChange = true
            if newValue {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = true
                }
            } else {
                isExpanded = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isHandlingToggleChange = false
            }
        }
    }
}

// MARK: - Power Mode Section

struct PowerModeSection: View {
    @ObservedObject private var powerModeManager = PowerModeManager.shared
    @AppStorage("powerModeUIFlag") private var powerModeUIFlag = false
    @AppStorage("powerModePersistConfig") private var powerModePersistSettings = false
    @State private var showDisableAlert = false
    @State private var isExpanded = false

    var body: some View {
        Section {
            ExpandableSettingsRow(
                isExpanded: $isExpanded,
                isEnabled: toggleBinding,
                label: "Power Mode",
                infoMessage: "Apply custom settings based on active app or website.",
                infoURL: "https://tryvoiceink.com/docs/power-mode"
            ) {
                Toggle(isOn: $powerModePersistSettings) {
                    HStack(spacing: 4) {
                        Text("Persist Configured Preferences")
                        InfoTip("When enabled, Power Mode preferences stay active after you stop recording instead of reverting to your original preferences. They will only change when a different Power Mode activates.")
                    }
                }
            }
        } header: {
            Text("Power Mode")
        }
        .alert("Power Mode Still Active", isPresented: $showDisableAlert) {
            Button("Got it", role: .cancel) { }
        } message: {
            Text("Disable or remove your Power Modes first.")
        }
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { powerModeUIFlag },
            set: { newValue in
                if newValue {
                    powerModeUIFlag = true
                } else if powerModeManager.configurations.allSatisfy({ !$0.isEnabled }) {
                    powerModeUIFlag = false
                } else {
                    showDisableAlert = true
                }
            }
        )
    }
}

// MARK: - Experimental Section

struct ExperimentalSection: View {
    @ObservedObject private var playbackController = PlaybackController.shared
    @ObservedObject private var mediaController = MediaController.shared
    @State private var isPauseMediaExpanded = false

    var body: some View {
        Section {
            ExpandableSettingsRow(
                isExpanded: $isPauseMediaExpanded,
                isEnabled: $playbackController.isPauseMediaEnabled,
                label: "Pause Media While Recording",
                infoMessage: "Pauses playing media when recording starts and resumes when done."
            ) {
                Picker("Resume Delay", selection: $mediaController.audioResumptionDelay) {
                    Text("0s").tag(0.0)
                    Text("1s").tag(1.0)
                    Text("2s").tag(2.0)
                    Text("3s").tag(3.0)
                    Text("4s").tag(4.0)
                    Text("5s").tag(5.0)
                }
            }
        } header: {
            Text("Experimental")
        }
    }
}

// MARK: - Text Extension

extension Text {
    func settingsDescription() -> some View {
        self
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

