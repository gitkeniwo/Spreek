import Foundation

/// Identifies a speech engine.
public enum ProviderID: String, Codable, Sendable, Hashable {
    case edge
    case system

    public var displayName: String {
        switch self {
        case .edge: "Edge"
        case .system: "System"
        }
    }
}

public struct Voice: Codable, Sendable, Hashable, Identifiable {
    public enum Quality: String, Codable, Sendable, Hashable, Comparable {
        case standard, enhanced, premium, neural

        private var rank: Int {
            switch self {
            case .standard: 0
            case .enhanced: 1
            case .premium: 2
            case .neural: 3
            }
        }

        public static func < (lhs: Quality, rhs: Quality) -> Bool { lhs.rank < rhs.rank }
    }

    /// Provider-specific identifier (`nl-NL-FennaNeural`, `com.apple.voice.premium.nl-NL.Xander`).
    public let id: String
    /// Short human name ("Fenna").
    public let name: String
    /// Locale such as `nl-NL`.
    public let locale: String
    public let gender: String?
    public let quality: Quality
    public let provider: ProviderID

    public init(id: String, name: String, locale: String, gender: String?, quality: Quality, provider: ProviderID) {
        self.id = id
        self.name = name
        self.locale = locale
        self.gender = gender
        self.quality = quality
        self.provider = provider
    }

    /// The Spreek language this voice speaks, if supported.
    public var language: LanguageCode? {
        LanguageCode(locale: locale)
    }
}

/// Which boundary marks the Edge service is asked for. Word marks give word-by-word highlighting;
/// sentence marks are what the edge-tts CLI uses, and some voices only work with them.
public enum BoundaryMode: String, Codable, Sendable, Hashable {
    case word, sentence
}

public struct SpeechRequest: Sendable, Hashable {
    public let text: String
    public let language: LanguageCode
    /// Preferred voice. A provider that doesn't recognize it uses its default for `language`.
    public let voiceID: String?
    /// Speed multiplier, 1.0 = normal.
    public let rate: Double
    /// Marks the native Edge client asks for. `ProviderChain` sets it per step; other providers ignore it.
    public var boundaryMode: BoundaryMode
    /// The voice to read with when `voiceID` fails (Settings › Backup); `nil` = Auto.
    public var backupVoiceID: String?

    public init(
        text: String, language: LanguageCode, voiceID: String? = nil, rate: Double = 1.0,
        boundaryMode: BoundaryMode = .word, backupVoiceID: String? = nil
    ) {
        self.text = text
        self.language = language
        self.voiceID = voiceID
        self.rate = rate
        self.boundaryMode = boundaryMode
        self.backupVoiceID = backupVoiceID
    }
}

/// A text range stored as UTF-16 offsets so it is `Codable` and survives caching.
public struct TextRange: Codable, Sendable, Hashable {
    public let location: Int
    public let length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    public init(_ range: Range<String.Index>, in text: String) {
        let ns = NSRange(range, in: text)
        self.init(location: ns.location, length: ns.length)
    }

    public init(_ ns: NSRange) {
        self.init(location: ns.location, length: ns.length)
    }

    public var nsRange: NSRange { NSRange(location: location, length: length) }

    public func range(in text: String) -> Range<String.Index>? {
        Range(nsRange, in: text)
    }
}

/// Maps a stretch of audio time onto the text spoken during it.
public struct BoundaryMark: Codable, Sendable, Hashable {
    public enum Granularity: String, Codable, Sendable, Hashable {
        case sentence, word
    }

    public let start: TimeInterval
    public let end: TimeInterval
    public let range: TextRange
    public let granularity: Granularity

    public init(start: TimeInterval, end: TimeInterval, range: TextRange, granularity: Granularity) {
        self.start = start
        self.end = end
        self.range = range
        self.granularity = granularity
    }

    /// The mark being spoken at `time`: the last one that has started (marks may overlap or leave gaps).
    public static func active(in marks: [BoundaryMark], at time: TimeInterval) -> BoundaryMark? {
        marks.last { $0.start <= time }
    }
}

/// Why the voice that spoke is not the one that was asked for, or why it reads differently.
public struct FallbackInfo: Sendable, Hashable {
    public enum Reason: String, Codable, Sendable, Hashable {
        /// The chosen voice speaks, but only with sentence marks (no word highlighting).
        case wordMarksUnavailable
        /// The chosen voice doesn't work; its backup voice speaks.
        case voiceUnavailable
        /// Edge doesn't work at all; a macOS voice speaks.
        case edgeUnavailable
    }

    /// The voice that was asked for.
    public let requestedVoiceID: String
    public let reason: Reason

    public init(requestedVoiceID: String, reason: Reason) {
        self.requestedVoiceID = requestedVoiceID
        self.reason = reason
    }
}

public struct SynthesisResult: Sendable, Hashable {
    /// Audio file (mp3 for Edge, caf for System). Owned by the caller after return.
    public let audioURL: URL
    public let marks: [BoundaryMark]
    public let provider: ProviderID
    /// The voice that actually spoke.
    public let voiceID: String
    /// Raw `.srt` subtitles, when the provider produced them.
    public let subtitlesURL: URL?
    /// Set by `ProviderChain` when the request was not served as asked.
    public var fallback: FallbackInfo?

    public init(
        audioURL: URL, marks: [BoundaryMark], provider: ProviderID, voiceID: String,
        subtitlesURL: URL? = nil, fallback: FallbackInfo? = nil
    ) {
        self.audioURL = audioURL
        self.marks = marks
        self.provider = provider
        self.voiceID = voiceID
        self.subtitlesURL = subtitlesURL
        self.fallback = fallback
    }
}

public protocol TTSProvider: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }
    func voices(for language: LanguageCode) async throws -> [Voice]
    func synthesize(_ request: SpeechRequest) async throws -> SynthesisResult
    /// Whether `voiceID` names one of this provider's voices.
    func supports(voiceID: String) -> Bool
}

extension TTSProvider {
    public func supports(voiceID: String) -> Bool { true }
}

public enum TTSError: Error, Sendable, Equatable, LocalizedError {
    case executableNotFound
    case timedOut(seconds: Double)
    case processFailed(status: Int32, message: String)
    case noAudioProduced
    case noVoice(LanguageCode)
    case emptyText

    public var errorDescription: String? {
        switch self {
        case .executableNotFound: "edge-tts not found. Install it with `uv tool install edge-tts`."
        case .timedOut(let seconds): "Speech synthesis timed out after \(Int(seconds)) s."
        case .processFailed(let status, let message): "edge-tts exited with status \(status): \(message)"
        case .noAudioProduced: "The speech engine produced no audio."
        case .noVoice(let language): "No voice available for \(language.info.englishName)."
        case .emptyText: "Nothing to speak."
        }
    }
}
