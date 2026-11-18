import AppKit
import SpreekCore
import SwiftData
import SwiftUI

/// Middle column: toolbar, search field, day-grouped sentences, activity footer.
struct SentenceListColumn: View {
    @Environment(AppModel.self) private var model
    /// Re-renders the list whenever the library changes; the rows themselves come from
    /// `LibraryStore` so scope and filtering logic stay in SpreekCore.
    @Query private var allSentences: [Sentence]
    @State private var pendingDelete: [Sentence] = []
    @FocusState private var listFocused: Bool

    var body: some View {
        let dashboard = model.dashboard
        let sentences = visibleSentences
        let buckets = model.library.dayBuckets(sentences, by: dashboard.query.sort)
        VStack(spacing: 0) {
            toolbar(sentences: sentences)
            SearchField()
                .padding(EdgeInsets(top: 6, leading: 12, bottom: 8, trailing: 12))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(buckets, id: \.day) { bucket in
                            DayHeader(bucket: bucket, isCollapsed: dashboard.collapsedDays.contains(bucket.day)) {
                                withAnimation(.snappy(duration: 0.2)) {
                                    if dashboard.collapsedDays.contains(bucket.day) {
                                        dashboard.collapsedDays.remove(bucket.day)
                                    } else {
                                        dashboard.collapsedDays.insert(bucket.day)
                                    }
                                }
                            }
                            if !dashboard.collapsedDays.contains(bucket.day) {
                                let rows = bucket.sentences
                                ForEach(Array(rows.enumerated()), id: \.element.persistentModelID) { index, sentence in
                                    SentenceRow(
                                        sentence: sentence,
                                        isSelected: dashboard.selection.contains(sentence.persistentModelID),
                                        joinsAbove: index > 0 && dashboard.selection.contains(rows[index - 1].persistentModelID),
                                        joinsBelow: index + 1 < rows.count && dashboard.selection.contains(rows[index + 1].persistentModelID),
                                        onDelete: { pendingDelete = deletionTargets(for: sentence) }
                                    )
                                    .id(sentence.persistentModelID)
                                    .draggable(dragPayload(for: sentence)) {
                                        SentenceDragPreview(
                                            sentence: sentence,
                                            count: dashboard.selection.contains(sentence.persistentModelID) ? dashboard.selection.count : 1,
                                            badgeStyle: model.settings.badgeStyle
                                        )
                                    }
                                    .onTapGesture {
                                        listFocused = true
                                        click(sentence, in: rowOrder(buckets))
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .overlay {
                    if sentences.isEmpty { emptyState }
                }
                .focusable()
                .focused($listFocused)
                .focusEffectDisabled()
                .onKeyPress(.upArrow) { move(-1, in: rowOrder(buckets), proxy: proxy) }
                .onKeyPress(.downArrow) { move(1, in: rowOrder(buckets), proxy: proxy) }
                .onKeyPress(.space) {
                    guard let sentence = focusedSentence else { return .ignored }
                    model.playOrPause(sentence)
                    return .handled
                }
                .onKeyPress(.delete) {
                    let targets = selectedSentences
                    guard !targets.isEmpty else { return .ignored }
                    pendingDelete = targets
                    return .handled
                }
                .onAppear {
                    if let focused = dashboard.focused { proxy.scrollTo(focused, anchor: .center) }
                }
                .onChange(of: dashboard.focused) { _, focused in
                    if let focused { withAnimation { proxy.scrollTo(focused) } }
                }
            }
            ActivityFooter(sentenceCount: sentences.count)
        }
        .confirmationDialog(
            pendingDelete.count == 1 ? "Delete this sentence?" : "Delete \(pendingDelete.count) sentences?",
            isPresented: Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } })
        ) {
            Button(pendingDelete.count == 1 ? "Delete" : "Delete \(pendingDelete.count) Sentences", role: .destructive) {
                model.delete(pendingDelete)
                pendingDelete = []
            }
        } message: {
            Text("Notes, play history and cached audio are removed too.")
        }
    }

    // MARK: Data

    private var scope: LibraryScope {
        let context = model.library.context
        switch model.dashboard.route {
        case .favorites: return .favorites
        case .folder(let id):
            if let folder = context.model(for: id) as? Folder, !folder.isDeleted { return .folder(folder) }
        case .tag(let id):
            if let tag = context.model(for: id) as? Tag, !tag.isDeleted { return .tag(tag) }
        case .history, .settings, .storage: break
        }
        return .history
    }

    private var visibleSentences: [Sentence] {
        _ = allSentences.count
        let dashboard = model.dashboard
        var sentences = model.library.sentences(in: scope, matching: dashboard.query)
        if dashboard.onlyWithNotes { sentences = sentences.filter(\.hasNote) }
        return sentences
    }

    /// Rows in display order (collapsed days skipped).
    private func rowOrder(_ buckets: [DayBucket]) -> [Sentence] {
        buckets.filter { !model.dashboard.collapsedDays.contains($0.day) }.flatMap(\.sentences)
    }

    private var selectedSentences: [Sentence] {
        visibleSentences.filter { model.dashboard.selection.contains($0.persistentModelID) }
    }

    private var focusedSentence: Sentence? {
        guard let id = model.dashboard.focused else { return nil }
        return visibleSentences.first { $0.persistentModelID == id }
    }

    /// The whole selection when the row is part of it, otherwise just the row.
    private func deletionTargets(for sentence: Sentence) -> [Sentence] {
        model.dashboard.selection.contains(sentence.persistentModelID) ? selectedSentences : [sentence]
    }

    /// Dragging a selected row drags the whole selection, in display order.
    private func dragTargets(for sentence: Sentence) -> [Sentence] {
        deletionTargets(for: sentence)
    }

    private func dragPayload(for sentence: Sentence) -> SentenceDrag {
        SentenceDrag(ids: dragTargets(for: sentence).map(\.persistentModelID))
    }

    // MARK: Selection

    /// Click selects; ⌘-click toggles; ⇧-click extends from the last clicked row.
    private func click(_ sentence: Sentence, in order: [Sentence]) {
        let dashboard = model.dashboard
        let id = sentence.persistentModelID
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if dashboard.selection.contains(id) {
                dashboard.selection.remove(id)
                if dashboard.focused == id { dashboard.focused = dashboard.selection.first }
            } else {
                dashboard.selection.insert(id)
                dashboard.focused = id
            }
        } else if flags.contains(.shift), let anchor = dashboard.focused,
                  let from = order.firstIndex(where: { $0.persistentModelID == anchor }),
                  let to = order.firstIndex(where: { $0.persistentModelID == id }) {
            dashboard.selection = Set(order[min(from, to)...max(from, to)].map(\.persistentModelID))
        } else {
            dashboard.select(id)
        }
    }

    private func move(_ step: Int, in order: [Sentence], proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !order.isEmpty else { return .ignored }
        let current = model.dashboard.focused.flatMap { id in order.firstIndex { $0.persistentModelID == id } }
        let next = current.map { min(max($0 + step, 0), order.count - 1) } ?? 0
        model.dashboard.select(order[next].persistentModelID)
        return .handled
    }

    // MARK: Pieces

    private func toolbar(sentences: [Sentence]) -> some View {
        let dashboard = model.dashboard
        return HStack(spacing: 2) {
            if case .folder(let folder) = scope {
                FolderTitle(folder: folder, count: sentences.count)
            }
            Spacer(minLength: 8)
            Menu {
                Picker("Sort By", selection: Binding(get: { dashboard.query.sort }, set: { dashboard.setSort($0) })) {
                    ForEach(LibrarySort.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuStyle(.button)
            .buttonStyle(.toolbarIcon)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Sort by: \(dashboard.query.sort.title)")
            .accessibilityLabel("Sort by \(dashboard.query.sort.title)")
            Button { dashboard.onlyWithNotes.toggle() } label: {
                Image(systemName: "line.3.horizontal.decrease")
            }
            .buttonStyle(.toolbarIcon(isOn: dashboard.onlyWithNotes))
            .help(dashboard.onlyWithNotes ? "Show all sentences" : "Only sentences with a note")
            .accessibilityLabel(dashboard.onlyWithNotes ? "Show all sentences" : "Only sentences with a note")
            Button { withAnimation(.snappy(duration: 0.2)) { dashboard.showsChart.toggle() } } label: {
                Image(systemName: "chart.bar.fill")
            }
            .buttonStyle(.toolbarIcon(isOn: dashboard.showsChart))
            .help(dashboard.showsChart ? "Hide Activity" : "Show Activity")
            .accessibilityLabel(dashboard.showsChart ? "Hide Activity" : "Show Activity")
            Button { model.playAll(sentences) } label: {
                Image(systemName: "play.square.stack")
            }
            .buttonStyle(.toolbarIcon)
            .disabled(sentences.isEmpty)
            .help("Play all as a playlist")
            .accessibilityLabel("Play all")
            Button { withAnimation(.snappy(duration: 0.2)) { dashboard.showsInspector.toggle() } } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.toolbarIcon(isOn: !dashboard.showsInspector))
            .help(dashboard.showsInspector ? "Hide details" : "Show details")
            .accessibilityLabel(dashboard.showsInspector ? "Hide details" : "Show details")
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 12))
        .frame(height: 44)
    }

    private var emptyState: some View {
        let filtered = !model.dashboard.query.text.isEmpty || model.dashboard.query.language != nil || model.dashboard.onlyWithNotes
        return VStack(spacing: 6) {
            Image(systemName: filtered ? "magnifyingglass" : "waveform")
                .font(.system(size: 24, weight: .semibold))
            Text(filtered ? "No matching sentences" : "Nothing here yet")
                .font(.spreekRounded(size: 15, weight: .heavy))
            if !filtered {
                Text("Select text anywhere and press ⌥S.")
                    .font(.system(size: 12))
            } else if model.dashboard.query.range != .all {
                Button("Search all time") { model.dashboard.query.range = .all }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
            }
        }
        .foregroundStyle(Color.fg3)
    }
}

// MARK: - Folder title

/// Icon, name and "Nederlands · 12 sentences" for the open folder. Click for Get Info.
private struct FolderTitle: View {
    @Environment(AppModel.self) private var model
    @Environment(\.badgeStyle) private var badgeStyle
    let folder: Folder
    let count: Int

    var body: some View {
        Button { model.dashboard.folderSheet = FolderSheetTarget(folder: folder) } label: {
            HStack(spacing: 9) {
                FolderIcon(symbol: folder.symbol, color: folder.color, size: .medium)
                VStack(alignment: .leading, spacing: 1) {
                    Text(folder.name)
                        .font(.spreekRounded(size: 15, weight: .black))
                        .foregroundStyle(Color.fg)
                    HStack(spacing: 4) {
                        if let language = folder.language {
                            LanguageBadge(language: language, style: badgeStyle, size: .s)
                        }
                        Text(details)
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.fg3)
                }
                .lineLimit(1)
                .truncationMode(.tail)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Folder Info…")
    }

    /// Total sentences in the folder; `count` is what the filters let through.
    private var details: String {
        let total = folder.sentences.count
        var parts: [String] = []
        if let language = folder.language { parts.append(language.nativeName) }
        parts.append(count == total ? "\(total) \(total == 1 ? "sentence" : "sentences")" : "\(count) of \(total) sentences")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Search field

/// Search + "All languages" + mono range (`7d` / `30d` / `All`).
private struct SearchField: View {
    @Environment(AppModel.self) private var model
    @Environment(\.badgeStyle) private var badgeStyle
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var dashboard = model.dashboard
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.fg3)
            TextField("Search", text: $dashboard.query.text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onChange(of: dashboard.searchFocusRequest) { focused = true }
                .onAppear { if dashboard.searchFocusRequest > 0 { focused = true } }
            if !dashboard.query.text.isEmpty {
                Button { dashboard.query.text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.fg3)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear search")
            }
            divider
            Menu {
                Button("All languages") { dashboard.query.language = nil }
                Divider()
                ForEach(model.pickerLanguages(including: dashboard.query.language), id: \.self) { language in
                    Button("\(language.info.flagEmoji)  \(language.nativeName)") { dashboard.query.language = language }
                }
            } label: {
                HStack(spacing: 5) {
                    if let language = dashboard.query.language {
                        LanguageBadge(language: language, style: badgeStyle, size: .s)
                        Text(language.nativeName)
                    } else {
                        Text("All languages")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.fg2)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .contentShape(Rectangle())
            }
            .plainMenu()
            .help("Filter by language")
            divider
            Menu {
                ForEach(LibraryRange.allCases, id: \.self) { range in
                    Button {
                        dashboard.query.range = range
                    } label: {
                        let title = switch range {
                        case .week: "Last 7 days"
                        case .month: "Last 30 days"
                        case .all: "All time"
                        }
                        if dashboard.query.range == range { Label(title, systemImage: "checkmark") } else { Text(title) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "clock").font(.system(size: 12, weight: .semibold))
                    Text(dashboard.query.range.shortLabel).font(.spreekMono(size: 12))
                }
                .foregroundStyle(Color.fg2)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .contentShape(Rectangle())
            }
            .plainMenu()
            .help("Time range")
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: 32)
        .background(Color.field, in: shape)
        .overlay(shape.strokeBorder(Color.separator, lineWidth: Metrics.hairline))
    }

    private var divider: some View {
        Rectangle().fill(Color.separator).frame(width: 1, height: 18)
    }
}

// MARK: - Day header

private struct DayHeader: View {
    let bucket: DayBucket
    let isCollapsed: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .heavy))
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                Text(title)
                Spacer()
                if isCollapsed {
                    Text("\(bucket.sentences.count)").monospacedDigit()
                }
            }
            .font(.spreekRounded(size: 12, weight: .heavy))
            .foregroundStyle(Color.fg3)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
    }

    private var title: String {
        switch bucket.label {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .date(let date): date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        }
    }
}

// MARK: - Row

/// Badge + sentence + note icon + 7-day mini bars + star. Accent fill when selected.
private struct SentenceRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.badgeStyle) private var badgeStyle
    @Environment(\.colorScheme) private var colorScheme
    let sentence: Sentence
    let isSelected: Bool
    /// The neighbouring row is selected too: square off that edge so a run reads as one block.
    var joinsAbove = false
    var joinsBelow = false
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            LanguageBadge(language: sentence.effectiveLanguage, style: badgeStyle, size: .s, inverted: isSelected)
            Text(sentence.text)
                .font(.system(size: 13.5, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if sentence.hasNote {
                Image(systemName: "note.text")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color(hex: 0x8E8E93))
                    .accessibilityLabel("Has note")
            }
            MiniBars(counts: model.library.miniBars(for: sentence), isSelected: isSelected)
            Button { model.toggleFavorite(sentence) } label: {
                Image(systemName: sentence.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : sentence.isFavorite ? Color.favorite : Color(hex: 0x8E8E93))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(sentence.isFavorite ? "Remove from Favorites" : "Add to Favorites")
            .accessibilityLabel(sentence.isFavorite ? "Remove from Favorites" : "Add to Favorites")
        }
        .foregroundStyle(isSelected ? Color.white : Color.fg)
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 38)
        .background {
            if isSelected {
                let top: CGFloat = joinsAbove ? 0 : 9
                let bottom: CGFloat = joinsBelow ? 0 : 9
                UnevenRoundedRectangle(
                    topLeadingRadius: top, bottomLeadingRadius: bottom, bottomTrailingRadius: bottom, topTrailingRadius: top,
                    style: .continuous
                )
                .fill(Color.accentColor)
            } else {
                VStack {
                    Spacer()
                    Rectangle().fill(Color(light: .black.opacity(0.07), dark: .white.opacity(0.06))).frame(height: Metrics.hairline)
                }
            }
        }
        .contentShape(Rectangle())
        .contextMenu { contextMenu }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var contextMenu: some View {
        Button("Play") { model.replay(sentence) }
        Menu("Move to Folder") {
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
        }
        Menu("Tags") {
            ForEach(model.library.tags()) { tag in
                let assigned = sentence.tags.contains { $0 === tag }
                Button {
                    if assigned { model.library.unassign(tag, from: sentence) } else { model.library.assign(tag, to: sentence) }
                } label: {
                    if assigned { Label(tag.name, systemImage: "checkmark") } else { Text(tag.name) }
                }
            }
        }
        Button(sentence.isFavorite ? "Remove from Favorites" : "Add to Favorites") { model.toggleFavorite(sentence) }
        Divider()
        let count = model.dashboard.selection.contains(sentence.persistentModelID) ? model.dashboard.selection.count : 1
        Button(count > 1 ? "Delete \(count) Sentences…" : "Delete…", role: .destructive, action: onDelete)
    }
}

/// Seven 3 pt bars: plays per day, oldest first.
private struct MiniBars: View {
    let counts: [Int]
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(counts.enumerated()), id: \.offset) { _, count in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color(count))
                    .frame(width: 3, height: 2 + CGFloat(min(count, 14)))
            }
        }
        .frame(height: 16, alignment: .bottom)
        .accessibilityLabel("Plays in the last 7 days: \(counts.reduce(0, +))")
    }

    private func color(_ count: Int) -> Color {
        if isSelected { return .white.opacity(0.85) }
        return count > 0 ? Color(hex: 0x8E8E93) : Color(lightHex: 0xC7C7CC, darkHex: 0x48484C)
    }
}
