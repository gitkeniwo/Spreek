import CryptoKit
import Foundation

/// A cached synthesis: audio file plus boundary marks.
public struct CachedAudio: Sendable, Hashable {
    public let key: String
    public let audioURL: URL
    public let marks: [BoundaryMark]
    public let provider: ProviderID
    public let voiceID: String
}

/// Synthesized audio on disk, keyed by `sha256(normalizedText|voiceID|rate)`.
///
/// Layout per entry: `<key>.<mp3|caf>` (audio), `<key>.json` (marks, provider, voice and, since
/// version 0.2, text, rate and creation date), and `<key>.srt` when the provider produced subtitles.
/// The audio file's modification date is the entry's last use: `lookup` hits touch it.
public struct AudioCache: Sendable {
    public static var defaultRoot: URL {
        URL.applicationSupportDirectory.appending(path: "Spreek/Audio")
    }

    public let root: URL

    public init(root: URL = AudioCache.defaultRoot) {
        self.root = root
    }

    struct Metadata: Codable {
        let audioFile: String
        let marks: [BoundaryMark]
        let provider: ProviderID
        let voiceID: String
        /// Normalized text; `nil` in entries written before version 0.2.
        var text: String?
        var rate: Double?
        var createdAt: Date?
    }

    // MARK: Key

    /// Trimmed, with whitespace runs collapsed to one space.
    public static func normalize(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The text a sentence's clips are keyed by: what `SpeechController` speaks for `text`
    /// (`TextNormalizer`), whitespace-normalized.
    public static func spokenText(_ text: String) -> String {
        normalize(TextNormalizer.normalize(text) ?? text)
    }

    /// Rates the controller can produce, in key precision (0.50…2.00).
    static let keyRates: [Double] = (50...200).map { Double($0) / 100 }

    /// Rate formatted with two decimals so 0.85 and 0.8500001 share a key.
    public static func key(text: String, voiceID: String, rate: Double) -> String {
        let material = "\(normalize(text))|\(voiceID)|\(String(format: "%.2f", rate))"
        return SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Operations

    public func lookup(text: String, voiceID: String, rate: Double) -> CachedAudio? {
        lookup(key: Self.key(text: text, voiceID: voiceID, rate: rate))
    }

    /// A hit counts as a use: the audio file's modification date becomes now.
    public func lookup(key: String) -> CachedAudio? {
        guard let entry = entry(key: key) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: entry.audioURL.path)
        return entry
    }

    /// Like `lookup(key:)` without touching the last-used date.
    func entry(key: String) -> CachedAudio? {
        guard let meta = metadata(key: key) else { return nil }
        let audioURL = root.appending(path: meta.audioFile)
        guard FileManager.default.fileExists(atPath: audioURL.path) else { return nil }
        return CachedAudio(key: key, audioURL: audioURL, marks: meta.marks, provider: meta.provider, voiceID: meta.voiceID)
    }

    func metadata(key: String) -> Metadata? {
        guard let data = try? Data(contentsOf: root.appending(path: "\(key).json")) else { return nil }
        return try? JSONDecoder().decode(Metadata.self, from: data)
    }

    /// Moves the result's files into the cache under the key for (text, actual voice, rate).
    @discardableResult
    public func store(_ result: SynthesisResult, text: String, rate: Double) throws -> CachedAudio {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let key = Self.key(text: text, voiceID: result.voiceID, rate: rate)
        let ext = result.audioURL.pathExtension.isEmpty ? "audio" : result.audioURL.pathExtension
        let audioURL = root.appending(path: "\(key).\(ext)")
        try replace(audioURL, with: result.audioURL)
        if let srt = result.subtitlesURL {
            try? replace(root.appending(path: "\(key).srt"), with: srt)
        }
        let meta = Metadata(
            audioFile: audioURL.lastPathComponent, marks: result.marks, provider: result.provider, voiceID: result.voiceID,
            text: Self.normalize(text), rate: Double(String(format: "%.2f", rate)), createdAt: Date()
        )
        try JSONEncoder().encode(meta).write(to: root.appending(path: "\(key).json"), options: .atomic)
        return CachedAudio(key: key, audioURL: audioURL, marks: result.marks, provider: result.provider, voiceID: result.voiceID)
    }

    /// Total bytes on disk.
    public func size() -> Int64 {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]
        )) ?? []
        return urls.reduce(0) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    /// The most recently used entry for `text` spoken by `voiceID`, at any rate.
    public func latestEntry(text: String, voiceID: String) -> CachedAudio? {
        entries(text: text, voiceID: voiceID).first
    }

    /// Every entry for `text` spoken by `voiceID`, most recently used first (doesn't count as a use).
    public func entries(text: String, voiceID: String) -> [CachedAudio] {
        Self.keyRates
            .compactMap { entry(key: Self.key(text: text, voiceID: voiceID, rate: $0)) }
            .sorted { modificationDate($0.audioURL) > modificationDate($1.audioURL) }
    }

    /// Size of one cached audio file in bytes.
    public static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    /// Removes every entry for `text` spoken by `voiceID` at any rate the controller allows
    /// (keys use two decimals, so that's a finite set).
    public func remove(text: String, voiceID: String) {
        for rate in Self.keyRates {
            removeEntry(key: Self.key(text: text, voiceID: voiceID, rate: rate))
        }
    }

    /// Removes every clip of `text`, whatever the voice or rate: entries whose metadata names the
    /// text, plus (for entries written before version 0.2, which don't) a key scan over each voice
    /// those older entries use.
    public func remove(text: String) {
        remove(texts: [text])
    }

    /// `remove(text:)` for several texts with one pass over the metadata.
    public func remove(texts: some Sequence<String>) {
        let texts = Set(texts.map(Self.spokenText))
        guard !texts.isEmpty else { return }
        var oldVoices: Set<String> = []
        for (key, meta) in allMetadata() {
            if let entryText = meta.text {
                if texts.contains(entryText) { removeEntry(key: key) }
            } else {
                oldVoices.insert(meta.voiceID)
            }
        }
        for voiceID in oldVoices {
            for text in texts { remove(text: text, voiceID: voiceID) }
        }
    }

    /// Every decodable metadata file, by key.
    func allMetadata() -> [(key: String, meta: Metadata)] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }.compactMap { url in
            let key = url.deletingPathExtension().lastPathComponent
            return metadata(key: key).map { (key, $0) }
        }
    }

    /// Deletes one entry's audio, subtitles and metadata.
    private func removeEntry(key: String) {
        let fm = FileManager.default
        let metaURL = root.appending(path: "\(key).json")
        guard fm.fileExists(atPath: metaURL.path) else { return }
        if let meta = metadata(key: key) { try? fm.removeItem(at: root.appending(path: meta.audioFile)) }
        try? fm.removeItem(at: root.appending(path: "\(key).srt"))
        try? fm.removeItem(at: metaURL)
    }

    public func clear() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return }
        for url in try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            try fm.removeItem(at: url)
        }
    }

    private func replace(_ destination: URL, with source: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        do {
            try fm.moveItem(at: source, to: destination)
        } catch {
            try fm.copyItem(at: source, to: destination)
        }
    }
}
