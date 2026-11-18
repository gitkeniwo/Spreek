import Foundation
import Testing
@testable import SpreekCore

@Suite struct VoiceListTests {
    private func edge(_ id: String) -> Voice {
        let locale = id.split(separator: "-").prefix(2).joined(separator: "-")
        return Voice(id: id, name: EdgeVoiceCatalog.displayName(for: id), locale: locale, gender: nil, quality: .neural, provider: .edge)
    }

    private func system(_ name: String, _ locale: String, _ quality: Voice.Quality) -> Voice {
        Voice(id: "com.apple.voice.\(quality.rawValue).\(locale).\(name)", name: name, locale: locale, gender: nil, quality: quality, provider: .system)
    }

    @Test func groupsEdgeThenSystemForTheLanguageOnly() {
        let groups = VoiceList.groups(
            for: .nl,
            edge: [edge("nl-BE-ArnaudNeural"), edge("nl-NL-MaartenNeural"), edge("de-DE-KatjaNeural"), edge("nl-NL-FennaNeural")],
            system: [system("Xander", "nl-NL", .standard), system("Claire", "nl-NL", .premium), system("Anna", "de-DE", .enhanced)]
        )
        #expect(groups.map(\.provider) == [.edge, .system])
        #expect(groups.map(\.title) == ["Edge Neural", "macOS System"])
        // nl-NL before nl-BE; German voices left out.
        #expect(groups[0].voices.map(\.id) == ["nl-NL-FennaNeural", "nl-NL-MaartenNeural", "nl-BE-ArnaudNeural"])
        // Best quality first.
        #expect(groups[1].voices.map(\.name) == ["Claire", "Xander"])
    }

    @Test func removesDuplicates() {
        let groups = VoiceList.groups(
            for: .de,
            edge: [edge("de-DE-KatjaNeural"), edge("de-DE-KatjaNeural"), edge("de-DE-ConradNeural")],
            system: [system("Anna", "de-DE", .enhanced), system("Anna", "de-DE", .enhanced)]
        )
        #expect(groups[0].voices.map(\.id) == ["de-DE-ConradNeural", "de-DE-KatjaNeural"])
        #expect(groups[1].voices.count == 1)
    }

    @Test func keepsDefaultAndSelectedWhenCatalogIsMissing() {
        // edge-tts not installed and no macOS voices: the default (and the selection) still show.
        let groups = VoiceList.groups(for: .nl, edge: [], system: [], selected: "nl-NL-MaartenNeural")
        #expect(groups.map(\.provider) == [.edge])
        #expect(groups[0].voices.map(\.id) == ["nl-NL-FennaNeural", "nl-NL-MaartenNeural"])
        #expect(groups[0].voices.map(\.name) == ["Fenna", "Maarten"])
    }

    @Test func aSelectedSystemVoiceThatIsNotInstalledGoesToTheSystemGroup() {
        let groups = VoiceList.groups(for: .ja, edge: [edge("ja-JP-NanamiNeural")], system: [], selected: "com.apple.voice.premium.ja-JP.Kyoko")
        #expect(groups.map(\.provider) == [.edge, .system])
        #expect(groups[1].voices.map(\.id) == ["com.apple.voice.premium.ja-JP.Kyoko"])
    }

    @Test func englishVariantsAreSeparate() {
        let voices = [edge("en-US-AvaNeural"), edge("en-GB-SoniaNeural"), edge("en-GB-RyanNeural")]
        #expect(VoiceList.groups(for: .enGB, edge: voices, system: [])[0].voices.map(\.id) == ["en-GB-RyanNeural", "en-GB-SoniaNeural"])
        #expect(VoiceList.groups(for: .enUS, edge: voices, system: [])[0].voices.map(\.id) == ["en-US-AvaNeural"])
    }
}
