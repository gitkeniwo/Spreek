import Foundation

/// Edge voice list, from the service's voice list (native) or `edge-tts --list-voices` (CLI),
/// cached on disk. Both paths share one cache file.
public struct EdgeVoiceCatalog: Sendable {
    /// How long a stored list is used before the next request fetches a new one.
    public static let maxAge: TimeInterval = 24 * 3600

    public var cacheURL: URL
    public var now: @Sendable () -> Date

    public init(
        cacheURL: URL = AudioCache.defaultRoot.deletingLastPathComponent().appending(path: "edge-voices.json"),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.cacheURL = cacheURL
        self.now = now
    }

    private struct Stored: Codable {
        let fetchedAt: Date
        let voices: [Voice]
        /// Genders of every voice seen so far, so a voice Microsoft retires keeps its gender
        /// (needed to pick a backup of the same gender).
        var genders: [String: String]?
    }

    /// The stored list as it is on disk (whatever its age).
    public struct Snapshot: Sendable, Hashable {
        public let voices: [Voice]
        public let fetchedAt: Date
        public let genders: [String: String]
        public var count: Int { voices.count }

        /// A voice the service no longer lists, although it lists others for the same language.
        /// Only meaningful for lists that came from the service (every stored list did).
        public func isRetired(_ voiceID: String) -> Bool {
            guard EdgeCLIProvider.isEdgeVoiceID(voiceID), !voices.isEmpty, !voices.contains(where: { $0.id == voiceID })
            else { return false }
            let locale = voiceID.split(separator: "-").prefix(2).joined(separator: "-")
            guard let language = LanguageCode(locale: locale) else { return false }
            return voices.contains { $0.language == language }
        }
    }

    /// The stored list, if there is a readable one.
    public func snapshot() -> Snapshot? {
        guard let stored = try? JSONDecoder().decode(Stored.self, from: Data(contentsOf: cacheURL)) else { return nil }
        return Snapshot(voices: stored.voices, fetchedAt: stored.fetchedAt, genders: stored.genders ?? [:])
    }

    /// Whether the stored list is missing or at least `minimumAge` seconds old.
    public func needsRefresh(minimumAge: TimeInterval = EdgeVoiceCatalog.maxAge) -> Bool {
        guard let snapshot = snapshot() else { return true }
        return now().timeIntervalSince(snapshot.fetchedAt) >= minimumAge
    }

    /// Cached voices if younger than a day, otherwise `fetch()`'s CLI listing, parsed and stored.
    public func voices(fetch: @Sendable () async throws -> String) async throws -> [Voice] {
        try await cachedVoices { Self.parse(try await fetch()) }
    }

    /// Cached voices if younger than a day, otherwise `fetchVoices()`'s, stored.
    /// If fetching fails, a stale cache is still better than nothing.
    public func cachedVoices(_ fetchVoices: @Sendable () async throws -> [Voice]) async throws -> [Voice] {
        let cached = snapshot()
        if let cached, now().timeIntervalSince(cached.fetchedAt) < Self.maxAge {
            return cached.voices
        }
        do {
            return try await refresh(fetchVoices)
        } catch {
            if let cached { return cached.voices }
            throw error
        }
    }

    /// Fetches and stores a new list whatever the stored one's age (Settings › Refresh voice list).
    /// An empty list counts as a failure and leaves the stored one alone.
    @discardableResult
    public func refresh(_ fetchVoices: @Sendable () async throws -> [Voice]) async throws -> [Voice] {
        let voices = try await fetchVoices()
        guard !voices.isEmpty else { throw TTSError.noVoice(.nl) }
        var genders = snapshot()?.genders ?? [:]
        for voice in voices { if let gender = voice.gender { genders[voice.id] = gender } }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(Stored(fetchedAt: now(), voices: voices, genders: genders)).write(to: cacheURL, options: .atomic)
        return voices
    }

    /// Parses the table printed by edge-tts 7.x:
    /// ```
    /// Name                Gender    ContentCategories   VoicePersonalities
    /// ------------------  --------  ------------------  ------------------
    /// nl-NL-FennaNeural   Female    General             Friendly, Positive
    /// ```
    public static func parse(_ listing: String) -> [Voice] {
        listing.split(whereSeparator: \.isNewline).compactMap { line in
            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            guard columns.count >= 2 else { return nil }
            let id = String(columns[0])
            guard EdgeCLIProvider.isEdgeVoiceID(id) else { return nil }
            let parts = id.split(separator: "-")
            let locale = parts.prefix(2).joined(separator: "-")
            return Voice(
                id: id, name: displayName(for: id), locale: locale,
                gender: String(columns[1]), quality: .neural, provider: .edge
            )
        }
    }

    /// Edge voices for `language` from the service's voice list and/or `edge-tts --list-voices`,
    /// in the order `mode` uses them (same cache either way).
    public static func liveVoices(
        for language: LanguageCode, mode: EdgeEngineMode = .automatic, edgeExecutablePath: String?
    ) async throws -> [Voice] {
        let cli = EdgeCLIProvider(resolver: EdgeExecutableResolver(configuredPath: edgeExecutablePath))
        switch mode {
        case .nativeOnly: return try await EdgeNativeProvider().voices(for: language)
        case .cliOnly: return try await cli.voices(for: language)
        case .automatic:
            do {
                return try await EdgeNativeProvider().voices(for: language)
            } catch {
                return try await cli.voices(for: language)
            }
        }
    }

    /// Fetches a new list through the engine `mode` allows (service first in Automatic) and stores it.
    @discardableResult
    public static func refreshLive(
        mode: EdgeEngineMode = .automatic, edgeExecutablePath: String?, native: EdgeNativeProvider = EdgeNativeProvider()
    ) async throws -> [Voice] {
        let cli = EdgeCLIProvider(resolver: EdgeExecutableResolver(configuredPath: edgeExecutablePath), catalog: native.catalog)
        switch mode {
        case .nativeOnly: return try await native.refreshVoices()
        case .cliOnly: return try await cli.refreshVoices()
        case .automatic:
            do {
                return try await native.refreshVoices()
            } catch {
                return try await cli.refreshVoices()
            }
        }
    }

    /// Parses the service's voice list JSON (`[{"ShortName": "nl-NL-FennaNeural", "Gender":
    /// "Female", "Locale": "nl-NL", …}]`). Unreadable input gives no voices.
    public static func parseJSON(_ data: Data) -> [Voice] {
        struct Entry: Decodable {
            let ShortName: String
            let Gender: String?
            let Locale: String?
        }
        guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries.compactMap { entry in
            guard EdgeCLIProvider.isEdgeVoiceID(entry.ShortName) else { return nil }
            let locale = entry.Locale ?? entry.ShortName.split(separator: "-").prefix(2).joined(separator: "-")
            return Voice(
                id: entry.ShortName, name: displayName(for: entry.ShortName), locale: locale,
                gender: entry.Gender, quality: .neural, provider: .edge
            )
        }
    }

    /// `nl-NL-FennaNeural` → `Fenna`; `de-DE-FlorianMultilingualNeural` → `Florian`.
    public static func displayName(for id: String) -> String {
        var name = id.split(separator: "-").dropFirst(2).joined(separator: "-")
        for suffix in ["Neural", "Multilingual"] where name.hasSuffix(suffix) {
            name.removeLast(suffix.count)
        }
        return name
    }
}
