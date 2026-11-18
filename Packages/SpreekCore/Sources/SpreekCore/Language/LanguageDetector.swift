import NaturalLanguage

/// Why a language was chosen; shown in debug UI and useful in tests.
public enum DetectionReason: Sendable, Hashable {
    /// A folder's language overrides detection.
    case folder
    /// Decided by script (Hangul, Kana, Cyrillic, Thai, Persian letters, Han).
    case script
    /// `NLLanguageRecognizer`, constrained to the enabled languages.
    case recognizer
    /// nl and de scored within `LanguageDetector.tieMargin`; the preference decided.
    case tiePreference
    /// Nothing usable (empty text, or the recognizer had no opinion); first enabled language.
    case fallback
}

public struct DetectionResult: Sendable, Hashable {
    public let language: LanguageCode
    /// 0…1. 1 for folder and script decisions.
    public let confidence: Double
    public let reason: DetectionReason

    public init(language: LanguageCode, confidence: Double, reason: DetectionReason) {
        self.language = language
        self.confidence = confidence
        self.reason = reason
    }
}

public enum LanguageDetector {
    /// nl/de hypotheses closer than this are treated as a tie.
    public static let tieMargin = 0.15

    /// Detects the language of `text`.
    ///
    /// Order: folder override → script shortcut (Kana → ja, Hangul → ko, Cyrillic → ru, Thai → th,
    /// Persian-only letters → fa; Han without kana → a Chinese variant by Simplified / Traditional
    /// when one is enabled, else ja) → `NLLanguageRecognizer` constrained to `enabled`
    /// (English → `englishVariant`) → nl/de tie → `preferOnNLDETie`.
    public static func detect(
        _ text: String,
        enabled: Set<LanguageCode> = LanguageCode.defaultEnabled,
        preferOnNLDETie: LanguageCode = .nl,
        englishVariant: LanguageCode = .enUS,
        folderLanguage: LanguageCode? = nil
    ) -> DetectionResult {
        if let folderLanguage {
            return DetectionResult(language: folderLanguage, confidence: 1, reason: .folder)
        }
        let enabled = enabled.isEmpty ? LanguageCode.defaultEnabled : enabled
        let fallbackLanguage = LanguageCode.allCases.first { enabled.contains($0) } ?? .nl

        if let scripted = scriptLanguage(of: text, enabled: enabled) {
            return DetectionResult(language: scripted, confidence: 1, reason: .script)
        }

        let recognizer = NLLanguageRecognizer()
        let constraints = Set(enabled.map(recognizerLanguage(for:)))
        recognizer.languageConstraints = Array(constraints)
        recognizer.processString(text)
        var best: [LanguageCode: Double] = [:]
        for (key, value) in recognizer.languageHypotheses(withMaximum: constraints.count) {
            guard let code = spreekLanguage(for: key, enabled: enabled, englishVariant: englishVariant) else { continue }
            best[code] = max(best[code] ?? 0, value)
        }
        let hypotheses = best.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }

        guard let top = hypotheses.first else {
            return DetectionResult(language: fallbackLanguage, confidence: 0, reason: .fallback)
        }
        if hypotheses.count > 1 {
            let second = hypotheses[1]
            let pair: Set<LanguageCode> = [top.0, second.0]
            if pair == [.nl, .de], top.1 - second.1 < tieMargin, pair.contains(preferOnNLDETie) {
                let preferred = preferOnNLDETie == top.0 ? top : second
                return DetectionResult(language: preferred.0, confidence: preferred.1, reason: .tiePreference)
            }
        }
        return DetectionResult(language: top.0, confidence: top.1, reason: .recognizer)
    }

    /// Script shortcut, limited to `enabled`. Kana anywhere → ja; Hangul → ko; Cyrillic → ru; Thai → th; Persian-only letters → fa;
    /// Han without kana → a Chinese variant by script (see `chineseVariant`), else ja.
    static func scriptLanguage(of text: String, enabled: Set<LanguageCode> = Set(LanguageCode.allCases)) -> LanguageCode? {
        var hasHan = false, hasHangul = false, hasKana = false, hasCyrillic = false, hasThai = false, hasPersianLetter = false
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F:
                hasKana = true
            case 0xAC00...0xD7AF, 0x1100...0x11FF, 0x3130...0x318F:
                hasHangul = true
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF:
                hasHan = true
            case 0x0400...0x04FF, 0x0500...0x052F:
                hasCyrillic = true
            case 0x0E00...0x0E7F:
                hasThai = true
            case 0x067E, 0x0686, 0x0698, 0x06AF, 0x06A9, 0x06CC:
                // پ چ ژ گ ک ی: Persian letters that Arabic doesn't use.
                hasPersianLetter = true
            default:
                break
            }
        }
        if hasKana, enabled.contains(.ja) { return .ja }
        if hasHangul, enabled.contains(.ko) { return .ko }
        if hasCyrillic, enabled.contains(.ru) { return .ru }
        if hasThai, enabled.contains(.th) { return .th }
        if hasPersianLetter, enabled.contains(.fa) { return .fa }
        if hasHan, !hasKana {
            if let chinese = chineseVariant(of: text, enabled: enabled) { return chinese }
            if enabled.contains(.ja) { return .ja }
        }
        return nil
    }

    /// Simplified → zh-CN, Traditional → zh-TW, else zh-HK; when only one script has an enabled
    /// variant, both scripts map to it. `nil` when no Chinese variant is enabled.
    static func chineseVariant(of text: String, enabled: Set<LanguageCode>) -> LanguageCode? {
        let simplifiedVariant: LanguageCode? = enabled.contains(.zhCN) ? .zhCN : nil
        let traditionalVariant = [LanguageCode.zhTW, .zhHK].first(where: enabled.contains)
        guard let simplifiedVariant, let traditionalVariant else { return simplifiedVariant ?? traditionalVariant }
        let recognizer = NLLanguageRecognizer()
        // ja is included to calibrate the scores, but Han-only text is never routed to it here.
        recognizer.languageConstraints = [.simplifiedChinese, .traditionalChinese, .japanese]
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        let simplified = hypotheses[.simplifiedChinese] ?? 0
        let traditional = hypotheses[.traditionalChinese] ?? 0
        return traditional > simplified ? traditionalVariant : simplifiedVariant
    }

    /// The recognizer language that stands for `code`.
    static func recognizerLanguage(for code: LanguageCode) -> NLLanguage {
        switch code {
        case .enUS, .enGB: .english
        case .zhCN: .simplifiedChinese
        case .zhTW, .zhHK: .traditionalChinese
        case .ptBR: .portuguese
        default: NLLanguage(code.rawValue)
        }
    }

    /// Maps a recognizer hypothesis back to an enabled Spreek language.
    static func spreekLanguage(for language: NLLanguage, enabled: Set<LanguageCode>, englishVariant: LanguageCode) -> LanguageCode? {
        let candidates: [LanguageCode] = switch language {
        case .english: [englishVariant] + LanguageCode.englishVariants
        case .simplifiedChinese: [.zhCN, .zhTW, .zhHK]
        case .traditionalChinese: [.zhTW, .zhHK, .zhCN]
        case .portuguese: [.ptBR]
        default: LanguageCode(rawValue: language.rawValue).map { [$0] } ?? []
        }
        return candidates.first(where: enabled.contains)
    }
}
