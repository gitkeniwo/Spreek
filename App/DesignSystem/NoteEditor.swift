import AppKit
import SpreekCore
import SwiftUI

/// Rounded note box with a bold/italic-only text editor. Edits arrive as restricted Markdown
/// (`NoteFormat`) through `onChange`, debounced; the last edit is flushed when the editor goes away.
/// Notes are never truncated: the editor grows with its text up to `maxTextHeight` (unlimited by
/// default, so the parent scrolls), then scrolls itself.
struct NoteEditor: View {
    enum Style {
        /// Dashboard and Folder Info: 34 pt toolbar (**B**, *I*, hint) above a hairline.
        case full
        /// Floating bar's pinned card: note icon + "Note" title, **B** / *I* on the right.
        case card
    }

    let markdown: String
    var onChange: (String) -> Void
    var style: Style = .full
    var background: Color = .field
    /// Mono "⌘B ⌘I · paste keeps bold & italic only" in the toolbar.
    var showsHint = true
    var maxTextHeight: CGFloat = .infinity
    var debounce: Duration = .milliseconds(400)
    /// Called when the text view is clicked, before it takes focus (the floating panel uses
    /// this to become key).
    var onBeginEditing: () -> Void = {}

    @State private var handle = NoteEditorHandle()
    @State private var textHeight: CGFloat = 20

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style == .full ? Radius.noteEditor : Radius.noteEditor + 2, style: .continuous)
        VStack(alignment: .leading, spacing: style == .full ? 0 : 4) {
            switch style {
            case .full:
                HStack(spacing: 2) {
                    formatButtons
                    Spacer(minLength: 8)
                    if showsHint { hint.padding(.trailing, 6) }
                }
                .padding(.horizontal, 6)
                .frame(height: 34)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.separator).frame(height: Metrics.hairline)
                }
            case .card:
                HStack(spacing: 4) {
                    Image(systemName: "note.text")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.fg2)
                    Text("Note")
                        .font(.spreekRounded(size: 12, weight: .heavy))
                        .foregroundStyle(Color.fg2)
                    Spacer(minLength: 8)
                    if showsHint { hint }
                    formatButtons
                }
                .frame(height: 26)
            }
            NoteTextView(
                markdown: markdown, onChange: onChange, debounce: debounce, onBeginEditing: onBeginEditing,
                handle: handle, height: $textHeight
            )
            .frame(height: min(max(textHeight, 20), maxTextHeight))
            .padding(style == .full ? EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: 14) : EdgeInsets())
        }
        .padding(style == .full ? EdgeInsets() : EdgeInsets(top: 6, leading: 12, bottom: 10, trailing: 8))
        .background(background, in: shape)
        .overlay(shape.strokeBorder(Color.separator, lineWidth: Metrics.hairline))
    }

    private var hint: some View {
        Text("⌘B ⌘I · paste keeps bold & italic only")
            .font(.spreekMono(size: 11))
            .foregroundStyle(Color.fg3)
            .lineLimit(1)
    }

    @ViewBuilder private var formatButtons: some View {
        Button { handle.toggle(.boldFontMask) } label: {
            Text("B").font(.system(size: 14, weight: .black))
        }
        .buttonStyle(.glyph(size: 28))
        .help("Bold (⌘B)")
        .accessibilityLabel("Bold")
        Button { handle.toggle(.italicFontMask) } label: {
            Text("I").font(.system(size: 15, design: .serif).italic())
        }
        .buttonStyle(.glyph(size: 28))
        .help("Italic (⌘I)")
        .accessibilityLabel("Italic")
    }
}

/// Settings › General › Notes, read by the AppKit text view (no SwiftUI environment there).
@MainActor
enum NoteSettings {
    /// Set by `AppModel` at launch.
    static weak var settings: AppSettings?

    /// Pasted rich text keeps only bold and italic (default on).
    static var pasteKeepsBoldItalicOnly: Bool {
        settings?.notesPasteKeepsBoldItalicOnly ?? true
    }
}

/// Lets the toolbar buttons reach the AppKit text view.
@MainActor
final class NoteEditorHandle {
    weak var textView: NoteNSTextView?

    func toggle(_ trait: NSFontTraitMask) {
        textView?.toggle(trait)
    }
}

/// `NSTextView` that keeps only bold and italic: ⌘B / ⌘I toggle them, pasted rich text is reduced.
final class NoteNSTextView: NSTextView {
    var onBeginEditing: () -> Void = {}

    override func mouseDown(with event: NSEvent) {
        onBeginEditing()
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
        else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers {
        case "b": toggle(.boldFontMask); return true
        case "i": toggle(.italicFontMask); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    override func paste(_ sender: Any?) {
        guard NoteSettings.pasteKeepsBoldItalicOnly else { return super.paste(sender) }
        let pasteboard = NSPasteboard.general
        if let rich = pasteboard.readObjects(forClasses: [NSAttributedString.self])?.first as? NSAttributedString {
            insertSanitized(rich)
        } else if let plain = pasteboard.string(forType: .string) {
            insertSanitized(NSAttributedString(string: plain))
        }
    }

    private func insertSanitized(_ attributed: NSAttributedString) {
        let clean = NSMutableAttributedString(attributedString: NoteFormat.sanitize(attributed))
        clean.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: clean.length))
        let range = selectedRange()
        guard shouldChangeText(in: range, replacementString: clean.string) else { return }
        textStorage?.replaceCharacters(in: range, with: clean)
        didChangeText()
        setSelectedRange(NSRange(location: range.location + clean.length, length: 0))
    }

    /// Toggles bold / italic on the selection, or for the next typed text.
    func toggle(_ trait: NSFontTraitMask) {
        let manager = NSFontManager.shared
        let range = selectedRange()
        let defaultFont = NoteFormat.defaultFont
        if range.length == 0 {
            let font = typingAttributes[.font] as? NSFont ?? defaultFont
            let has = manager.traits(of: font).contains(trait)
            typingAttributes[.font] = has ? manager.convert(font, toNotHaveTrait: trait) : manager.convert(font, toHaveTrait: trait)
            return
        }
        guard let storage = textStorage, shouldChangeText(in: range, replacementString: nil) else { return }
        let first = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? defaultFont
        let remove = manager.traits(of: first).contains(trait)
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = value as? NSFont ?? defaultFont
            let converted = remove ? manager.convert(font, toNotHaveTrait: trait) : manager.convert(font, toHaveTrait: trait)
            storage.addAttribute(.font, value: converted, range: subrange)
        }
        storage.endEditing()
        didChangeText()
    }
}

private struct NoteTextView: NSViewRepresentable {
    let markdown: String
    let onChange: (String) -> Void
    let debounce: Duration
    let onBeginEditing: () -> Void
    let handle: NoteEditorHandle
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NoteNSTextView()
        textView.isRichText = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.typingAttributes = [.font: NoteFormat.defaultFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: Self.paragraphStyle]
        textView.delegate = context.coordinator
        textView.onBeginEditing = onBeginEditing
        scrollView.documentView = textView
        // Re-measure when the width changes (window resize) so the editor never clips text.
        scrollView.contentView.postsFrameChangedNotifications = true
        context.coordinator.observeWidth(of: scrollView.contentView, textView: textView)
        handle.textView = textView
        context.coordinator.load(markdown, into: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NoteNSTextView else { return }
        textView.onBeginEditing = onBeginEditing
        handle.textView = textView
        // While an edit waits for its debounced save, the incoming markdown is stale.
        if !context.coordinator.hasPendingEdit, markdown != context.coordinator.lastMarkdown {
            context.coordinator.load(markdown, into: textView)
        }
        context.coordinator.reportHeight(of: textView)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.flush()
    }

    static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.15
        style.paragraphSpacing = 4
        return style
    }()

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextView
        var lastMarkdown = ""
        private var pending: (markdown: String, onChange: (String) -> Void)?
        private var saveTask: Task<Void, Never>?
        private var lastWidth: CGFloat = 0

        init(_ parent: NoteTextView) {
            self.parent = parent
        }

        func observeWidth(of view: NSView, textView: NSTextView) {
            NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification, object: view, queue: .main
            ) { [weak self, weak textView] _ in
                MainActor.assumeIsolated {
                    guard let self, let textView, abs(textView.frame.width - self.lastWidth) > 0.5 else { return }
                    self.lastWidth = textView.frame.width
                    self.reportHeight(of: textView)
                }
            }
        }

        var hasPendingEdit: Bool { pending != nil }

        /// Delivers a pending edit now.
        func flush() {
            saveTask?.cancel()
            saveTask = nil
            if let pending {
                self.pending = nil
                pending.onChange(pending.markdown)
            }
        }

        func load(_ markdown: String, into textView: NSTextView) {
            lastMarkdown = markdown
            let attributed = NSMutableAttributedString(attributedString: NoteFormat.nsAttributedString(fromMarkdown: markdown))
            let whole = NSRange(location: 0, length: attributed.length)
            attributed.addAttribute(.foregroundColor, value: NSColor.labelColor, range: whole)
            attributed.addAttribute(.paragraphStyle, value: NoteTextView.paragraphStyle, range: whole)
            textView.textStorage?.setAttributedString(attributed)
            reportHeight(of: textView)
        }

        func textDidEndEditing(_ notification: Notification) {
            flush()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, let storage = textView.textStorage else { return }
            let markdown = NoteFormat.markdown(from: storage)
            lastMarkdown = markdown
            // Bound to the current target: if the editor is reused for another sentence before
            // the delay ends, the edit still lands on the one it was typed into.
            pending = (markdown, parent.onChange)
            saveTask?.cancel()
            let delay = parent.debounce
            saveTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.flush()
            }
            reportHeight(of: textView)
        }

        func reportHeight(of textView: NSTextView) {
            guard let container = textView.textContainer, let layout = textView.layoutManager else { return }
            layout.ensureLayout(for: container)
            let height = ceil(layout.usedRect(for: container).height) + 2
            if abs(height - parent.height) > 0.5 {
                DispatchQueue.main.async { [parent] in parent.height = height }
            }
        }
    }
}

#Preview {
    NoteEditor(markdown: "**gezeik** — *informal*: endless complaining.\n\nSecond paragraph.", onChange: { _ in })
        .frame(width: 420)
        .padding()
    NoteEditor(markdown: "**Ja, nee** — typisch Nederlands.", onChange: { _ in }, style: .card, showsHint: false)
        .frame(width: 420)
        .padding()
}
