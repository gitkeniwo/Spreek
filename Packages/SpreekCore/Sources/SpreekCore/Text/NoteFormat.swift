import AppKit
import Foundation

/// Notes are stored as a restricted Markdown string: `**bold**`, `*italic*` (`***both***`),
/// `\*` / `\\` escapes, and paragraphs separated by a blank line. Everything else is plain text.
///
/// In attributed form each paragraph is one line (separated by `"\n"`); bold and italic are
/// `inlinePresentationIntent` (`AttributedString`) or font traits (`NSAttributedString`).
/// Nothing is ever truncated.
public enum NoteFormat {
    /// A stretch of text with one style.
    struct Run: Equatable {
        var text: String
        var bold = false
        var italic = false
    }

    typealias Paragraph = [Run]

    // MARK: Markdown ⇄ AttributedString

    public static func attributedString(fromMarkdown markdown: String) -> AttributedString {
        var result = AttributedString()
        for (index, paragraph) in parse(markdown).enumerated() {
            if index > 0 { result.append(AttributedString("\n")) }
            for run in paragraph {
                var piece = AttributedString(run.text)
                if let intent = intent(bold: run.bold, italic: run.italic) {
                    piece.inlinePresentationIntent = intent
                }
                result.append(piece)
            }
        }
        return result
    }

    public static func markdown(from attributed: AttributedString) -> String {
        var runs: [Run] = []
        for run in attributed.runs {
            let intent = run.inlinePresentationIntent ?? []
            runs.append(Run(
                text: String(attributed[run.range].characters),
                bold: intent.contains(.stronglyEmphasized),
                italic: intent.contains(.emphasized)
            ))
        }
        return serialize(paragraphs(splitting: runs))
    }

    /// The note without markup, paragraphs separated by `"\n"` (for search and previews).
    public static func plainText(fromMarkdown markdown: String) -> String {
        parse(markdown).map { $0.map(\.text).joined() }.joined(separator: "\n")
    }

    // MARK: Markdown ⇄ NSAttributedString

    /// The note as editor text: `font` for plain runs, its bold/italic variants for the rest.
    public static func nsAttributedString(fromMarkdown markdown: String, font: NSFont = defaultFont) -> NSAttributedString {
        render(parse(markdown), font: font)
    }

    /// Reads bold/italic from font traits (or `inlinePresentationIntent`); everything else is dropped.
    public static func markdown(from attributed: NSAttributedString) -> String {
        serialize(paragraphs(from: attributed, dropHeadings: false))
    }

    /// Reduces pasted rich text to what a note can hold: text, paragraphs, bold and italic.
    /// Links, colors, fonts and sizes are dropped; headings become plain lines; list items lose
    /// their bullets/numbers and become plain lines; runs of blank lines collapse to one.
    public static func sanitize(_ attributed: NSAttributedString, font: NSFont = defaultFont) -> NSAttributedString {
        var paragraphs = paragraphs(from: attributed, dropHeadings: true)
        // Collapse blank-line runs and trim blank lines at both ends.
        var collapsed: [Paragraph] = []
        for paragraph in paragraphs {
            let isBlank = paragraph.allSatisfy { $0.text.allSatisfy(\.isWhitespace) }
            if isBlank {
                if let last = collapsed.last, !last.isEmpty { collapsed.append([]) }
            } else {
                collapsed.append(paragraph)
            }
        }
        while collapsed.last?.isEmpty == true { collapsed.removeLast() }
        paragraphs = collapsed
        return render(paragraphs, font: font)
    }

    public static var defaultFont: NSFont { .systemFont(ofSize: 13) }

    // MARK: Parsing

    private enum Token {
        case text(String)
        /// A `*` (italic) or `**` (bold) delimiter; `literal` is set when it doesn't pair up.
        case marker(bold: Bool, canOpen: Bool, canClose: Bool)
    }

    static func parse(_ markdown: String) -> [Paragraph] {
        let normalized = normalizeNewlines(markdown)
        var paragraphs: [Paragraph] = []
        for block in normalized.components(separatedBy: "\n\n") {
            for line in block.components(separatedBy: "\n") {
                paragraphs.append(parseLine(line))
            }
        }
        return paragraphs
    }

    private static func parseLine(_ line: String) -> Paragraph {
        let characters = Array(line)
        var tokens: [Token] = []
        var text = ""
        func flushText() {
            if !text.isEmpty { tokens.append(.text(text)) }
            text = ""
        }

        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\\", index + 1 < characters.count, characters[index + 1] == "*" || characters[index + 1] == "\\" {
                text.append(characters[index + 1])
                index += 2
                continue
            }
            guard character == "*" else {
                text.append(character)
                index += 1
                continue
            }
            var end = index
            while end < characters.count, characters[end] == "*" { end += 1 }
            let count = end - index
            guard count <= 3 else {
                text.append(String(repeating: "*", count: count))
                index = end
                continue
            }
            let before = index > 0 ? characters[index - 1] : nil
            let after = end < characters.count ? characters[end] : nil
            let canOpen = after.map { !$0.isWhitespace } ?? false
            let canClose = before.map { !$0.isWhitespace } ?? false
            flushText()
            if count >= 2 { tokens.append(.marker(bold: true, canOpen: canOpen, canClose: canClose)) }
            if count != 2 { tokens.append(.marker(bold: false, canOpen: canOpen, canClose: canClose)) }
            index = end
        }
        flushText()

        // Pair delimiters per kind; anything unpaired is literal text.
        var paired = Set<Int>()
        var open: [Bool: Int] = [:]
        for (position, token) in tokens.enumerated() {
            guard case .marker(let bold, let canOpen, let canClose) = token else { continue }
            if let opener = open[bold], canClose {
                paired.insert(opener)
                paired.insert(position)
                open[bold] = nil
            } else if open[bold] == nil, canOpen {
                open[bold] = position
            }
        }

        var runs: [Run] = []
        var bold = false
        var italic = false
        func append(_ string: String) {
            if let last = runs.last, last.bold == bold, last.italic == italic {
                runs[runs.count - 1].text += string
            } else {
                runs.append(Run(text: string, bold: bold, italic: italic))
            }
        }
        for (position, token) in tokens.enumerated() {
            switch token {
            case .text(let string):
                append(string)
            case .marker(let isBold, _, _):
                if paired.contains(position) {
                    if isBold { bold.toggle() } else { italic.toggle() }
                } else {
                    append(isBold ? "**" : "*")
                }
            }
        }
        return runs
    }

    // MARK: Serializing

    static func serialize(_ paragraphs: [Paragraph]) -> String {
        paragraphs.map(serializeLine).joined(separator: "\n\n")
    }

    private static func serializeLine(_ paragraph: Paragraph) -> String {
        // Styled whitespace at a run's edges keeps only the style it shares with the neighbor on
        // that side, so `**word **` never appears (it wouldn't parse back as bold).
        let source = paragraph.filter { !$0.text.isEmpty }
        var runs: [Run] = []
        func append(_ text: Substring, bold: Bool, italic: Bool) {
            guard !text.isEmpty else { return }
            if let last = runs.last, last.bold == bold, last.italic == italic {
                runs[runs.count - 1].text += text
            } else {
                runs.append(Run(text: String(text), bold: bold, italic: italic))
            }
        }
        for (index, run) in source.enumerated() {
            guard run.bold || run.italic else {
                append(run.text[...], bold: false, italic: false)
                continue
            }
            let previous = index > 0 ? source[index - 1] : Run(text: "")
            let next = index + 1 < source.count ? source[index + 1] : Run(text: "")
            let leading = run.text.prefix { $0.isWhitespace }
            let rest = run.text.dropFirst(leading.count)
            let trailingCount = rest.reversed().prefix { $0.isWhitespace }.count
            append(leading, bold: run.bold && previous.bold, italic: run.italic && previous.italic)
            append(rest.dropLast(trailingCount), bold: run.bold, italic: run.italic)
            append(rest.suffix(trailingCount), bold: run.bold && next.bold, italic: run.italic && next.italic)
        }

        var output = ""
        var bold = false
        var italic = false
        func transition(toBold newBold: Bool, italic newItalic: Bool) {
            // Close inner (italic) before outer (bold), then open.
            if italic, !newItalic { output += "*"; italic = false }
            if bold, !newBold { output += "**"; bold = false }
            if !bold, newBold { output += "**"; bold = true }
            if !italic, newItalic { output += "*"; italic = true }
        }
        for run in runs {
            transition(toBold: run.bold, italic: run.italic)
            output += escape(run.text)
        }
        transition(toBold: false, italic: false)
        return output
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "*", with: "\\*")
    }

    // MARK: Attributed helpers

    private static func intent(bold: Bool, italic: Bool) -> InlinePresentationIntent? {
        var intent: InlinePresentationIntent = []
        if bold { intent.insert(.stronglyEmphasized) }
        if italic { intent.insert(.emphasized) }
        return intent.isEmpty ? nil : intent
    }

    /// Splits runs on `"\n"` into paragraphs (one per line).
    private static func paragraphs(splitting runs: [Run]) -> [Paragraph] {
        var paragraphs: [Paragraph] = [[]]
        for run in runs {
            let lines = normalizeNewlines(run.text).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                if index > 0 { paragraphs.append([]) }
                if !line.isEmpty {
                    paragraphs[paragraphs.count - 1].append(Run(text: line, bold: run.bold, italic: run.italic))
                }
            }
        }
        return paragraphs
    }

    private static func paragraphs(from attributed: NSAttributedString, dropHeadings: Bool) -> [Paragraph] {
        let full = NSRange(location: 0, length: attributed.length)
        let string = attributed.string as NSString

        // The most common font size (by characters) is body text; clearly bigger text is a heading.
        var sizes: [CGFloat: Int] = [:]
        attributed.enumerateAttribute(.font, in: full) { value, range, _ in
            if let font = value as? NSFont { sizes[font.pointSize, default: 0] += range.length }
        }
        let bodySize = sizes.max { $0.value < $1.value }?.key

        var runs: [Run] = []
        attributed.enumerateAttributes(in: full) { attributes, range, _ in
            let text = string.substring(with: range).replacingOccurrences(of: "\u{FFFC}", with: "")
            let font = attributes[.font] as? NSFont
            let intent = (attributes[.inlinePresentationIntent] as? NSNumber)
                .map { InlinePresentationIntent(rawValue: $0.uintValue) } ?? []
            let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle

            var isHeading = false
            if dropHeadings {
                if let paragraphStyle, paragraphStyle.headerLevel > 0 { isHeading = true }
                if let font, let bodySize, font.pointSize >= bodySize * 1.15 { isHeading = true }
            }

            let bold = intent.contains(.stronglyEmphasized) || (font.map(isBold) ?? false)
            let italic = intent.contains(.emphasized) || (font.map(isItalic) ?? false)
                || ((attributes[.obliqueness] as? NSNumber)?.doubleValue ?? 0) > 0
            runs.append(Run(text: text, bold: bold && !isHeading, italic: italic && !isHeading))
        }

        var paragraphs = paragraphs(splitting: runs)
        // List items (paragraphs with an `NSTextList`) lose their bullet or number.
        var offset = 0
        for (index, line) in normalizeNewlines(attributed.string).components(separatedBy: "\n").enumerated()
        where index < paragraphs.count {
            if offset < attributed.length,
               let style = attributed.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle,
               !style.textLists.isEmpty {
                paragraphs[index] = dropListMarker(paragraphs[index])
            }
            offset += (line as NSString).length + 1
        }
        return paragraphs
    }

    nonisolated(unsafe) private static let listMarker = /^\s*(?:[•◦▪▫‣⁃●○■□–—\-*+]|\d{1,3}[.)]|[a-zA-Z][.)]|[ivxIVX]{1,4}[.)])\s+/

    private static func dropListMarker(_ paragraph: Paragraph) -> Paragraph {
        let text = paragraph.map(\.text).joined()
        guard let match = text.prefixMatch(of: listMarker) else { return paragraph }
        var toDrop = text.distance(from: text.startIndex, to: match.range.upperBound)
        var result: Paragraph = []
        for var run in paragraph {
            if toDrop > 0 {
                let count = min(toDrop, run.text.count)
                run.text.removeFirst(count)
                toDrop -= count
            }
            if !run.text.isEmpty { result.append(run) }
        }
        return result
    }

    private static func render(_ paragraphs: [Paragraph], font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let bold = styled(font, bold: true, italic: false)
        let italic = styled(font, bold: false, italic: true)
        let both = styled(font, bold: true, italic: true)
        for (index, paragraph) in paragraphs.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n", attributes: [.font: font])) }
            for run in paragraph {
                let runFont = run.bold ? (run.italic ? both : bold) : (run.italic ? italic : font)
                result.append(NSAttributedString(string: run.text, attributes: [.font: runFont]))
            }
        }
        return result
    }

    private static func styled(_ font: NSFont, bold: Bool, italic: Bool) -> NSFont {
        var traits = font.fontDescriptor.symbolicTraits
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }

    private static func isBold(_ font: NSFont) -> Bool {
        if font.fontDescriptor.symbolicTraits.contains(.bold) { return true }
        let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        let weight = (traits?[.weight] as? NSNumber)?.doubleValue ?? 0
        return weight >= NSFont.Weight.semibold.rawValue - 0.01
    }

    private static func isItalic(_ font: NSFont) -> Bool {
        font.fontDescriptor.symbolicTraits.contains(.italic)
    }

    private static func normalizeNewlines(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
    }
}
