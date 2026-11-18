import AppKit
import SpreekCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Right column: the focused sentence, a multi-selection summary, or an empty state.
struct SentenceDetailColumn: View {
    @Environment(AppModel.self) private var model
    @Query private var allSentences: [Sentence]

    var body: some View {
        let dashboard = model.dashboard
        let selected = allSentences.filter { dashboard.selection.contains($0.persistentModelID) }
        Group {
            if selected.count > 1 {
                MultiSelectionSummary(sentences: selected)
            } else if let sentence = selected.first {
                SentenceDetail(sentence: sentence)
                    .id(sentence.persistentModelID)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "text.quote").font(.system(size: 24, weight: .semibold))
                    Text("No sentence selected").font(.spreekRounded(size: 15, weight: .heavy))
                }
                .foregroundStyle(Color.fg3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct MultiSelectionSummary: View {
    @Environment(AppModel.self) private var model
    let sentences: [Sentence]
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 12) {
            Text("\(sentences.count) sentences selected")
                .font(.spreekRounded(size: 20, weight: .black))
                .foregroundStyle(Color.fg)
            HStack(spacing: 8) {
                Button("Play All") { model.playAll(sentences) }
                    .buttonStyle(CapsuleButtonStyle())
                Button("Delete…", role: .destructive) { confirmDelete = true }
                    .buttonStyle(CapsuleButtonStyle(prominent: true))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog("Delete \(sentences.count) sentences?", isPresented: $confirmDelete) {
            Button("Delete \(sentences.count) Sentences", role: .destructive) { model.delete(sentences) }
        } message: {
            Text("Notes, play history and cached audio are removed too.")
        }
    }
}

// MARK: - Detail

private struct SentenceDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.badgeStyle) private var badgeStyle
    @AppStorage("dashboard.section.pronunciation") private var showsPronunciation = true
    @AppStorage("dashboard.section.note") private var showsNote = true
    @AppStorage("dashboard.section.collection") private var showsCollection = true
    @AppStorage("dashboard.section.source") private var showsSource = true
    @State private var confirmDelete = false
    let sentence: Sentence

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(EdgeInsets(top: 26, leading: 24, bottom: 16, trailing: 24))
            Rectangle().fill(Color.separator).frame(height: Metrics.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    SectionBar("Pronunciation", isExpanded: $showsPronunciation) {
                        PronunciationSection(sentence: sentence)
                    }
                    SectionBar("Note", isExpanded: $showsNote) {
                        NoteEditor(markdown: sentence.note, onChange: { model.library.setNote($0, for: sentence) })
                            .padding(.horizontal, -10)
                            .padding(.bottom, 4)
                    }
                    SectionBar("Collection", isExpanded: $showsCollection) {
                        CollectionSection(sentence: sentence)
                    }
                    SectionBar("Source", isExpanded: $showsSource) {
                        SourceSection(sentence: sentence)
                    }
                }
                .padding(EdgeInsets(top: 14, leading: 16, bottom: 20, trailing: 16))
                .overlayScrollers()
            }
        }
        .confirmationDialog("Delete this sentence?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { model.delete([sentence]) }
        } message: {
            Text("Its note, play history and cached audio are removed too.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    LanguageBadge(language: sentence.effectiveLanguage, style: badgeStyle, size: .m)
                    Text("\(sentence.effectiveLanguage.nativeName) · \(sentence.folder?.language == nil ? "auto-detected" : "from folder")")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.fg3)
                }
                Spacer()
                HStack(spacing: 2) {
                    Button(action: copy) { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.toolbarIcon)
                        .help("Copy text")
                        .accessibilityLabel("Copy text")
                    Button(action: exportAudio) { Image(systemName: "square.and.arrow.down") }
                        .buttonStyle(.toolbarIcon)
                        .disabled(cachedAudio == nil)
                        .help(cachedAudio == nil ? "No cached audio yet — play the sentence first" : "Export audio…")
                        .accessibilityLabel("Export audio")
                    Button { confirmDelete = true } label: { Image(systemName: "trash") }
                        .buttonStyle(.toolbarIcon)
                        .help("Delete")
                        .accessibilityLabel("Delete")
                }
            }
            HStack(alignment: .center, spacing: 16) {
                let playing = model.isPlayingOrPaused(sentence) && model.speech.state.isPlaying
                Button { model.playOrPause(sentence) } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: playing ? 0 : 1.5)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Color.accentColor))
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 8, y: 6)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(playing ? "Pause (Space)" : "Play (Space)")
                .accessibilityLabel(playing ? "Pause" : "Play")
                SentenceTitle(text: sentence.text)
            }
            HStack(spacing: 10) {
                StatPill(tint: .pink, label: "played", value: "\(sentence.playCount)×", symbol: "speaker.wave.2.fill", height: 46, valueSize: 22)
                StatPill(tint: .blue, label: savedLabel, value: savedValue, symbol: "star.fill", height: 46, valueSize: 18)
            }
        }
    }

    private var savedLabel: String {
        sentence.folder != nil || sentence.isFavorite ? "saved in" : "saved"
    }

    private var savedValue: String {
        if let folder = sentence.folder { return folder.name }
        return sentence.isFavorite ? "Favorites" : "—"
    }

    private var cachedAudio: CachedAudio? {
        sentence.voiceID.flatMap { AudioCache().latestEntry(text: sentence.text, voiceID: $0) }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sentence.text, forType: .string)
    }

    /// Copies the cached audio file wherever the user chooses.
    private func exportAudio() {
        guard let audio = cachedAudio else { return }
        let panel = NSSavePanel()
        let ext = audio.audioURL.pathExtension
        panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .audio]
        panel.nameFieldStringValue = Self.fileName(for: sentence.text) + "." + ext
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        do {
            try fm.copyItem(at: audio.audioURL, to: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// First words of the sentence, safe for a file name.
    static func fileName(for text: String) -> String {
        let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).prefix(6).joined(separator: " ")
        return words.isEmpty ? "Spreek" : words
    }
}

/// The sentence in the detail header, as big as it can be within a fixed height at the column's
/// current width (3 lines at 27 pt, 4 at 23, …): 27 pt for a phrase, stepping down for longer sentences
/// (CJK and narrow columns included, since it's measured, not counted). A paragraph that's still
/// too tall at the smallest size scrolls inside the header instead of pushing the sections away.
///
/// The steps are measured with `NSAttributedString` when the width changes and only the chosen one
/// is laid out: a `ViewThatFits` over five selectable `Text`s made each live-resize frame ~35 ms.
private struct SentenceTitle: View {
    let text: String
    @State private var width: CGFloat = 0

    private struct Step {
        let size: CGFloat
        let weight: Font.Weight
        let nsWeight: NSFont.Weight
        var tracking: CGFloat { size >= 20 ? -0.3 : 0 }
        var lineSpacing: CGFloat { size >= 20 ? 2 : 3 }
    }

    private static let steps = [
        Step(size: 27, weight: .bold, nsWeight: .bold),
        Step(size: 23, weight: .bold, nsWeight: .bold),
        Step(size: 20, weight: .bold, nsWeight: .bold),
        Step(size: 17, weight: .semibold, nsWeight: .semibold),
        Step(size: 15, weight: .semibold, nsWeight: .semibold),
    ]
    private static let paragraph = Step(size: 14, weight: .medium, nsWeight: .medium)
    /// Three lines of the biggest step, four of the next, …; also the scrolling paragraph's height.
    private static let maxHeight: CGFloat = 128

    var body: some View {
        Group {
            if let step = Self.step(for: text, width: width) {
                label(step)
            } else {
                ScrollView { label(Self.paragraph).padding(EdgeInsets(top: 0, leading: 0, bottom: 14, trailing: 10)) }
                    .frame(height: Self.maxHeight)
                    // Fades the last line so a cut-off paragraph reads as "scrolls", not as clipped.
                    .mask {
                        VStack(spacing: 0) {
                            Color.black
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 22)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Whole points: sub-point changes during a resize don't re-measure.
        .onGeometryChange(for: CGFloat.self) { $0.size.width.rounded(.down) } action: { width = $0 }
    }

    private func label(_ step: Step) -> some View {
        Text(text)
            .font(.system(size: step.size, weight: step.weight))
            .tracking(step.tracking)
            .lineSpacing(step.lineSpacing)
            .foregroundStyle(Color.fg)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The biggest step whose text fits `maxHeight` at `width`; nil means scroll. Before the first
    /// layout (`width` 0) it's the biggest step.
    private static func step(for text: String, width: CGFloat) -> Step? {
        guard width > 0 else { return steps[0] }
        return steps.first { height(of: text, step: $0, width: width) <= maxHeight }
    }

    private static func height(of text: String, step: Step, width: CGFloat) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = step.lineSpacing
        // Same line breaking as SwiftUI's Text (no lone last word), else a 3-line measure renders as 4.
        style.lineBreakStrategy = .standard
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: step.size, weight: step.nsWeight),
            .kern: step.tracking,
            .paragraphStyle: style,
        ])
        let rect = string.boundingRect(
            with: CGSize(width: width - 4, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(rect.height)
    }
}

// MARK: - Pronunciation

/// "Practice speed": Default (the folder's or language's speed) or a fixed speed for every
/// play in the dashboard.
private struct PracticeSpeedMenu: View {
    @Environment(AppModel.self) private var model
    let language: LanguageCode

    var body: some View {
        let current = model.practiceSpeed
        Menu {
            Button {
                model.practiceSpeed = nil
            } label: {
                let title = "Default (\(PlaybackFormat.speed(model.speech.defaultRate(for: language))))"
                if current == nil { Label(title, systemImage: "checkmark") } else { Text(title) }
            }
            Divider()
            ForEach(SpeechController.speedChoices, id: \.self) { speed in
                Button { model.practiceSpeed = speed } label: {
                    let title = PlaybackFormat.speed(speed)
                    if current == speed { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(current.map(PlaybackFormat.speed) ?? "Default")
                    .font(.spreekMono(size: 11.5, weight: .bold))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.fg2)
            }
            .foregroundStyle(Color.fg)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Color.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Speed for playing sentences in the Dashboard")
        .accessibilityLabel("Practice speed")
    }
}

private struct PronunciationSection: View {
    @Environment(AppModel.self) private var model
    let sentence: Sentence

    private struct Candidate: Identifiable {
        let id: String
        let name: String
        let detail: String
        let tag: String?
        let isDefault: Bool
    }

    var body: some View {
        let language = sentence.effectiveLanguage
        VStack(spacing: 0) {
            ForEach(candidates(for: language)) { candidate in
                HStack(spacing: 12) {
                    Button {
                        model.speech.speak(
                            text: sentence.text, language: language, voiceID: candidate.id, rate: model.practiceSpeed,
                            source: sentence.folder == nil ? .history : .folder
                        )
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.fg)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.control))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Play with \(candidate.name) at \(PlaybackFormat.speed(model.practiceSpeed ?? model.speech.defaultRate(for: language)))")
                    .accessibilityLabel("Play with \(candidate.name)")
                    Text(candidate.name)
                        .font(.spreekRounded(size: 13.5, weight: .heavy))
                        .foregroundStyle(Color.fg)
                        .lineLimit(1)
                        .frame(width: 80, alignment: .leading)
                    Text(candidate.detail)
                        .font(.spreekMono(size: 11.5))
                        .foregroundStyle(Color.fg3)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let tag = candidate.tag {
                        Text(tag)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(candidate.isDefault ? Color.blueFG : Color.fg3)
                    }
                }
                .frame(height: 36)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color(light: .black.opacity(0.07), dark: .white.opacity(0.06))).frame(height: Metrics.hairline)
                }
            }
            HStack(spacing: 12) {
                Text("Practice speed")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.fg3)
                    .frame(width: 118, alignment: .leading)
                PracticeSpeedMenu(language: language)
                Spacer()
            }
            .frame(height: 40)
        }
        .padding(.horizontal, -2)
        .onAppear { model.voices.load(language) }
    }

    /// The voice this sentence normally uses, the language's other Edge voices, then the best
    /// installed macOS voice.
    private func candidates(for language: LanguageCode) -> [Candidate] {
        let defaultID = sentence.folder?.voiceID ?? model.speech.defaultVoice(for: language)
        var result = [Candidate(
            id: defaultID, name: VoiceName.name(defaultID),
            detail: EdgeCLIProvider.isEdgeVoiceID(defaultID) ? defaultID : "macOS",
            tag: "Default", isDefault: true
        )]
        let others = (model.voices.edgeVoices[language] ?? []).filter { $0.id != defaultID }.prefix(4)
        result += others.map { Candidate(id: $0.id, name: $0.displayName, detail: $0.id, tag: nil, isDefault: false) }
        if let system = model.voices.bestSystemVoice(for: language), system.id != defaultID {
            result.append(Candidate(id: system.id, name: system.displayName, detail: system.detail, tag: "Offline", isDefault: false))
        }
        return result
    }
}

// MARK: - Collection

/// Label column of the Collection and Source grids: fits "Captured from:" and leaves the values
/// room when the dashboard is at its minimum width.
private let detailLabelWidth: CGFloat = 104

private struct CollectionSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.badgeStyle) private var badgeStyle
    @State private var creatingTag = false
    @State private var tagName = ""
    let sentence: Sentence

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                FormLabel("Folder:", width: detailLabelWidth)
                folderMenu
            }
            GridRow {
                FormLabel("Language:", width: detailLabelWidth)
                languageRow
            }
            GridRow(alignment: .top) {
                FormLabel("Tags:", width: detailLabelWidth).padding(.top, 4)
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(sentence.tags.sorted { $0.name < $1.name }) { tag in
                        TagChip(name: tag.name, color: tag.color)
                            .contextMenu {
                                Button("Remove “\(tag.name)”") { model.library.unassign(tag, from: sentence) }
                            }
                            .help("Right-click to remove")
                    }
                    addTagMenu
                }
            }
        }
        .padding(EdgeInsets(top: 4, leading: -2, bottom: 6, trailing: 0))
        .alert("New Tag", isPresented: $creatingTag) {
            TextField("Name", text: $tagName)
            Button("Create") {
                let name = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                let tag = model.library.tags().first { $0.name == name } ?? model.createTag(named: name)
                model.library.assign(tag, to: sentence)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var folderMenu: some View {
        Menu {
            ForEach(model.library.folders()) { folder in
                Button {
                    model.library.move(sentence, to: folder)
                } label: {
                    if sentence.folder === folder { Label(folder.name, systemImage: "checkmark") } else { Text(folder.name) }
                }
            }
            Divider()
            Button("New Folder…") { model.dashboard.folderSheet = FolderSheetTarget(folder: nil, moving: sentence) }
            if sentence.folder != nil {
                Button("Remove from Folder") { model.library.move(sentence, to: nil) }
            }
        } label: {
            HStack(spacing: 6) {
                if let folder = sentence.folder {
                    FolderIcon(symbol: folder.symbol, color: folder.color, size: .small)
                    Text(folder.name)
                } else {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.fg2)
                        .frame(width: 18, height: 18)
                    Text("None").foregroundStyle(Color.fg2)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.fg2)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.fg)
            .padding(.leading, 4)
            .padding(.trailing, 9)
            .frame(height: 24)
            .background(Capsule().fill(Color.control))
            .contentShape(Capsule())
        }
        .plainMenu()
        .help("Move to folder")
    }

    /// The language plus where it comes from; at the dashboard's minimum width the
    /// "· auto-detected" / "· inherited from folder" note goes (the header says it too).
    private var languageRow: some View {
        HStack(spacing: 6) {
            if let language = sentence.folder?.language {
                LanguageBadge(language: language, style: badgeStyle, size: .s)
                Text(language.nativeName).foregroundStyle(Color.fg).fixedSize()
                    .help("Inherited from the folder")
                originNote("· inherited from folder")
            } else {
                Menu {
                    ForEach(model.pickerLanguages(including: sentence.language), id: \.self) { language in
                        Button {
                            model.library.setLanguage(language, for: sentence)
                        } label: {
                            if sentence.language == language {
                                Label(language.nativeName, systemImage: "checkmark")
                            } else {
                                Text(language.nativeName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        LanguageBadge(language: sentence.language, style: badgeStyle, size: .s)
                        Text(sentence.language.nativeName).foregroundStyle(Color.fg).fixedSize()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.fg2)
                    }
                    .contentShape(Rectangle())
                }
                .plainMenu()
                .fixedSize()
                .help("Auto-detected — click to correct")
                originNote("· auto-detected")
            }
        }
        .font(.system(size: 13))
    }

    /// Whole or not at all (only the note is measured twice, not the menu).
    private func originNote(_ note: String) -> some View {
        ViewThatFits(in: .horizontal) {
            Text(note).foregroundStyle(Color.fg3).fixedSize()
            Color.clear.frame(width: 0, height: 0)
        }
    }

    private var addTagMenu: some View {
        let unassigned = model.library.tags().filter { tag in !sentence.tags.contains { $0 === tag } }
        return Menu {
            ForEach(unassigned) { tag in
                Button(tag.name) { model.library.assign(tag, to: sentence) }
            }
            if !unassigned.isEmpty { Divider() }
            Button("New Tag…") {
                tagName = ""
                creatingTag = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                Text("Tag").font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.fg2)
            .padding(.horizontal, 9)
            .frame(height: Metrics.tagChipHeight)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .strokeBorder(Color.separator, lineWidth: Metrics.hairline)
            )
            .contentShape(Rectangle())
        }
        .plainMenu()
        .help("Add tag")
        .accessibilityLabel("Add tag")
    }
}

// MARK: - Source

/// Second "Captured from" line: one mono `fg3` line, middle-truncated, opens the URL; the full
/// URL is in the tooltip and "Copy URL" in the context menu.
private struct SourceURLLine: View {
    let urlString: String
    @State private var hovering = false

    var body: some View {
        let label = Text(SourceSection.shortURL(urlString))
            .font(.spreekMono(size: 12))
            .foregroundStyle(Color.fg3)
            .underline(hovering)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
        Group {
            if let url = URL(string: urlString), url.scheme != nil {
                Button { NSWorkspace.shared.open(url) } label: { label }
                    .buttonStyle(.plain)
                    .onHover { hovering = $0 }
                    .pointerStyle(.link)
            } else {
                label
            }
        }
        .help(urlString)
        .contextMenu {
            Button("Copy URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(urlString, forType: .string)
            }
        }
    }
}

private struct SourceSection: View {
    @Environment(AppModel.self) private var model
    let sentence: Sentence
    /// Bumped after removing other speeds so the cache is read again.
    @State private var cacheRevision = 0

    var body: some View {
        let _ = cacheRevision
        let clips = sentence.voiceID.map { AudioCache().entries(text: sentence.text, voiceID: $0) } ?? []
        let audio = clips.first
        let otherSpeeds = Array(clips.dropFirst())
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                FormLabel("Captured from:", width: detailLabelWidth)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if let icon = Self.appIcon(bundleID: sentence.sourceBundleID, name: sentence.sourceApp) {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                        }
                        Text(sentence.sourceApp ?? "Unknown")
                            .foregroundStyle(Color.fg)
                    }
                    if let urlString = sentence.sourceURL {
                        SourceURLLine(urlString: urlString)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            GridRow {
                FormLabel("First heard:", width: detailLabelWidth)
                Text(DashboardFormat.timestamp(sentence.createdAt))
                    .font(.spreekMono(size: 12))
                    .foregroundStyle(Color.fg)
                    .fixedSize()
            }
            GridRow {
                FormLabel("Audio cache:", width: detailLabelWidth)
                if let audio {
                    HStack(spacing: 8) {
                        Text("\(Self.shortFileName(audio.audioURL)) · \(DashboardFormat.bytes(AudioCache.fileSize(audio.audioURL)))")
                            .font(.spreekMono(size: 12))
                            .foregroundStyle(Color.fg)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(audio.audioURL.lastPathComponent)
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([audio.audioURL]) }
                            .buttonStyle(.link)
                            .fixedSize()
                    }
                } else {
                    Text("Not cached").foregroundStyle(Color.fg3)
                }
            }
            if !otherSpeeds.isEmpty {
                GridRow {
                    Color.clear.frame(width: detailLabelWidth, height: 1)
                    HStack(spacing: 8) {
                        let bytes = otherSpeeds.reduce(Int64(0)) { $0 + AudioCache.fileSize($1.audioURL) }
                        (Text("+ \(otherSpeeds.count) other speed\(otherSpeeds.count == 1 ? "" : "s") · ")
                            + Text(DashboardFormat.bytes(bytes)).font(.spreekMono(size: 12)))
                            .font(.system(size: 12))
                            .foregroundStyle(Color.fg3)
                        Button("Remove") { removeOtherSpeeds(otherSpeeds) }
                            .buttonStyle(.link)
                            .font(.system(size: 12))
                            .fixedSize()
                    }
                }
            }
        }
        .font(.system(size: 13))
        .padding(EdgeInsets(top: 4, leading: -2, bottom: 6, trailing: 0))
    }

    /// Keeps the last-used clip; the playing one stays too.
    private func removeOtherSpeeds(_ clips: [CachedAudio]) {
        let protecting = Set([model.speech.currentAudioURL].compactMap { $0 })
        AudioCache().remove(keys: clips.map(\.key), protecting: protecting)
        cacheRevision += 1
        model.storage.refresh()
    }

    /// The source app's icon: by bundle id, else (rows from before 5b) a running app with that name.
    static func appIcon(bundleID: String?, name: String?) -> NSImage? {
        let workspace = NSWorkspace.shared
        if let bundleID, let url = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            return workspace.icon(forFile: url.path(percentEncoded: false))
        }
        guard let name else { return nil }
        return workspace.runningApplications.first { $0.localizedName == name }?.icon
    }

    /// Host + path without the scheme: `reddit.com/r/thenetherlands`.
    static func shortURL(_ string: String) -> String {
        var result = string
        for prefix in ["https://", "http://", "www."] where result.hasPrefix(prefix) {
            result.removeFirst(prefix.count)
        }
        if result.hasSuffix("/") { result.removeLast() }
        return result
    }

    /// `3f9a…c21e.mp3` — cache keys are 64 hex characters.
    static func shortFileName(_ url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        guard name.count > 12 else { return url.lastPathComponent }
        return "\(name.prefix(4))…\(name.suffix(4)).\(url.pathExtension)"
    }
}
