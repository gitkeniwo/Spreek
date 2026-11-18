import Foundation

/// Cleans captured text before it is detected and spoken.
public enum TextNormalizer {
    /// Longest text Spreek speaks, in characters.
    public static let maxLength = 2_000

    /// Invisible characters that only get in the way of synthesis (and of cache-key stability).
    static let zeroWidth: Set<Unicode.Scalar> = ["\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{FEFF}", "\u{00AD}"]

    /// Sentence-ending punctuation used to find a clean cut when truncating.
    static let sentenceTerminators: Set<Character> = [".", "!", "?", "…", "。", "！", "？"]
    /// Full-width terminators end a sentence even without a following space (Japanese has none).
    static let fullWidthTerminators: Set<Character> = ["。", "！", "？"]

    /// Strips zero-width characters, collapses all whitespace (including newlines) to single
    /// spaces, trims, and caps at `maxLength` characters — cutting after the last sentence that
    /// fits when there is one in the second half, else at the last word boundary.
    /// Returns `nil` when nothing speakable is left.
    public static func normalize(_ text: String, maxLength: Int = maxLength) -> String? {
        var scalars = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in text.unicodeScalars where !zeroWidth.contains(scalar) {
            if scalar.properties.isWhitespace {
                pendingSpace = !scalars.isEmpty
                continue
            }
            if pendingSpace {
                scalars.append(" ")
                pendingSpace = false
            }
            scalars.append(scalar)
        }
        let collapsed = String(scalars)
        guard !collapsed.isEmpty else { return nil }
        return truncate(collapsed, to: maxLength)
    }

    static func truncate(_ text: String, to maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let prefix = text.prefix(maxLength)
        // The character right after the prefix tells us whether its last word/sentence is complete.
        let next = text[prefix.endIndex]
        let minimumKeep = maxLength / 2

        var sentenceEnd: String.Index?
        var wordEnd: String.Index?
        var index = prefix.endIndex
        var following: Character = next
        while index > prefix.startIndex {
            let previous = prefix.index(before: index)
            let character = prefix[previous]
            if sentenceEnd == nil, fullWidthTerminators.contains(character)
                || (following == " " && sentenceTerminators.contains(character)) {
                sentenceEnd = index
            }
            if wordEnd == nil, following == " ", character != " " { wordEnd = index }
            if sentenceEnd != nil { break }
            following = character
            index = previous
        }

        if let sentenceEnd, prefix.distance(from: prefix.startIndex, to: sentenceEnd) >= minimumKeep {
            return String(prefix[..<sentenceEnd])
        }
        if let wordEnd {
            return String(prefix[..<wordEnd])
        }
        return String(prefix)
    }
}
