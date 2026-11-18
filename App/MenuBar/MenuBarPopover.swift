import AppKit
import SpreekCore
import SwiftData
import SwiftUI

/// The `MenuBarExtra(.window)` content: Control-Center-style tiles over darker glass.
struct MenuBarPopover: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.permission.showsExplainer {
                AccessibilityExplainer(permission: model.permission)
                    .padding(12)
                    .tileBackground()
            }
            HStack(spacing: 10) {
                LanguageTile()
                MuteTile()
                PinTile()
            }
            NowSpeakingTile()
            SpeedTile()
            RecentSection()
            MenuSeparator()
            FavoritesSection()
            MenuSeparator()
            VStack(spacing: 0) {
                MenuRow("Open Dashboard…", shortcut: "⌘D") { model.openDashboard() }
                    .keyboardShortcut("d")
                MenuRow("Settings…", shortcut: "⌘,") { model.openDashboard(.settings(.voices)) }
                    .keyboardShortcut(",")
                MenuRow("Quit Spreek", shortcut: "⌘Q") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            #if DEBUG
            DebugSection()
            #endif
        }
        .padding(12)
        .frame(width: 340)
        .background(Color.popoverTint)
        .environment(\.badgeStyle, model.settings.badgeStyle)
        .onAppear { model.permission.refresh() }
        .background(WindowReader { model.menuBarWindow = $0 })
    }
}

/// Reports the window hosting this view once it's attached.
private struct WindowReader: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { onWindow(window) } }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if let window = view.window { onWindow(window) }
    }
}

// MARK: - Tiles

private struct TileBackground: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
        content
            .background(Color.tile, in: shape)
            .overlay(shape.strokeBorder(Color.tileBorder, lineWidth: Metrics.hairline))
    }
}

extension View {
    fileprivate func tileBackground() -> some View { modifier(TileBackground()) }
}

/// 36 pt circle with a glyph; accent when `active`.
private struct TileCircle: View {
    let symbol: String
    var active: Bool
    var size: CGFloat = 17

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(active ? Color.white : Color.fg)
            .frame(width: 36, height: 36)
            .background(Circle().fill(active ? Color.accentColor : Color.glassCircle))
    }
}

/// Wide tile: current / last detected language, menu to fix one or auto-detect.
private struct LanguageTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Button {
                model.forcedLanguage = nil
            } label: {
                if model.forcedLanguage == nil { Label("Auto-detect", systemImage: "checkmark") } else { Text("Auto-detect") }
            }
            Divider()
            ForEach(model.pickerLanguages(including: model.forcedLanguage), id: \.self) { language in
                Button {
                    model.forcedLanguage = language
                } label: {
                    let title = "Always \(language.info.nativeName)"
                    if model.forcedLanguage == language { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
        } label: {
            HStack(spacing: 10) {
                TileCircle(symbol: "waveform", active: true, size: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text((model.forcedLanguage ?? model.displayLanguage).info.nativeName)
                        .font(.spreekRounded(size: 15, weight: .heavy))
                        .foregroundStyle(Color.fg)
                    Text(model.forcedLanguage == nil ? "Auto-detect" : "Fixed language")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.fg2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 64, maxHeight: 64)
            .tileBackground()
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help("Language")
    }
}

private struct MuteTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button { model.isMuted.toggle() } label: {
            TileCircle(symbol: "speaker.slash.fill", active: model.isMuted)
                .frame(width: 64, height: 64)
                .tileBackground()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.isMuted ? "Unmute speech" : "Mute speech")
        .accessibilityLabel(model.isMuted ? "Unmute speech" : "Mute speech")
    }
}

private struct PinTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let pinned = model.bar.isPinned
        Button { model.setBarPinned(!pinned) } label: {
            TileCircle(symbol: "pin.fill", active: pinned, size: 16)
                .frame(width: 64, height: 64)
                .tileBackground()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(pinned ? "Unpin floating bar" : "Pin floating bar")
        .accessibilityLabel(pinned ? "Floating bar pinned" : "Pin floating bar")
    }
}

/// Control Center Music-style tile: artwork badge, sentence, voice, progress, transport.
private struct NowSpeakingTile: View {
    @Environment(AppModel.self) private var model
    @Environment(\.badgeStyle) private var badgeStyle

    var body: some View {
        let speech = model.speech
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                LanguageBadge(language: model.displayLanguage, style: badgeStyle, size: .xl)
                VStack(alignment: .leading, spacing: 4) {
                    if let text = speech.currentText {
                        Text(highlightedSentence(text, range: speech.highlightedRange))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.fg)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Nothing playing")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.fg2)
                    }
                    Text(voiceLine)
                        .font(.spreekMono(size: 11))
                        .foregroundStyle(Color.fg2)
                        .lineLimit(1)
                    if let hint = FallbackHint(speech: speech) {
                        HStack(spacing: 6) {
                            FallbackDot(hint: hint, size: 6)
                            Text(hint.first)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.fg2)
                                .lineLimit(1)
                        }
                        .help(hint.tooltip)
                    }
                }
                Spacer(minLength: 0)
            }
            TimedProgress(current: speech.currentTime, duration: speech.duration, fraction: speech.progress, onSeek: speech.seek(toFraction:))
            ZStack {
                HStack(spacing: 14) {
                    Button { model.playPrevious() } label: {
                        Image(systemName: "backward.fill").font(.system(size: 19))
                    }
                    .buttonStyle(.glyph(size: 36, color: .fg2))
                    .help("Previous sentence")
                    .accessibilityLabel("Previous sentence")
                    Button { model.togglePlayback() } label: {
                        Image(systemName: showsPause ? "pause.fill" : "play.fill")
                            .font(.system(size: 24, weight: .bold))
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.glyph(size: 40))
                    .disabled(speech.currentText == nil && model.lastSentence == nil)
                    .help(showsPause ? "Pause" : "Play")
                    .accessibilityLabel(showsPause ? "Pause" : "Play")
                    Button { model.playNext() } label: {
                        Image(systemName: "forward.fill").font(.system(size: 19))
                    }
                    .buttonStyle(.glyph(size: 36, color: .fg2))
                    .help("Next sentence")
                    .accessibilityLabel("Next sentence")
                }
                HStack {
                    SpeedPill(rate: model.playbackRate) { model.replayCurrent(at: $0) }
                        .disabled(speech.currentText == nil)
                    Spacer()
                    let sentence = model.currentSentence
                    Button {
                        if let sentence { model.toggleFavorite(sentence) }
                    } label: {
                        FavoriteGlyph(isFavorite: sentence?.isFavorite ?? false, size: 17)
                    }
                    .buttonStyle(.glyph(size: 30))
                    .disabled(sentence == nil)
                    .help("Save to favorites (⌥F)")
                    .accessibilityLabel("Save to favorites")
                }
            }
            if let message = model.statusMessage {
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.fg2)
            }
        }
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 10, trailing: 12))
        .tileBackground()
    }

    private var showsPause: Bool {
        switch model.speech.state {
        case .playing, .synthesizing: true
        default: false
        }
    }

    private var voiceLine: String {
        let speech = model.speech
        if case .failed = speech.state { return "Couldn't speak this" }
        if case .synthesizing = speech.state { return "Synthesizing…" }
        guard let name = speech.voiceName, let provider = speech.provider else { return "⌥S speaks selection" }
        return "\(name) · \(provider.displayName)"
    }
}

/// CC-style slider: white fill with a clock glyph, round knob, mono value.
private struct SpeedTile: View {
    @Environment(AppModel.self) private var model
    private static let range = 0.5...1.5
    private static let step = 0.05

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Speed")
                    .font(.spreekRounded(size: 13.5, weight: .heavy))
                    .foregroundStyle(Color.fg)
                Spacer()
                Text(PlaybackFormat.speed(model.rate))
                    .font(.spreekMono(size: 12))
                    .foregroundStyle(Color.fg2)
            }
            GeometryReader { proxy in
                let width = proxy.size.width
                let fraction = (min(max(model.rate, Self.range.lowerBound), Self.range.upperBound) - Self.range.lowerBound)
                    / (Self.range.upperBound - Self.range.lowerBound)
                let knobX = 13 + (width - 26) * fraction
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.track)
                    Capsule()
                        .fill(Color.knob)
                        .frame(width: knobX + 13)
                        .overlay(alignment: .leading) {
                            Image(systemName: "clock")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x6B6B72))
                                .padding(.leading, 8)
                        }
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.35), radius: 2.5, y: 1)
                        .frame(width: 26, height: 26)
                        .offset(x: knobX - 13)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let raw = (value.location.x - 13) / max(width - 26, 1)
                    let rate = Self.range.lowerBound + min(max(raw, 0), 1) * (Self.range.upperBound - Self.range.lowerBound)
                    model.rate = (rate / Self.step).rounded() * Self.step
                })
            }
            .frame(height: 26)
            .accessibilityElement()
            .accessibilityLabel("Speed")
            .accessibilityValue(PlaybackFormat.speed(model.rate))
            .accessibilityAdjustableAction { direction in
                let delta = direction == .increment ? Self.step : -Self.step
                model.rate = min(max(model.rate + delta, Self.range.lowerBound), Self.range.upperBound)
            }
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 12, trailing: 12))
        .tileBackground()
    }
}

// MARK: - Lists

/// Badge + truncated sentence + small play; click replays.
private struct SentenceRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.badgeStyle) private var badgeStyle
    let sentence: Sentence
    @State private var hovering = false

    var body: some View {
        Button { model.replay(sentence) } label: {
            HStack(spacing: 9) {
                LanguageBadge(language: sentence.effectiveLanguage, style: badgeStyle, size: .s)
                Text(sentence.text)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.fg)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Image(systemName: "play.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.fg3)
                    .frame(width: 24, height: 24)
            }
            .padding(.leading, 6)
            .padding(.trailing, 4)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? Color.glassHover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Play again")
        .accessibilityLabel("Play again")
    }
}

private struct RecentSection: View {
    @Query(Self.descriptor) private var recent: [Sentence]

    private static var descriptor: FetchDescriptor<Sentence> {
        var descriptor = FetchDescriptor<Sentence>(sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)])
        descriptor.fetchLimit = 4
        return descriptor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent")
                    .font(.spreekRounded(size: 13, weight: .heavy))
                    .foregroundStyle(Color.fg2)
                Spacer()
                Text("⌥S speaks selection")
                    .font(.spreekMono(size: 11))
                    .foregroundStyle(Color.fg3)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            if recent.isEmpty {
                Text("Select text anywhere and press ⌥S.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.fg3)
                    .padding(.horizontal, 6)
                    .frame(height: 28)
            }
            ForEach(recent) { SentenceRow(sentence: $0) }
        }
    }
}

/// "Favorites ›" — expands in place, like a submenu.
private struct FavoritesSection: View {
    @Query(
        filter: #Predicate<Sentence> { $0.isFavorite },
        sort: [SortDescriptor(\Sentence.favoritedAt, order: .reverse)]
    ) private var favorites: [Sentence]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            MenuRow("Favorites", trailing: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }) {
                withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
            }
            if expanded {
                if favorites.isEmpty {
                    Text("No favorites yet — ⌥F saves the current sentence.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.fg3)
                        .padding(.horizontal, 6)
                        .frame(height: 28)
                }
                ForEach(favorites.prefix(8)) { SentenceRow(sentence: $0) }
            }
        }
    }
}

// MARK: - Menu rows

private struct MenuSeparator: View {
    var body: some View {
        Rectangle().fill(Color.separator).frame(height: 1).padding(.horizontal, 2)
    }
}

private struct MenuRow<Trailing: View>: View {
    let title: String
    let trailing: Trailing
    let action: () -> Void
    @State private var hovering = false

    init(_ title: String, @ViewBuilder trailing: () -> Trailing, action: @escaping () -> Void) {
        self.title = title
        self.trailing = trailing()
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 13))
                Spacer()
                trailing
            }
            .foregroundStyle(Color.fg)
            .padding(.horizontal, 6)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? Color.glassHover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

extension MenuRow where Trailing == AnyView {
    init(_ title: String, shortcut: String, action: @escaping () -> Void) {
        self.init(title, trailing: {
            AnyView(ShortcutHint(shortcut))
        }, action: action)
    }
}

/// Native-menu-style key equivalent: the modifiers right-aligned in one column, the key
/// left-aligned in a fixed column, so "⌘D", "⌘," and "⌘Q" line up.
private struct ShortcutHint: View {
    let modifiers: String
    let key: String

    init(_ shortcut: String) {
        modifiers = String(shortcut.dropLast())
        key = String(shortcut.suffix(1))
    }

    var body: some View {
        HStack(spacing: 1) {
            Text(modifiers).frame(minWidth: 14, alignment: .trailing)
            Text(key).frame(width: 14, alignment: .leading)
        }
        .font(.system(size: 13))
        .foregroundStyle(Color.fg3)
    }
}

// MARK: - Accessibility explainer

/// One-time explainer shown while Spreek lacks the Accessibility permission.
private struct AccessibilityExplainer: View {
    let permission: AccessibilityPermission

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Allow Accessibility access")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.fg)
            Text("To read the text you select in other apps, Spreek needs to be turned on in System Settings › Privacy & Security › Accessibility.")
                .font(.system(size: 12))
                .foregroundStyle(Color.fg2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Open System Settings…") { permission.openSystemSettings() }
                    .buttonStyle(.borderedProminent)
                Button("Not now") { permission.explainerDismissed = true }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.fg3)
            }
        }
    }
}

// MARK: - Debug

#if DEBUG
/// Collapsed "Debug" disclosure (debug builds only).
private struct DebugSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Query private var sentences: [Sentence]
    @State private var expanded = false
    @State private var message: String?

    private static let dutchSample = "Goedemorgen! Zullen we straks samen een kopje koffie drinken?"
    private static let germanSample = "Guten Morgen! Wollen wir nachher zusammen einen Kaffee trinken?"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MenuSeparator()
            MenuRow("Debug", trailing: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }) {
                withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
            }
            .foregroundStyle(Color.fg3)
            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Button("Speak sample (NL)") { model.speech.speak(text: Self.dutchSample, source: .debug) }
                        Button("Speak sample (DE)") { model.speech.speak(text: Self.germanSample, source: .debug) }
                    }
                    HStack(spacing: 12) {
                        Button("Seed sample library") {
                            message = SampleLibrary.seed(into: model.library) ? "Seeded." : "Already seeded."
                        }
                        Text("\(sentences.count) sentences\(message.map { " · \($0)" } ?? "")")
                            .font(.spreekMono(size: 11))
                            .foregroundStyle(Color.fg3)
                    }
                    HStack(spacing: 12) {
                        Button("Design Preview…") {
                            openWindow(id: "design-preview")
                            NSApp.activate()
                        }
                        Text("state: \(model.speech.state.name) · bar: \(String(describing: model.bar.phase))")
                            .font(.spreekMono(size: 11))
                            .foregroundStyle(Color.fg3)
                    }
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
                .padding(.horizontal, 6)
            }
        }
    }
}
#endif
