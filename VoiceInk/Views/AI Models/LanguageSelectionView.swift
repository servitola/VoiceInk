import SwiftUI

// Define a display mode for flexible usage
enum LanguageDisplayMode {
    case full  // For settings page with descriptions
    case menuItem  // For menu bar with compact layout
}

struct LanguageSelectionView: View {
    @ObservedObject var transcriptionModelManager: TranscriptionModelManager
    @State private var selectedLanguages: [String] = UserDefaults.standard.selectedLanguages
    // Add display mode parameter with full as the default
    var displayMode: LanguageDisplayMode = .full
    @ObservedObject var whisperPrompt: WhisperPrompt

    private func updateLanguages(_ languages: [String]) {
        let normalized = languages.isEmpty ? ["en"] : languages
        guard normalized != selectedLanguages else { return }

        selectedLanguages = normalized

        // Save to UserDefaults
        UserDefaults.standard.selectedLanguages = selectedLanguages

        // Force the prompt to update for the new languages
        whisperPrompt.updateTranscriptionPrompt()

        // Post notification for language change
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    private func toggleLanguage(_ languageCode: String) {
        var newLanguages = selectedLanguages
        if let index = newLanguages.firstIndex(of: languageCode) {
            // Don't allow deselecting if it's the only language
            if newLanguages.count > 1 {
                newLanguages.remove(at: index)
            }
        } else {
            newLanguages.append(languageCode)
        }
        updateLanguages(newLanguages)
    }

    // Function to check if current model is multilingual
    private func isMultilingualModel() -> Bool {
        guard let currentModel = transcriptionModelManager.currentTranscriptionModel else {
            return false
        }
        return currentModel.isMultilingualModel
    }

    private func languageSelectionDisabled() -> Bool {
        guard let provider = transcriptionModelManager.currentTranscriptionModel?.provider else {
            return false
        }
        return provider == .gemini
    }

    private func isNativeAppleModelSelected() -> Bool {
        transcriptionModelManager.currentTranscriptionModel?.provider == .nativeApple
    }

    private func availableLanguagesForCurrentModel() -> [String: String] {
        guard let currentModel = transcriptionModelManager.currentTranscriptionModel else {
            return ["en": "English"]  // Default to English if no model found
        }
        return TranscriptionLanguageSupport.languages(for: currentModel)
    }

    private func useCompatibleLanguageForCurrentModel() {
        guard let currentModel = transcriptionModelManager.currentTranscriptionModel else { return }
        let available = TranscriptionLanguageSupport.languages(for: currentModel)
        let kept = selectedLanguages.filter { available.keys.contains($0) }
        if kept.isEmpty {
            updateLanguages([TranscriptionLanguageSupport.validLanguageOrFallback(selectedLanguages.first ?? "en", for: currentModel)])
        } else if kept != selectedLanguages {
            updateLanguages(kept)
        }
    }

    // Get the display name of the current languages
    private func currentLanguagesDisplayName() -> String {
        let languages = availableLanguagesForCurrentModel()
        let names = selectedLanguages.compactMap { languages[$0] }
        if names.isEmpty {
            return "Unknown"
        } else if names.count == 1 {
            return names[0]
        } else if names.count == 2 {
            return names.joined(separator: " + ")
        } else {
            return "\(names.count) languages"
        }
    }

    private var nativeAppleAssetControl: some View {
        NativeAppleLanguageAssetControl(
            localeIdentifier: selectedLanguages.first ?? "en",
            isVisible: true
        )
        .layoutPriority(1)
    }

    var body: some View {
        Group {
            switch displayMode {
            case .full:
                fullView
            case .menuItem:
                menuItemView
            }
        }
        .onAppear {
            useCompatibleLanguageForCurrentModel()
        }
        .onChange(of: transcriptionModelManager.currentTranscriptionModel?.name) { _, _ in
            useCompatibleLanguageForCurrentModel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AppSettingsDidChange)) { _ in
            useCompatibleLanguageForCurrentModel()
        }
    }

    // The original full view layout for settings page
    private var fullView: some View {
        VStack(alignment: .leading, spacing: 16) {
            languageSelectionSection
        }
    }

    private var languageSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcription Language")
                .font(.headline)

            if transcriptionModelManager.currentTranscriptionModel != nil {
                if languageSelectionDisabled() {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Language: Autodetected")
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        Text("The transcription language is automatically detected by the model.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .disabled(true)
                } else if isMultilingualModel() {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Select Languages")
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        if isNativeAppleModelSelected() {
                            nativeAppleAssetControl
                        }

                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(
                                    availableLanguagesForCurrentModel().sorted(by: {
                                        if $0.key == "auto" { return true }
                                        if $1.key == "auto" { return false }
                                        return $0.value < $1.value
                                    }), id: \.key
                                ) { key, value in
                                    Toggle(isOn: Binding(
                                        get: { selectedLanguages.contains(key) },
                                        set: { _ in toggleLanguage(key) }
                                    )) {
                                        Text(value)
                                            .font(.body)
                                    }
                                    .toggleStyle(.checkbox)
                                }
                            }
                        }
                        .frame(maxHeight: 300)

                        Text("Selected: \(currentLanguagesDisplayName())")
                            .font(.caption)
                            .foregroundColor(.blue)

                        Text(
                            "This model supports multiple languages. Select one or more languages for transcription."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                } else {
                    // For English-only models, force set language to English
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Language: English")
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        Text(
                            "This is an English-optimized model and only supports English transcription."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .onAppear {
                        // Ensure English is set when viewing English-only model
                        updateLanguages(["en"])
                    }
                }
            } else {
                Text("No model selected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Surface.control)
        .cornerRadius(10)
    }

    // New compact view for menu bar
    private var menuItemView: some View {
        Group {
            if languageSelectionDisabled() {
                Button {
                    // Do nothing, just showing info
                } label: {
                    Text("Language: Autodetected")
                        .foregroundColor(.secondary)
                }
                .disabled(true)
            } else if isMultilingualModel() {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(
                            availableLanguagesForCurrentModel().sorted(by: {
                                if $0.key == "auto" { return true }
                                if $1.key == "auto" { return false }
                                return $0.value < $1.value
                            }), id: \.key
                        ) { key, value in
                            Button {
                                toggleLanguage(key)
                            } label: {
                                HStack {
                                    Text(value)
                                    if selectedLanguages.contains(key) {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(String(format: String(localized: "Languages: %@"), currentLanguagesDisplayName()))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10))
                        }
                    }

                    if isNativeAppleModelSelected() {
                        nativeAppleAssetControl
                    }
                }
            } else {
                // For English-only models
                Button {
                    // Do nothing, just showing info
                } label: {
                    Text("Language: English (only)")
                        .foregroundColor(.secondary)
                }
                .disabled(true)
                .onAppear {
                    // Ensure English is set for English-only models
                    updateLanguages(["en"])
                }
            }
        }
    }
}
