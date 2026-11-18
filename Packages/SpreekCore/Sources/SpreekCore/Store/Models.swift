import Foundation
import SwiftData

// SwiftData models for the library.
//
// Languages are stored as `LanguageCode` raw values and colors as palette IDs
// (`FolderColor` / `TagColor` raw values in the app's design system) so that
// predicates can compare plain strings.

/// A spoken sentence. Speaking the same `normalizedText` in the same language again bumps
/// `playCount` instead of adding a row.
@Model
public final class Sentence {
    public var text: String
    /// Dedupe key: `LibraryStore.normalizedKey(for:)` of `text`.
    public var normalizedText: String
    /// Detected language (`LanguageCode` raw value). See `effectiveLanguage`.
    public var languageID: String
    public var createdAt: Date
    public var lastPlayedAt: Date
    public var playCount: Int
    public var isFavorite: Bool
    public var favoritedAt: Date?
    /// Restricted Markdown (`NoteFormat`); empty when there is no note.
    public var note: String
    public var sourceApp: String?
    public var sourceURL: String?
    /// Bundle id of `sourceApp` (for its icon); `nil` for rows recorded before 5b.
    public var sourceBundleID: String?
    /// Voice that last spoke it (after any fallback).
    public var voiceID: String?

    @Relationship(deleteRule: .nullify, inverse: \Folder.sentences)
    public var folder: Folder?
    @Relationship(deleteRule: .nullify, inverse: \Tag.sentences)
    public var tags: [Tag] = []
    @Relationship(deleteRule: .cascade, inverse: \PlayEvent.sentence)
    public var playEvents: [PlayEvent] = []

    public init(
        text: String,
        normalizedText: String,
        language: LanguageCode,
        createdAt: Date = .now,
        voiceID: String? = nil,
        sourceApp: String? = nil,
        sourceURL: String? = nil,
        sourceBundleID: String? = nil
    ) {
        self.text = text
        self.normalizedText = normalizedText
        self.languageID = language.rawValue
        self.createdAt = createdAt
        self.lastPlayedAt = createdAt
        self.playCount = 0
        self.isFavorite = false
        self.note = ""
        self.voiceID = voiceID
        self.sourceApp = sourceApp
        self.sourceURL = sourceURL
        self.sourceBundleID = sourceBundleID
    }

    /// The detected language.
    public var language: LanguageCode {
        get { LanguageCode(rawValue: languageID) ?? .nl }
        set { languageID = newValue.rawValue }
    }

    /// The folder's language when filed in a folder that has one, else the detected one. Replays use this.
    public var effectiveLanguage: LanguageCode {
        folder?.language ?? language
    }

    public var hasNote: Bool {
        !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// A user folder. With a `language`, sentences in it are read in that language; without one
/// they keep their detected language.
@Model
public final class Folder {
    public var name: String
    /// Folder palette ID (`orange`, `yellow`, `green`, `teal`, `blue`, `purple`, `pink`, `gray`).
    public var colorID: String
    /// SF Symbol name, e.g. `bubble.left.fill`.
    public var symbol: String
    /// Empty = no folder language.
    public var languageID: String
    /// Voice override; `nil` = the language's default voice.
    public var voiceID: String?
    /// Speed override; `nil` = the global speed.
    public var speed: Double?
    /// Restricted Markdown (`NoteFormat`).
    public var note: String
    public var createdAt: Date

    public var sentences: [Sentence] = []

    public init(name: String, colorID: String, symbol: String, language: LanguageCode?, createdAt: Date = .now) {
        self.name = name
        self.colorID = colorID
        self.symbol = symbol
        self.languageID = language?.rawValue ?? ""
        self.note = ""
        self.createdAt = createdAt
    }

    public var language: LanguageCode? {
        get { LanguageCode(rawValue: languageID) }
        set { languageID = newValue?.rawValue ?? "" }
    }
}

@Model
public final class Tag {
    public var name: String
    /// Tag palette ID (`pink`, `blue`, `green`, `yellow`).
    public var colorID: String

    public var sentences: [Sentence] = []

    public init(name: String, colorID: String) {
        self.name = name
        self.colorID = colorID
    }
}

/// One playback of a sentence, for the dashboard charts.
@Model
public final class PlayEvent {
    public var sentence: Sentence?
    public var date: Date

    public init(sentence: Sentence, date: Date) {
        self.sentence = sentence
        self.date = date
    }
}

/// Where a spoken sentence came from, recorded on first sight.
public struct SpokenSource: Sendable, Hashable {
    public var kind: SpeechSource
    public var appName: String?
    public var url: URL?
    public var bundleID: String?

    public init(kind: SpeechSource, appName: String? = nil, url: URL? = nil, bundleID: String? = nil) {
        self.kind = kind
        self.appName = appName
        self.url = url
        self.bundleID = bundleID
    }
}
