import Testing
@testable import SpreekCore

@Suite struct TextNormalizerTests {
    @Test func trimsAndCollapsesWhitespace() {
        #expect(TextNormalizer.normalize("  Goedemorgen,\n\n  hoe\tgaat   het?  ") == "Goedemorgen, hoe gaat het?")
        #expect(TextNormalizer.normalize("Eins.\r\nZwei!\u{00A0}\u{00A0}Drei?") == "Eins. Zwei! Drei?")
    }

    @Test func keepsSentencePunctuation() {
        #expect(TextNormalizer.normalize("Ja… nee! Echt? Ok.") == "Ja… nee! Echt? Ok.")
        #expect(TextNormalizer.normalize("今日は。 元気？") == "今日は。 元気？")
    }

    @Test func stripsZeroWidthCharacters() {
        #expect(TextNormalizer.normalize("\u{FEFF}Goe\u{200B}de\u{200D}morgen\u{2060}") == "Goedemorgen")
        #expect(TextNormalizer.normalize("on\u{00AD}der\u{00AD}weg") == "onderweg")
        // A zero-width char between spaces must not leave a double space.
        #expect(TextNormalizer.normalize("a \u{200B} b") == "a b")
    }

    @Test func emptyBecomesNil() {
        #expect(TextNormalizer.normalize("") == nil)
        #expect(TextNormalizer.normalize(" \n\t ") == nil)
        #expect(TextNormalizer.normalize("\u{200B}\u{FEFF} \u{200C}") == nil)
    }

    @Test func shortTextIsUntouched() {
        let text = String(repeating: "a", count: TextNormalizer.maxLength)
        #expect(TextNormalizer.normalize(text) == text)
    }

    @Test func truncatesAtSentenceBoundary() throws {
        let sentence = "Dit is een zin van precies wat woorden. " // 40 chars
        let text = String(repeating: sentence, count: 60) // 2,400 chars
        let result = try #require(TextNormalizer.normalize(text))
        #expect(result.count <= TextNormalizer.maxLength)
        #expect(result.hasSuffix("woorden."))
        #expect(result.count == 50 * 40 - 1)
    }

    @Test func truncatesAtWordWhenNoSentenceInSecondHalf() throws {
        let text = "Begin. " + String(repeating: "woord ", count: 400)
        let result = try #require(TextNormalizer.normalize(text))
        #expect(result.count <= TextNormalizer.maxLength)
        #expect(result.hasSuffix("woord"))
        #expect(!result.hasSuffix(" "))
    }

    @Test func truncatesJapaneseAtFullWidthStop() throws {
        let text = String(repeating: "今日はいい天気ですね。", count: 300) // 11 chars each, no spaces
        let result = try #require(TextNormalizer.normalize(text))
        #expect(result.count <= TextNormalizer.maxLength)
        #expect(result.hasSuffix("。"))
        #expect(result.count == (TextNormalizer.maxLength / 11) * 11)
    }

    @Test func hardCutWithoutAnyBoundary() throws {
        let result = try #require(TextNormalizer.normalize(String(repeating: "x", count: 2_500)))
        #expect(result.count == TextNormalizer.maxLength)
    }
}
