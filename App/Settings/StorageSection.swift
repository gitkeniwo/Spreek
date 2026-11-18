import AppKit
import SpreekCore
import SwiftUI

/// The Storage page in the dashboard: its own route, so the Settings page doesn't carry the
/// scan, table and clean-up rows.
struct StorageView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                header
                    .padding(.top, 26)
                StorageSection()
            }
            .padding(EdgeInsets(top: 0, leading: 28, bottom: 40, trailing: 40))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
    }

    /// Same layout as the Settings header, with the Storage symbol in an accent squircle.
    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.accentColor)
                .frame(width: 46, height: 46)
                .overlay {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.18), radius: 5, y: 4)
                .accessibilityHidden(true)
            Text("Storage")
                .font(.spreekRounded(size: 28, weight: .black))
                .foregroundStyle(Color.fg)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(EdgeInsets(top: 0, leading: 4, bottom: 8, trailing: 4))
    }
}

/// What Spreek keeps on disk and the clean-ups (the body of `StorageView`).
struct StorageSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        let storage = model.storage
        VStack(alignment: .leading, spacing: 18) {
            StorageOverviewCard()
            StorageBreakdown()
            VStack(alignment: .leading, spacing: 8) {
                Text("Clean up")
                    .font(.spreekRounded(size: 13, weight: .heavy))
                    .foregroundStyle(Color.fg)
                    .accessibilityAddTraits(.isHeader)
                StorageCard {
                    VStack(spacing: 0) {
                        CleanupRow(kind: .unlinked, symbol: "personalhotspot.slash", title: "Unlinked audio",
                                   detail: "Clips whose sentence was deleted or is now read by another voice.", button: "Remove…")
                        CleanupRow(kind: .extraSpeeds, symbol: "gauge.with.dots.needle.67percent", title: "Extra speeds",
                                   detail: "Keeps the most recent speed of each sentence, removes the rest.", button: "Remove…")
                        CleanupRow(kind: .idle, symbol: "clock", title: "Audio not played in",
                                   detail: "Only the audio goes; sentences, notes and favorites stay.", button: "Remove…") {
                            @Bindable var storage = storage
                            OptionsPopup(options: IdleAge.allCases.map { ($0, $0.title) }, selection: $storage.idleAge, accessibilityName: "Audio not played in")
                        }
                        CleanupRow(kind: .temporary, symbol: "xmark.bin", title: "Temporary files",
                                   detail: "Leftovers from interrupted syntheses.", button: "Remove")
                        CleanupRow(kind: .oldSentences, symbol: "text.badge.xmark", title: "Old sentences now",
                                   detail: settings.historyRetention == .never
                                       ? "Choose when to “Remove old sentences” below first."
                                       : "Applies “Remove old sentences” (below) right away, with their audio.",
                                   button: "Remove…")
                        CleanupRow(kind: .all, symbol: "trash", title: "All audio",
                                   detail: "Every clip is synthesized again the next time you play it. History, notes and favorites stay.",
                                   button: "Clear Cache…", isDestructive: true, isLast: true)
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                SettingsRow("Limit audio cache:") {
                    OptionsPopup(
                        options: [(.none, "No limit"), (.mb100, "100 MB"), (.mb250, "250 MB"), (.mb500, "500 MB"), (.gb1, "1 GB")],
                        selection: $settings.audioCacheLimit, accessibilityName: "Limit audio cache"
                    )
                    SettingsHint("Over the limit, audio played longest ago is removed first. Favorites are removed last.")
                }
                SettingsRow("Remove old sentences:") {
                    OptionsPopup(
                        options: [
                            (.never, "Never"), (.oneWeek, "After 1 week"), (.oneMonth, "After 1 month"),
                            (.twoMonths, "After 2 months"), (.threeMonths, "After 3 months"),
                            (.sixMonths, "After 6 months"), (.oneYear, "After 1 year"),
                        ],
                        selection: $settings.historyRetention, accessibilityName: "Remove old sentences"
                    )
                    SettingsHint("Counted from the last time a sentence was played. Favorites and sentences in a folder, with a tag or with a note are always kept.")
                }
            }
        }
        .padding(.top, 4)
        .onAppear { storage.isVisible = true }
        .onDisappear { storage.isVisible = false }
        .onChange(of: settings.historyRetention) { storage.refresh() }
        .confirmationDialog(
            storage.pending?.title ?? "",
            isPresented: Binding(get: { storage.pending != nil }, set: { if !$0 { storage.pending = nil } }),
            presenting: storage.pending
        ) { pending in
            Button(pending.confirmLabel, role: pending.isDestructive ? .destructive : nil) { storage.confirm(pending) }
        } message: { pending in
            Text(pending.message)
        }
    }
}

// MARK: - Overview

private struct StorageOverviewCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let storage = model.storage
        let report = storage.report
        StorageCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Spreek on this Mac")
                            .font(.spreekRounded(size: 11.5, weight: .heavy))
                            .foregroundStyle(Color.fg3)
                        Text(report.map { StorageModel.size($0.totalBytes) } ?? "…")
                            .font(.spreekRounded(size: 34, weight: .black))
                            .foregroundStyle(Color.fg)
                            .contentTransition(.numericText())
                        Text(Self.displayPath(StorageScanner.defaultRoot))
                            .font(.spreekMono(size: 11.5))
                            .foregroundStyle(Color.fg3)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([StorageScanner.defaultRoot])
                    }
                    .buttonStyle(.small)
                    GlyphButton(symbol: "arrow.clockwise", accessibilityName: "Recalculate", isBusy: storage.isScanning) {
                        storage.refresh(clearingDone: true)
                    }
                    .disabled(storage.isWorking)
                }
                if let report, report.entries.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().fill(Color.chartTrack).frame(height: 12)
                        SettingsHint("No audio cached yet. Clips appear here after you play a sentence.")
                    }
                } else {
                    StorageUsageBar(report: report ?? StorageReport())
                }
                StorageLegend(report: report ?? StorageReport())
                HStack(spacing: 8) {
                    StatPill(tint: .blue, label: "cached clips", value: "\(report?.usage(.audio).count ?? 0)", height: 34, valueSize: 18)
                    StatPill(tint: .pink, label: "sentences with audio", value: "\(storage.classification?.sentencesWithAudio ?? 0)", height: 34, valueSize: 18)
                    StatPill(tint: .gray, label: "reclaimable", value: StorageModel.size(storage.reclaimableBytes), height: 34, valueSize: 18)
                }
                .padding(.top, 2)
            }
            .padding(EdgeInsets(top: 18, leading: 18, bottom: 16, trailing: 18))
        }
    }

    static func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

extension StorageCategory {
    /// Legend order.
    static let displayOrder: [StorageCategory] = [.audio, .library, .subtitlesAndMarks, .voiceList, .temporary]

    var color: Color {
        switch self {
        case .audio: .accentColor
        case .library: .chartPink
        case .subtitlesAndMarks: Color(hex: 0x14A3B8)
        case .voiceList: .favorite
        case .temporary: Color(hex: 0x8E8E93)
        }
    }
}

/// 12 pt bar, one segment per category (2 pt gaps, 3 pt minimum); hover names the segment.
struct StorageUsageBar: View {
    let report: StorageReport
    @State private var hovered: StorageCategory?

    var body: some View {
        let categories = StorageCategory.displayOrder.filter { report.usage($0).bytes > 0 }
        GeometryReader { geometry in
            let widths = Self.widths(categories.map { report.usage($0).bytes }, in: geometry.size.width)
            HStack(spacing: 2) {
                ForEach(Array(categories.enumerated()), id: \.element) { index, category in
                    Rectangle()
                        .fill(category.color)
                        .opacity(hovered == nil || hovered == category ? 1 : 0.55)
                        .frame(width: widths[index])
                        .onHover { inside in
                            if inside { hovered = category } else if hovered == category { hovered = nil }
                        }
                        .help(tooltip(category))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 12)
        .background(Color.chartTrack)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .animation(.easeOut(duration: 0.12), value: hovered)
        .accessibilityElement()
        .accessibilityLabel("Storage by category: " + categories.map { "\($0.title) \(share($0))" }.joined(separator: ", "))
    }

    private func share(_ category: StorageCategory) -> String {
        let total = max(report.totalBytes, 1)
        return "\(Int((Double(report.usage(category).bytes) / Double(total) * 100).rounded()))%"
    }

    private func tooltip(_ category: StorageCategory) -> String {
        "\(category.title) · \(StorageModel.size(report.usage(category).bytes)) · \(share(category))"
    }

    /// Proportional widths that leave room for the gaps, each at least 3 pt.
    static func widths(_ bytes: [Int64], in width: CGFloat) -> [CGFloat] {
        guard !bytes.isEmpty else { return [] }
        let available = max(width - CGFloat(bytes.count - 1) * 2, 0)
        let total = CGFloat(bytes.reduce(0, +))
        var widths = bytes.map { max(CGFloat($0) / max(total, 1) * available, 3) }
        let excess = widths.reduce(0, +) - available
        let shrinkable = widths.filter { $0 > 3 }.reduce(0, +)
        if excess > 0, shrinkable > 0 {
            widths = widths.map { $0 > 3 ? max(3, $0 - excess * $0 / shrinkable) : $0 }
        }
        return widths
    }
}

private struct StorageLegend: View {
    let report: StorageReport

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(StorageCategory.displayOrder, id: \.self) { category in
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(category.color)
                        .frame(width: 10, height: 10)
                        .padding(.top, 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(category.title)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.fg)
                            .lineLimit(1)
                        Text(StorageModel.size(report.usage(category).bytes))
                            .font(.spreekMono(size: 11.5))
                            .foregroundStyle(Color.fg3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Audio cache by

private enum BreakdownView: String, CaseIterable, Hashable {
    case language, voice, engine

    var title: String {
        switch self {
        case .language: "Language"
        case .voice: "Voice"
        case .engine: "Engine"
        }
    }
}

private struct StorageBreakdown: View {
    @Environment(AppModel.self) private var model
    @Environment(\.badgeStyle) private var badgeStyle
    @State private var view: BreakdownView = .language

    /// Voices beyond these collapse into "N more voices".
    private static let voiceRows = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Audio cache by")
                    .font(.spreekRounded(size: 13, weight: .heavy))
                    .foregroundStyle(Color.fg)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                SegmentedControl("Group audio by", options: BreakdownView.allCases, selection: $view) { $0.title }
            }
            StorageCard {
                VStack(spacing: 0) {
                    StorageColumns {
                        Text(view.title)
                        Text("Clips").frame(maxWidth: .infinity, alignment: .trailing)
                        Text("Share")
                        Text("Size").frame(maxWidth: .infinity, alignment: .trailing)
                        Color.clear
                    }
                    .font(.spreekRounded(size: 11.5, weight: .heavy))
                    .foregroundStyle(Color.fg3)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.separator).frame(height: Metrics.hairline) }
                    rows
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
            }
        }
    }

    @ViewBuilder private var rows: some View {
        let report = model.storage.report ?? StorageReport()
        switch view {
        case .language:
            let groups = report.byLanguage()
            let largest = groups.first?.bytes ?? 0
            if groups.isEmpty { emptyRow }
            ForEach(groups) { group in
                StorageBreakdownRow(
                    name: group.id.info.nativeName, meta: voicesMeta(group.voiceIDs), count: group.count,
                    share: Self.share(group.bytes, of: largest), bytes: group.bytes
                ) {
                    LanguageBadge(language: group.id, style: badgeStyle, size: .s)
                } menu: {
                    languageMenu(group)
                }
            }
        case .voice:
            let groups = report.byVoice()
            let shown = groups.prefix(Self.voiceRows)
            let rest = groups.dropFirst(Self.voiceRows)
            let largest = groups.first?.bytes ?? 0
            if groups.isEmpty { emptyRow }
            ForEach(Array(shown)) { group in
                StorageBreakdownRow(
                    name: Self.voiceName(group.id), meta: group.id, count: group.count,
                    share: Self.share(group.bytes, of: largest), bytes: group.bytes
                ) {
                    if let language = LanguageCode.forVoiceID(group.id) {
                        LanguageBadge(language: language, style: badgeStyle, size: .s)
                    } else {
                        NeutralBadge(text: "?")
                    }
                } menu: {
                    voiceMenu(group)
                }
            }
            if !rest.isEmpty {
                let count = rest.reduce(0) { $0 + $1.count }
                let bytes = rest.reduce(0) { $0 + $1.bytes }
                StorageBreakdownRow(
                    name: "\(rest.count) more voices", meta: "", count: count, share: Self.share(bytes, of: largest), bytes: bytes
                ) {
                    NeutralBadge(text: "+\(rest.count)")
                } menu: {
                    EmptyView()
                }
            }
        case .engine:
            let groups = report.byProvider()
            let largest = groups.first?.bytes ?? 0
            if groups.isEmpty { emptyRow }
            ForEach(groups) { group in
                StorageBreakdownRow(
                    name: group.id == .edge ? "Edge Neural" : "macOS System",
                    meta: group.id == .edge ? "Microsoft Edge voices · .mp3" : "AVSpeechSynthesizer · .caf",
                    count: group.count, share: Self.share(group.bytes, of: largest), bytes: group.bytes
                ) {
                    NeutralBadge(symbol: group.id == .edge ? "cloud" : "desktopcomputer")
                } menu: {
                    EmptyView()
                }
            }
        }
    }

    private var emptyRow: some View {
        Text("No audio cached yet.")
            .font(.system(size: 12))
            .foregroundStyle(Color.fg3)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .padding(.horizontal, 10)
    }

    @ViewBuilder private func languageMenu(_ group: StorageGroup<LanguageCode>) -> some View {
        let storage = model.storage
        let name = group.id.info.englishName
        let unlinked = unlinkedKeys(in: group.keys)
        Button("Remove \(name) Audio…") {
            storage.askRemoving(
                group.keys, title: "Remove \(StorageModel.count(group.count, "\(name) clip")) (\(StorageModel.size(group.bytes)))?",
                isDestructive: true
            )
        }
        Button("Remove Unlinked Only") {
            storage.askRemoving(
                unlinked, title: "Remove \(StorageModel.count(unlinked.count, "unlinked \(name) clip")) (\(StorageModel.size(storage.bytes(of: unlinked))))?",
                isDestructive: false
            )
        }
        .disabled(unlinked.isEmpty)
        Divider()
        Button("Show Sentences in History") { showHistory(group.id) }
    }

    @ViewBuilder private func voiceMenu(_ group: StorageGroup<String>) -> some View {
        let storage = model.storage
        let name = Self.voiceName(group.id)
        let unlinked = unlinkedKeys(in: group.keys)
        Button("Remove This Voice’s Audio…") {
            storage.askRemoving(
                group.keys, title: "Remove \(StorageModel.count(group.count, "clip")) by \(name) (\(StorageModel.size(group.bytes)))?",
                isDestructive: true
            )
        }
        Button("Remove Unlinked Only") {
            storage.askRemoving(
                unlinked, title: "Remove \(StorageModel.count(unlinked.count, "unlinked clip")) by \(name) (\(StorageModel.size(storage.bytes(of: unlinked))))?",
                isDestructive: false
            )
        }
        .disabled(unlinked.isEmpty)
        if let language = LanguageCode.forVoiceID(group.id) {
            Divider()
            Button("Show Sentences in History") { showHistory(language) }
        }
    }

    private func unlinkedKeys(in keys: [String]) -> [String] {
        guard let classification = model.storage.classification else { return [] }
        return keys.filter { classification.link(of: $0) == .unlinked }
    }

    private func showHistory(_ language: LanguageCode) {
        let dashboard = model.dashboard
        dashboard.show(.history)
        dashboard.query.text = ""
        dashboard.query.language = language
        dashboard.query.range = .all
    }

    private func voicesMeta(_ voices: Set<String>) -> String {
        voices.count == 1 ? voices.first.map(Self.voiceName) ?? "" : "\(voices.count) voices"
    }

    static func voiceName(_ voiceID: String) -> String {
        if EdgeCLIProvider.isEdgeVoiceID(voiceID) { return EdgeVoiceCatalog.displayName(for: voiceID) }
        return SystemProvider.voiceName(for: voiceID) ?? voiceID.split(separator: ".").last.map(String.init) ?? voiceID
    }

    static func share(_ bytes: Int64, of largest: Int64) -> Double {
        largest > 0 ? max(Double(bytes) / Double(largest), 0.02) : 0
    }
}

/// One "Audio cache by" row: badge + name + meta, clips, share bar, size, `…` menu.
struct StorageBreakdownRow<Badge: View, MenuItems: View>: View {
    let name: String
    let meta: String
    let count: Int
    /// 0…1 of the largest row.
    let share: Double
    let bytes: Int64
    @ViewBuilder var badge: () -> Badge
    @ViewBuilder var menu: () -> MenuItems

    @Environment(AppModel.self) private var model
    @State private var hovering = false

    var body: some View {
        StorageColumns {
            HStack(spacing: 9) {
                badge()
                Text(name)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.fg)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(meta)
                    .font(.spreekMono(size: 11))
                    .foregroundStyle(Color.fg3)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text("\(count)")
                .font(.spreekMono(size: 12))
                .foregroundStyle(Color.fg2)
                .frame(maxWidth: .infinity, alignment: .trailing)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.chartTrack)
                    Capsule().fill(Color.accentColor).frame(width: geometry.size.width * share)
                }
            }
            .frame(height: 6)
            Text(StorageModel.size(bytes))
                .font(.spreekMono(size: 12))
                .foregroundStyle(Color.fg)
                .frame(maxWidth: .infinity, alignment: .trailing)
            if MenuItems.self == EmptyView.self {
                Color.clear.frame(width: 24, height: 24)
            } else {
                Menu(content: menu) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.fg2)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hovering ? Color.field : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .plainMenu()
                .disabled(model.storage.isWorking)
                .accessibilityLabel("Actions for \(name)")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? Color.control : .clear))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(light: .black.opacity(0.07), dark: .white.opacity(0.06))).frame(height: Metrics.hairline)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
    }
}

/// Columns of the breakdown table: name 1.3 : share 1 share the flexible width; clips 70,
/// size 80 and the menu 30 are fixed; 14 pt gaps.
private struct StorageColumns: Layout {
    private static let fixed: [Int: CGFloat] = [1: 70, 3: 80, 4: 30]
    private static let spacing: CGFloat = 14

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 600, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let fixedTotal = Self.fixed.values.reduce(0, +)
        let flexible = max(bounds.width - fixedTotal - Self.spacing * CGFloat(subviews.count - 1), 0)
        let widths: [CGFloat] = subviews.indices.map { Self.fixed[$0] ?? (flexible * ($0 == 0 ? 1.3 : 1) / 2.3) }
        var x = bounds.minX
        for (index, subview) in subviews.enumerated() {
            let width = widths[index]
            subview.place(
                at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + Self.spacing
        }
    }
}

/// Gray badge the size of a `LanguageBadge` .s, for engines and "more voices".
private struct NeutralBadge: View {
    var text: String?
    var symbol: String?

    var body: some View {
        Group {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            } else {
                Text(text ?? "").font(.spreekRounded(size: 9.5, weight: .heavy))
            }
        }
        .foregroundStyle(Color(lightHex: 0x45454B, darkHex: 0xC7C7CC))
        .frame(width: 24, height: 16)
        .background(Color(lightHex: 0xE4E4E8, darkHex: 0x3A3A3D), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Clean up

/// One clean-up: icon tile, title (+ inline popup), description, amount and button, or its
/// working / done state.
struct CleanupRow<Accessory: View>: View {
    let kind: CleanupKind
    let symbol: String
    let title: String
    let detail: String
    let button: String
    var isDestructive = false
    var isLast = false
    @ViewBuilder var accessory: () -> Accessory

    @Environment(AppModel.self) private var model

    var body: some View {
        let storage = model.storage
        let state = storage.state(kind)
        HStack(spacing: 14) {
            iconTile(state)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.fg)
                    accessory()
                        .disabled(storage.isWorking)
                }
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.fg3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing(state)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 58)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Color(light: .black.opacity(0.07), dark: .white.opacity(0.06))).frame(height: Metrics.hairline)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func iconTile(_ state: CleanupRowState) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.control)
            switch state {
            case .working:
                ProgressView().controlSize(.small)
            case .done:
                Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.storageOK)
            case .ready, .nothing:
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isDestructive ? Color.storageDanger : Color.fg2)
            }
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func trailing(_ state: CleanupRowState) -> some View {
        let storage = model.storage
        switch state {
        case .working(let done, let total):
            Text(total > 1 ? "Removing… \(done) / \(total)" : "Removing…")
                .font(.spreekMono(size: 12))
                .foregroundStyle(Color.fg2)
        case .done(let freed):
            HStack(spacing: 6) {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                if kind == .oldSentences {
                    Text("Removed \(StorageModel.count(Int(freed), "sentence"))")
                } else {
                    Text("Freed")
                    Text(StorageModel.size(freed)).font(.spreekMono(size: 12))
                }
            }
            .font(.system(size: 12.5))
            .foregroundStyle(Color.storageOK)
        case .ready, .nothing:
            Text(storage.amount(kind))
                .font(.spreekMono(size: 12))
                .foregroundStyle(state == .nothing ? Color.fg3 : Color.fg2)
                .lineLimit(1)
                .fixedSize()
            Button { storage.ask(kind) } label: {
                Text(button).foregroundStyle(isDestructive ? Color.storageDanger : Color.fg)
            }
            .buttonStyle(.small)
            .disabled(state == .nothing || storage.isWorking || storage.report == nil)
        }
    }
}

extension CleanupRow where Accessory == EmptyView {
    init(kind: CleanupKind, symbol: String, title: String, detail: String, button: String, isDestructive: Bool = false, isLast: Bool = false) {
        self.init(kind: kind, symbol: symbol, title: title, detail: detail, button: button, isDestructive: isDestructive, isLast: isLast) {
            EmptyView()
        }
    }
}

// MARK: - Pieces

extension Color {
    /// Done state ("Freed …").
    static let storageOK = Color(lightHex: 0x1F7A3D, darkHex: 0x7FD69A)
    /// "Clear Cache…" text and icon.
    static let storageDanger = Color(lightHex: 0xC4291C, darkHex: 0xFF8A80)
}

/// `card` surface: 14 pt radius, hairline, soft shadow (like the Engines cards).
struct StorageCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(light: .white, dark: Color(hex: 0x2E2E31)), in: shape)
            .overlay(shape.strokeBorder(Color.separator, lineWidth: Metrics.hairline))
            .shadow(color: .black.opacity(0.06), radius: 1.5, y: 1)
    }
}

/// 24 pt borderless glyph button (`.glyph`); a spinner while `isBusy`.
private struct GlyphButton: View {
    let symbol: String
    let accessibilityName: String
    var isBusy = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if isBusy {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(Color.fg2)
            .frame(width: 24, height: 24)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hovering ? Color.control : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(accessibilityName)
        .accessibilityLabel(accessibilityName)
    }
}
