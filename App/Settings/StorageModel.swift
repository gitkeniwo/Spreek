import Foundation
import Observation
import SpreekCore
import SwiftData

/// Settings › Storage clean-up rows.
enum CleanupKind: Hashable {
    case unlinked, extraSpeeds, idle, temporary, oldSentences, all
    /// A row menu in "Audio cache by" (a language's or voice's clips); no row state of its own.
    case group
}

/// What a clean-up row shows.
enum CleanupRowState: Equatable {
    case ready
    case nothing
    case working(done: Int, total: Int)
    /// `freed` bytes, or for old sentences the number removed.
    case done(freed: Int64)
}

/// "Audio not played in" choices.
enum IdleAge: String, CaseIterable, Hashable {
    case oneMonth, threeMonths, sixMonths, oneYear

    var title: String {
        switch self {
        case .oneMonth: "1 month"
        case .threeMonths: "3 months"
        case .sixMonths: "6 months"
        case .oneYear: "1 year"
        }
    }

    func cutoff(now: Date = .now) -> Date {
        let months = switch self {
        case .oneMonth: 1
        case .threeMonths: 3
        case .sixMonths: 6
        case .oneYear: 12
        }
        return Calendar.current.date(byAdding: .month, value: -months, to: now) ?? now
    }
}

/// A clean-up waiting for its confirmation alert.
struct PendingCleanup: Identifiable {
    enum Action {
        case keys([String])
        case idle(Date)
        case oldSentences
        case all
    }

    let id = UUID()
    let kind: CleanupKind
    let action: Action
    let title: String
    let message: String
    let confirmLabel: String
    var isDestructive = false
}

/// Settings › Storage: the last scan, its classification against the library, clean-up state,
/// and the audio cache limit. Scans and clean-ups run off the main actor.
@MainActor
@Observable
final class StorageModel {
    private(set) var report: StorageReport?
    private(set) var classification: StorageClassification?
    private(set) var isScanning = false
    /// Sentences "Old sentences now" would remove.
    private(set) var oldSentenceCount = 0
    /// Rows that are working or done; the others follow from the report.
    private(set) var states: [CleanupKind: CleanupRowState] = [:]
    var pending: PendingCleanup?
    var idleAge: IdleAge = .threeMonths
    /// The Storage page is on screen (library saves rescan only then).
    var isVisible = false {
        didSet { if isVisible && !oldValue { refresh(clearingDone: true) } }
    }

    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private let speech: SpeechController
    @ObservationIgnored private let settings: AppSettings
    /// `AppModel.pruneHistory()`.
    @ObservationIgnored var pruneHistory: () -> Void = {}
    @ObservationIgnored private let scanner = StorageScanner()
    @ObservationIgnored private var scanGeneration = 0
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var saveObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var isTrimming = false
    @ObservationIgnored private var trimsAgain = false

    init(library: LibraryStore, speech: SpeechController, settings: AppSettings) {
        self.library = library
        self.speech = speech
        self.settings = settings
        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: library.context, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
    }

    var isWorking: Bool {
        states.values.contains { if case .working = $0 { true } else { false } }
    }

    /// The clip the speech controller has loaded: never removed.
    private var protected: Set<URL> {
        Set([speech.currentAudioURL].compactMap { $0 })
    }

    // MARK: Scanning

    /// Rescans. `clearingDone` drops the "Freed …" results (page opened, recalculate).
    func refresh(clearingDone: Bool = false) {
        debounce?.cancel()
        let owners = library.audioOwners()
        oldSentenceCount = settings.historyRetention.cutoff().map { library.unkeptSentences(lastPlayedBefore: $0).count } ?? 0
        scanGeneration += 1
        let generation = scanGeneration
        isScanning = true
        let scanner = scanner
        Task {
            let (report, classification) = await Task.detached(priority: .userInitiated) {
                let report = scanner.scan()
                return (report, StorageClassification(report: report, owners: owners))
            }.value
            guard generation == scanGeneration else { return }
            self.report = report
            self.classification = classification
            isScanning = false
            if clearingDone { states = states.filter { if case .working = $0.value { true } else { false } } }
        }
    }

    /// Library changed (a sentence played, deleted, favorited): rescan shortly, while visible.
    private func scheduleRefresh() {
        guard isVisible else { return }
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            refresh()
        }
    }

    // MARK: Amounts

    func keys(_ kind: CleanupKind) -> [String] {
        guard let report, let classification else { return [] }
        return switch kind {
        case .unlinked: classification.keys(.unlinked)
        case .extraSpeeds: classification.keys(.extraSpeed)
        case .idle: report.entries(lastUsedBefore: idleAge.cutoff()).map(\.key)
        case .all: report.entries.map(\.key)
        case .temporary, .oldSentences, .group: []
        }
    }

    func bytes(of keys: some Sequence<String>) -> Int64 {
        guard let report else { return 0 }
        let wanted = Set(keys)
        return report.entries.reduce(0) { wanted.contains($1.key) ? $0 + $1.totalBytes : $0 }
    }

    /// Unlinked plus extra speeds.
    var reclaimableBytes: Int64 { bytes(of: keys(.unlinked) + keys(.extraSpeeds)) }

    /// "38 clips · 1.5 MB", "7 folders · 8 KB", "3 sentences".
    func amount(_ kind: CleanupKind) -> String {
        switch kind {
        case .temporary:
            let usage = report?.usage(.temporary) ?? StorageUsage()
            return usage.count == 0 ? "0 items" : "\(Self.count(usage.count, "item")) · \(Self.size(usage.bytes))"
        case .oldSentences:
            return Self.count(oldSentenceCount, "sentence")
        default:
            let keys = keys(kind)
            return keys.isEmpty ? "0 clips" : "\(Self.count(keys.count, "clip")) · \(Self.size(bytes(of: keys)))"
        }
    }

    func state(_ kind: CleanupKind) -> CleanupRowState {
        if let state = states[kind] { return state }
        let isEmpty = switch kind {
        case .temporary: (report?.usage(.temporary).count ?? 0) == 0
        case .oldSentences: oldSentenceCount == 0
        default: keys(kind).isEmpty
        }
        return isEmpty ? .nothing : .ready
    }

    // MARK: Clean-ups

    /// The row's button: asks first (temporary files run at once).
    func ask(_ kind: CleanupKind) {
        let keys = keys(kind)
        let size = Self.size(bytes(of: keys))
        switch kind {
        case .unlinked:
            pending = PendingCleanup(
                kind: kind, action: .keys(keys), title: "Remove \(Self.count(keys.count, "unlinked clip"))?",
                message: "No sentence in your library plays \(keys.count == 1 ? "it" : "these") any more. Frees \(size).",
                confirmLabel: "Remove"
            )
        case .extraSpeeds:
            pending = PendingCleanup(
                kind: kind, action: .keys(keys), title: "Remove \(Self.count(keys.count, "clip")) at other speeds?",
                message: "Each sentence keeps the speed it was last played at. Other speeds are synthesized again when needed. Frees \(size).",
                confirmLabel: "Remove"
            )
        case .idle:
            pending = PendingCleanup(
                kind: kind, action: .idle(idleAge.cutoff()),
                title: "Remove \(Self.count(keys.count, "clip")) not played in \(idleAge.title)?",
                message: "Only the audio goes; sentences, notes and favorites stay. Frees \(size).",
                confirmLabel: "Remove"
            )
        case .temporary:
            run(.temporary)
        case .oldSentences:
            pending = PendingCleanup(
                kind: kind, action: .oldSentences, title: "Remove \(Self.count(oldSentenceCount, "old sentence"))?",
                message: "Applies “Remove old sentences”: sentences not played since then that aren't favorites, in a folder, tagged or annotated are deleted with their audio.",
                confirmLabel: "Remove"
            )
        case .all:
            pending = PendingCleanup(
                kind: kind, action: .all, title: "Clear the audio cache?",
                message: "Spoken sentences are synthesized again the next time you play them. Your history, notes and favorites stay.",
                confirmLabel: "Clear Cache", isDestructive: true
            )
        case .group:
            break
        }
    }

    /// A row menu in "Audio cache by": removes `keys` after asking.
    func askRemoving(_ keys: [String], title: String, isDestructive: Bool) {
        guard !keys.isEmpty else { return }
        pending = PendingCleanup(
            kind: .group, action: .keys(keys), title: title,
            message: "The sentences stay. Their audio is synthesized again the next time you play them.",
            confirmLabel: "Remove", isDestructive: isDestructive
        )
    }

    func confirm(_ pending: PendingCleanup) {
        self.pending = nil
        switch pending.action {
        case .keys(let keys): run(pending.kind, keys: keys)
        case .idle(let cutoff): run(pending.kind, idleCutoff: cutoff)
        case .oldSentences: run(.oldSentences)
        case .all: run(.all)
        }
    }

    private func run(_ kind: CleanupKind, keys: [String] = [], idleCutoff: Date? = nil) {
        guard !isWorking else { return }
        let protecting = protected
        let cache = scanner.cache
        let scanner = scanner
        if kind == .oldSentences {
            let before = oldSentenceCount
            pruneHistory()
            states[kind] = .done(freed: Int64(before))
            refresh()
            return
        }
        states[kind] = .working(done: 0, total: max(keys.count, 1))
        Task {
            let progress: @Sendable (Int, Int) -> Void = { done, total in
                Task { @MainActor [weak self] in
                    guard let self, case .working = self.states[kind] else { return }
                    self.states[kind] = .working(done: done, total: total)
                }
            }
            let freed = await Task.detached(priority: .userInitiated) { () -> Int64 in
                switch kind {
                case .temporary:
                    // Anything written in the last half minute may belong to a synthesis in progress.
                    return scanner.removeTemporaryFiles(protecting: protecting, modifiedBefore: Date().addingTimeInterval(-30))
                case .all:
                    let report = scanner.scan()
                    guard !protecting.isEmpty else {
                        // Nothing loaded in the player: clear the folder outright.
                        return (try? cache.clear()) != nil ? report.cacheBytes : 0
                    }
                    return cache.remove(keys: report.entries.map(\.key), protecting: protecting, progress: progress)
                case .idle:
                    return cache.removeEntries(lastUsedBefore: idleCutoff ?? .distantPast, protecting: protecting)
                default:
                    return cache.remove(keys: keys, protecting: protecting, progress: progress)
                }
            }.value
            states[kind] = .done(freed: freed)
            if kind == .group { states[kind] = nil }
            refresh()
        }
    }

    // MARK: Cache limit

    /// Trims the cache to `settings.audioCacheLimit`, least recently used first, favorites last.
    /// Called when the setting changes and after each newly spoken clip.
    func applyCacheLimit() {
        guard let limit = settings.audioCacheLimit.bytes else { return }
        guard !isTrimming else {
            trimsAgain = true
            return
        }
        isTrimming = true
        let favorites = library.favorites().map {
            AudioOwner(normalizedText: AudioCache.spokenText($0.text), voiceID: $0.voiceID, isFavorite: true)
        }
        let protecting = protected
        let scanner = scanner
        Task {
            let freed = await Task.detached(priority: .utility) { () -> Int64 in
                guard scanner.cache.size() > limit else { return 0 }
                let report = scanner.scan()
                let favoriteKeys = StorageClassification(report: report, owners: favorites).favoriteKeys
                return scanner.cache.trim(toBytes: limit, favoriteKeys: favoriteKeys, protecting: protecting)
            }.value
            isTrimming = false
            if freed > 0 { scheduleRefresh() }
            if trimsAgain {
                trimsAgain = false
                applyCacheLimit()
            }
        }
    }

    // MARK: Formatting

    static func size(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }

    static func count(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }
}

/// Deletes the cached audio of deleted sentences off the main actor, batching the deletions of
/// one run loop turn (History retention removes many sentences at once).
@MainActor
final class CachedAudioRemover {
    private let cache: AudioCache
    /// Texts whose every clip goes.
    private var texts: Set<String> = []
    /// Text + voice pairs (another sentence still has the text).
    private var voiced: [(text: String, voiceID: String)] = []

    init(cache: AudioCache = AudioCache()) {
        self.cache = cache
    }

    /// `LibraryStore`'s `removeCachedAudio`: `voiceID == nil` removes every voice's clips.
    func remove(text: String, voiceID: String?) {
        let isFirst = texts.isEmpty && voiced.isEmpty
        if let voiceID { voiced.append((text, voiceID)) } else { texts.insert(text) }
        guard isFirst else { return }
        Task { @MainActor in flush() }
    }

    private func flush() {
        let cache = cache
        let texts = texts
        let voiced = voiced
        self.texts = []
        self.voiced = []
        Task.detached(priority: .utility) {
            cache.remove(texts: texts)
            for pair in voiced { cache.remove(text: pair.text, voiceID: pair.voiceID) }
        }
    }
}
