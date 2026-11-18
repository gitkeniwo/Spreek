import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let speakSelection = Self("speakSelection", default: .init(.s, modifiers: [.option]))
    static let speakSlower = Self("speakSlower", default: .init(.s, modifiers: [.option, .shift]))
    static let replayLast = Self("replayLast", default: .init(.r, modifiers: [.option]))
    static let saveFavorite = Self("saveFavorite", default: .init(.f, modifiers: [.option]))
    static let pauseResume = Self("pauseResume", default: .init(.p, modifiers: [.option]))
    /// No default: the user records one in Settings › Shortcuts.
    static let speakClipboard = Self("speakClipboard")
}

@MainActor
enum Hotkeys {
    /// Handlers fire on key-up, so the user's fingers are (mostly) off the keys before we post ⌘C.
    static func register(_ model: AppModel) {
        KeyboardShortcuts.onKeyUp(for: .speakSelection) { [weak model] in model?.speakSelection() }
        KeyboardShortcuts.onKeyUp(for: .speakSlower) { [weak model] in model?.speakSelection(slower: true) }
        KeyboardShortcuts.onKeyUp(for: .replayLast) { [weak model] in model?.replayLast() }
        KeyboardShortcuts.onKeyUp(for: .saveFavorite) { [weak model] in model?.saveFavorite() }
        // Pauses / resumes the loaded sentence in place (no new synthesis); no-op when idle.
        KeyboardShortcuts.onKeyUp(for: .pauseResume) { [weak model] in model?.speech.togglePause() }
        KeyboardShortcuts.onKeyUp(for: .speakClipboard) { [weak model] in model?.speakClipboard() }
    }
}
