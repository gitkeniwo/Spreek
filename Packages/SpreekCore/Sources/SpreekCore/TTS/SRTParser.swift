import Foundation

/// One subtitle block from an `.srt` file.
public struct SRTCue: Sendable, Hashable {
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String
}

public enum SRTParser {
    /// Parses SubRip text. Malformed blocks are skipped.
    public static func parse(_ srt: String) -> [SRTCue] {
        let normalized = srt.replacingOccurrences(of: "\r\n", with: "\n")
        var cues: [SRTCue] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[timingIndex].components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = parseTimestamp(parts[0]),
                  let end = parseTimestamp(parts[1])
            else { continue }
            let text = lines[(timingIndex + 1)...].joined(separator: " ")
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            cues.append(SRTCue(start: start, end: end, text: text))
        }
        return cues
    }

    /// `HH:MM:SS,mmm` (also accepts `.` as the millisecond separator).
    static func parseTimestamp(_ raw: String) -> TimeInterval? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let parts = trimmed.split(separator: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2])
        else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }

    /// Turns cues into sentence marks whose ranges point into `original`.
    ///
    /// Cue text is matched against the original ignoring whitespace, in order, so line
    /// breaks or collapsed spaces in the subtitles don't matter. Cues that can't be found
    /// are dropped.
    public static func marks(from cues: [SRTCue], in original: String) -> [BoundaryMark] {
        // Non-whitespace characters of the original with their positions.
        let indexed: [(Character, String.Index)] = original.indices
            .filter { !original[$0].isWhitespace }
            .map { (original[$0], $0) }
        var cursor = 0
        var marks: [BoundaryMark] = []
        for cue in cues {
            let needle = Array(cue.text.filter { !$0.isWhitespace })
            guard !needle.isEmpty,
                  let found = firstMatch(of: needle, in: indexed, from: cursor)
            else { continue }
            let lowerIndex = indexed[found].1
            let lastIndex = indexed[found + needle.count - 1].1
            let range = lowerIndex..<original.index(after: lastIndex)
            marks.append(BoundaryMark(
                start: cue.start, end: cue.end,
                range: TextRange(range, in: original), granularity: .sentence
            ))
            cursor = found + needle.count
        }
        return marks
    }

    private static func firstMatch(of needle: [Character], in haystack: [(Character, String.Index)], from start: Int) -> Int? {
        guard haystack.count - start >= needle.count else { return nil }
        outer: for i in start...(haystack.count - needle.count) {
            for (offset, char) in needle.enumerated() where haystack[i + offset].0 != char {
                continue outer
            }
            return i
        }
        return nil
    }
}
