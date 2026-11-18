import SpreekCore
import SwiftData
import SwiftUI

/// Root of the floating panel: the compact capsule (playing / finished) or, when pinned,
/// the expanded card.
struct FloatingBarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let expanded = model.bar.isExpanded
        let shape = RoundedRectangle(cornerRadius: expanded ? Radius.pinnedCard : Metrics.floatingBarHeight / 2, style: expanded ? .continuous : .circular)
        Group {
            if expanded {
                PinnedCard()
            } else {
                CompactBar()
            }
        }
        .frame(width: FloatingBarLayout.width)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.badgeStyle, model.settings.badgeStyle)
        .glassBackground(.hudWindow, in: shape)
        .overlay(shape.inset(by: -Metrics.hairline).strokeBorder(Color.glassOuterLine, lineWidth: Metrics.hairline))
        .background(ShadowOnly(shape: shape))
        // Dragging the glass moves the panel; buttons, the progress line and the note editor
        // keep their own clicks and drags.
        .contentShape(shape)
        .gesture(WindowDragGesture())
        .animation(.snappy(duration: 0.25), value: expanded)
    }
}

enum FloatingBarLayout {
    static let width: CGFloat = 560
    /// Transparent margin around the glass so its shadow (0 16 44) isn't clipped by the panel.
    static let margins = NSEdgeInsets(top: 24, left: 36, bottom: 58, right: 36)
    /// Gap between the bar's bottom edge and the visible frame (Dock / screen bottom).
    static let bottomGap: CGFloat = 34
}

/// Drop shadow of `shape` without filling it, so the glass stays see-through.
private struct ShadowOnly<S: InsettableShape>: View {
    let shape: S

    var body: some View {
        shape.inset(by: 1).fill(Color.black)
            .shadow(color: .black.opacity(0.3), radius: 22, y: 16)
            .mask {
                ZStack {
                    Rectangle().padding(-120)
                    shape.fill(Color.black).blendMode(.destinationOut)
                }
                .compositingGroup()
            }
            .allowsHitTesting(false)
    }
}

// MARK: - Compact

/// `[badge] [sentence + progress] │ [replay · PAUSE · 0.8×] │ [star · dashboard · pin · close]`.
private struct CompactBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.badgeStyle) private var badgeStyle

    var body: some View {
        let speech = model.speech
        let finished = model.bar.phase == .finished
        HStack(spacing: 10) {
            LanguageBadge(language: model.displayLanguage, style: badgeStyle, size: .m)
            if let failure = model.speechFailure {
                FailureToast(message: failure)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        if let hint = FallbackHint(speech: speech) { FallbackDot(hint: hint) }
                        Text(highlightedSentence(speech.currentText ?? "", range: model.barHighlightRange))
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Color.fg)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    if !finished {
                        ProgressLine(fraction: speech.progress, height: 3, fill: .accentColor, onSeek: speech.seek(toFraction:))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            BarDivider()
            HStack(spacing: 2) {
                Button { speech.replay() } label: {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(.glyph(color: .fg2))
                .help("Replay")
                .accessibilityLabel("Replay")
                PlayPauseButton(size: 26, frame: 38)
                SpeedPill(rate: model.playbackRate, filled: false) { model.replayCurrent(at: $0) }
            }
            BarDivider()
            HStack(spacing: 0) {
                FavoriteButton()
                Button { model.openDashboard(selecting: model.currentSentence ?? model.lastSentence) } label: {
                    Image(systemName: "sidebar.left").font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(.glyph())
                .help("Open in Dashboard")
                .accessibilityLabel("Open in Dashboard")
                Button { model.setBarPinned(true) } label: {
                    Image(systemName: "pin").font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(.glyph())
                .help("Pin bar")
                .accessibilityLabel("Pin bar")
                CloseButton(countdown: finished)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: Metrics.floatingBarHeight)
    }
}

/// Both engines failed: shown in place of the sentence until the next speech.
private struct FailureToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.white, Color.orange)
                .symbolRenderingMode(.palette)
            VStack(alignment: .leading, spacing: 1) {
                Text("Couldn’t speak this sentence")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.fg)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.fg3)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .help(message)
        .accessibilityElement(children: .combine)
    }
}

private struct BarDivider: View {
    var body: some View {
        Rectangle().fill(Color.separator).frame(width: 1, height: 26)
    }
}

/// Big pause / play glyph, emphasized by size only (no circle).
private struct PlayPauseButton: View {
    @Environment(AppModel.self) private var model
    var size: CGFloat
    var frame: CGFloat

    var body: some View {
        let showsPause = switch model.speech.state {
        case .playing, .synthesizing: true
        default: false
        }
        Button { model.togglePlayback() } label: {
            Image(systemName: showsPause ? "pause.fill" : "play.fill")
                .font(.system(size: size, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.glyph(size: frame))
        .help(showsPause ? "Pause" : "Play")
        .accessibilityLabel(showsPause ? "Pause" : "Play")
    }
}

private struct FavoriteButton: View {
    @Environment(AppModel.self) private var model
    var frame: CGFloat = 32

    var body: some View {
        let sentence = model.currentSentence
        Button {
            if let sentence { model.toggleFavorite(sentence) }
        } label: {
            FavoriteGlyph(isFavorite: sentence?.isFavorite ?? false, size: 16)
        }
        .buttonStyle(.glyph(size: frame))
        .disabled(sentence == nil)
        .help(sentence?.isFavorite == true ? "Saved to favorites (⌥F)" : "Save to favorites (⌥F)")
        .accessibilityLabel(sentence?.isFavorite == true ? "Remove from Favorites" : "Save to Favorites")
    }
}

/// `xmark`, or while finishing the accent countdown ring with the seconds left.
private struct CloseButton: View {
    @Environment(AppModel.self) private var model
    var countdown: Bool
    var frame: CGFloat = 32

    var body: some View {
        Button { model.closeBar() } label: {
            if countdown {
                ZStack {
                    Circle().stroke(Color.track, lineWidth: 2.4)
                    Circle()
                        .trim(from: 0, to: model.bar.countdownFraction)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.05), value: model.bar.countdownFraction)
                    Text("\(model.bar.displayedSeconds)")
                        .font(.spreekRounded(size: 12, weight: .black))
                        .monospacedDigit()
                }
                .frame(width: 24, height: 24)
            } else {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
            }
        }
        .buttonStyle(.glyph(size: frame))
        .help(countdown ? "Close — closes automatically in \(model.bar.displayedSeconds) s" : "Close")
        .accessibilityLabel("Close")
    }
}

// MARK: - Pinned card

private struct PinnedCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.beginPanelEditing) private var beginEditing
    @Environment(\.badgeStyle) private var badgeStyle

    var body: some View {
        let speech = model.speech
        let sentence = model.currentSentence
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                LanguageBadge(language: model.displayLanguage, style: badgeStyle, size: .m)
                VoiceMenu()
                Spacer()
                Button { model.setBarPinned(false) } label: {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.accentColor))
                }
                .buttonStyle(.plain)
                .help("Unpin bar")
                .accessibilityLabel("Unpin bar")
                CloseButton(countdown: false, frame: 28)
            }
            if let failure = model.speechFailure {
                FailureToast(message: failure)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let hint = FallbackHint(speech: speech) { FallbackDot(hint: hint).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 2 } }
                Text(highlightedSentence(speech.currentText ?? "", range: model.barHighlightRange))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.fg)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            TimedProgress(current: speech.currentTime, duration: speech.duration, fraction: speech.progress, onSeek: speech.seek(toFraction:))
            HStack(spacing: 6) {
                Button { model.playPrevious() } label: {
                    Image(systemName: "backward.fill").font(.system(size: 17))
                }
                .buttonStyle(.glyph(color: .fg2))
                .help("Previous sentence")
                .accessibilityLabel("Previous sentence")
                PlayPauseButton(size: 24, frame: 36)
                Button { model.playNext() } label: {
                    Image(systemName: "forward.fill").font(.system(size: 17))
                }
                .buttonStyle(.glyph(color: .fg2))
                .help("Next sentence")
                .accessibilityLabel("Next sentence")
                SpeedPill(rate: model.playbackRate) { model.replayCurrent(at: $0) }
                Spacer(minLength: 6)
                FavoriteButton(frame: 28)
                if let sentence {
                    FolderMenu(sentence: sentence)
                    ForEach(sentence.tags.sorted { $0.name < $1.name }.prefix(3)) { tag in
                        TagChip(name: tag.name, color: TagColor(rawValue: tag.colorID) ?? .pink)
                            .contextMenu {
                                Button("Remove “\(tag.name)”") { model.library.unassign(tag, from: sentence) }
                            }
                    }
                    AddTagMenu(sentence: sentence)
                }
            }
            if let sentence {
                NoteEditor(
                    markdown: sentence.note,
                    onChange: { model.library.setNote($0, for: sentence) },
                    style: .card,
                    background: .noteGlass,
                    showsHint: false,
                    maxTextHeight: 220,
                    onBeginEditing: beginEditing
                )
                .id(sentence.persistentModelID)
            }
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 14))
    }
}

/// "Fenna edge ▾".
private struct VoiceMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let speech = model.speech
        Menu {
            if let language = speech.language {
                let current = speech.voiceID ?? model.settings.voice(for: language)
                ForEach(model.voices.groups(for: language, selected: current)) { group in
                    Section(group.title) {
                        ForEach(group.voices) { voice in
                            Button {
                                model.useVoice(voice.id, for: language)
                            } label: {
                                let title = voice.id == language.info.defaultEdgeVoice
                                    ? "\(voice.displayName) (default)" : voice.displayName
                                if voice.id == current { Label(title, systemImage: "checkmark") } else { Text(title) }
                            }
                        }
                    }
                }
                Divider()
            }
            Button("Voices & Engines…") { model.openDashboard(.settings(.voices)) }
        } label: {
            HStack(spacing: 5) {
                Text(speech.voiceName ?? "Voice")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.fg)
                if let provider = speech.provider {
                    Text(provider.rawValue)
                        .font(.spreekMono(size: 11))
                        .foregroundStyle(Color.fg3)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.fg2)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(Color.glassCircle))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .task(id: speech.language) {
            if let language = speech.language { model.voices.load(language) }
        }
    }
}

/// Folder chip: squircle icon + name; menu files the sentence.
private struct FolderMenu: View {
    @Environment(AppModel.self) private var model
    let sentence: Sentence

    var body: some View {
        Menu {
            ForEach(model.library.folders()) { folder in
                Button {
                    model.library.move(sentence, to: folder)
                } label: {
                    if sentence.folder === folder { Label(folder.name, systemImage: "checkmark") } else { Text(folder.name) }
                }
            }
            if sentence.folder != nil {
                Divider()
                Button("Remove from Folder") { model.library.move(sentence, to: nil) }
            }
        } label: {
            HStack(spacing: 6) {
                if let folder = sentence.folder {
                    FolderIcon(symbol: folder.symbol, color: FolderColor(rawValue: folder.colorID) ?? .gray, size: .small)
                    Text(folder.name)
                } else {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.fg2)
                        .frame(width: 18, height: 18)
                    Text("Folder").foregroundStyle(Color.fg2)
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.fg)
            .lineLimit(1)
            .padding(.leading, 4)
            .padding(.trailing, 10)
            .frame(height: 26)
            .background(Capsule().fill(Color.glassCircle))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Folder")
    }
}

/// "+" — assigns an existing tag.
private struct AddTagMenu: View {
    @Environment(AppModel.self) private var model
    let sentence: Sentence

    var body: some View {
        let unassigned = model.library.tags().filter { tag in !sentence.tags.contains { $0 === tag } }
        Menu {
            if unassigned.isEmpty {
                Text("No more tags")
            }
            ForEach(unassigned) { tag in
                Button(tag.name) { model.library.assign(tag, to: sentence) }
            }
        } label: {
            Text("+")
                .font(.system(size: 15))
                .foregroundStyle(Color.fg2)
                .frame(width: 26, height: 26)
                .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.separator, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Add tag")
        .accessibilityLabel("Add tag")
    }
}

// MARK: - Panel editing

private struct BeginPanelEditingKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable () -> Void = {}
}

extension EnvironmentValues {
    /// Lets the note editor make the non-activating panel key while the user types.
    var beginPanelEditing: @MainActor @Sendable () -> Void {
        get { self[BeginPanelEditingKey.self] }
        set { self[BeginPanelEditingKey.self] = newValue }
    }
}
