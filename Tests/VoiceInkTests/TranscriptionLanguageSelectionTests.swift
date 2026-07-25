import Foundation
import Testing

@testable import VoiceInk

#if canImport(FluidAudio)
import FluidAudio
#endif

/// Covers the multi-language selection: clamping a selection to a model, reducing it for
/// single-locale backends, the Parakeet script reduction, and ModeConfig persistence.
struct TranscriptionLanguageSelectionTests {

    private func model(named name: String) -> any TranscriptionModel {
        guard let model = TranscriptionModelRegistry.models.first(where: { $0.name == name }) else {
            fatalError("Missing model \(name) in the registry")
        }
        return model
    }

    private var parakeetV3: any TranscriptionModel { model(named: "parakeet-tdt-0.6b-v3") }
    private var parakeetV2: any TranscriptionModel { model(named: "parakeet-tdt-0.6b-v2") }
    private var whisperLargeV3Turbo: any TranscriptionModel {
        guard let model = TranscriptionModelRegistry.models.first(where: {
            $0.provider == .whisper && $0.isMultilingualModel
        }) else {
            fatalError("Missing a multilingual whisper model in the registry")
        }
        return model
    }

    // MARK: - validLanguagesOrFallback

    @Test func keepsSupportedLanguagesInOrder() {
        let result = TranscriptionLanguageSupport.validLanguagesOrFallback(
            ["ru", "en", "el"], for: parakeetV3)
        #expect(result == ["ru", "en", "el"])
    }

    @Test func dropsLanguagesTheModelDoesNotSupport() {
        // Parakeet V3 covers European languages only — Japanese is not among them.
        let result = TranscriptionLanguageSupport.validLanguagesOrFallback(
            ["ru", "ja", "en"], for: parakeetV3)
        #expect(result == ["ru", "en"])
    }

    @Test func removesDuplicates() {
        let result = TranscriptionLanguageSupport.validLanguagesOrFallback(
            ["ru", "en", "ru"], for: parakeetV3)
        #expect(result == ["ru", "en"])
    }

    @Test func collapsesToAutoWhenAutoIsSelected() {
        let result = TranscriptionLanguageSupport.validLanguagesOrFallback(
            ["ru", "auto", "en"], for: parakeetV3)
        #expect(result == ["auto"])
    }

    @Test func neverReturnsEmpty() {
        #expect(!TranscriptionLanguageSupport.validLanguagesOrFallback([], for: parakeetV3).isEmpty)
        // Every pick unsupported -> falls back rather than yielding nothing.
        #expect(!TranscriptionLanguageSupport.validLanguagesOrFallback(["ja", "ko"], for: parakeetV3).isEmpty)
    }

    @Test func englishOnlyModelClampsToEnglish() {
        let result = TranscriptionLanguageSupport.validLanguagesOrFallback(
            ["ru", "el"], for: parakeetV2)
        #expect(result == ["en"])
    }

    // MARK: - singleLanguage

    @Test func singleSelectionPassesThrough() {
        let result = TranscriptionLanguageSupport.singleLanguage(from: ["ru"], for: parakeetV3)
        #expect(result == "ru")
    }

    @Test func multipleSelectionDegradesToAuto() {
        let result = TranscriptionLanguageSupport.singleLanguage(from: ["ru", "en", "el"], for: parakeetV3)
        #expect(result == "auto")
    }

    @Test func multipleSelectionWithoutAutoSupportTakesFirst() {
        // Parakeet V2 is English-only and offers no auto-detect entry.
        let result = TranscriptionLanguageSupport.singleLanguage(from: ["ru", "en"], for: parakeetV2)
        #expect(result == "en")
    }

    // MARK: - Parakeet script reduction

    #if canImport(FluidAudio)
    private let parakeetV3Name = "parakeet-tdt-0.6b-v3"

    @Test func singleLanguageMapsToItsOwnHint() {
        let hint = FluidAudioModelManager.languageHint(from: ["ru"], for: parakeetV3Name)
        #expect(hint == .russian)
    }

    @Test func sameScriptSelectionKeepsTheScriptFilter() {
        // ru + uk + bg are all Cyrillic, so the filter is still representable.
        let hint = FluidAudioModelManager.languageHint(from: ["ru", "uk", "bg"], for: parakeetV3Name)
        #expect(hint?.script == .cyrillic)
    }

    @Test func mixedScriptSelectionDisablesTheFilter() {
        // Russian (Cyrillic) + English (Latin) + Greek (Greek) spans every script Parakeet V3
        // emits, so there is nothing to filter — same behaviour as auto-detect.
        let hint = FluidAudioModelManager.languageHint(from: ["ru", "en", "el"], for: parakeetV3Name)
        #expect(hint == nil)
    }

    @Test func latinOnlySelectionKeepsLatinFilter() {
        let hint = FluidAudioModelManager.languageHint(from: ["en", "de", "fr"], for: parakeetV3Name)
        #expect(hint?.script == .latin)
    }

    @Test func autoDisablesTheFilter() {
        #expect(FluidAudioModelManager.languageHint(from: ["auto"], for: parakeetV3Name) == nil)
        #expect(FluidAudioModelManager.languageHint(from: ["ru", "auto"], for: parakeetV3Name) == nil)
    }

    @Test func emptySelectionDisablesTheFilter() {
        #expect(FluidAudioModelManager.languageHint(from: [], for: parakeetV3Name) == nil)
    }

    @Test func nonV3ParakeetIgnoresTheHint() {
        #expect(FluidAudioModelManager.languageHint(from: ["ru"], for: "parakeet-tdt-0.6b-v2") == nil)
        #expect(FluidAudioModelManager.languageHint(from: ["ru"], for: "parakeet-unified-0.6b") == nil)
        #expect(FluidAudioModelManager.languageHint(from: ["ru"], for: "nemotron-multilingual-0.6b") == nil)
    }
    #endif

    // MARK: - ModeConfig persistence

    private func decodeConfig(_ json: String) throws -> ModeConfig {
        try JSONDecoder().decode(ModeConfig.self, from: Data(json.utf8))
    }

    /// Everything ModeConfig decodes without a fallback. The rest is optional.
    private var requiredConfigFields: String {
        """
        "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
        "name": "Test",
        "isAIEnhancementEnabled": false
        """
    }

    @Test func decodesLegacySingularLanguage() throws {
        let config = try decodeConfig("{\(requiredConfigFields), \"selectedLanguage\": \"ru\"}")
        #expect(config.selectedLanguages == ["ru"])
        #expect(config.selectedLanguage == "ru")
    }

    @Test func decodesPluralLanguages() throws {
        let config = try decodeConfig("{\(requiredConfigFields), \"selectedLanguages\": [\"ru\", \"en\", \"el\"]}")
        #expect(config.selectedLanguages == ["ru", "en", "el"])
    }

    @Test func pluralWinsOverLegacySingular() throws {
        let config = try decodeConfig(
            "{\(requiredConfigFields), \"selectedLanguage\": \"en\", \"selectedLanguages\": [\"ru\", \"el\"]}")
        #expect(config.selectedLanguages == ["ru", "el"])
    }

    @Test func roundTripsMultipleLanguages() throws {
        var config = ModeConfig(name: "Test", isAIEnhancementEnabled: false)
        config.selectedLanguages = ["ru", "en", "el"]

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ModeConfig.self, from: data)

        #expect(decoded.selectedLanguages == ["ru", "en", "el"])
    }

    @Test func encodesSingularKeyForOlderBuilds() throws {
        var config = ModeConfig(name: "Test", isAIEnhancementEnabled: false)
        config.selectedLanguages = ["ru", "en"]

        let data = try JSONEncoder().encode(config)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["selectedLanguage"] as? String == "ru")
        #expect(json["selectedLanguages"] as? [String] == ["ru", "en"])
    }

    @Test func singularFacadeWritesThroughToPlural() {
        var config = ModeConfig(name: "Test", isAIEnhancementEnabled: false)
        config.selectedLanguages = ["ru", "en", "el"]

        config.selectedLanguage = "de"

        #expect(config.selectedLanguages == ["de"])
    }

    // MARK: - Draft toggling

    @MainActor
    @Test func toggleAddsAndRemovesLanguages() {
        var draft = makeDraft(languages: ["en"])

        draft.toggleLanguage("ru")
        #expect(draft.selectedLanguages == ["en", "ru"])

        draft.toggleLanguage("en")
        #expect(draft.selectedLanguages == ["ru"])
    }

    @MainActor
    @Test func toggleRefusesToEmptyTheSelection() {
        var draft = makeDraft(languages: ["ru"])

        draft.toggleLanguage("ru")

        #expect(draft.selectedLanguages == ["ru"])
    }

    @MainActor
    @Test func pickingAutoReplacesTheSelection() {
        var draft = makeDraft(languages: ["ru", "en"])

        draft.toggleLanguage("auto")

        #expect(draft.selectedLanguages == ["auto"])
    }

    @MainActor
    @Test func pickingALanguageClearsAuto() {
        var draft = makeDraft(languages: ["auto"])

        draft.toggleLanguage("ru")

        #expect(draft.selectedLanguages == ["ru"])
    }

    @MainActor
    private func makeDraft(languages: [String]) -> ModeConfigDraft {
        var draft = ModeConfigDraft(mode: .add, modeManager: ModeManager.shared)
        draft.selectedLanguages = languages
        return draft
    }
}
