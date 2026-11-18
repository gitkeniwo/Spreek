import Foundation
/// A language Spreek can detect and speak. Adding a language = adding a case
/// here plus an entry in `LanguageRegistry`.
///
/// Raw values are stored in the library; never change an existing one.
public enum LanguageCode: String, CaseIterable, Codable, Sendable, Hashable {
    case nl, de, ja, ko
    case enUS = "en-US"
    case enGB = "en-GB"
    case zhCN = "zh-CN"
    case zhTW = "zh-TW"
    case es, fr, it, ru
    case ptBR = "pt-BR"
    /// Cantonese, read with Hong Kong voices.
    case zhHK = "zh-HK"
    case ar, pl, sv, da, fi, vi, tr, th, fa

    /// Enabled until the user changes `LanguagePreferences.enabledKey`.
    public static let defaultEnabled: Set<LanguageCode> = [.nl, .de, .ja, .ko, .enUS, .zhCN, .fr, .es, .ptBR]

    /// The English variants (`LanguagePreferences.englishVariantKey`).
    public static let englishVariants: [LanguageCode] = [.enUS, .enGB]

    /// The Chinese variants, picked by script (Simplified → zh-CN; Traditional → zh-TW, then zh-HK).
    public static let chineseVariants: [LanguageCode] = [.zhCN, .zhTW, .zhHK]

    /// Every language in display order: by native name, Latin scripts first.
    public static let sortedByName: [LanguageCode] = allCases.sorted {
        $0.info.nativeName.compare($1.info.nativeName, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
            == .orderedAscending
    }

    /// Short code shown in `LanguageBadge` (code style), e.g. `NL`, `US`, `TW`.
    public var badgeLabel: String { info.badgeCode }

    /// The Spreek language for a voice locale like `nl-BE`, `en_GB` or `zh-TW`:
    /// an exact match first, then a region-less code by primary subtag.
    public init?(locale: String) {
        let normalized = locale.replacingOccurrences(of: "_", with: "-")
        if let exact = LanguageCode.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(normalized) == .orderedSame }) {
            self = exact
            return
        }
        let primary = String(normalized.prefix { $0 != "-" }).lowercased()
        guard let code = LanguageCode(rawValue: primary) else { return nil }
        self = code
    }
}

/// UserDefaults keys and defaults for language choices (read through `AppSettings`).
public enum LanguagePreferences {
    /// `[String]` of `LanguageCode` raw values.
    public static let enabledKey = "languages.enabled"
    /// `LanguageCode` raw value of the English variant used for detected English.
    public static let englishVariantKey = "languages.englishVariant"

    public static func enabled(in defaults: UserDefaults = .standard) -> Set<LanguageCode> {
        guard let stored = defaults.stringArray(forKey: enabledKey) else { return LanguageCode.defaultEnabled }
        let codes = Set(stored.compactMap(LanguageCode.init(rawValue:)))
        return codes.isEmpty ? LanguageCode.defaultEnabled : codes
    }

    public static func englishVariant(in defaults: UserDefaults = .standard) -> LanguageCode {
        defaults.string(forKey: englishVariantKey)
            .flatMap(LanguageCode.init(rawValue:))
            .flatMap { LanguageCode.englishVariants.contains($0) ? $0 : nil } ?? .enUS
    }
}
