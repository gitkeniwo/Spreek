import AppKit
import Foundation
import Testing
@testable import SpreekCore

struct NoteFormatTests {
    /// (text, bold, italic) per run, merged.
    private func runs(_ attributed: AttributedString) -> [(String, Bool, Bool)] {
        attributed.runs.map { run in
            let intent = run.inlinePresentationIntent ?? []
            return (String(attributed[run.range].characters), intent.contains(.stronglyEmphasized), intent.contains(.emphasized))
        }
    }

    private func traits(_ attributed: NSAttributedString) -> [(String, Bool, Bool)] {
        var result: [(String, Bool, Bool)] = []
        attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            let font = value as? NSFont
            let symbolic = font?.fontDescriptor.symbolicTraits ?? []
            result.append(((attributed.string as NSString).substring(with: range), symbolic.contains(.bold), symbolic.contains(.italic)))
        }
        return result
    }

    @Test func parsesBoldItalicAndParagraphs() {
        let attributed = NoteFormat.attributedString(fromMarkdown: "**gezeik** (het) — *zeiken*\n\n***beide*** klaar")
        #expect(String(attributed.characters) == "gezeik (het) — zeiken\nbeide klaar")
        let parsed = runs(attributed)
        #expect(parsed.map(\.0) == ["gezeik", " (het) — ", "zeiken", "\n", "beide", " klaar"])
        #expect(parsed.map(\.1) == [true, false, false, false, true, false])
        #expect(parsed.map(\.2) == [false, false, true, false, true, false])
    }

    @Test func markdownRoundTrip() {
        let samples = [
            "Dit. — **单独成句**，是 Reddit 上表示 *同意楼上* 的说法。",
            "**gezeik** (het)\n\n*blijft maar doorgaan* — **blijven *+ infinitief***",
            "Sterretjes blijven: 2 \\* 3 en een backslash \\\\.",
            "Eerste\n\n\n\nNa een lege regel",
            "",
        ]
        for markdown in samples {
            let attributed = NoteFormat.attributedString(fromMarkdown: markdown)
            #expect(NoteFormat.markdown(from: attributed) == markdown)
            let ns = NoteFormat.nsAttributedString(fromMarkdown: markdown)
            #expect(NoteFormat.markdown(from: ns) == markdown)
        }
    }

    @Test func attributedRoundTripKeepsStyles() {
        var attributed = AttributedString("Ja, nee, dat valt mee hoor.\nTweede alinea")
        let range = attributed.range(of: "valt mee")!
        attributed[range].inlinePresentationIntent = .stronglyEmphasized
        let back = NoteFormat.attributedString(fromMarkdown: NoteFormat.markdown(from: attributed))
        #expect(back == attributed)
    }

    @Test func unpairedOrSpacedStarsStayLiteral() {
        #expect(String(NoteFormat.attributedString(fromMarkdown: "5 * 3 = 15").characters) == "5 * 3 = 15")
        #expect(String(NoteFormat.attributedString(fromMarkdown: "**open").characters) == "**open")
        #expect(runs(NoteFormat.attributedString(fromMarkdown: "a * b *c*")).map(\.0) == ["a * b ", "c"])
    }

    @Test func styledEdgeWhitespaceMovesOutsideDelimiters() {
        var attributed = AttributedString("een vet woord")
        attributed[attributed.range(of: "vet ")!].inlinePresentationIntent = .stronglyEmphasized
        #expect(NoteFormat.markdown(from: attributed) == "een **vet** woord")
    }

    @Test func longNoteIsKeptInFull() {
        let paragraph = "Dit is een **lange** uitleg met *cursief* en gewone tekst over grammatica. "
        let markdown = (0..<60).map { _ in String(repeating: paragraph, count: 4) }.joined(separator: "\n\n")
        #expect(markdown.count > 10_000)
        let attributed = NoteFormat.attributedString(fromMarkdown: markdown)
        #expect(NoteFormat.markdown(from: attributed) == markdown)
        let ns = NoteFormat.nsAttributedString(fromMarkdown: markdown)
        #expect(NoteFormat.markdown(from: ns) == markdown)
        #expect(NoteFormat.sanitize(ns).string == ns.string)
        #expect(NoteFormat.plainText(fromMarkdown: markdown).count == ns.string.count)
    }

    @Test func sanitizeKeepsBoldItalicAndDropsTheRest() throws {
        let body = NSFont(name: "Helvetica", size: 16)!
        let bold = NSFont(name: "Helvetica-Bold", size: 16)!
        let italic = NSFontManager.shared.convert(body, toHaveTrait: .italicFontMask)
        let heading = NSFont(name: "Helvetica-Bold", size: 28)!

        let pasted = NSMutableAttributedString()
        pasted.append(NSAttributedString(string: "Kop van de pagina\n", attributes: [.font: heading]))
        pasted.append(NSAttributedString(string: "Lees ", attributes: [.font: body, .foregroundColor: NSColor.red]))
        pasted.append(NSAttributedString(string: "dit artikel", attributes: [.font: body, .link: URL(string: "https://example.com")!, .underlineStyle: 1]))
        pasted.append(NSAttributedString(string: " met ", attributes: [.font: body, .backgroundColor: NSColor.yellow]))
        pasted.append(NSAttributedString(string: "vet", attributes: [.font: bold]))
        pasted.append(NSAttributedString(string: " en ", attributes: [.font: body]))
        pasted.append(NSAttributedString(string: "schuin", attributes: [.font: italic]))
        pasted.append(NSAttributedString(string: ".\n\n\n\n", attributes: [.font: body]))
        let list = NSMutableParagraphStyle()
        list.textLists = [NSTextList(markerFormat: .disc, options: 0)]
        pasted.append(NSAttributedString(string: "\t•\tEerste punt\n\t•\tTweede punt", attributes: [.font: body, .paragraphStyle: list]))

        let font = NSFont.systemFont(ofSize: 13)
        let clean = NoteFormat.sanitize(pasted, font: font)
        #expect(clean.string == "Kop van de pagina\nLees dit artikel met vet en schuin.\n\nEerste punt\nTweede punt")

        let all = NSRange(location: 0, length: clean.length)
        var keys = Set<NSAttributedString.Key>()
        clean.enumerateAttributes(in: all) { attributes, _, _ in keys.formUnion(attributes.keys) }
        #expect(keys == [.font])
        clean.enumerateAttribute(.font, in: all) { value, _, _ in
            #expect((value as? NSFont)?.pointSize == 13)
        }

        let styled = traits(clean).filter { $0.1 || $0.2 }
        #expect(styled.map(\.0) == ["vet", "schuin"])
        #expect(styled.map(\.1) == [true, false])
        #expect(styled.map(\.2) == [false, true])
        #expect(NoteFormat.markdown(from: clean) == "Kop van de pagina\n\nLees dit artikel met **vet** en *schuin*.\n\n\n\nEerste punt\n\nTweede punt")
        // (an empty paragraph is a blank line of its own in Markdown)
    }
}
