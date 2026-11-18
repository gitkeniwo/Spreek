import Foundation
import Testing
@testable import SpreekCore

@Suite struct AudioCacheTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "SpreekCacheTests-\(UUID().uuidString)")

    @Test func keyIsStableHex() {
        let key = AudioCache.key(text: "Goedemorgen.", voiceID: "nl-NL-FennaNeural", rate: 0.85)
        #expect(key == AudioCache.key(text: "Goedemorgen.", voiceID: "nl-NL-FennaNeural", rate: 0.85))
        #expect(key.count == 64)
        #expect(key.allSatisfy { $0.isHexDigit })
    }

    @Test func keyIgnoresWhitespaceDifferences() {
        let a = AudioCache.key(text: "  Hoe gaat\n het?  ", voiceID: "v", rate: 1)
        let b = AudioCache.key(text: "Hoe gaat het?", voiceID: "v", rate: 1)
        #expect(a == b)
    }

    @Test func keyRoundsRate() {
        #expect(AudioCache.key(text: "a", voiceID: "v", rate: 0.85) == AudioCache.key(text: "a", voiceID: "v", rate: 0.8500001))
    }

    @Test func keyDistinguishesInputs() {
        let base = AudioCache.key(text: "Hallo", voiceID: "nl-NL-FennaNeural", rate: 1)
        let variants = [
            AudioCache.key(text: "Hallo!", voiceID: "nl-NL-FennaNeural", rate: 1),
            AudioCache.key(text: "Hallo", voiceID: "nl-NL-ColetteNeural", rate: 1),
            AudioCache.key(text: "Hallo", voiceID: "nl-NL-FennaNeural", rate: 0.85),
            // The separator must keep text/voice boundaries apart.
            AudioCache.key(text: "Hallo|nl-NL-FennaNeural", voiceID: "", rate: 1),
        ]
        #expect(Set(variants + [base]).count == variants.count + 1)
    }

    @Test func removeDeletesEveryRateForTextAndVoice() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = AudioCache(root: root)
        func store(_ text: String, rate: Double) throws {
            let audio = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mp3")
            try Data(repeating: 7, count: 10).write(to: audio)
            try cache.store(SynthesisResult(audioURL: audio, marks: [], provider: .edge, voiceID: "v"), text: text, rate: rate)
        }
        try store("Hallo", rate: 1)
        try store("Hallo", rate: 0.85)
        try store("Dag", rate: 1)

        cache.remove(text: "Hallo", voiceID: "v")
        #expect(cache.lookup(text: "Hallo", voiceID: "v", rate: 1) == nil)
        #expect(cache.lookup(text: "Hallo", voiceID: "v", rate: 0.85) == nil)
        #expect(cache.lookup(text: "Dag", voiceID: "v", rate: 1) != nil)
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(files.count == 2, "only Dag's audio + metadata remain")
    }

    @Test func latestEntryFindsAnyRate() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = AudioCache(root: root)
        #expect(cache.latestEntry(text: "Hallo", voiceID: "v") == nil)
        func store(rate: Double, modified: Date) throws -> CachedAudio {
            let audio = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mp3")
            try Data(repeating: 7, count: 24).write(to: audio)
            let entry = try cache.store(SynthesisResult(audioURL: audio, marks: [], provider: .edge, voiceID: "v"), text: "Hallo", rate: rate)
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: entry.audioURL.path)
            return entry
        }
        _ = try store(rate: 1, modified: Date(timeIntervalSince1970: 1_000))
        let newer = try store(rate: 0.85, modified: Date(timeIntervalSince1970: 2_000))
        #expect(cache.latestEntry(text: "Hallo", voiceID: "v")?.key == newer.key)
        #expect(cache.latestEntry(text: "Hallo", voiceID: "other") == nil)
        #expect(AudioCache.fileSize(newer.audioURL) == 24)
    }

    @Test func storeLookupSizeClear() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = AudioCache(root: root)
        #expect(cache.lookup(text: "Hallo", voiceID: "v", rate: 1) == nil)
        #expect(cache.size() == 0)

        let audio = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mp3")
        try Data(repeating: 7, count: 1000).write(to: audio)
        let marks = [BoundaryMark(start: 0, end: 1, range: TextRange(location: 0, length: 5), granularity: .sentence)]
        let stored = try cache.store(
            SynthesisResult(audioURL: audio, marks: marks, provider: .edge, voiceID: "v"), text: "Hallo", rate: 1
        )
        #expect(!FileManager.default.fileExists(atPath: audio.path), "source is moved into the cache")
        #expect(stored.audioURL.pathExtension == "mp3")

        let hit = try #require(cache.lookup(text: " Hallo ", voiceID: "v", rate: 1))
        #expect(hit.marks == marks)
        #expect(hit.provider == .edge)
        #expect(hit.audioURL == stored.audioURL)
        #expect(cache.lookup(key: stored.key) != nil)
        #expect(cache.size() >= 1000)

        try cache.clear()
        #expect(cache.size() == 0)
        #expect(cache.lookup(text: "Hallo", voiceID: "v", rate: 1) == nil)
    }

    /// Settings › Clear Cache…: every entry goes, the folder and its neighbours (the Edge voice
    /// catalog next to it) stay, and the cache works again right after.
    @Test func clearCacheInATemporaryDirectory() throws {
        let parent = temporaryDirectory("ClearCache")
        defer { try? FileManager.default.removeItem(at: parent) }
        let cache = AudioCache(root: parent.appending(path: "Audio"))
        let catalog = parent.appending(path: "edge-voices.json")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: catalog)

        for (index, text) in ["Hallo", "Goedemorgen", "Tot ziens"].enumerated() {
            let audio = temporaryDirectory("ClearSource").appendingPathExtension("mp3")
            try Data(repeating: UInt8(index), count: 2048).write(to: audio)
            let srt = audio.deletingPathExtension().appendingPathExtension("srt")
            try Data("1\n00:00:00,000 --> 00:00:01,000\n\(text)\n".utf8).write(to: srt)
            try cache.store(SynthesisResult(audioURL: audio, marks: [], provider: .edge, voiceID: "v", subtitlesURL: srt), text: text, rate: 1)
        }
        #expect(cache.size() >= 3 * 2048)

        try cache.clear()
        #expect(cache.size() == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: cache.root.path).isEmpty)
        #expect(FileManager.default.fileExists(atPath: catalog.path))
        #expect(cache.lookup(text: "Hallo", voiceID: "v", rate: 1) == nil)

        let audio = temporaryDirectory("ClearSource").appendingPathExtension("mp3")
        try Data([1, 2, 3]).write(to: audio)
        try cache.store(SynthesisResult(audioURL: audio, marks: [], provider: .edge, voiceID: "v"), text: "Hallo", rate: 1)
        #expect(cache.lookup(text: "Hallo", voiceID: "v", rate: 1) != nil)
    }

    @Test func clearingAMissingCacheIsFine() throws {
        let cache = AudioCache(root: temporaryDirectory("NoCache"))
        try cache.clear()
        #expect(cache.size() == 0)
    }

    @Test func missingAudioIsAMiss() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = AudioCache(root: root)
        let audio = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).caf")
        try Data([1, 2, 3]).write(to: audio)
        let stored = try cache.store(SynthesisResult(audioURL: audio, marks: [], provider: .system, voiceID: "v"), text: "x", rate: 1)
        try FileManager.default.removeItem(at: stored.audioURL)
        #expect(cache.lookup(key: stored.key) == nil)
    }
}
