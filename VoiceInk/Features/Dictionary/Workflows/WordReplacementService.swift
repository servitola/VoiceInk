import Foundation
import SwiftData
import os

@MainActor
final class WordReplacementService {
    static let shared = WordReplacementService()

    private struct RuleRecord: Equatable {
        let id: UUID
        let originalText: String
        let replacementText: String
        let dateAdded: Date
    }

    /// Store-independent description of one rule, so the matching engine can be
    /// driven either from SwiftData or from plain values in tests.
    private struct RuleSource {
        let originalText: String
        let replacementText: String
        let dateAdded: Date
        let order: Int
    }

    private struct PreparedRule {
        let original: String
        let replacement: String
        let regex: NSRegularExpression?
    }

    private let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "WordReplacementService"
    )
    private var cachedRecords: [RuleRecord]?
    private var cachedRules: [PreparedRule] = []

    private init() {}

    func applyReplacements(to text: String, using context: ModelContext) -> String {
        // `isEnabled` is retained only for store and CloudKit compatibility.
        // Replacement rules are intentionally always active.
        let descriptor = FetchDescriptor<WordReplacement>()

        let replacements: [WordReplacement]
        do {
            replacements = try context.fetch(descriptor)
        } catch {
            logger.error("Could not load word replacements: \(error, privacy: .public)")
            return text
        }

        guard !replacements.isEmpty else {
            logger.debug("Word replacement skipped: no enabled rules")
            return text
        }

        logger.debug(
            "Starting word replacement with \(replacements.count, privacy: .public) enabled rule(s)"
        )

        let rules = preparedRules(from: replacements)

        logger.debug(
            "Prepared \(rules.count, privacy: .public) replacement variant(s)"
        )

        return apply(rules, to: text)
    }

    /// Pure transform over plain rules: no store access and no caching, so the
    /// Unicode boundary behaviour can be exercised directly from tests.
    func applyReplacements(to text: String, rules: [(original: String, replacement: String)]) -> String {
        guard !rules.isEmpty else { return text }

        let sources = rules.enumerated().map { entry in
            RuleSource(
                originalText: entry.element.original,
                replacementText: entry.element.replacement,
                dateAdded: .distantPast,
                order: entry.offset
            )
        }

        return apply(buildRules(from: sources), to: text)
    }

    private func apply(_ rules: [PreparedRule], to text: String) -> String {
        var modifiedText = text

        var matchedRuleCount = 0
        for rule in rules {
            let original = rule.original
            let replacementText = rule.replacement

            if let regex = rule.regex {
                let range = NSRange(modifiedText.startIndex..., in: modifiedText)
                let matchCount = regex.numberOfMatches(in: modifiedText, options: [], range: range)
                guard matchCount > 0 else { continue }

                logger.debug(
                    "Applying boundary-aware word replacement \(original, privacy: .private) -> \(replacementText, privacy: .private), matches=\(matchCount, privacy: .public)"
                )
                modifiedText = regex.stringByReplacingMatches(
                    in: modifiedText,
                    options: [],
                    range: range,
                    withTemplate: replacementText
                )
                matchedRuleCount += 1
            } else {
                // Fallback substring replace for non-spaced scripts
                let replacedText = modifiedText.replacingOccurrences(
                    of: original, with: replacementText, options: .caseInsensitive)
                guard replacedText != modifiedText else { continue }

                logger.debug(
                    "Applying substring word replacement \(original, privacy: .private) -> \(replacementText, privacy: .private)"
                )
                modifiedText = replacedText
                matchedRuleCount += 1
            }
        }

        logger.debug(
            "Finished word replacement: \(matchedRuleCount, privacy: .public) rule(s) matched; output changed=\(modifiedText != text, privacy: .public)"
        )

        return modifiedText
    }

    private func preparedRules(from replacements: [WordReplacement]) -> [PreparedRule] {
        let records = replacements
            .map {
                RuleRecord(
                    id: $0.id,
                    originalText: $0.originalText,
                    replacementText: $0.replacementText,
                    dateAdded: $0.dateAdded
                )
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }

        if cachedRecords == records {
            return cachedRules
        }

        // Records are already ordered by id, so the positional tie-break below
        // matches the previous id-based one.
        let sources = records.enumerated().map { entry in
            RuleSource(
                originalText: entry.element.originalText,
                replacementText: entry.element.replacementText,
                dateAdded: entry.element.dateAdded,
                order: entry.offset
            )
        }

        let prepared = buildRules(from: sources)

        cachedRecords = records
        cachedRules = prepared
        logger.debug("Rebuilt cached word replacement plan with \(prepared.count, privacy: .public) rule(s)")
        return prepared
    }

    private func buildRules(from sources: [RuleSource]) -> [PreparedRule] {
        let sortedRules = sources
            .flatMap { source in
                WordReplacementVariants.parse(source.originalText).map {
                    (
                        original: $0,
                        replacement: source.replacementText,
                        dateAdded: source.dateAdded,
                        order: source.order
                    )
                }
            }
            .sorted {
                // Longest-first so specific triggers match before shorter overlapping ones
                if $0.original.count != $1.original.count {
                    return $0.original.count > $1.original.count
                }
                let leftKey = WordReplacementVariants.key(for: $0.original)
                let rightKey = WordReplacementVariants.key(for: $1.original)
                if leftKey != rightKey {
                    return leftKey < rightKey
                }
                if $0.dateAdded != $1.dateAdded {
                    return $0.dateAdded < $1.dateAdded
                }
                return $0.order < $1.order
            }

        // Preserve every legacy rule. New dictionary mutations prevent source
        // conflicts, but older stores may contain multiple rules for a trigger.
        return sortedRules.compactMap { rule -> PreparedRule? in
            guard usesWordBoundaries(for: rule.original) else {
                return PreparedRule(original: rule.original, replacement: rule.replacement, regex: nil)
            }

            // Unicode-aware lookarounds instead of \b, so punctuation acts as a
            // word boundary while triggers can't match inside larger words like
            // "vergrößern"; non-spaced scripts are exempt so Latin triggers
            // flush against CJK/Thai still match (mirrors usesWordBoundaries).
            do {
                let escaped = NSRegularExpression.escapedPattern(for: rule.original)
                // scx (Script_Extensions) so shared marks like the prolonged sound mark
                // U+30FC (Script=Common, scx=Hira Kana) stay exempt too.
                let wordChar = "[[\\p{L}\\p{M}\\p{N}]-[\\p{scx=Han}\\p{scx=Hiragana}\\p{scx=Katakana}\\p{scx=Hangul}\\p{scx=Thai}]]"
                let pattern = "(?<!\(wordChar))\(escaped)(?!\(wordChar))"
                let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
                return PreparedRule(original: rule.original, replacement: rule.replacement, regex: regex)
            } catch {
                logger.error(
                    "Could not build matcher for word replacement \(rule.original, privacy: .private): \(error, privacy: .public)"
                )
                return nil
            }
        }
    }

    private func usesWordBoundaries(for text: String) -> Bool {
        // Returns false for languages without spaces (CJK, Thai), true for spaced languages
        let nonSpacedScripts: [ClosedRange<UInt32>] = [
            0x3040...0x309F,  // Hiragana
            0x30A0...0x30FF,  // Katakana
            0x4E00...0x9FFF,  // CJK Unified Ideographs
            0xAC00...0xD7AF,  // Hangul Syllables
            0x0E00...0x0E7F,  // Thai
        ]

        for scalar in text.unicodeScalars {
            for range in nonSpacedScripts {
                if range.contains(scalar.value) {
                    return false
                }
            }
        }

        return true
    }
}
