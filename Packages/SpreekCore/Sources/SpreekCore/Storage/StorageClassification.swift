import Foundation

/// A sentence as far as its cached audio is concerned (`LibraryStore.audioOwners()`).
public struct AudioOwner: Sendable, Hashable {
    /// The text its clips are keyed by (`AudioCache.spokenText`).
    public let normalizedText: String
    /// The voice that last spoke it; `nil` = never played, any voice counts.
    public let voiceID: String?
    public let isFavorite: Bool

    public init(normalizedText: String, voiceID: String?, isFavorite: Bool) {
        self.normalizedText = normalizedText
        self.voiceID = voiceID
        self.isFavorite = isFavorite
    }
}

/// How a clip relates to the library.
public enum CacheLink: Sendable, Hashable {
    /// A sentence plays it.
    case linked
    /// No sentence has that text and voice (deleted, or now read by another voice), or the clip
    /// can't be played (metadata or audio missing).
    case unlinked
    /// Same text and voice as a linked clip that was used more recently: another speed.
    case extraSpeed
}

/// The cache matched against a library snapshot.
public struct StorageClassification: Sendable {
    public let links: [String: CacheLink]
    /// Clips of favorite sentences (`trim` removes these last).
    public let favoriteKeys: Set<String>
    /// Sentences with at least one linked clip.
    public let sentencesWithAudio: Int
    /// Entries written before version 0.2 whose text was recovered from the library.
    public let recoveredText: [String: (text: String, rate: Double)]

    public func keys(_ link: CacheLink) -> [String] {
        links.filter { $0.value == link }.map(\.key)
    }

    public func link(of key: String) -> CacheLink { links[key] ?? .unlinked }

    /// Classifies every entry of `report` against `owners`.
    ///
    /// Entries carry their text since version 0.2. Older ones are matched by recomputing keys for
    /// each owner whose voice an old entry uses, at every rate the controller allows (as
    /// `AudioCache.remove(text:voiceID:)` does); their rate is recovered the same way.
    public init(report: StorageReport, owners: [AudioOwner]) {
        var ownersByText: [String: [Int]] = [:]
        for (index, owner) in owners.enumerated() { ownersByText[owner.normalizedText, default: []].append(index) }

        // Old entries: key → (owner text, rate), only for voices that old entries use.
        let oldVoices = Set(report.entries.filter { $0.text == nil && $0.provider != nil }.compactMap(\.voiceID))
        var recovered: [String: (text: String, rate: Double)] = [:]
        if !oldVoices.isEmpty {
            let oldKeys = Set(report.entries.filter { $0.text == nil }.map(\.key))
            var seen: Set<String> = []
            for owner in owners {
                let voices = owner.voiceID.map { oldVoices.contains($0) ? [$0] : [] } ?? Array(oldVoices)
                for voiceID in voices where seen.insert("\(voiceID)|\(owner.normalizedText)").inserted {
                    for rate in AudioCache.keyRates {
                        let key = AudioCache.key(text: owner.normalizedText, voiceID: voiceID, rate: rate)
                        if oldKeys.contains(key) { recovered[key] = (owner.normalizedText, rate) }
                    }
                }
            }
        }

        var links: [String: CacheLink] = [:]
        var favorites: Set<String> = []
        var ownersWithAudio: Set<Int> = []
        // Linked clips per text + voice, to find the extra speeds.
        var linkedGroups: [String: [CacheEntryInfo]] = [:]
        for entry in report.entries {
            guard entry.audioURL != nil, let voiceID = entry.voiceID,
                  let text = entry.text ?? recovered[entry.key]?.text else {
                links[entry.key] = .unlinked
                continue
            }
            let matching = (ownersByText[text] ?? []).filter { owners[$0].voiceID == nil || owners[$0].voiceID == voiceID }
            guard !matching.isEmpty else {
                links[entry.key] = .unlinked
                continue
            }
            links[entry.key] = .linked
            ownersWithAudio.formUnion(matching)
            if matching.contains(where: { owners[$0].isFavorite }) { favorites.insert(entry.key) }
            linkedGroups["\(voiceID)|\(text)", default: []].append(entry)
        }
        for group in linkedGroups.values where group.count > 1 {
            let kept = group.max { $0.lastUsed < $1.lastUsed }
            for entry in group where entry.key != kept?.key { links[entry.key] = .extraSpeed }
        }

        self.links = links
        self.favoriteKeys = favorites
        self.sentencesWithAudio = ownersWithAudio.count
        self.recoveredText = recovered
    }
}
