import Foundation
import os

struct TranscriptionOutputFilter {
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TranscriptionOutputFilter")

    private static let hallucinationPatterns = [
        #"\[.*?\]"#,  // []
        #"\(.*?\)"#,  // ()
        #"\{.*?\}"#,  // {}
    ]

    static func filter(_ text: String, language: String? = nil) -> String {
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

        filteredText = FillerWordCleanup.remove(
            from: filteredText, fillers: FillerWordManager.shared.fillerWords, language: language
        )

        // Normalize horizontal whitespace without flattening paragraphs or lists.
        filteredText = filteredText.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
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
    /// A wake word may be a phrase, and - the part that bit - the recogniser
    /// decides for itself how many words it heard. A single configured word can
    /// come back split ("авадакедавра" → "Авада Кедавра"), and a phrase can come
    /// back merged. So the tail is not read at a fixed width: several widths are
    /// tried and compared with spaces and punctuation removed, which makes the
    /// split and merged renderings identical strings.
    ///
    /// Exact matches are tried at every width before any fuzzy one, so the wider
    /// search cannot let a near miss eat real words when a clean match exists.
    static func removeTrailingWakeWord(from text: String, wakeWord: String) -> String {
        let target = normalizedForMatching(wakeWord)
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        guard let last = words.last, !target.isEmpty else { return text }

        let phraseWordCount = wakeWord.split(separator: " ", omittingEmptySubsequences: true).count
        // Two words of slack: enough for the recogniser to split a word in half
        // or wedge in a stray particle, not enough to swallow a clause.
        let widestTail = min(words.count, max(phraseWordCount, 1) + 2)
        guard widestTail >= 1 else { return text }

        let widths = Array(stride(from: widestTail, through: 1, by: -1))
        let matchedWidth =
            widths.first { normalizedForMatching(words.suffix($0).joined(separator: " ")) == target }
            ?? widths.first { width in
                let candidate = normalizedForMatching(words.suffix(width).joined(separator: " "))
                guard !candidate.isEmpty else { return false }
                return levenshteinDistance(candidate, target) <= 2
            }

        guard let matchedWidth else { return text }

        let remainder = words.dropLast(matchedWidth).joined(separator: " ")
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

    /// Lowercased, with whitespace and punctuation dropped entirely.
    ///
    /// Dropping the spaces is the point: it makes "Авада Кедавра", "авадакедавра"
    /// and "авада, кедавра." one and the same string, so how the recogniser chose
    /// to break up a made-up word stops mattering.
    private static func normalizedForMatching(_ text: String) -> String {
        text.lowercased().unicodeScalars
            .filter {
                !CharacterSet.whitespacesAndNewlines.contains($0)
                    && !CharacterSet.punctuationCharacters.contains($0)
            }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
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

/// Repairs only the gaps left by configured fillers; surviving words keep their original casing.
private enum FillerWordCleanup {
    private static let punctuation: Set<Character> = [",", ".", "!", "?", ":", ";", "…", "。", "！", "？", "।", "॥"]
    private static let openingQuotes: Set<Character> = ["\"", "'", "“", "‘", "«"]
    private static let closingQuotes: Set<Character> = ["\"", "'", "”", "’", "»"]
    private static let sentenceEndings: Set<Character> = ["!", "?", "。", "！", "？", "।", "॥"]
    private static let abbreviations: Set<String> = [
        "dr", "mr", "mrs", "ms", "prof", "sr", "jr", "vs", "etc", "inc", "ltd", "co",
        "e.g", "i.e", "a.m", "p.m", "no", "fig", "st",
    ]

    static func remove(from text: String, fillers: [String], language: String?) -> String {
        guard !fillers.isEmpty, !text.isEmpty else { return text }
        let characters = Array(text)
        let protected = protectedCharacters(in: characters)
        // Regex ranges use UTF-16 offsets. Map once instead of walking the string for every match.
        var offsets = [Int](repeating: -1, count: text.utf16.count + 1)
        var offset = 0
        for (index, character) in characters.enumerated() {
            offsets[offset] = index
            offset += character.utf16.count
        }
        offsets[offset] = characters.count
        var removed = [Bool](repeating: false, count: characters.count)
        for filler in Set(fillers) {
            let words = filler.split(whereSeparator: { $0.isWhitespace })
            guard !words.isEmpty else { continue }
            let phrase = words.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "[ \\t]+")
            guard let regex = try? NSRegularExpression(pattern: "\\b\(phrase)\\b", options: .caseInsensitive) else { continue }
            regex.enumerateMatches(in: text, range: NSRange(location: 0, length: offset)) { match, _, _ in
                guard let range = match?.range else { return }
                let start = offsets[range.location]
                let end = offsets[NSMaxRange(range)]
                guard start >= 0, end > start, !protected[start..<end].contains(true) else { return }
                // Preserve a literal quoted word, such as: The word is "um".
                if start > 0, end < characters.count,
                    openingQuotes.contains(characters[start - 1]), closingQuotes.contains(characters[end]) { return }
                for index in start..<end { removed[index] = true }
            }
        }
        guard removed.contains(true) else { return text }
        let locale = language.flatMap { $0.isEmpty || $0 == "auto" ? nil : Locale(identifier: $0) }
        var output: [Character] = []
        output.reserveCapacity(characters.count)
        var index = 0
        var capitalizeNext = false
        while index < characters.count {
            guard removed[index] else {
                let character = characters[index]
                if capitalizeNext, !character.isWhitespace, !openingQuotes.contains(character) {
                    if character.isLowercase, canCapitalize(at: index, in: characters, protected: protected) {
                        let letter = String(character)
                        output.append(contentsOf: locale.map { letter.uppercased(with: $0) } ?? letter.uppercased())
                    } else {
                        output.append(character)
                    }
                    capitalizeNext = false
                } else {
                    output.append(character)
                }
                index += 1
                continue
            }

            let sentenceStart = startsSentence(after: output)
            var end = index
            var marks: [Character] = []
            var newlines: [Character] = []
            var wasFiller = false
            while end < characters.count {
                let character = characters[end]
                if removed[end] {
                    if !wasFiller { marks.removeAll(keepingCapacity: true) }
                    wasFiller = true
                } else if character.isWhitespace {
                    if character.isNewline { newlines.append(character) }
                    wasFiller = false
                } else if punctuation.contains(character) {
                    // A comma attached directly to a filler belongs to that hesitation.
                    if character != "," || end == 0 || !removed[end - 1] { marks.append(character) }
                    wasFiller = false
                } else {
                    break
                }
                end += 1
            }
            var afterQuotes = end
            while afterQuotes < characters.count,
                closingQuotes.contains(characters[afterQuotes]) || characters[afterQuotes].isWhitespace {
                afterQuotes += 1
            }
            let atEnd = afterQuotes == characters.count
            var nextContent = end
            while nextContent < characters.count,
                openingQuotes.contains(characters[nextContent]) || characters[nextContent].isWhitespace {
                nextContent += 1
            }
            let nextIsUppercase = nextContent < characters.count && characters[nextContent].isUppercase
            if sentenceStart {
                marks.removeAll()
            } else if marks.allSatisfy({ $0 == "." || $0 == "…" }), !atEnd, !nextIsUppercase {
                // A mid-sentence "um. think" is ambiguous; do not invent a sentence boundary.
                marks.removeAll()
            } else if atEnd, marks.allSatisfy({ $0 == "," }) {
                marks.removeAll()
            }
            while let last = output.last, last.isWhitespace && !last.isNewline { output.removeLast() }
            if atEnd || !marks.isEmpty {
                while output.last == "," {
                    output.removeLast()
                    while let last = output.last, last.isWhitespace && !last.isNewline { output.removeLast() }
                }
            }
            output.append(contentsOf: marks)
            if !newlines.isEmpty {
                output.append(contentsOf: newlines)
            } else if !atEnd, let last = output.last,
                !last.isNewline, !openingQuotes.contains(last),
                !closingQuotes.contains(characters[end]) {
                output.append(" ")
            }
            capitalizeNext = sentenceStart || marks.last.map { sentenceEndings.contains($0) } == true
                || newlines.count >= 2
                || (!newlines.isEmpty && output.dropLast(newlines.count).last == ":")
            index = end
        }
        return String(output)
    }

    private static func canCapitalize(at index: Int, in characters: [Character], protected: [Bool]) -> Bool {
        guard !protected[index] else { return false }
        var end = index
        while end < characters.count,
            characters[end].isLetter || characters[end].isNumber || characters[end] == "_" {
            end += 1
        }
        let word = characters[index..<end]
        // Preserve iOS, eBay, camelCase, x86, and snake_case, including all remaining letters.
        if word.contains("_") || word.dropFirst().contains(where: { $0.isUppercase || $0.isNumber }) { return false }
        if word.count == 1, let letter = word.first, ("b"..."z").contains(letter), letter != "i" { return false }
        return true
    }

    private static func startsSentence(after output: [Character]) -> Bool {
        var end = output.count
        var newlines = 0
        let lowerBound = max(0, output.count - 96)
        while end > lowerBound, output[end - 1].isWhitespace || openingQuotes.contains(output[end - 1]) || closingQuotes.contains(output[end - 1]) {
            if output[end - 1].isNewline { newlines += 1 }
            end -= 1
        }
        guard end > 0 else { return true }
        if newlines >= 2 || (newlines > 0 && output[end - 1] == ":") { return true }
        guard end > lowerBound else { return false }
        // Look back at most 96 characters. Long transcripts never cause repeated prefix scans.
        let start = max(0, end - 96)
        let context = String(output[start..<end])
        let line = context.split(whereSeparator: { $0.isNewline }).last.map(String.init) ?? context
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        if ["-", "*", "•"].contains(trimmedLine)
            || trimmedLine.range(of: #"^\d+[.)]$"#, options: .regularExpression) != nil { return true }
        if sentenceEndings.contains(output[end - 1]) { return true }
        guard output[end - 1] == ".", end < 2 || output[end - 2] != "." else { return false }
        let token = context.dropLast().split(whereSeparator: { $0.isWhitespace || openingQuotes.contains($0) }).last.map(String.init) ?? ""
        if abbreviations.contains(token.lowercased()) || token.last?.isNumber == true { return false }
        let initials = token.split(separator: ".")
        if !initials.isEmpty, initials.allSatisfy({ $0.count == 1 && $0.first?.isLetter == true }) { return false }
        return true
    }

    private static func protectedCharacters(in characters: [Character]) -> [Bool] {
        var protected = [Bool](repeating: false, count: characters.count)
        var codeDelimiter: Int?
        var index = 0
        while index < characters.count {
            if characters[index] == "`" {
                var end = index + 1
                while end < characters.count, characters[end] == "`" { end += 1 }
                let length = end - index
                if codeDelimiter == length { codeDelimiter = nil }
                else if codeDelimiter == nil { codeDelimiter = length }
                for position in index..<end { protected[position] = true }
                index = end
            } else {
                if codeDelimiter != nil { protected[index] = true }
                index += 1
            }
        }
        var start = 0
        let delimiters: Set<Character> = [",", "!", "?", ";", "\"", "'", "“", "”", "‘", "’", "«", "»"]
        while start < characters.count {
            if characters[start].isWhitespace || delimiters.contains(characters[start]) { start += 1; continue }
            var end = start + 1
            while end < characters.count, !characters[end].isWhitespace, !delimiters.contains(characters[end]) { end += 1 }
            let token = characters[start..<end]
            let structured = token.contains("@") || token.contains("/") || token.contains("\\")
                || (start..<max(start, end - 1)).contains(where: {
                    characters[$0] == "." && $0 > start && characters[$0 - 1].isLetter
                        && (characters[$0 + 1].isLetter || characters[$0 + 1].isNumber)
                })
            if structured { for index in start..<end { protected[index] = true } }
            start = end
        }
        return protected
    }
}
