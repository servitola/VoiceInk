import Foundation
import SwiftData

class WordReplacementService {
    static let shared = WordReplacementService()

    private init() {}

    func applyReplacements(to text: String, using context: ModelContext) -> String {
        let descriptor = FetchDescriptor<WordReplacement>(
            predicate: #Predicate { $0.isEnabled }
        )

        guard let replacements = try? context.fetch(descriptor), !replacements.isEmpty else {
            return text  // No replacements to apply
        }

        let rules = replacements.map { (original: $0.originalText, replacement: $0.replacementText) }
        return applyReplacements(to: text, rules: rules)
    }

    /// Pure string transform, exposed for testing without SwiftData.
    func applyReplacements(to text: String, rules: [(original: String, replacement: String)]) -> String {
        guard !rules.isEmpty else { return text }

        var modifiedText = text

        // Longest-first so specific triggers match before shorter overlapping ones
        let sortedRules = rules.sorted { $0.original.count > $1.original.count }

        for rule in sortedRules {
            let variants = rule.original
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .sorted { $0.count > $1.count }

            for original in variants {
                if usesWordBoundaries(for: original) {
                    // Unicode-aware boundary: any letter/digit/underscore in any script counts
                    // as a word char, so "клод" won't match inside "клодеы".
                    let escaped = NSRegularExpression.escapedPattern(for: original)
                    let pattern = "(?<![\\p{L}\\p{N}_])\(escaped)(?![\\p{L}\\p{N}_])"
                    if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                        let range = NSRange(modifiedText.startIndex..., in: modifiedText)
                        modifiedText = regex.stringByReplacingMatches(
                            in: modifiedText,
                            options: [],
                            range: range,
                            withTemplate: rule.replacement
                        )
                    }
                } else {
                    // Fallback substring replace for non-spaced scripts
                    modifiedText = modifiedText.replacingOccurrences(of: original, with: rule.replacement, options: .caseInsensitive)
                }
            }
        }

        return modifiedText
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
