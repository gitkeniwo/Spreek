/// Static metadata for one supported language.
public struct LanguageInfo: Sendable, Hashable {
    public let code: LanguageCode
    public let englishName: String
    public let nativeName: String
    /// BCP-47 tag, e.g. `nl-NL`.
    public let bcp47: String
    /// Edge neural voice short name used when no voice is configured.
    public let defaultEdgeVoice: String
    /// Language identifier for `AVSpeechSynthesisVoice(language:)`.
    public let systemVoiceLanguage: String
    public let flagEmoji: String
    /// Short upper-case code for `LanguageBadge`; unique across languages.
    public let badgeCode: String

    public init(
        code: LanguageCode,
        englishName: String,
        nativeName: String,
        bcp47: String,
        defaultEdgeVoice: String,
        systemVoiceLanguage: String,
        flagEmoji: String,
        badgeCode: String
    ) {
        self.code = code
        self.englishName = englishName
        self.nativeName = nativeName
        self.bcp47 = bcp47
        self.defaultEdgeVoice = defaultEdgeVoice
        self.systemVoiceLanguage = systemVoiceLanguage
        self.flagEmoji = flagEmoji
        self.badgeCode = badgeCode
    }
}

public enum LanguageRegistry {
    public static let all: [LanguageInfo] = [
        LanguageInfo(
            code: .nl, englishName: "Dutch", nativeName: "Nederlands", bcp47: "nl-NL",
            defaultEdgeVoice: "nl-NL-FennaNeural", systemVoiceLanguage: "nl-NL", flagEmoji: "🇳🇱",
            badgeCode: "NL"
        ),
        LanguageInfo(
            code: .de, englishName: "German", nativeName: "Deutsch", bcp47: "de-DE",
            defaultEdgeVoice: "de-DE-KatjaNeural", systemVoiceLanguage: "de-DE", flagEmoji: "🇩🇪",
            badgeCode: "DE"
        ),
        LanguageInfo(
            code: .ja, englishName: "Japanese", nativeName: "日本語", bcp47: "ja-JP",
            defaultEdgeVoice: "ja-JP-NanamiNeural", systemVoiceLanguage: "ja-JP", flagEmoji: "🇯🇵",
            badgeCode: "JA"
        ),
        LanguageInfo(
            code: .ko, englishName: "Korean", nativeName: "한국어", bcp47: "ko-KR",
            defaultEdgeVoice: "ko-KR-SunHiNeural", systemVoiceLanguage: "ko-KR", flagEmoji: "🇰🇷",
            badgeCode: "KO"
        ),
        LanguageInfo(
            code: .enUS, englishName: "English (US)", nativeName: "English (US)", bcp47: "en-US",
            defaultEdgeVoice: "en-US-AvaNeural", systemVoiceLanguage: "en-US", flagEmoji: "🇺🇸",
            badgeCode: "US"
        ),
        LanguageInfo(
            code: .enGB, englishName: "English (UK)", nativeName: "English (UK)", bcp47: "en-GB",
            defaultEdgeVoice: "en-GB-SoniaNeural", systemVoiceLanguage: "en-GB", flagEmoji: "🇬🇧",
            badgeCode: "UK"
        ),
        LanguageInfo(
            code: .zhCN, englishName: "Mandarin (Mainland)", nativeName: "普通话", bcp47: "zh-CN",
            defaultEdgeVoice: "zh-CN-XiaoxiaoNeural", systemVoiceLanguage: "zh-CN", flagEmoji: "🇨🇳",
            badgeCode: "ZH"
        ),
        LanguageInfo(
            code: .zhTW, englishName: "Mandarin (Taiwan)", nativeName: "國語", bcp47: "zh-TW",
            defaultEdgeVoice: "zh-TW-HsiaoChenNeural", systemVoiceLanguage: "zh-TW", flagEmoji: "🇹🇼",
            badgeCode: "TW"
        ),
        LanguageInfo(
            code: .es, englishName: "Spanish (Spain)", nativeName: "Español", bcp47: "es-ES",
            defaultEdgeVoice: "es-ES-ElviraNeural", systemVoiceLanguage: "es-ES", flagEmoji: "🇪🇸",
            badgeCode: "ES"
        ),
        LanguageInfo(
            code: .fr, englishName: "French", nativeName: "Français", bcp47: "fr-FR",
            defaultEdgeVoice: "fr-FR-DeniseNeural", systemVoiceLanguage: "fr-FR", flagEmoji: "🇫🇷",
            badgeCode: "FR"
        ),
        LanguageInfo(
            code: .it, englishName: "Italian", nativeName: "Italiano", bcp47: "it-IT",
            defaultEdgeVoice: "it-IT-ElsaNeural", systemVoiceLanguage: "it-IT", flagEmoji: "🇮🇹",
            badgeCode: "IT"
        ),
        LanguageInfo(
            code: .ru, englishName: "Russian", nativeName: "Русский", bcp47: "ru-RU",
            defaultEdgeVoice: "ru-RU-SvetlanaNeural", systemVoiceLanguage: "ru-RU", flagEmoji: "🇷🇺",
            badgeCode: "RU"
        ),
        LanguageInfo(
            code: .ptBR, englishName: "Portuguese (Brazil)", nativeName: "Português (Brasil)", bcp47: "pt-BR",
            defaultEdgeVoice: "pt-BR-FranciscaNeural", systemVoiceLanguage: "pt-BR", flagEmoji: "🇧🇷",
            badgeCode: "BR"
        ),
        LanguageInfo(
            code: .zhHK, englishName: "Cantonese (Hong Kong)", nativeName: "粵語", bcp47: "zh-HK",
            defaultEdgeVoice: "zh-HK-HiuGaaiNeural", systemVoiceLanguage: "zh-HK", flagEmoji: "🇭🇰",
            badgeCode: "HK"
        ),
        LanguageInfo(
            code: .ar, englishName: "Arabic", nativeName: "العربية", bcp47: "ar-SA",
            defaultEdgeVoice: "ar-SA-ZariyahNeural", systemVoiceLanguage: "ar-SA", flagEmoji: "🇸🇦",
            badgeCode: "AR"
        ),
        LanguageInfo(
            code: .pl, englishName: "Polish", nativeName: "Polski", bcp47: "pl-PL",
            defaultEdgeVoice: "pl-PL-ZofiaNeural", systemVoiceLanguage: "pl-PL", flagEmoji: "🇵🇱",
            badgeCode: "PL"
        ),
        LanguageInfo(
            code: .sv, englishName: "Swedish", nativeName: "Svenska", bcp47: "sv-SE",
            defaultEdgeVoice: "sv-SE-SofieNeural", systemVoiceLanguage: "sv-SE", flagEmoji: "🇸🇪",
            badgeCode: "SV"
        ),
        LanguageInfo(
            code: .da, englishName: "Danish", nativeName: "Dansk", bcp47: "da-DK",
            defaultEdgeVoice: "da-DK-ChristelNeural", systemVoiceLanguage: "da-DK", flagEmoji: "🇩🇰",
            badgeCode: "DA"
        ),
        LanguageInfo(
            code: .fi, englishName: "Finnish", nativeName: "Suomi", bcp47: "fi-FI",
            defaultEdgeVoice: "fi-FI-NooraNeural", systemVoiceLanguage: "fi-FI", flagEmoji: "🇫🇮",
            badgeCode: "FI"
        ),
        LanguageInfo(
            code: .vi, englishName: "Vietnamese", nativeName: "Tiếng Việt", bcp47: "vi-VN",
            defaultEdgeVoice: "vi-VN-HoaiMyNeural", systemVoiceLanguage: "vi-VN", flagEmoji: "🇻🇳",
            badgeCode: "VI"
        ),
        LanguageInfo(
            code: .tr, englishName: "Turkish", nativeName: "Türkçe", bcp47: "tr-TR",
            defaultEdgeVoice: "tr-TR-EmelNeural", systemVoiceLanguage: "tr-TR", flagEmoji: "🇹🇷",
            badgeCode: "TR"
        ),
        LanguageInfo(
            code: .th, englishName: "Thai", nativeName: "ไทย", bcp47: "th-TH",
            defaultEdgeVoice: "th-TH-PremwadeeNeural", systemVoiceLanguage: "th-TH", flagEmoji: "🇹🇭",
            badgeCode: "TH"
        ),
        LanguageInfo(
            code: .fa, englishName: "Persian", nativeName: "فارسی", bcp47: "fa-IR",
            defaultEdgeVoice: "fa-IR-DilaraNeural", systemVoiceLanguage: "fa-IR", flagEmoji: "🇮🇷",
            badgeCode: "FA"
        ),
    ]

    private static let byCode: [LanguageCode: LanguageInfo] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.code, $0) })

    public static func info(for code: LanguageCode) -> LanguageInfo {
        // Every case has an entry; enforced by tests.
        byCode[code]!
    }
}

extension LanguageCode {
    public var info: LanguageInfo { LanguageRegistry.info(for: self) }
}
