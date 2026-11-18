import Foundation
import SwiftData
import Testing
@testable import SpreekCore

/// Mutable test clock.
@MainActor
private final class Clock {
    var now: Date
    init(_ now: Date) { self.now = now }
}

@MainActor
@Suite struct LibraryStoreTests {
    let container: ModelContainer
    let store: LibraryStore
    fileprivate let clock: Clock
    let calendar: Calendar
    let removed: Box<[(String, String?)]>

    final class Box<T> {
        var value: T
        init(_ value: T) { self.value = value }
    }

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        self.calendar = calendar
        // 2026-10-14 21:20 Amsterdam.
        let clock = Clock(calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 21, minute: 20))!)
        self.clock = clock
        let removed = Box<[(String, String?)]>([])
        self.removed = removed
        container = try LibraryStore.makeContainer(inMemory: true)
        store = LibraryStore(
            context: container.mainContext, calendar: calendar, now: { clock.now },
            removeCachedAudio: { removed.value.append(($0, $1)) }
        )
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func allSentences() throws -> [Sentence] {
        try container.mainContext.fetch(FetchDescriptor<Sentence>())
    }

    private func record(_ text: String, _ language: LanguageCode = .nl, at date: Date? = nil) -> Sentence {
        if let date { clock.now = date }
        return store.recordSpoken(text: text, language: language, voiceID: "nl-NL-FennaNeural", source: SpokenSource(kind: .selection))
    }

    // MARK: Recording

    @Test func speakingTwiceDedupesAndCountsPlays() throws {
        let first = store.recordSpoken(
            text: "Dit. Gezeik blijft maar doorgaan.", language: .nl, voiceID: "nl-NL-FennaNeural",
            source: SpokenSource(kind: .selection, appName: "Safari", url: URL(string: "https://reddit.com/r/thenetherlands"))
        )
        clock.now = clock.now.addingTimeInterval(60)
        let second = record("  dit.   Gezeik blijft maar doorgaan. ")

        #expect(first === second)
        #expect(try allSentences().count == 1)
        #expect(first.playCount == 2)
        #expect(first.lastPlayedAt == clock.now)
        #expect(first.createdAt == clock.now.addingTimeInterval(-60))
        #expect(first.playEvents.count == 2)
        #expect(try container.mainContext.fetch(FetchDescriptor<PlayEvent>()).count == 2)
        #expect(first.sourceApp == "Safari")
        #expect(first.sourceURL == "https://reddit.com/r/thenetherlands")
        #expect(first.text == "Dit. Gezeik blijft maar doorgaan.")
    }

    @Test func sameTextInAnotherLanguageIsANewRow() throws {
        _ = record("Hallo", .nl)
        _ = record("Hallo", .de)
        #expect(try allSentences().count == 2)
    }

    @Test func diacriticsAreNotFoldedForDedupe() throws {
        _ = record("schon", .de)
        _ = record("schön", .de)
        #expect(try allSentences().count == 2)
    }

    // MARK: Favorites

    @Test func toggleFavorite() {
        let sentence = record("Ah toe, geef nou.")
        store.toggleFavorite(sentence)
        #expect(sentence.isFavorite)
        #expect(sentence.favoritedAt == clock.now)
        #expect(store.favorites().map(\.text) == ["Ah toe, geef nou."])
        store.toggleFavorite(sentence)
        #expect(!sentence.isFavorite)
        #expect(sentence.favoritedAt == nil)
        #expect(store.favorites().isEmpty)
    }

    // MARK: Folders

    @Test func folderLanguageIsInheritedAndOverridesDetectionOnReplay() async {
        let sentence = record("Die Katze schläft.", .nl) // misdetected
        #expect(sentence.effectiveLanguage == .nl)
        let folder = store.createFolder(name: "Duits A2", color: "green", symbol: "book.fill", language: .de)
        store.move(sentence, to: folder)
        #expect(sentence.effectiveLanguage == .de)
        #expect(sentence.language == .nl)
        #expect(store.sentences(in: folder).map(\.text) == ["Die Katze schläft."])

        // Replaying from the folder speaks it as German …
        let edge = MockProvider(id: .edge)
        let controller = SpeechController(
            chain: ProviderChain(primary: edge, fallback: MockProvider(id: .system)),
            cache: AudioCache(root: temporaryDirectory()), player: MockPlayer(), tickInterval: nil
        )
        var spoken: [SpokenUtterance] = []
        controller.onSpoken = { spoken.append($0) }
        await controller.speak(text: sentence.text, folderLanguage: sentence.folder?.language, source: .folder).value
        #expect(edge.requests.first?.language == .de)
        #expect(controller.detection?.reason == .folder)

        // … and recording that play bumps the same row.
        let utterance = try! #require(spoken.first)
        #expect(utterance.language == .de)
        let recorded = store.recordSpoken(text: utterance.text, language: utterance.language, voiceID: utterance.voiceID, source: SpokenSource(kind: utterance.source))
        #expect(recorded === sentence)
        #expect(sentence.playCount == 2)

        store.updateFolder(folder, name: "Duits B1", language: .nl, speed: .some(0.9))
        #expect(folder.name == "Duits B1")
        #expect(folder.speed == 0.9)
        #expect(sentence.effectiveLanguage == .nl)
    }

    @Test func deletingAFolderUnfilesItsSentences() throws {
        let folder = store.createFolder(name: "Reddit", color: "orange", symbol: "bubble.left.fill", language: .nl)
        let a = record("Dit.")
        let b = record("Ik geloof het pas als ie klaar is.")
        store.move(a, to: folder)
        store.move(b, to: folder)
        store.deleteFolder(folder)
        #expect(try allSentences().count == 2)
        #expect(a.folder == nil && b.folder == nil)
        #expect(store.folders().isEmpty)
    }

    @Test func unkeptSentencesSkipFavoritesFoldersTagsAndNotes() throws {
        let old = date(1, 10, month: 8)
        let plain = record("Oud en vergeten.", at: old)
        let favorite = record("Bewaard als favoriet.", at: old)
        store.toggleFavorite(favorite)
        let filed = record("In een map.", at: old)
        store.move(filed, to: store.createFolder(name: "Map", color: "blue", symbol: "folder", language: .nl))
        let tagged = record("Met een tag.", at: old)
        store.assign(store.createTag(name: "tag", color: "pink"), to: tagged)
        let annotated = record("Met een notitie.", at: old)
        store.setNote("**let op**", for: annotated)
        _ = record("Gisteren nog gehoord.", at: date(14, 9))

        let cutoff = date(1, 10, month: 9)
        #expect(store.unkeptSentences(lastPlayedBefore: cutoff).map(\.text) == [plain.text])
        // Playing it again keeps it.
        _ = record("Oud en vergeten.", at: date(14, 10))
        #expect(store.unkeptSentences(lastPlayedBefore: cutoff).isEmpty)
    }

    // MARK: Tags

    @Test func tagAssignAndUnassign() {
        let tag = store.createTag(name: "informeel", color: "pink")
        let other = store.createTag(name: "uitdrukking", color: "blue")
        let sentence = record("Ah toe, geef nou.")
        store.assign(tag, to: sentence)
        store.assign(tag, to: sentence) // idempotent
        store.assign(other, to: sentence)
        #expect(sentence.tags.count == 2)
        #expect(store.sentences(with: tag).map(\.text) == ["Ah toe, geef nou."])
        store.unassign(tag, from: sentence)
        #expect(sentence.tags.map(\.name) == ["uitdrukking"])
        #expect(store.sentences(with: tag).isEmpty)
        store.updateTag(other, name: "idioom")
        store.deleteTag(other)
        #expect(sentence.tags.isEmpty)
        #expect(store.tags().map(\.name) == ["informeel"])
    }

    // MARK: Notes, delete, search

    @Test func searchHitsTextAndNoteIgnoringCaseAndDiacritics() {
        let a = record("Ich hätte gern einen Kaffee.", .de)
        let b = record("Dit. Gezeik blijft maar doorgaan.")
        _ = record("Ah toe, geef nou.")
        store.setNote("**gezeik** — van het werkwoord *zeiken*: zeuren", for: b)
        #expect(store.search("HATTE").map(\.text) == [a.text])
        #expect(store.search("werkwoord ZEIKEN").map(\.text) == [b.text])
        #expect(store.search("zeiken").map(\.text) == [b.text])
        #expect(store.search("nothing here").isEmpty)
        #expect(store.search("  ").count == 3)
    }

    @Test func deleteRemovesSentenceEventsAndCachedAudio() throws {
        let sentence = record("Ah toe, geef nou.")
        _ = record("Ah toe, geef nou.")
        store.delete(sentence)
        #expect(try allSentences().isEmpty)
        #expect(try container.mainContext.fetch(FetchDescriptor<PlayEvent>()).isEmpty)
        #expect(removed.value.count == 1)
        #expect(removed.value.first?.0 == "Ah toe, geef nou.")
        #expect(removed.value.first?.1 == nil, "every voice's clips go")
    }

    /// The same text in two languages shares clips: deleting one keeps the other's voice.
    @Test func deleteKeepsAudioOfASentenceWithTheSameText() throws {
        let dutch = record("Hallo")
        let german = store.recordSpoken(text: "Hallo", language: .de, voiceID: "de-DE-KatjaNeural", source: SpokenSource(kind: .selection))
        store.delete(dutch)
        #expect(removed.value.count == 1)
        #expect(removed.value.first?.1 == "nl-NL-FennaNeural")
        #expect(store.audioOwners() == [AudioOwner(normalizedText: "Hallo", voiceID: "de-DE-KatjaNeural", isFavorite: false)])
        _ = german
    }

    @Test func recentIsNewestFirstWithLimit() {
        _ = record("een", at: date(13, 9))
        _ = record("twee", at: date(14, 9))
        _ = record("drie", at: date(12, 9))
        _ = record("een", at: date(14, 10))
        #expect(store.recent(limit: 2).map(\.text) == ["een", "twee"])
    }

    // MARK: Dashboard

    @Test func dayBucketsAcrossMidnight() {
        _ = record("late yesterday", at: date(13, 23, 59))
        _ = record("just after midnight", at: date(14, 0, 1))
        _ = record("two days ago", at: date(12, 12))
        _ = record("too old", at: date(1, 12))
        clock.now = date(14, 21, 20)

        let buckets = store.dayBuckets(range: store.lastDays(7))
        #expect(buckets.map(\.label) == [.today, .yesterday, .date(date(12, 0))])
        #expect(buckets.map { $0.sentences.map(\.text) } == [["just after midnight"], ["late yesterday"], ["two days ago"]])

        // Five minutes into the next day, everything shifts by one bucket label.
        clock.now = date(15, 0, 5)
        let next = store.dayBuckets(range: store.lastDays(7))
        #expect(next.map(\.label) == [.yesterday, .date(date(13, 0)), .date(date(12, 0))])
    }

    @Test func dailyCountsIncludeEmptyDays() {
        let a = record("een", at: date(12, 10))
        _ = record("een", at: date(12, 23, 59))
        _ = record("twee", at: date(14, 0, 0))
        store.toggleFavorite(a) // saved on the 14th
        clock.now = date(14, 21)

        let counts = store.dailyCounts(range: store.lastDays(4))
        #expect(counts.map(\.day) == [date(11, 0), date(12, 0), date(13, 0), date(14, 0)])
        #expect(counts.map(\.plays) == [0, 2, 0, 1])
        #expect(counts.map(\.saves) == [0, 0, 0, 1])
    }

    // MARK: Dashboard list filtering

    @Test func scopesListTheirSentencesNewestFirst() {
        let a = record("een", at: date(12, 9))
        let b = record("twee", at: date(13, 9))
        let c = record("drie", .de, at: date(14, 9))
        let folder = store.createFolder(name: "Duits", color: "green", symbol: "book.fill", language: .de)
        store.move(a, to: folder)
        store.move(c, to: folder)
        let tag = store.createTag(name: "informeel", color: "pink")
        store.assign(tag, to: b)
        store.toggleFavorite(c)
        clock.now = date(14, 10)
        store.toggleFavorite(a)

        #expect(store.sentences(in: .history).map(\.text) == ["drie", "twee", "een"])
        // Favorites are listed by last play, like every other list.
        #expect(store.sentences(in: .favorites).map(\.text) == ["drie", "een"])
        #expect(store.sentences(in: .folder(folder)).map(\.text) == ["drie", "een"])
        #expect(store.sentences(in: .tag(tag)).map(\.text) == ["twee"])
    }

    @Test func queryFiltersByTextLanguageAndRange() {
        let dutch = record("Dit. Gezeik blijft maar doorgaan.", at: date(14, 9))
        _ = record("Ich hätte gern einen Kaffee.", .de, at: date(13, 9))
        _ = record("Ah toe, geef nou.", at: date(1, 9))
        store.setNote("van het werkwoord *zeiken*", for: dutch)
        clock.now = date(14, 21)

        func texts(_ query: LibraryQuery) -> [String] { store.sentences(in: .history, matching: query).map(\.text) }
        #expect(texts(LibraryQuery()).count == 3)
        #expect(texts(LibraryQuery(range: .week)) == ["Dit. Gezeik blijft maar doorgaan.", "Ich hätte gern einen Kaffee."])
        #expect(texts(LibraryQuery(range: .month)).count == 3)
        #expect(texts(LibraryQuery(language: .nl)) == ["Dit. Gezeik blijft maar doorgaan.", "Ah toe, geef nou."])
        #expect(texts(LibraryQuery(language: .nl, range: .week)) == ["Dit. Gezeik blijft maar doorgaan."])
        #expect(texts(LibraryQuery(text: "HATTE")) == ["Ich hätte gern einen Kaffee."])
        #expect(texts(LibraryQuery(text: "ZEIKEN", language: .nl)) == ["Dit. Gezeik blijft maar doorgaan."])
        #expect(texts(LibraryQuery(text: "zeiken", language: .de)).isEmpty)
        #expect(texts(LibraryQuery(text: "  ", range: .week)).count == 2)
    }

    @Test func languageFilterUsesTheFolderLanguage() {
        let sentence = record("Das kommt ganz darauf an.", .nl, at: date(14, 9))
        let folder = store.createFolder(name: "Duits", color: "green", symbol: "book.fill", language: .de)
        #expect(store.sentences(in: .history, matching: LibraryQuery(language: .de)).isEmpty)
        store.move(sentence, to: folder)
        #expect(store.sentences(in: .history, matching: LibraryQuery(language: .de)).map(\.text) == [sentence.text])
        #expect(store.sentences(in: .history, matching: LibraryQuery(language: .nl)).isEmpty)
    }

    @Test func folderWithoutLanguageKeepsTheDetectedOne() {
        let sentence = record("Das kommt ganz darauf an.", .de, at: date(14, 9))
        let folder = store.createFolder(name: "Mixed", color: "gray", symbol: "folder", language: nil)
        store.move(sentence, to: folder)
        #expect(folder.language == nil)
        #expect(sentence.effectiveLanguage == .de)
        store.updateFolder(folder, language: .some(.nl))
        #expect(sentence.effectiveLanguage == .nl)
        store.updateFolder(folder, language: .some(nil))
        #expect(folder.language == nil)
        #expect(sentence.effectiveLanguage == .de)
    }

    @Test func dayBucketsGroupAnyList() {
        _ = record("today", at: date(14, 8))
        _ = record("yesterday", at: date(13, 8))
        _ = record("earlier", at: date(2, 8))
        clock.now = date(14, 21)
        let buckets = store.dayBuckets(store.sentences(in: .history))
        #expect(buckets.map(\.label) == [.today, .yesterday, .date(date(2, 0))])
        #expect(buckets.map { $0.sentences.map(\.text) } == [["today"], ["yesterday"], ["earlier"]])
    }

    @Test func miniBarsCountSevenDaysOldestFirst() {
        _ = record("een", at: date(7, 12)) // eight days back: outside the window
        _ = record("een", at: date(8, 0, 0))
        _ = record("een", at: date(8, 23, 59))
        _ = record("een", at: date(11, 9))
        _ = record("een", at: date(14, 0, 30))
        let sentence = record("een", at: date(14, 21))
        let other = record("twee", at: date(14, 21, 10))

        #expect(store.miniBars(for: sentence) == [2, 0, 0, 1, 0, 0, 2])
        #expect(store.miniBars(for: other) == [0, 0, 0, 0, 0, 0, 1])
        #expect(store.miniBars(for: sentence, days: 3) == [0, 0, 2])

        // Next morning the window slides by a day.
        clock.now = date(15, 8)
        #expect(store.miniBars(for: sentence) == [0, 0, 1, 0, 0, 2, 0])
    }

    @Test func chartWindowPagesBackByWholeWindows() {
        clock.now = date(14, 21)
        #expect(store.chartWindow(days: 7, offset: 0) == store.lastDays(7))
        let previous = store.chartWindow(days: 7, offset: 1)
        #expect(previous.start == date(1, 0))
        #expect(previous.end == date(8, 0).addingTimeInterval(-1))
        let counts = store.dailyCounts(range: previous)
        #expect(counts.map(\.day) == (1...7).map { date($0, 0) })
    }

    @Test func activityHasOneColumnPerDayFor30And90Days() {
        clock.now = date(14, 21)
        _ = record("een", at: date(14, 9))
        _ = record("een", at: date(14, 10))
        _ = record("twee", at: date(10, 9))
        let fav = record("drie", at: date(2, 9))
        clock.now = date(3, 9)
        store.toggleFavorite(fav)
        clock.now = date(14, 21)

        let month = store.activity(.days30)
        #expect(month.days.count == 30)
        #expect(month.days.last?.day == date(14, 0))
        #expect(month.days.first?.day == date(14, 0).addingTimeInterval(-29 * 86_400))
        #expect(month.days.last?.plays == 2)
        #expect(month.totalPlays == 4)
        #expect(month.totalSaves == 1)
        #expect(month.scale == 2)
        #expect(month.days.first { $0.day == date(3, 0) }?.saves == 1)

        let quarter = store.activity(.days90)
        #expect(quarter.days.count == 90)
        #expect(quarter.totalPlays == 4)
        #expect(Set(quarter.days.map(\.day)).count == 90)

        // Paging back a whole window: the 30 days before, nothing recorded there.
        let previous = store.activity(.days30, offset: 1)
        #expect(previous.days.count == 30)
        #expect(previous.days.last?.day == month.days.first?.day.addingTimeInterval(-86_400))
        #expect(previous.totalPlays == 0)
        #expect(previous.scale == 1)
    }

    // MARK: Batch operations

    @Test func batchMoveFilesAndUnfilesSentences() {
        let reddit = store.createFolder(name: "Reddit", color: "orange", symbol: "bubble.left.fill", language: .nl)
        let a = record("Dit.")
        let b = record("Die Katze schläft.", .de)
        let c = record("Blijft hier.")
        store.move([a, b], to: reddit)
        #expect(a.folder === reddit && b.folder === reddit && c.folder == nil)
        // The folder's language wins over the detected one.
        #expect(b.effectiveLanguage == .nl)
        #expect(Set(store.sentences(in: reddit).map(\.text)) == ["Dit.", "Die Katze schläft."])
        store.move([b], to: nil)
        #expect(b.folder == nil && b.effectiveLanguage == .de)
        store.move([], to: reddit)
        #expect(store.sentences(in: reddit).map(\.text) == ["Dit."])
    }

    @Test func batchAddTagIsIdempotent() {
        let tag = store.createTag(name: "informeel", color: "pink")
        let a = record("Ah toe, geef nou.")
        let b = record("Dit.")
        store.assign(tag, to: a)
        store.addTag(tag, to: [a, b])
        #expect(a.tags.count == 1 && b.tags.count == 1)
        #expect(Set(store.sentences(with: tag).map(\.text)) == ["Ah toe, geef nou.", "Dit."])
    }

    // MARK: Sort

    @Test func sortsByFirstRecordedByDefaultOrLastPlayed() {
        let old = record("oud", at: date(1, 9))
        _ = record("nieuw", at: date(12, 9))
        _ = record("middel", at: date(10, 9))
        _ = record("oud", at: date(14, 20)) // replayed today
        func texts(_ query: LibraryQuery) -> [String] { store.sentences(in: .history, matching: query).map(\.text) }

        #expect(LibraryQuery().sort == .firstRecorded)
        #expect(texts(LibraryQuery()) == ["nieuw", "middel", "oud"])
        #expect(texts(LibraryQuery(sort: .lastPlayed)) == ["oud", "nieuw", "middel"])

        // The range follows the sort date: first recorded 13 days ago is outside "7d".
        #expect(texts(LibraryQuery(range: .week)) == ["nieuw", "middel"])
        #expect(texts(LibraryQuery(range: .week, sort: .lastPlayed)) == ["oud", "nieuw", "middel"])

        // Day headers use the same date.
        let byFirst = store.dayBuckets(store.sentences(in: .history), by: .firstRecorded)
        #expect(byFirst.map(\.day) == [date(12, 0), date(10, 0), date(1, 0)])
        let byLast = store.dayBuckets(store.sentences(in: .history, matching: LibraryQuery(sort: .lastPlayed)), by: .lastPlayed)
        #expect(byLast.first?.label == .today)
        #expect(byLast.first?.sentences.map(\.text) == ["oud"])
        #expect(old.createdAt == date(1, 9))
    }

    @Test func sortAppliesToEveryScope() {
        let folder = store.createFolder(name: "Reddit", color: "orange", symbol: "bubble.left.fill", language: .nl)
        let a = record("a", at: date(2, 9))
        let b = record("b", at: date(5, 9))
        _ = record("a", at: date(14, 9))
        store.move([a, b], to: folder)
        store.toggleFavorite(a)
        store.toggleFavorite(b)
        #expect(store.sentences(in: .folder(folder)).map(\.text) == ["b", "a"])
        #expect(store.sentences(in: .folder(folder), matching: LibraryQuery(sort: .lastPlayed)).map(\.text) == ["a", "b"])
        #expect(store.sentences(in: .favorites).map(\.text) == ["b", "a"])
    }

    @Test func firstRunSamplesCoverEveryDefaultLanguageAsPlainUnplayedSentences() {
        #expect(Set(LibraryStore.firstRunSamples.map(\.language)) == LanguageCode.defaultEnabled)
        store.insertFirstRunSamples()
        let sentences = store.recent()
        #expect(sentences.count == LanguageCode.defaultEnabled.count)
        for sentence in sentences {
            #expect(sentence.playCount == 0)
            #expect(sentence.folder == nil && sentence.tags.isEmpty && sentence.note.isEmpty)
            #expect(sentence.normalizedText == LibraryStore.normalizedKey(for: sentence.text))
        }
    }
}
