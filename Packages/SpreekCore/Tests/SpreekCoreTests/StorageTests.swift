import Foundation
import Testing
@testable import SpreekCore

/// Settings › Storage: scanner, classification and clean-ups on a temporary Application Support
/// folder with hand-written entries.
@Suite struct StorageTests {
    let support = temporaryDirectory("StorageSupport")
    let tmp = temporaryDirectory("StorageTmp")
    var scanner: StorageScanner { StorageScanner(root: support, temporaryRoot: tmp) }
    var cache: AudioCache { scanner.cache }

    static let fenna = "nl-NL-FennaNeural"
    static let colette = "nl-NL-ColetteNeural"
    static let katja = "de-DE-KatjaNeural"
    static let amelie = "com.apple.voice.premium.fr-FR.Amelie"

    init() throws {
        try FileManager.default.createDirectory(at: support.appending(path: "Audio"), withIntermediateDirectories: true)
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: support)
        try? FileManager.default.removeItem(at: tmp)
    }

    /// Writes one entry by hand. `oldFormat` leaves out text, rate and createdAt (pre-0.2).
    @discardableResult
    private func entry(
        _ text: String, voice: String = fenna, rate: Double = 1, bytes: Int = 100, ext: String = "mp3",
        srt: Int? = nil, provider: ProviderID = .edge, oldFormat: Bool = false, lastUsed: Date = Date(timeIntervalSince1970: 1_000)
    ) throws -> String {
        let key = AudioCache.key(text: text, voiceID: voice, rate: rate)
        let root = cache.root
        let audio = root.appending(path: "\(key).\(ext)")
        try Data(repeating: 1, count: bytes).write(to: audio)
        if let srt { try Data(repeating: 2, count: srt).write(to: root.appending(path: "\(key).srt")) }
        var json: [String: Any] = ["audioFile": audio.lastPathComponent, "marks": [], "provider": provider.rawValue, "voiceID": voice]
        if !oldFormat {
            json["text"] = text
            json["rate"] = rate
            json["createdAt"] = 0
        }
        try JSONSerialization.data(withJSONObject: json).write(to: root.appending(path: "\(key).json"))
        try FileManager.default.setAttributes([.modificationDate: lastUsed], ofItemAtPath: audio.path)
        return key
    }

    private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    private func exists(_ key: String) -> Bool {
        FileManager.default.fileExists(atPath: cache.root.appending(path: "\(key).json").path)
    }

    // MARK: Metadata

    @Test func storeWritesTextRateAndCreationAndOldMetadataStillDecodes() throws {
        defer { cleanUp() }
        let audio = temporaryDirectory("StorageSource").appendingPathExtension("mp3")
        try Data([1, 2, 3]).write(to: audio)
        let stored = try cache.store(SynthesisResult(audioURL: audio, marks: [], provider: .edge, voiceID: Self.fenna), text: " Hallo  daar ", rate: 0.8500001)
        let meta = try #require(cache.metadata(key: stored.key))
        #expect(meta.text == "Hallo daar")
        #expect(meta.rate == 0.85)
        #expect(meta.createdAt != nil)

        let old = try entry("Oud", oldFormat: true)
        #expect(cache.metadata(key: old)?.text == nil)
        #expect(cache.lookup(key: old)?.voiceID == Self.fenna)
    }

    @Test func lookupTouchesLastUsedButLatestEntryDoesNot() throws {
        defer { cleanUp() }
        let slow = try entry("Hallo", rate: 0.85, lastUsed: date(2_000))
        let normal = try entry("Hallo", rate: 1, lastUsed: date(1_000))
        #expect(cache.latestEntry(text: "Hallo", voiceID: Self.fenna)?.key == slow)
        #expect(cache.latestEntry(text: "Hallo", voiceID: Self.fenna)?.key == slow, "looking doesn't count as using")
        _ = cache.lookup(text: "Hallo", voiceID: Self.fenna, rate: 1)
        #expect(cache.latestEntry(text: "Hallo", voiceID: Self.fenna)?.key == normal)
        #expect(cache.entries(text: "Hallo", voiceID: Self.fenna).map(\.key) == [normal, slow])
    }

    @Test func removeTextRemovesEveryVoiceIncludingOldEntries() throws {
        defer { cleanUp() }
        try entry("Hallo", voice: Self.fenna)
        try entry("Hallo", voice: Self.colette, rate: 0.7)
        try entry("Hallo", voice: Self.katja, oldFormat: true)
        let other = try entry("Dag", voice: Self.katja, oldFormat: true)
        let kept = try entry("Dag")
        cache.remove(text: "  Hallo ")
        #expect(Set(scanner.scan().entries.map(\.key)) == [other, kept])
    }

    // MARK: Scanner

    @Test func scannerTotalsPerCategoryAndGroups() throws {
        defer { cleanUp() }
        try entry("Hallo", bytes: 1_000, srt: 50)
        try entry("Hallo", rate: 0.85, bytes: 900)
        try entry("Dag", voice: Self.colette, bytes: 800, oldFormat: true)
        try entry("Guten Tag", voice: Self.katja, bytes: 700, srt: 40)
        try entry("Bonjour", voice: Self.amelie, bytes: 600, ext: "caf", provider: .system)
        let fm = FileManager.default
        for (name, size) in [("Library.store", 4_000), ("Library.store-wal", 300), ("Library.store-shm", 32), ("edge-voices.json", 2_000)] {
            try Data(repeating: 0, count: size).write(to: support.appending(path: name))
        }
        let edge = tmp.appending(path: "Spreek-Edge")
        try fm.createDirectory(at: edge.appending(path: "job"), withIntermediateDirectories: true)
        try Data(repeating: 0, count: 10).write(to: edge.appending(path: "job/a.mp3"))
        try Data(repeating: 0, count: 5).write(to: edge.appending(path: "b.srt"))
        try fm.createDirectory(at: tmp.appending(path: "Spreek-System"), withIntermediateDirectories: true)
        let leftover = tmp.appending(path: "Spreek-\(UUID().uuidString)")
        try fm.createDirectory(at: leftover, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 999).write(to: leftover.appending(path: "x.mp3"))

        let report = scanner.scan()
        #expect(report.usage(.audio) == StorageUsage(bytes: 4_000, count: 5))
        #expect(report.usage(.subtitlesAndMarks).bytes == report.entries.reduce(0) { $0 + $1.sideBytes })
        #expect(report.usage(.library) == StorageUsage(bytes: 4_332, count: 3))
        #expect(report.usage(.voiceList) == StorageUsage(bytes: 2_000, count: 1))
        #expect(report.usage(.temporary) == StorageUsage(bytes: 15, count: 2), "test leftovers aren't counted")
        #expect(report.totalBytes == 4_000 + report.usage(.subtitlesAndMarks).bytes + 4_332 + 2_000 + 15)
        #expect(report.entries.count == 5)

        let languages = report.byLanguage()
        #expect(languages.map(\.id) == [.nl, .de, .fr])
        #expect(languages[0].count == 3)
        #expect(languages[0].voiceIDs == [Self.fenna, Self.colette])
        #expect(report.byVoice().first?.id == Self.fenna)
        #expect(report.byVoice().first?.count == 2)
        let engines = report.byProvider()
        #expect(engines.map(\.id) == [.edge, .system])
        #expect(engines.map(\.count) == [4, 1])
    }

    @Test func voiceIDLanguages() {
        #expect(LanguageCode.forVoiceID("nl-NL-FennaNeural") == .nl)
        #expect(LanguageCode.forVoiceID("nl-BE-ArnaudNeural") == .nl)
        #expect(LanguageCode.forVoiceID("zh-TW-HsiaoYuNeural") == .zhTW)
        #expect(LanguageCode.forVoiceID("en-GB-SoniaNeural") == .enGB)
        #expect(LanguageCode.forVoiceID("com.apple.voice.premium.fr-FR.Amelie") == .fr)
        #expect(LanguageCode.forVoiceID("xx-YY-NobodyNeural") == nil)
    }

    @Test func emptyCacheScansToZero() {
        defer { cleanUp() }
        let report = StorageScanner(root: temporaryDirectory("NoSupport"), temporaryRoot: temporaryDirectory("NoTmp")).scan()
        #expect(report.totalBytes == 0)
        #expect(report.entries.isEmpty)
    }

    // MARK: Classification

    @Test func classifiesLinkedUnlinkedAndExtraSpeeds() throws {
        defer { cleanUp() }
        let linked = try entry("Hallo", rate: 1, lastUsed: date(3_000))
        let slower = try entry("Hallo", rate: 0.85, lastUsed: date(2_000))
        let slowest = try entry("Hallo", rate: 0.7, lastUsed: date(1_000))
        let oldVoice = try entry("Hallo", voice: Self.colette)
        let deleted = try entry("Weg")
        let oldLinked = try entry("Goedemorgen", rate: 0.9, oldFormat: true)
        let oldUnlinked = try entry("Vergeten", oldFormat: true)
        let neverPlayed = try entry("Guten Tag", voice: Self.katja)
        let favorite = try entry("Ster", voice: Self.katja, oldFormat: true)
        let owners = [
            AudioOwner(normalizedText: "Hallo", voiceID: Self.fenna, isFavorite: false),
            AudioOwner(normalizedText: "Goedemorgen", voiceID: Self.fenna, isFavorite: false),
            AudioOwner(normalizedText: "Guten Tag", voiceID: nil, isFavorite: false),
            AudioOwner(normalizedText: "Ster", voiceID: Self.katja, isFavorite: true),
            AudioOwner(normalizedText: "Zonder audio", voiceID: Self.fenna, isFavorite: false),
        ]
        let result = StorageClassification(report: scanner.scan(), owners: owners)
        #expect(Set(result.keys(.linked)) == [linked, oldLinked, neverPlayed, favorite])
        #expect(Set(result.keys(.extraSpeed)) == [slower, slowest])
        #expect(Set(result.keys(.unlinked)) == [oldVoice, deleted, oldUnlinked])
        #expect(result.favoriteKeys == [favorite])
        #expect(result.sentencesWithAudio == 4)
        #expect(result.recoveredText[oldLinked]?.text == "Goedemorgen")
        #expect(result.recoveredText[oldLinked]?.rate == 0.9)
    }

    /// An old extra speed is found once its text is recovered.
    @Test func oldEntriesCountAsExtraSpeeds() throws {
        defer { cleanUp() }
        let recent = try entry("Hallo", rate: 1, lastUsed: date(2_000))
        let old = try entry("Hallo", rate: 0.8, oldFormat: true, lastUsed: date(1_000))
        let result = StorageClassification(report: scanner.scan(), owners: [AudioOwner(normalizedText: "Hallo", voiceID: Self.fenna, isFavorite: false)])
        #expect(result.link(of: recent) == .linked)
        #expect(result.link(of: old) == .extraSpeed)
    }

    @Test func entriesWithoutMetadataOrAudioAreUnlinked() throws {
        defer { cleanUp() }
        let noMeta = try entry("Hallo")
        try FileManager.default.removeItem(at: cache.root.appending(path: "\(noMeta).json"))
        let noAudio = try entry("Hallo", rate: 0.9)
        try FileManager.default.removeItem(at: cache.root.appending(path: "\(noAudio).mp3"))
        let report = scanner.scan()
        #expect(report.entries.count == 2)
        let result = StorageClassification(report: report, owners: [AudioOwner(normalizedText: "Hallo", voiceID: Self.fenna, isFavorite: false)])
        #expect(Set(result.keys(.unlinked)) == [noMeta, noAudio])
        #expect(cache.remove(keys: [noMeta, noAudio]) > 0)
        #expect(scanner.scan().entries.isEmpty)
    }

    // MARK: Clean-ups

    @Test func removeKeysReportsFreedBytesAndSkipsTheProtectedClip() throws {
        defer { cleanUp() }
        let a = try entry("Een", bytes: 1_000, srt: 100)
        let b = try entry("Twee", bytes: 500)
        let playing = try entry("Drie", bytes: 700)
        let jsonBytes = { (key: String) in StorageScanner.fileSize(cache.root.appending(path: "\(key).json")) }
        let expected = 1_000 + 100 + jsonBytes(a) + 500 + jsonBytes(b)
        let progress = LockedCounter()
        let freed = cache.remove(
            keys: [a, b, playing], protecting: [cache.root.appending(path: "\(playing).mp3")],
            progress: { done, total in progress.record(done, total) }
        )
        #expect(freed == expected)
        #expect(!exists(a) && !exists(b))
        #expect(exists(playing))
        #expect(progress.last?.0 == 3 && progress.last?.1 == 3)
    }

    @Test func removeEntriesLastUsedBefore() throws {
        defer { cleanUp() }
        let old = try entry("Oud", bytes: 300, lastUsed: date(1_000))
        let playing = try entry("Speelt", bytes: 300, lastUsed: date(1_000))
        let recent = try entry("Nieuw", bytes: 300, lastUsed: date(5_000))
        let oldJSON = StorageScanner.fileSize(cache.root.appending(path: "\(old).json"))
        let freed = cache.removeEntries(lastUsedBefore: date(2_000), protecting: [cache.root.appending(path: "\(playing).mp3")])
        #expect(freed == 300 + oldJSON)
        #expect(!exists(old))
        #expect(exists(playing) && exists(recent))
    }

    @Test func trimRemovesLeastRecentlyUsedFirstAndFavoritesLast() throws {
        defer { cleanUp() }
        let favorite = try entry("Ster", bytes: 1_000, lastUsed: date(100))
        let oldest = try entry("Een", bytes: 1_000, lastUsed: date(200))
        let playing = try entry("Speelt", bytes: 1_000, lastUsed: date(250))
        let middle = try entry("Twee", bytes: 1_000, lastUsed: date(300))
        let newest = try entry("Drie", bytes: 1_000, lastUsed: date(400))
        let total = scanner.scan().cacheBytes
        let perEntry = total / 5

        // Room for three entries: the oldest non-favorite goes, the playing one is skipped, then the next one.
        let freed = cache.trim(
            toBytes: perEntry * 3 + 10, favoriteKeys: [favorite], protecting: [cache.root.appending(path: "\(playing).mp3")]
        )
        #expect(!exists(oldest) && !exists(middle))
        #expect(exists(favorite) && exists(playing) && exists(newest))
        #expect(freed == total - scanner.scan().cacheBytes)

        // Below what non-favorites can free: the favorite goes too.
        cache.trim(toBytes: 0, favoriteKeys: [favorite])
        #expect(!exists(favorite) && !exists(newest) && !exists(playing))
        #expect(cache.trim(toBytes: 0) == 0)
    }

    @Test func trimUnderTheLimitDoesNothing() throws {
        defer { cleanUp() }
        let key = try entry("Een", bytes: 1_000)
        #expect(cache.trim(toBytes: 1_000_000) == 0)
        #expect(exists(key))
    }

    @Test func temporaryCleanUpOnlyTouchesSpreekWorkFolders() throws {
        defer { cleanUp() }
        let fm = FileManager.default
        let edge = tmp.appending(path: "Spreek-Edge")
        let system = tmp.appending(path: "Spreek-System")
        let leftover = tmp.appending(path: "Spreek-\(UUID().uuidString)")
        for folder in [edge, system, leftover] { try fm.createDirectory(at: folder, withIntermediateDirectories: true) }
        try Data(repeating: 0, count: 40).write(to: edge.appending(path: "a.mp3"))
        try fm.createDirectory(at: edge.appending(path: "job"), withIntermediateDirectories: true)
        try Data(repeating: 0, count: 60).write(to: edge.appending(path: "job/b.mp3"))
        try Data(repeating: 0, count: 20).write(to: system.appending(path: "c.caf"))
        try Data(repeating: 0, count: 20).write(to: system.appending(path: "playing.caf"))
        try Data(repeating: 0, count: 80).write(to: leftover.appending(path: "keep.mp3"))
        let entryKey = try entry("Hallo")

        let freed = scanner.removeTemporaryFiles(protecting: [system.appending(path: "playing.caf")])
        #expect(freed == 120)
        #expect(try fm.contentsOfDirectory(atPath: edge.path).isEmpty)
        #expect(try fm.contentsOfDirectory(atPath: system.path) == ["playing.caf"])
        #expect(fm.fileExists(atPath: leftover.appending(path: "keep.mp3").path))
        #expect(exists(entryKey))
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: system.appending(path: "playing.caf").path)
        #expect(scanner.removeTemporaryFiles(modifiedBefore: Date().addingTimeInterval(-30)) == 0, "in progress")
        #expect(scanner.removeTemporaryFiles() == 20)
    }

    @Test func clearFreesEverything() throws {
        defer { cleanUp() }
        try entry("Een", bytes: 1_000)
        try entry("Twee", bytes: 1_000, srt: 10)
        #expect(scanner.scan().cacheBytes > 2_000)
        try cache.clear()
        #expect(scanner.scan().cacheBytes == 0)
    }
}

final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _last: (Int, Int)?

    func record(_ done: Int, _ total: Int) { lock.withLock { _last = (done, total) } }
    var last: (Int, Int)? { lock.withLock { _last } }
}
