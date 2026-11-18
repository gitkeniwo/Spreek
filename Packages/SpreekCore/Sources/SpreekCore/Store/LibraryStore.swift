import Foundation
import SwiftData

/// Sentences grouped under one day header in the History list.
public struct DayBucket {
    public enum Label: Hashable, Sendable {
        case today
        case yesterday
        /// Start of that day.
        case date(Date)
    }

    /// Start of the day.
    public let day: Date
    public let label: Label
    /// Most recently played first.
    public let sentences: [Sentence]
}

/// Reads and writes the library. All mutations save immediately.
@MainActor
public final class LibraryStore {
    public let context: ModelContext
    public let calendar: Calendar
    let now: () -> Date
    private let removeCachedAudio: (_ text: String, _ voiceID: String?) -> Void

    /// - Parameters:
    ///   - now: clock, injectable for tests.
    ///   - removeCachedAudio: deletes a sentence's cached audio when the sentence is deleted:
    ///     every clip of the text with `voiceID == nil`, else only that voice's clips.
    public init(
        context: ModelContext,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        removeCachedAudio: @escaping (_ text: String, _ voiceID: String?) -> Void = { _, _ in }
    ) {
        self.context = context
        self.calendar = calendar
        self.now = now
        self.removeCachedAudio = removeCachedAudio
    }

    // MARK: Container

    public static let schema = Schema([Sentence.self, Folder.self, Tag.self, PlayEvent.self])

    /// `~/Library/Application Support/Spreek/Library.store`.
    public static var defaultStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: "Spreek/Library.store")
    }

    /// The app's shared container (on disk), or an in-memory one for tests and previews.
    public static func makeContainer(inMemory: Bool = false, url: URL = defaultStoreURL) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            configuration = ModelConfiguration(schema: schema, url: url)
        }
        return try ModelContainer(for: schema, configurations: configuration)
    }

    // MARK: Recording

    /// Dedupe key: normalized whitespace, case- and width-folded. Diacritics are kept
    /// (they matter in German and Dutch).
    public static func normalizedKey(for text: String) -> String {
        (TextNormalizer.normalize(text, maxLength: .max) ?? "")
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
    }

    /// Records one playback. Same normalized text + language as an existing sentence (by its
    /// detected or effective language) bumps that row instead of inserting a new one.
    @discardableResult
    public func recordSpoken(text: String, language: LanguageCode, voiceID: String?, source: SpokenSource) -> Sentence {
        let date = now()
        let key = Self.normalizedKey(for: text)
        let sentence: Sentence
        if let existing = existingSentence(normalizedText: key, language: language) {
            sentence = existing
            if let voiceID { sentence.voiceID = voiceID }
            if sentence.sourceApp == nil {
                sentence.sourceApp = source.appName
                sentence.sourceBundleID = source.bundleID
            }
            if sentence.sourceURL == nil { sentence.sourceURL = source.url?.absoluteString }
        } else {
            sentence = Sentence(
                text: text, normalizedText: key, language: language, createdAt: date, voiceID: voiceID,
                sourceApp: source.appName, sourceURL: source.url?.absoluteString, sourceBundleID: source.bundleID
            )
            context.insert(sentence)
        }
        sentence.playCount += 1
        sentence.lastPlayedAt = date
        context.insert(PlayEvent(sentence: sentence, date: date))
        save()
        return sentence
    }

    private func existingSentence(normalizedText key: String, language: LanguageCode) -> Sentence? {
        let descriptor = FetchDescriptor<Sentence>(predicate: #Predicate { $0.normalizedText == key })
        let matches = (try? context.fetch(descriptor)) ?? []
        return matches.first { $0.language == language } ?? matches.first { $0.effectiveLanguage == language }
    }

    // MARK: First run

    /// One everyday sentence per default language, added to a brand-new library so the
    /// dashboard isn't empty. Ordinary, unplayed sentences: no folder, no tags.
    public static let firstRunSamples: [(language: LanguageCode, text: String)] = [
        (.nl, "Goedemorgen! Mag ik een kopje koffie, alstublieft?"),
        (.de, "Entschuldigung, wie komme ich zum Bahnhof?"),
        (.ja, "今日はいい天気ですね。散歩に行きませんか。"),
        (.ko, "안녕하세요, 만나서 반갑습니다."),
        (.enUS, "Could you tell me where the nearest bus stop is?"),
        (.zhCN, "你好，请问最近的地铁站怎么走？"),
        (.fr, "Bonjour, je voudrais réserver une table pour deux, s'il vous plaît."),
        (.es, "¿Dónde está la estación de tren más cercana?"),
        (.ptBR, "Bom dia! Você sabe a que horas o museu abre?"),
    ]

    /// Inserts `firstRunSamples`, oldest-first in list order (the first sample ends up on top).
    public func insertFirstRunSamples() {
        let date = now()
        for (index, sample) in Self.firstRunSamples.enumerated() {
            let created = date.addingTimeInterval(-Double(index))
            context.insert(Sentence(
                text: sample.text, normalizedText: Self.normalizedKey(for: sample.text),
                language: sample.language, createdAt: created
            ))
        }
        save()
    }

    // MARK: Sentences

    public func toggleFavorite(_ sentence: Sentence) {
        sentence.isFavorite.toggle()
        sentence.favoritedAt = sentence.isFavorite ? now() : nil
        save()
    }

    /// Files `sentence` in `folder`, or unfiles it with `nil`.
    public func move(_ sentence: Sentence, to folder: Folder?) {
        move([sentence], to: folder)
    }

    /// Files all `sentences` in `folder` (`nil` unfiles them) with one save. The folder's
    /// language wins over each sentence's detected language, as for a single move.
    public func move(_ sentences: [Sentence], to folder: Folder?) {
        guard !sentences.isEmpty else { return }
        for sentence in sentences { sentence.folder = folder }
        save()
    }

    /// Stores `markdown` (restricted Markdown, see `NoteFormat`) as the sentence's note.
    public func setNote(_ markdown: String, for sentence: Sentence) {
        sentence.note = markdown
        save()
    }

    /// Deletes the sentence, its play events and its cached audio: every clip of its text, unless
    /// another sentence (same text, other language) still has that text, then only its voice's.
    public func delete(_ sentence: Sentence) {
        let text = AudioCache.spokenText(sentence.text)
        let shared = fetch(FetchDescriptor<Sentence>()).contains {
            $0 !== sentence && !$0.isDeleted && AudioCache.spokenText($0.text) == text
        }
        if !shared {
            removeCachedAudio(sentence.text, nil)
        } else if let voiceID = sentence.voiceID {
            removeCachedAudio(sentence.text, voiceID)
        }
        context.delete(sentence)
        save()
    }

    /// Who plays which cached audio: one owner per sentence (Settings › Storage classification).
    public func audioOwners() -> [AudioOwner] {
        fetch(FetchDescriptor<Sentence>()).map {
            AudioOwner(normalizedText: AudioCache.spokenText($0.text), voiceID: $0.voiceID, isFavorite: $0.isFavorite)
        }
    }

    /// Sentences last played before `cutoff` that nothing keeps: not a favorite, in no folder,
    /// without tags and without a note (History retention).
    public func unkeptSentences(lastPlayedBefore cutoff: Date) -> [Sentence] {
        let descriptor = FetchDescriptor<Sentence>(predicate: #Predicate { !$0.isFavorite && $0.lastPlayedAt < cutoff })
        return fetch(descriptor).filter { sentence in
            sentence.folder == nil && sentence.tags.isEmpty
                && sentence.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    // MARK: Folders

    @discardableResult
    public func createFolder(name: String, color: String, symbol: String, language: LanguageCode?) -> Folder {
        let folder = Folder(name: name, colorID: color, symbol: symbol, language: language, createdAt: now())
        context.insert(folder)
        save()
        return folder
    }

    /// Changes the given fields. `language` / `voiceID` / `speed` take a double optional: `.some(nil)` clears.
    public func updateFolder(
        _ folder: Folder,
        name: String? = nil,
        color: String? = nil,
        symbol: String? = nil,
        language: LanguageCode?? = nil,
        voiceID: String?? = nil,
        speed: Double?? = nil,
        note: String? = nil
    ) {
        if let name { folder.name = name }
        if let color { folder.colorID = color }
        if let symbol { folder.symbol = symbol }
        if let language { folder.language = language }
        if let voiceID { folder.voiceID = voiceID }
        if let speed { folder.speed = speed }
        if let note { folder.note = note }
        save()
    }

    /// Deletes the folder; its sentences become unfiled.
    public func deleteFolder(_ folder: Folder) {
        for sentence in folder.sentences { sentence.folder = nil }
        context.delete(folder)
        save()
    }

    public func folders() -> [Folder] {
        fetch(FetchDescriptor<Folder>(sortBy: [SortDescriptor(\.createdAt), SortDescriptor(\.name)]))
    }

    // MARK: Tags

    @discardableResult
    public func createTag(name: String, color: String) -> Tag {
        let tag = Tag(name: name, colorID: color)
        context.insert(tag)
        save()
        return tag
    }

    public func updateTag(_ tag: Tag, name: String? = nil, color: String? = nil) {
        if let name { tag.name = name }
        if let color { tag.colorID = color }
        save()
    }

    public func deleteTag(_ tag: Tag) {
        for sentence in tag.sentences { sentence.tags.removeAll { $0 === tag } }
        context.delete(tag)
        save()
    }

    public func tags() -> [Tag] {
        fetch(FetchDescriptor<Tag>(sortBy: [SortDescriptor(\.name)]))
    }

    public func assign(_ tag: Tag, to sentence: Sentence) {
        guard !sentence.tags.contains(where: { $0 === tag }) else { return }
        sentence.tags.append(tag)
        save()
    }

    /// Adds `tag` to every sentence that doesn't have it yet, with one save.
    public func addTag(_ tag: Tag, to sentences: [Sentence]) {
        var changed = false
        for sentence in sentences where !sentence.tags.contains(where: { $0 === tag }) {
            sentence.tags.append(tag)
            changed = true
        }
        if changed { save() }
    }

    public func unassign(_ tag: Tag, from sentence: Sentence) {
        sentence.tags.removeAll { $0 === tag }
        save()
    }

    // MARK: Queries

    /// Most recently played first.
    public func recent(limit: Int? = nil) -> [Sentence] {
        var descriptor = FetchDescriptor<Sentence>(sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return fetch(descriptor)
    }

    /// Most recently favorited first.
    public func favorites() -> [Sentence] {
        fetch(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.isFavorite },
            sortBy: [SortDescriptor(\.favoritedAt, order: .reverse), SortDescriptor(\.lastPlayedAt, order: .reverse)]
        ))
    }

    /// Most recently played first.
    public func sentences(in folder: Folder) -> [Sentence] {
        folder.sentences.sorted { $0.lastPlayedAt > $1.lastPlayedAt }
    }

    /// Most recently played first.
    public func sentences(with tag: Tag) -> [Sentence] {
        tag.sentences.sorted { $0.lastPlayedAt > $1.lastPlayedAt }
    }

    /// Sentences whose text or note contains `query`, ignoring case and diacritics.
    /// An empty query returns everything. Most recently played first.
    public func search(_ query: String) -> [Sentence] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return recent() }
        return recent().filter { sentence in
            Self.matches(sentence.text, query) || Self.matches(NoteFormat.plainText(fromMarkdown: sentence.note), query)
        }
    }

    static func matches(_ haystack: String, _ needle: String) -> Bool {
        haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil
    }

    // MARK: Dashboard aggregations

    /// The last `days` days including today, as a range from the start of the first day to now.
    public func lastDays(_ days: Int) -> DateInterval {
        let end = now()
        let todayStart = calendar.startOfDay(for: end)
        let start = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: todayStart) ?? todayStart
        return DateInterval(start: start, end: end)
    }

    /// Sentences last played in `range`, grouped by day (newest day first): "Today",
    /// "Yesterday", then dates.
    public func dayBuckets(range: DateInterval) -> [DayBucket] {
        let start = range.start
        let end = range.end
        let played = fetch(FetchDescriptor<Sentence>(
            predicate: #Predicate { $0.lastPlayedAt >= start && $0.lastPlayedAt <= end },
            sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
        ))
        return dayBuckets(played)
    }

    /// One entry per calendar day in `range` (oldest first, zeros included): playbacks and
    /// sentences favorited ("saved") that day.
    public func dailyCounts(range: DateInterval) -> [(day: Date, plays: Int, saves: Int)] {
        let start = range.start
        let end = range.end
        let events = fetch(FetchDescriptor<PlayEvent>(predicate: #Predicate { $0.date >= start && $0.date <= end }))
        let saved = fetch(FetchDescriptor<Sentence>(predicate: #Predicate { $0.isFavorite }))

        var plays: [Date: Int] = [:]
        for event in events { plays[calendar.startOfDay(for: event.date), default: 0] += 1 }
        var saves: [Date: Int] = [:]
        for sentence in saved {
            guard let date = sentence.favoritedAt, range.contains(date) else { continue }
            saves[calendar.startOfDay(for: date), default: 0] += 1
        }

        var result: [(day: Date, plays: Int, saves: Int)] = []
        var day = calendar.startOfDay(for: start)
        repeat {
            result.append((day, plays[day] ?? 0, saves[day] ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        } while day < end
        return result
    }

    // MARK: Helpers

    private func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        (try? context.fetch(descriptor)) ?? []
    }

    func save() {
        do {
            try context.save()
        } catch {
            assertionFailure("LibraryStore save failed: \(error)")
        }
    }
}
