import Foundation

/// Picks the voice that reads when the chosen Edge voice doesn't work.
public enum BackupVoice {
    /// The Auto pick for `chosen`, from the catalog's voices:
    /// same locale and gender → same locale → same language and gender → the language's default
    /// voice. Ties go to the language's default voice when it qualifies, else the first by id.
    /// `chosen` and everything in `excluding` (known broken, retired) never qualify.
    /// `knownGenders` supplies the gender of a chosen voice the catalog no longer lists.
    /// Returns `nil` only when the default voice is the chosen one (or excluded) and nothing else qualifies.
    public static func auto(
        for chosen: String, language: LanguageCode, in voices: [Voice],
        knownGenders: [String: String] = [:], excluding: Set<String> = []
    ) -> String? {
        let known = voices.first { $0.id == chosen }
        let locale = known?.locale ?? chosen.split(separator: "-").prefix(2).joined(separator: "-")
        let gender = (known?.gender ?? knownGenders[chosen])?.lowercased()
        let defaultVoice = language.info.defaultEdgeVoice

        let candidates = voices.filter {
            $0.provider == .edge && $0.id != chosen && !excluding.contains($0.id) && $0.language == language
        }
        func sameGender(_ voice: Voice) -> Bool { gender != nil && voice.gender?.lowercased() == gender }

        let tiers: [[Voice]] = [
            candidates.filter { $0.locale == locale && sameGender($0) },
            candidates.filter { $0.locale == locale },
            candidates.filter(sameGender),
        ]
        for tier in tiers where !tier.isEmpty {
            if tier.contains(where: { $0.id == defaultVoice }) { return defaultVoice }
            return tier.map(\.id).min()
        }
        return defaultVoice != chosen && !excluding.contains(defaultVoice) ? defaultVoice : nil
    }
}
