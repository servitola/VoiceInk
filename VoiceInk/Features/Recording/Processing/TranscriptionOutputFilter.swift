import Foundation
import os

struct TranscriptionOutputFilter {
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TranscriptionOutputFilter")

    private static let hallucinationPatterns = [
        #"\[.*?\]"#,  // []
        #"\(.*?\)"#,  // ()
        #"\{.*?\}"#,  // {}
    ]

    static func filter(_ text: String) -> String {
        var filteredText = text

        // Remove <TAG>...</TAG> blocks
        let tagBlockPattern = #"<([A-Za-z][A-Za-z0-9:_-]*)[^>]*>[\s\S]*?</\1>"#
        if let regex = try? NSRegularExpression(pattern: tagBlockPattern) {
            let range = NSRange(filteredText.startIndex..., in: filteredText)
            filteredText = regex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "")
        }

        // Remove bracketed hallucinations
        for pattern in hallucinationPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(filteredText.startIndex..., in: filteredText)
                filteredText = regex.stringByReplacingMatches(
                    in: filteredText, options: [], range: range, withTemplate: "")
            }
        }

        // Remove configured filler words. An empty list is naturally a no-op.
        for fillerWord in FillerWordManager.shared.fillerWords {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: fillerWord))\\b[,.]?"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(filteredText.startIndex..., in: filteredText)
                filteredText = regex.stringByReplacingMatches(
                    in: filteredText, options: [], range: range, withTemplate: "")
            }
        }

        // Clean whitespace
        filteredText = filteredText.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        filteredText = filteredText.trimmingCharacters(in: .whitespacesAndNewlines)

        return filteredText
    }

    /// Remove wake word from the beginning of transcription if enabled
    static func removeWakeWord(from text: String) -> String {
        // Check if wake word removal is enabled
        guard UserDefaults.standard.removeWakeWordFromTranscription else {
            return text
        }

        let wakeWord = UserDefaults.standard.string(forKey: "wakeWord") ?? "лошадка"
        let sendWakeWord = UserDefaults.standard.wakeWordSend
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Whatever ended the dictation was spoken into it, so it is in the
        // recording too and has to come off the tail. The send word always ends
        // one - that is all it does - while the primary word only does when its
        // own switch is on. Everything below works on this result, not on the
        // original text.
        var text = text
        if !sendWakeWord.isEmpty {
            text = removeTrailingWakeWord(from: text, wakeWord: sendWakeWord)
        }
        if UserDefaults.standard.wakeWordStopsRecording {
            text = removeTrailingWakeWord(from: text, wakeWord: wakeWord)
        }

        var filteredText = text
        let normalizedText = text.lowercased()
        let normalizedWakeWord = wakeWord.lowercased()

        // Check if text starts with wake word (case-insensitive)
        if normalizedText.hasPrefix(normalizedWakeWord) {
            // Remove wake word from beginning
            let startIndex = text.index(text.startIndex, offsetBy: wakeWord.count)
            filteredText = String(text[startIndex...])

            // Trim leading punctuation and whitespace
            filteredText = filteredText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet.punctuationCharacters))

            // Capitalize first letter if needed
            if !filteredText.isEmpty {
                filteredText = filteredText.prefix(1).uppercased() + filteredText.dropFirst()
            }

            logger.notice("🎯 Wake word '\(wakeWord)' removed from transcription")
        } else {
            // Try to find wake word in the first few words with fuzzy matching
            let words = text.components(separatedBy: .whitespaces)
            if words.count > 0 {
                let firstWord = words[0].lowercased()
                    .trimmingCharacters(in: .punctuationCharacters)

                // Levenshtein distance check for fuzzy matching
                if levenshteinDistance(firstWord, normalizedWakeWord) <= 2 {
                    // Remove first word
                    filteredText = words.dropFirst().joined(separator: " ")
                    filteredText = filteredText.trimmingCharacters(in: .whitespacesAndNewlines)

                    if !filteredText.isEmpty {
                        filteredText = filteredText.prefix(1).uppercased() + filteredText.dropFirst()
                    }

                    logger.notice("🎯 Wake word '\(wakeWord)' (fuzzy match) removed from transcription")
                }
            }
        }

        return filteredText
    }

    /// Drops a wake word spoken at the end to finish dictation.
    ///
    /// Only the tail is considered, and only when it matches: a sentence that
    /// genuinely ends in the wake word is indistinguishable from the stop
    /// command, and dropping it is the right call either way, because the user
    /// did just stop the recording with it.
    ///
    /// A wake word may be a phrase, so the comparison takes as many trailing
    /// words as the phrase has and matches them as one string - "отправляй
    /// сообщение" has to come off whole, not one word of it.
    static func removeTrailingWakeWord(from text: String, wakeWord: String) -> String {
        let phrase = wakeWord
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { $0.lowercased() }
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        guard let last = words.last, !phrase.isEmpty, words.count >= phrase.count else { return text }

        let normalizedTail = words.suffix(phrase.count)
            .map {
                $0.lowercased().trimmingCharacters(
                    in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let normalizedWakeWord = phrase.joined(separator: " ")
        guard !normalizedTail.isEmpty, !normalizedWakeWord.isEmpty else { return text }

        guard normalizedTail == normalizedWakeWord
            || levenshteinDistance(normalizedTail, normalizedWakeWord) <= 2
        else { return text }

        let remainder = words.dropLast(phrase.count).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        logger.notice("🎯 Closing wake word '\(wakeWord)' removed from transcription")

        // A lone wake word means the recording held nothing else - the user
        // started and stopped without saying anything in between.
        guard !remainder.isEmpty else { return "" }

        // The sentence lost its final word, so restore terminal punctuation the
        // wake word was carrying, if any.
        if let tail = last.last, ".!?…".contains(tail),
            let existing = remainder.last, !".!?…,;:".contains(existing)
        {
            return remainder + String(tail)
        }
        return remainder
    }

    /// Calculate Levenshtein distance between two strings for fuzzy matching
    private static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
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
}
