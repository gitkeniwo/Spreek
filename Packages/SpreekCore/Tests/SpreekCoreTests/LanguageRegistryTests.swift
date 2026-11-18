import Foundation
import Testing
@testable import SpreekCore

@Suite struct LanguageRegistryTests {
    @Test func everyCodeHasExactlyOneEntry() {
        #expect(LanguageRegistry.all.count == LanguageCode.allCases.count)
        #expect(Set(LanguageRegistry.all.map(\.code)) == Set(LanguageCode.allCases))
    }

    @Test(arguments: LanguageCode.allCases)
    func entryIsConsistent(code: LanguageCode) {
        let info = code.info
        #expect(info.code == code)
        #expect(info.bcp47 == code.rawValue || info.bcp47.hasPrefix(code.rawValue + "-"))
        #expect(info.systemVoiceLanguage == info.bcp47)
        #expect(!info.badgeCode.isEmpty && info.badgeCode == info.badgeCode.uppercased())
        #expect(info.defaultEdgeVoice.hasPrefix(info.bcp47 + "-"))
        #expect(info.defaultEdgeVoice.hasSuffix("Neural"))
        #expect(!info.nativeName.isEmpty)
        #expect(!info.flagEmoji.isEmpty)
    }

    @Test func dutchMetadata() {
        let nl = LanguageCode.nl.info
        #expect(nl.nativeName == "Nederlands")
        #expect(nl.defaultEdgeVoice == "nl-NL-FennaNeural")
        #expect(nl.flagEmoji == "🇳🇱")
        #expect(LanguageCode.nl.badgeLabel == "NL")
    }

    @Test func badgeCodesAreUnique() {
        let codes = LanguageCode.allCases.map(\.badgeLabel)
        #expect(Set(codes).count == codes.count)
    }

    /// Stored library rows use these; they must never change.
    @Test func originalRawValuesUnchanged() {
        #expect(LanguageCode.nl.rawValue == "nl")
        #expect(LanguageCode.de.rawValue == "de")
        #expect(LanguageCode.ja.rawValue == "ja")
        #expect(LanguageCode.ko.rawValue == "ko")
    }

    @Test func languagesWithRegionalVariants() {
        #expect(LanguageCode.allCases.count == 23)
        #expect(LanguageCode(rawValue: "zh-HK") == .zhHK)
        #expect(LanguageCode(locale: "zh_HK") == .zhHK)
        #expect(LanguageCode(locale: "ar-EG") == .ar)
        #expect(LanguageCode(rawValue: "en-US") == .enUS)
        #expect(LanguageCode(rawValue: "zh-TW") == .zhTW)
        #expect(LanguageCode(rawValue: "pt-BR") == .ptBR)
        #expect(LanguageCode.zhTW.info.nativeName == "國語")
        #expect(LanguageCode.enGB.badgeLabel == "UK")
    }

    @Test func defaultEnabledLanguages() {
        #expect(LanguageCode.defaultEnabled == [.nl, .de, .ja, .ko, .enUS, .zhCN, .fr, .es, .ptBR])
    }

    @Test func sortedByNativeNameLatinFirst() {
        let sorted = LanguageCode.sortedByName
        #expect(sorted.count == LanguageCode.allCases.count)
        #expect(Array(sorted.prefix(3)) == [.da, .de, .enGB])
        #expect(sorted.firstIndex(of: .nl)! < sorted.firstIndex(of: .pl)!)
        #expect(sorted.firstIndex(of: .tr)! < sorted.firstIndex(of: .ru)!)
    }

    @Test func preferencesReadFromDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "LanguagePreferencesTests-\(UUID())"))
        #expect(LanguagePreferences.enabled(in: defaults) == LanguageCode.defaultEnabled)
        #expect(LanguagePreferences.englishVariant(in: defaults) == .enUS)
        defaults.set(["nl", "fr", "bogus"], forKey: LanguagePreferences.enabledKey)
        defaults.set("en-GB", forKey: LanguagePreferences.englishVariantKey)
        #expect(LanguagePreferences.enabled(in: defaults) == [.nl, .fr])
        #expect(LanguagePreferences.englishVariant(in: defaults) == .enGB)
        defaults.set("fr", forKey: LanguagePreferences.englishVariantKey)
        #expect(LanguagePreferences.englishVariant(in: defaults) == .enUS)
    }
}
