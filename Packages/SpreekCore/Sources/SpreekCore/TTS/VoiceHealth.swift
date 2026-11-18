import Foundation

/// What Spreek remembers about Edge voices that misbehave, so it doesn't wait on them every time.
/// Persisted as `voice-health.json` next to `edge-voices.json`.
///
/// A failing step is skipped until its `retryAfter`; after that the next real request tries it
/// again (no background polling). The wait starts at 3 hours and doubles with every failed retry
/// up to 24 hours. A success clears the entry.
public final class VoiceHealth: @unchecked Sendable {
    /// The part of the chain that failed.
    public enum Step: String, Codable, Sendable, Hashable {
        /// Native client with word marks. The voice still speaks, with sentence marks.
        case wordMarks
        /// Native client in either mode; the edge-tts CLI may still work.
        case nativeVoice
        /// Every Edge route for the voice: its backup voice reads instead.
        case voice
        /// The whole native client (any voice): the CLI and the macOS voice remain.
        case service
    }

    public struct Entry: Codable, Sendable, Hashable {
        public var failingSince: Date
        public var retryAfter: Date
        /// Failed attempts in a row; sets the wait.
        public var failures: Int
    }

    /// Voice id used for the service-wide entry.
    public static let serviceKey = "*"
    public static let firstRetryDelay: TimeInterval = 3 * 3600
    public static let maxRetryDelay: TimeInterval = 24 * 3600

    public static var defaultURL: URL {
        AudioCache.defaultRoot.deletingLastPathComponent().appending(path: "voice-health.json")
    }

    /// Wait after the `failures`-th failure in a row: 3 h, 6 h, 12 h, 24 h, 24 h, …
    public static func delay(afterFailures failures: Int) -> TimeInterval {
        let doublings = max(failures - 1, 0)
        return min(firstRetryDelay * pow(2, Double(min(doublings, 10))), maxRetryDelay)
    }

    private struct Key: Hashable { let voiceID: String; let step: Step }

    private let url: URL?
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var entries: [Key: Entry] = [:]
    /// Called (on whichever thread changed it) after every change.
    public var onChange: (@Sendable () -> Void)? {
        get { lock.withLock { changeHandler } }
        set { lock.withLock { changeHandler = newValue } }
    }
    private var changeHandler: (@Sendable () -> Void)?

    /// `url == nil` keeps everything in memory (tests, previews).
    public init(url: URL? = VoiceHealth.defaultURL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.url = url
        self.now = now
        entries = Self.load(url)
    }

    // MARK: Queries

    /// A failure is on record, whether or not it is time to try again.
    public func isFailing(_ voiceID: String, _ step: Step) -> Bool {
        lock.withLock { entries[Key(voiceID: voiceID, step: step)] != nil }
    }

    /// A failure is on record and `retryAfter` is still ahead: skip the step.
    public func isBlocked(_ voiceID: String, _ step: Step) -> Bool {
        lock.withLock { entries[Key(voiceID: voiceID, step: step)].map { $0.retryAfter > now() } ?? false }
    }

    public func entry(_ voiceID: String, _ step: Step) -> Entry? {
        lock.withLock { entries[Key(voiceID: voiceID, step: step)] }
    }

    /// Voices with a failure on record for `step`.
    public func failingVoices(_ step: Step) -> Set<String> {
        lock.withLock { Set(entries.keys.filter { $0.step == step }.map(\.voiceID)) }
    }

    public var isServiceFailing: Bool { isFailing(Self.serviceKey, .service) }

    // MARK: Updates

    /// Notes a failed attempt. The first failure starts the clock; a failed retry (its time had
    /// come) doubles the wait; a repeat while the step is still blocked changes nothing.
    public func recordFailure(_ voiceID: String, _ step: Step) {
        let changed: Bool = lock.withLock {
            let key = Key(voiceID: voiceID, step: step)
            let date = now()
            if var existing = entries[key] {
                guard existing.retryAfter <= date else { return false }
                existing.failures += 1
                existing.retryAfter = date.addingTimeInterval(Self.delay(afterFailures: existing.failures))
                entries[key] = existing
            } else {
                entries[key] = Entry(
                    failingSince: date, retryAfter: date.addingTimeInterval(Self.delay(afterFailures: 1)), failures: 1
                )
            }
            save()
            return true
        }
        if changed { notify() }
    }

    /// A success clears the entry.
    public func recordSuccess(_ voiceID: String, _ step: Step) {
        let changed: Bool = lock.withLock {
            guard entries.removeValue(forKey: Key(voiceID: voiceID, step: step)) != nil else { return false }
            save()
            return true
        }
        if changed { notify() }
    }

    /// Forgets everything about `voiceID` (all steps).
    public func clear(voiceID: String) {
        let changed: Bool = lock.withLock {
            let before = entries.count
            entries = entries.filter { $0.key.voiceID != voiceID }
            guard entries.count != before else { return false }
            save()
            return true
        }
        if changed { notify() }
    }

    // MARK: Persistence

    private struct Stored: Codable {
        struct Item: Codable {
            let voiceID: String
            let step: Step
            let entry: Entry
        }
        var items: [Item]
    }

    private static func load(_ url: URL?) -> [Key: Entry] {
        guard let url, let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let stored = try? decoder.decode(Stored.self, from: data) else { return [:] }
        return Dictionary(stored.items.map { (Key(voiceID: $0.voiceID, step: $0.step), $0.entry) }) { first, _ in first }
    }

    /// Caller holds the lock.
    private func save() {
        guard let url else { return }
        let items = entries
            .map { Stored.Item(voiceID: $0.key.voiceID, step: $0.key.step, entry: $0.value) }
            .sorted { ($0.voiceID, $0.step.rawValue) < ($1.voiceID, $1.step.rawValue) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(Stored(items: items)).write(to: url, options: .atomic)
    }

    private func notify() {
        let handler = lock.withLock { changeHandler }
        handler?()
    }
}
