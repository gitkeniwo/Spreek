import NaturalLanguage
import Testing
@testable import SpreekCore

@Suite struct LanguageDetectorTests {
    @Test func dutchSentence() {
        let result = LanguageDetector.detect("De kat slaapt op de bank.")
        #expect(result.language == .nl)
        #expect(result.reason == .recognizer)
        #expect(result.confidence > 0.9)
    }

    @Test func germanSentence() {
        let result = LanguageDetector.detect("Die Katze schläft auf dem Sofa.")
        #expect(result.language == .de)
        #expect(result.reason == .recognizer)
    }

    @Test func hangulIsKorean() {
        let result = LanguageDetector.detect("안녕하세요, 만나서 반갑습니다.")
        #expect(result == DetectionResult(language: .ko, confidence: 1, reason: .script))
    }

    @Test func kanaIsJapanese() {
        #expect(LanguageDetector.detect("ありがとうございます").language == .ja)
        #expect(LanguageDetector.detect("コーヒーをください").reason == .script)
    }

    @Test func kanaWinsOverHanInMixedJapanese() {
        let result = LanguageDetector.detect("日本語を勉強しています。")
        #expect(result.language == .ja)
        #expect(result.reason == .script)
    }

    @Test func hanOnlyWithoutChineseIsJapanese() {
        let result = LanguageDetector.detect("東京大学", enabled: [.nl, .ja])
        #expect(result == DetectionResult(language: .ja, confidence: 1, reason: .script))
    }

    @Test func simplifiedHanIsMainlandMandarin() {
        let result = LanguageDetector.detect("我们今天去学校学习中文。", enabled: [.ja, .zhCN, .zhTW])
        #expect(result == DetectionResult(language: .zhCN, confidence: 1, reason: .script))
    }

    @Test func traditionalHanFallsBackToCantonese() {
        #expect(LanguageDetector.detect("我們今天去學校。", enabled: [.zhCN, .zhHK]).language == .zhHK)
        #expect(LanguageDetector.detect("我們今天去學校。", enabled: [.zhCN, .zhTW, .zhHK]).language == .zhTW)
        #expect(LanguageDetector.detect("我们今天去学校。", enabled: [.zhCN, .zhHK]).language == .zhCN)
        #expect(LanguageDetector.detect("我们今天去学校。", enabled: [.nl, .zhHK]).language == .zhHK)
    }

    @Test func thaiScriptAndRecognizedNewLanguages() {
        #expect(LanguageDetector.detect("สวัสดีตอนเช้า", enabled: [.nl, .th]).reason == .script)
        #expect(LanguageDetector.detect("สวัสดีตอนเช้า", enabled: [.nl, .th]).language == .th)
        let enabled: Set<LanguageCode> = [.nl, .ar, .fa, .pl, .sv, .tr, .vi]
        #expect(LanguageDetector.detect("صباح الخير! هل نشرب القهوة معاً لاحقاً؟", enabled: enabled).language == .ar)
        #expect(LanguageDetector.detect("صبح بخیر! بعداً با هم قهوه بنوشیم؟", enabled: enabled).language == .fa)
        #expect(LanguageDetector.detect("Dzień dobry! Napijemy się później razem kawy?", enabled: enabled).language == .pl)
        #expect(LanguageDetector.detect("Günaydın! Sonra birlikte kahve içelim mi?", enabled: enabled).language == .tr)
        #expect(LanguageDetector.detect("Chào buổi sáng! Lát nữa mình cùng uống cà phê nhé?", enabled: enabled).language == .vi)
    }

    @Test func traditionalHanIsTaiwanMandarin() {
        let result = LanguageDetector.detect("我們今天去學校學習中文。", enabled: [.ja, .zhCN, .zhTW])
        #expect(result == DetectionResult(language: .zhTW, confidence: 1, reason: .script))
    }

    /// Recognizer leans ja for "東京大学", but Han without kana goes to Chinese when enabled.
    @Test func hanOnlyPrefersChineseOverJapanese() {
        #expect(LanguageDetector.detect("東京大学", enabled: [.ja, .zhCN, .zhTW]).language == .zhCN)
    }

    @Test(arguments: [LanguageCode.zhCN, .zhTW])
    func singleChineseVariantTakesBothScripts(variant: LanguageCode) {
        let enabled: Set<LanguageCode> = [.nl, .ja, variant]
        #expect(LanguageDetector.detect("我们今天去学校学习中文。", enabled: enabled).language == variant)
        #expect(LanguageDetector.detect("我們今天去學校學習中文。", enabled: enabled).language == variant)
    }

    @Test func defaultEnabledRoutesHanToMainland() {
        #expect(LanguageDetector.detect("这是什么").language == .zhCN)
    }

    @Test func kanaStillWinsWithChineseEnabled() {
        #expect(LanguageDetector.detect("日本語を勉強しています。", enabled: [.ja, .zhCN, .zhTW]).language == .ja)
    }

    @Test func cyrillicIsRussian() {
        let result = LanguageDetector.detect("Я люблю читать книги.", enabled: [.nl, .ru])
        #expect(result == DetectionResult(language: .ru, confidence: 1, reason: .script))
    }

    @Test func cyrillicNotScriptedWhenRussianDisabled() {
        #expect(LanguageDetector.detect("Я люблю читать книги.", enabled: [.nl, .de]).language != .ru)
    }

    @Test(arguments: [LanguageCode.enUS, .enGB])
    func englishUsesVariantSetting(variant: LanguageCode) {
        let result = LanguageDetector.detect(
            "The weather is lovely today, isn't it?", enabled: [.nl, .de, .enUS, .enGB], englishVariant: variant
        )
        #expect(result.language == variant)
        #expect(result.reason == .recognizer)
    }

    @Test func englishFallsBackToTheEnabledVariant() {
        let result = LanguageDetector.detect(
            "The weather is lovely today, isn't it?", enabled: [.nl, .enGB], englishVariant: .enUS
        )
        #expect(result.language == .enGB)
    }

    @Test func portugueseIsBrazilian() {
        let result = LanguageDetector.detect("Eu gosto muito de café com leite.", enabled: [.nl, .es, .ptBR])
        #expect(result.language == .ptBR)
    }

    @Test func spanishIsSpanish() {
        let result = LanguageDetector.detect("Me gusta mucho el café con leche.", enabled: [.nl, .es, .ptBR])
        #expect(result.language == .es)
    }

    @Test func frenchAndItalian() {
        let enabled: Set<LanguageCode> = [.nl, .fr, .it]
        #expect(LanguageDetector.detect("Je voudrais un café, s'il vous plaît.", enabled: enabled).language == .fr)
        #expect(LanguageDetector.detect("Vorrei un caffè, per favore.", enabled: enabled).language == .it)
    }

    @Test func folderLanguageOverridesScript() {
        let result = LanguageDetector.detect("我們學習中文", enabled: [.zhCN, .zhTW], folderLanguage: .zhCN)
        #expect(result == DetectionResult(language: .zhCN, confidence: 1, reason: .folder))
    }

    @Test func folderLanguageOverridesDetection() {
        let result = LanguageDetector.detect("Die Katze schläft auf dem Sofa.", folderLanguage: .nl)
        #expect(result == DetectionResult(language: .nl, confidence: 1, reason: .folder))
    }

    /// "Kind" scores ~0.53 nl / ~0.47 de: a tie, so the preference decides. (With English
    /// enabled it reads as English, so this uses the original four languages.)
    /// Needs a system language model that scores "Kind" as a near-tie; other macOS versions (such
    /// as CI images) score it differently, and then there is no tie to exercise.
    static let kindIsANlDeTie: Bool = {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.dutch, .german, .japanese, .korean]
        recognizer.processString("Kind")
        let scores = recognizer.languageHypotheses(withMaximum: 4)
        guard let nl = scores[.dutch], let de = scores[.german] else { return false }
        return abs(nl - de) < LanguageDetector.tieMargin
            && scores.filter { ![.dutch, .german].contains($0.key) }.allSatisfy { $0.value < min(nl, de) }
    }()

    @Test(.enabled(if: LanguageDetectorTests.kindIsANlDeTie), arguments: [LanguageCode.nl, .de])
    func nlDeTieUsesPreference(preferred: LanguageCode) {
        let result = LanguageDetector.detect("Kind", enabled: [.nl, .de, .ja, .ko], preferOnNLDETie: preferred)
        #expect(result.language == preferred)
        #expect(result.reason == .tiePreference)
    }

    @Test func clearWinnerIgnoresPreference() {
        let result = LanguageDetector.detect("Ich bin müde", preferOnNLDETie: .nl)
        #expect(result.language == .de)
        #expect(result.reason == .recognizer)
    }

    @Test func constrainedToEnabledLanguages() {
        let result = LanguageDetector.detect("Die Katze schläft auf dem Sofa.", enabled: [.nl, .ja])
        #expect(result.language == .nl)
    }

    @Test func scriptShortcutRespectsEnabled() {
        // Korean disabled: Hangul can't be routed to ko, and nothing else fits.
        let result = LanguageDetector.detect("안녕하세요", enabled: [.nl, .de])
        #expect(result.language != .ko)
    }

    @Test func emptyTextFallsBack() {
        let result = LanguageDetector.detect("   ", enabled: [.de, .ja])
        #expect(result.language == .de)
        #expect(result.reason == .fallback)
        #expect(result.confidence == 0)
    }

    @Test func latinTextIsNotScripted() {
        #expect(LanguageDetector.scriptLanguage(of: "Goedemorgen") == nil)
    }
}
