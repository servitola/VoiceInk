import Testing
@testable import VoiceInk

struct WordReplacementServiceTests {
    private let service = WordReplacementService.shared

    // MARK: - Unicode word boundary

    @Test func doesNotReplaceInsideCyrillicWord() {
        // The bug: "клод" -> "Claude" was matching inside "клодеы",
        // producing "Claudeы" because the old boundary ([a-zA-Z0-9])
        // ignored Cyrillic letters.
        let out = service.applyReplacements(
            to: "у меня клодеы какие-то",
            rules: [("клод", "Claude")]
        )
        #expect(out == "у меня клодеы какие-то")
    }

    @Test func replacesStandaloneCyrillicWord() {
        let out = service.applyReplacements(
            to: "спросил клод вчера",
            rules: [("клод", "Claude")]
        )
        #expect(out == "спросил Claude вчера")
    }

    @Test func doesNotReplaceInsideGreekWord() {
        let out = service.applyReplacements(
            to: "καλόςμερα",
            rules: [("καλός", "good")]
        )
        #expect(out == "καλόςμερα")
    }

    @Test func doesNotReplaceInsideLatinWord() {
        let out = service.applyReplacements(
            to: "claudemorphism",
            rules: [("claude", "Claude")]
        )
        #expect(out == "claudemorphism")
    }

    // MARK: - Punctuation acts as boundary

    @Test func replacesNextToPunctuation() {
        let out = service.applyReplacements(
            to: "(клод), сказал он.",
            rules: [("клод", "Claude")]
        )
        #expect(out == "(Claude), сказал он.")
    }

    // MARK: - Case insensitivity

    @Test func caseInsensitiveMatch() {
        let out = service.applyReplacements(
            to: "КЛОД ответил",
            rules: [("клод", "Claude")]
        )
        #expect(out == "Claude ответил")
    }

    // MARK: - Comma-separated variants

    @Test func appliesAllCommaSeparatedVariants() {
        let out = service.applyReplacements(
            to: "клод и клауд и клот",
            rules: [("клод, клауд, клот", "Claude")]
        )
        #expect(out == "Claude и Claude и Claude")
    }

    // MARK: - Longest-first ordering within a variant group

    @Test func longerVariantWithinGroupReplacedFirst() {
        // Both variants live in the same rule, so the longer one ("клод код")
        // must run before the shorter "клод" — otherwise "клод" would eat the
        // prefix and leave " код" behind.
        let out = service.applyReplacements(
            to: "обсудил клод код вчера",
            rules: [("клод, клод код", "Claude Code")]
        )
        #expect(out == "обсудил Claude Code вчера")
    }

    // MARK: - Non-spaced scripts fall back to substring replace

    @Test func nonSpacedScriptUsesSubstringReplace() {
        // Chinese has no word boundaries; we accept substring replacement here.
        let out = service.applyReplacements(
            to: "你好世界",
            rules: [("世界", "World")]
        )
        #expect(out == "你好World")
    }

    // MARK: - Empty rules / empty text

    @Test func emptyRulesReturnsOriginal() {
        let out = service.applyReplacements(to: "hello", rules: [])
        #expect(out == "hello")
    }

    @Test func underscoreCountsAsWordChar() {
        // Should NOT replace because _ is a word char (matches \b semantics).
        let out = service.applyReplacements(
            to: "foo_клод_bar",
            rules: [("клод", "Claude")]
        )
        #expect(out == "foo_клод_bar")
    }
}
