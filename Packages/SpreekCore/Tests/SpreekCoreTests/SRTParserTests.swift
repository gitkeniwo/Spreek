import Foundation
import Testing
@testable import SpreekCore

@Suite struct SRTParserTests {
    /// Verbatim output of edge-tts 7.3.1.
    let sample = """
    1
    00:00:00,100 --> 00:00:02,226
    Goedemorgen.

    2
    00:00:02,176 --> 00:00:04,397
    Hoe gaat het met je?

    3
    00:00:04,397 --> 00:00:07,588
    Ik heb vandaag veel zin in koffie.

    """

    @Test func parsesCues() {
        let cues = SRTParser.parse(sample)
        #expect(cues.count == 3)
        #expect(cues[0] == SRTCue(start: 0.1, end: 2.226, text: "Goedemorgen."))
        #expect(abs(cues[2].start - 4.397) < 0.0001)
        #expect(abs(cues[2].end - 7.588) < 0.0001)
        #expect(cues[1].text == "Hoe gaat het met je?")
    }

    @Test func parsesCRLFAndMultilineCues() {
        let srt = "1\r\n00:01:02,500 --> 01:00:00,000\r\nline one\r\nline two\r\n\r\ngarbage\r\n"
        let cues = SRTParser.parse(srt)
        #expect(cues.count == 1)
        #expect(cues[0].start == 62.5)
        #expect(cues[0].end == 3600)
        #expect(cues[0].text == "line one line two")
    }

    @Test func timestamps() {
        #expect(SRTParser.parseTimestamp("00:00:01,250") == 1.25)
        #expect(SRTParser.parseTimestamp("bad") == nil)
    }

    @Test func marksMapOntoOriginalText() throws {
        let original = "Goedemorgen.  Hoe gaat\nhet met je? Ik heb vandaag veel zin in koffie."
        let marks = SRTParser.marks(from: SRTParser.parse(sample), in: original)
        #expect(marks.count == 3)
        #expect(marks.allSatisfy { $0.granularity == .sentence })
        let texts = try marks.map { String(original[try #require($0.range.range(in: original))]) }
        #expect(texts == ["Goedemorgen.", "Hoe gaat\nhet met je?", "Ik heb vandaag veel zin in koffie."])
        #expect(marks[1].start == 2.176)
    }

    @Test func repeatedSentencesMapInOrder() throws {
        let original = "Ja. Ja. Nee."
        let cues = [SRTCue(start: 0, end: 1, text: "Ja."), SRTCue(start: 1, end: 2, text: "Ja."), SRTCue(start: 2, end: 3, text: "Nee.")]
        let marks = SRTParser.marks(from: cues, in: original)
        #expect(marks.map(\.range.location) == [0, 4, 8])
    }

    @Test func unmatchedCueIsDropped() {
        let marks = SRTParser.marks(from: [SRTCue(start: 0, end: 1, text: "Elders")], in: "Hallo")
        #expect(marks.isEmpty)
    }

    @Test func utf16RangesWithEmojiAndCJK() throws {
        let original = "🇳🇱 Hallo. 日本語です。"
        let cues = [SRTCue(start: 0, end: 1, text: "🇳🇱 Hallo."), SRTCue(start: 1, end: 2, text: "日本語です。")]
        let marks = SRTParser.marks(from: cues, in: original)
        #expect(try marks.map { String(original[try #require($0.range.range(in: original))]) } == ["🇳🇱 Hallo.", "日本語です。"])
    }

    @Test func activeMarkPicksLatestStarted() {
        let marks = SRTParser.marks(from: SRTParser.parse(sample), in: "Goedemorgen. Hoe gaat het met je? Ik heb vandaag veel zin in koffie.")
        #expect(BoundaryMark.active(in: marks, at: 0.05) == nil)
        #expect(BoundaryMark.active(in: marks, at: 1) == marks[0])
        #expect(BoundaryMark.active(in: marks, at: 2.2) == marks[1], "overlap goes to the newer sentence")
        #expect(BoundaryMark.active(in: marks, at: 99) == marks[2])
    }
}
