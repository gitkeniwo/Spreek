import Foundation

/// What Spreek keeps on disk, by kind (Settings › Storage usage bar).
public enum StorageCategory: String, CaseIterable, Sendable, Hashable {
    /// `Audio/<key>.<mp3|caf>`.
    case audio
    /// `Audio/<key>.srt` and `Audio/<key>.json`.
    case subtitlesAndMarks
    /// `Library.store` with its `-wal` and `-shm`.
    case library
    /// `edge-voices.json`.
    case voiceList
    /// Work files in `$TMPDIR/Spreek-Edge` and `$TMPDIR/Spreek-System`.
    case temporary

    public var title: String {
        switch self {
        case .audio: "Audio"
        case .subtitlesAndMarks: "Subtitles & marks"
        case .library: "Library"
        case .voiceList: "Voice list"
        case .temporary: "Temporary"
        }
    }
}

/// Bytes and file count of one category.
public struct StorageUsage: Sendable, Hashable {
    public var bytes: Int64 = 0
    /// Clips for audio, top-level items for temporary, files otherwise.
    public var count = 0

    public init(bytes: Int64 = 0, count: Int = 0) {
        self.bytes = bytes
        self.count = count
    }
}

/// One cached clip with its side files.
public struct CacheEntryInfo: Sendable, Hashable, Identifiable {
    public let key: String
    /// The audio file; `nil` when only side files are left.
    public let audioURL: URL?
    /// Audio file bytes.
    public let bytes: Int64
    /// Subtitles and metadata bytes.
    public let sideBytes: Int64
    /// `nil` when the metadata is missing or unreadable (the clip can't be played).
    public let provider: ProviderID?
    public let voiceID: String?
    /// Written since version 0.2; `nil` for older entries until classification recovers them.
    public let rate: Double?
    public let text: String?
    /// The audio file's modification date (`AudioCache.lookup` touches it).
    public let lastUsed: Date

    public var id: String { key }
    /// Everything removing the entry frees.
    public var totalBytes: Int64 { bytes + sideBytes }
    /// From the voice id (`nl-NL-FennaNeural` → Dutch).
    public var language: LanguageCode? { voiceID.flatMap(LanguageCode.forVoiceID) }

    public init(
        key: String, audioURL: URL?, bytes: Int64, sideBytes: Int64 = 0, provider: ProviderID?, voiceID: String?,
        rate: Double? = nil, text: String? = nil, lastUsed: Date
    ) {
        self.key = key
        self.audioURL = audioURL
        self.bytes = bytes
        self.sideBytes = sideBytes
        self.provider = provider
        self.voiceID = voiceID
        self.rate = rate
        self.text = text
        self.lastUsed = lastUsed
    }
}

/// A snapshot of Spreek's disk usage.
public struct StorageReport: Sendable {
    public var categories: [StorageCategory: StorageUsage]
    /// Most recently used first.
    public var entries: [CacheEntryInfo]
    /// Top-level items in the temporary folders.
    public var temporaryItems: [URL]

    public init(categories: [StorageCategory: StorageUsage] = [:], entries: [CacheEntryInfo] = [], temporaryItems: [URL] = []) {
        self.categories = categories
        self.entries = entries
        self.temporaryItems = temporaryItems
    }

    public func usage(_ category: StorageCategory) -> StorageUsage { categories[category] ?? StorageUsage() }

    public var totalBytes: Int64 { categories.values.reduce(0) { $0 + $1.bytes } }

    /// Audio plus side files of every clip.
    public var cacheBytes: Int64 { entries.reduce(0) { $0 + $1.totalBytes } }

    public func entries(lastUsedBefore cutoff: Date) -> [CacheEntryInfo] {
        entries.filter { $0.lastUsed < cutoff }
    }

    // MARK: Grouping

    /// Clips per language (from the voice id); clips without a known language are left out.
    public func byLanguage() -> [StorageGroup<LanguageCode>] {
        Self.group(entries) { $0.language }
    }

    /// Clips per voice id.
    public func byVoice() -> [StorageGroup<String>] {
        Self.group(entries) { $0.voiceID }
    }

    /// Clips per engine.
    public func byProvider() -> [StorageGroup<ProviderID>] {
        Self.group(entries) { $0.provider }
    }

    /// Largest first, ties by count.
    static func group<ID: Hashable>(_ entries: [CacheEntryInfo], by id: (CacheEntryInfo) -> ID?) -> [StorageGroup<ID>] {
        var groups: [ID: StorageGroup<ID>] = [:]
        for entry in entries {
            guard let key = id(entry) else { continue }
            groups[key, default: StorageGroup(id: key)].add(entry)
        }
        return groups.values.sorted { ($0.bytes, $0.keys.count) > ($1.bytes, $1.keys.count) }
    }
}

/// Clips that share a language, voice or engine.
public struct StorageGroup<ID: Hashable & Sendable>: Sendable, Identifiable {
    public let id: ID
    public private(set) var keys: [String] = []
    /// Audio plus side files.
    public private(set) var bytes: Int64 = 0
    public private(set) var voiceIDs: Set<String> = []

    public var count: Int { keys.count }

    init(id: ID) {
        self.id = id
    }

    mutating func add(_ entry: CacheEntryInfo) {
        keys.append(entry.key)
        bytes += entry.totalBytes
        if let voiceID = entry.voiceID { voiceIDs.insert(voiceID) }
    }
}

/// Measures Spreek's files. Plain file system reads: run it off the main actor.
public struct StorageScanner: Sendable {
    /// `~/Library/Application Support/Spreek`.
    public static var defaultRoot: URL { AudioCache.defaultRoot.deletingLastPathComponent() }

    public let root: URL
    /// Holds `Spreek-Edge` and `Spreek-System`.
    public let temporaryRoot: URL

    public init(root: URL = StorageScanner.defaultRoot, temporaryRoot: URL = FileManager.default.temporaryDirectory) {
        self.root = root
        self.temporaryRoot = temporaryRoot
    }

    public var cache: AudioCache { AudioCache(root: root.appending(path: "Audio")) }

    /// The providers' work folders. Other `Spreek-*` folders (test runs) aren't Spreek's.
    public var temporaryFolders: [URL] {
        ["Spreek-Edge", "Spreek-System"].map { temporaryRoot.appending(path: $0) }
    }

    public func scan() -> StorageReport {
        var report = StorageReport()
        let entries = scanCache(into: &report)
        report.entries = entries.sorted { $0.lastUsed > $1.lastUsed }

        var library = StorageUsage()
        for name in ["Library.store", "Library.store-wal", "Library.store-shm"] {
            let url = root.appending(path: name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            library.bytes += Self.fileSize(url)
            library.count += 1
        }
        report.categories[.library] = library

        let voiceList = root.appending(path: "edge-voices.json")
        report.categories[.voiceList] = FileManager.default.fileExists(atPath: voiceList.path)
            ? StorageUsage(bytes: Self.fileSize(voiceList), count: 1) : StorageUsage()

        var temporary = StorageUsage()
        for folder in temporaryFolders {
            for item in Self.contents(of: folder) {
                temporary.bytes += Self.allocatedSize(item)
                temporary.count += 1
                report.temporaryItems.append(item)
            }
        }
        report.categories[.temporary] = temporary
        return report
    }

    private func scanCache(into report: inout StorageReport) -> [CacheEntryInfo] {
        let entries = scanEntries(cache: cache)
        report.categories[.audio] = StorageUsage(
            bytes: entries.reduce(0) { $0 + $1.bytes }, count: entries.count { $0.audioURL != nil }
        )
        report.categories[.subtitlesAndMarks] = StorageUsage(
            bytes: entries.reduce(0) { $0 + $1.sideBytes }, count: entries.count { $0.sideBytes > 0 }
        )
        return entries
    }

    /// One entry per key in the cache folder, in no particular order.
    func scanEntries(cache: AudioCache) -> [CacheEntryInfo] {
        cache.entryFiles().map { key, urls in
            let meta = cache.metadata(key: key)
            var audioURL: URL?
            var bytes: Int64 = 0
            var sideBytes: Int64 = 0
            for url in urls {
                let size = Self.fileSize(url)
                if url.pathExtension == "json" || url.pathExtension == "srt" {
                    sideBytes += size
                } else {
                    // The metadata names the audio file; without metadata any other file is it.
                    if meta == nil || meta?.audioFile == url.lastPathComponent { audioURL = url }
                    bytes += size
                }
            }
            return CacheEntryInfo(
                key: key, audioURL: audioURL, bytes: bytes, sideBytes: sideBytes, provider: meta?.provider,
                voiceID: meta?.voiceID, rate: meta?.rate, text: meta?.text, lastUsed: (audioURL ?? urls[0]).modificationDate
            )
        }
    }

    /// Deletes what is inside the temporary folders (not the folders themselves) and returns the
    /// bytes freed. Items in `protecting`, and items modified at or after `modifiedBefore` (a
    /// synthesis in progress), stay.
    @discardableResult
    public func removeTemporaryFiles(protecting: Set<URL> = [], modifiedBefore: Date = .distantFuture) -> Int64 {
        let protected = Set(protecting.map(\.standardizedPath))
        var freed: Int64 = 0
        for folder in temporaryFolders {
            for item in Self.contents(of: folder)
            where !protected.contains(item.standardizedPath) && item.modificationDate < modifiedBefore {
                let size = Self.allocatedSize(item)
                if (try? FileManager.default.removeItem(at: item)) != nil { freed += size }
            }
        }
        return freed
    }

    // MARK: File helpers

    static func contents(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]
        )) ?? []
    }

    static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    /// A file's size, or a folder's total.
    static func allocatedSize(_ url: URL) -> Int64 {
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return fileSize(url) }
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
        var total: Int64 = 0
        while let item = enumerator?.nextObject() as? URL { total += fileSize(item) }
        return total
    }
}

extension URL {
    var modificationDate: Date {
        (try? resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    /// For comparing URLs that may differ in `/private` prefixes or `..`.
    var standardizedPath: String { resolvingSymlinksInPath().standardizedFileURL.path }
}

extension LanguageCode {
    /// The language a voice speaks, from the `xx-YY` locale in its id: Edge short names start
    /// with it (`nl-NL-FennaNeural`), macOS ids contain it (`com.apple.voice.premium.fr-FR.Amelie`).
    /// An exact registry match wins, else the first language with the same language subtag.
    public static func forVoiceID(_ voiceID: String) -> LanguageCode? {
        let parts = voiceID.split(separator: "-")
        var locale: String?
        if parts.count >= 3 {
            locale = "\(parts[0])-\(parts[1])"
        } else {
            locale = voiceID.split(separator: ".").first { $0.contains("-") && $0.count <= 7 }.map(String.init)
        }
        if locale == nil, let systemLanguage = SystemProvider.installedVoice(identifier: voiceID)?.language {
            locale = systemLanguage
        }
        guard let locale else { return nil }
        let lowered = locale.lowercased()
        if let exact = LanguageRegistry.all.first(where: { $0.bcp47.lowercased() == lowered }) { return exact.code }
        let subtag = lowered.split(separator: "-").first.map(String.init)
        return LanguageRegistry.all.first { $0.bcp47.lowercased().split(separator: "-").first.map(String.init) == subtag }?.code
    }
}
