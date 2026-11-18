import Foundation
import Testing
@testable import SpreekCore

@Suite struct AppSettingsTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "SpreekTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func defaults() {
        let settings = AppSettings(defaults: makeDefaults())
        #expect(settings.enabledLanguages == LanguageCode.defaultEnabled)
        #expect(settings.voice(for: .nl) == "nl-NL-FennaNeural")
        #expect(settings.speed(for: .nl) == 1)
        #expect(settings.englishVariant == .enUS)
        #expect(settings.detectionMode == .folderThenAuto)
        #expect(settings.nlDeTiePreference == .nl)
        #expect(settings.badgeStyle == .code)
        #expect(settings.barShowMode == .whileSpeaking)
        #expect(settings.barHideAfterSeconds == 3)
        #expect(!settings.barPinByDefault)
        #expect(settings.barPlacement == .fixed)
        #expect(settings.barPosition == .bottomCenter)
        #expect(settings.barDragPosition == nil)
        #expect(settings.highlightSpokenWord)
        #expect(settings.appearance == .system)
        #expect(settings.appIcon == .snavel)
        #expect(settings.dockIconMode == .whileDashboardOpen)
        #expect(!settings.openDashboardOnLaunch)
        #expect(settings.historyRetention == .never)
        #expect(settings.audioCacheLimit == .none)
        #expect(settings.notesPasteKeepsBoldItalicOnly)
        #expect(settings.edgeExecutablePath == nil)
        #expect(settings.edgeEngineMode == .automatic)
        #expect(settings.backupVoices.isEmpty)
        #expect(!settings.isMuted)
        #expect(settings.forcedLanguage == nil)
    }

    @Test func codableRoundTrip() throws {
        let settings = AppSettings()
        settings.enabledLanguages = [.nl, .enGB, .fr]
        settings.voices = [.nl: "nl-NL-MaartenNeural", .fr: "com.apple.voice.premium.fr-FR.Amelie"]
        settings.backupVoices = [.nl: "nl-NL-ColetteNeural"]
        settings.speeds = [.nl: 0.85]
        settings.englishVariant = .enGB
        settings.detectionMode = .autoOnly
        settings.nlDeTiePreference = .de
        settings.badgeStyle = .flag
        settings.barShowMode = .onlyWhenPinned
        settings.barHideAfterSeconds = 5
        settings.barPinByDefault = true
        settings.barPlacement = .lastDragged
        settings.barPosition = .topRight
        settings.barDragPosition = FloatingBarDragPosition(screenID: "A1", horizontal: .right, horizontalInset: 40, vertical: .top, verticalInset: 120)
        settings.highlightSpokenWord = false
        settings.appearance = .dark
        settings.appIcon = .merel
        settings.dockIconMode = .never
        settings.openDashboardOnLaunch = true
        settings.historyRetention = .threeMonths
        settings.audioCacheLimit = .mb250
        settings.notesPasteKeepsBoldItalicOnly = false
        settings.edgeExecutablePath = "~/bin/edge-tts"
        settings.edgeEngineMode = .cliOnly
        settings.isMuted = true
        settings.forcedLanguage = .de

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(try encoder.encode(decoded) == data)
        #expect(decoded.enabledLanguages == [.nl, .enGB, .fr])
        #expect(decoded.voice(for: .nl) == "nl-NL-MaartenNeural")
        #expect(decoded.speed(for: .nl) == 0.85)
        #expect(decoded.backupVoices == [.nl: "nl-NL-ColetteNeural"])
        #expect(decoded.badgeStyle == .flag)
        #expect(decoded.barPlacement == .lastDragged)
        #expect(decoded.barPosition == .topRight)
        #expect(decoded.barDragPosition?.verticalInset == 120)
        #expect(decoded.edgeExecutablePath == "~/bin/edge-tts")
        #expect(decoded.edgeEngineMode == .cliOnly)
        #expect(decoded.forcedLanguage == .de)
        #expect(decoded.openDashboardOnLaunch)
        #expect(decoded.historyRetention == .threeMonths)
        #expect(decoded.audioCacheLimit == .mb250)
        #expect(decoded.appIcon == .merel)
    }

    @Test func historyRetentionCutoffs() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12))!
        let day = { (y: Int, m: Int, d: Int) in calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }
        #expect(HistoryRetention.never.cutoff(now: now, calendar: calendar) == nil)
        #expect(HistoryRetention.oneWeek.cutoff(now: now, calendar: calendar) == day(2026, 10, 8))
        #expect(HistoryRetention.oneMonth.cutoff(now: now, calendar: calendar) == day(2026, 9, 15))
        #expect(HistoryRetention.threeMonths.cutoff(now: now, calendar: calendar) == day(2026, 7, 15))
        #expect(HistoryRetention.oneYear.cutoff(now: now, calendar: calendar) == day(2025, 10, 15))
    }

    @Test func decodingAnEmptyPayloadGivesDefaults() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(decoded.enabledLanguages == LanguageCode.defaultEnabled)
        #expect(decoded.barHideAfterSeconds == 3)
        #expect(decoded.highlightSpokenWord)
        #expect(decoded.edgeEngineMode == .automatic)
    }

    @Test func appIconPersistsUnderItsKey() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.appIcon = .raaf
        #expect(defaults.string(forKey: "app.icon") == "raaf")
        #expect(AppSettings(defaults: defaults).appIcon == .raaf)
        // An icon from a future build falls back to the bundle icon.
        defaults.set("dodo", forKey: "app.icon")
        #expect(AppSettings(defaults: defaults).appIcon == .snavel)
    }

    @Test func edgeEngineModePersistsUnderItsKey() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.edgeEngineMode = .nativeOnly
        #expect(defaults.string(forKey: "edge.engineMode") == "nativeOnly")
        #expect(AppSettings(defaults: defaults).edgeEngineMode == .nativeOnly)
        // An unknown stored value falls back to Automatic.
        defaults.set("carrierPigeon", forKey: "edge.engineMode")
        #expect(AppSettings(defaults: defaults).edgeEngineMode == .automatic)
    }

    @Test func audioCacheLimitPersistsUnderItsKey() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.audioCacheLimit = .gb1
        #expect(defaults.string(forKey: "storage.audioCacheLimit") == "gb1")
        #expect(AppSettings(defaults: defaults).audioCacheLimit == .gb1)
        #expect(AudioCacheLimit.gb1.bytes == 1_000_000_000)
        #expect(AudioCacheLimit.none.bytes == nil)
    }

    @Test func changesPersistToUserDefaults() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.voices[.nl] = "nl-NL-MaartenNeural"
        settings.backupVoices[.nl] = "nl-NL-ColetteNeural"
        settings.speeds[.nl] = 0.85
        settings.badgeStyle = .flag
        settings.barHideAfterSeconds = 5
        settings.setEnabled(false, .ko)
        settings.englishVariant = .enGB

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.voice(for: .nl) == "nl-NL-MaartenNeural")
        #expect(reloaded.speed(for: .nl) == 0.85)
        #expect(reloaded.backupVoices == [.nl: "nl-NL-ColetteNeural"])
        #expect(reloaded.badgeStyle == .flag)
        #expect(reloaded.barHideAfterSeconds == 5)
        #expect(!reloaded.enabledLanguages.contains(.ko))
        // Keys from earlier batches are kept.
        #expect(defaults.string(forKey: "languageBadgeStyle") == "flag")
        #expect(defaults.integer(forKey: "floatingBar.autoHideSeconds") == 5)
        #expect(defaults.string(forKey: "languages.englishVariant") == "en-GB")
    }

    @Test func readsSettingsWrittenByEarlierBatches() {
        let defaults = makeDefaults()
        defaults.set(["nl", "de"], forKey: "languages.enabled")
        defaults.set("flag", forKey: "languageBadgeStyle")
        defaults.set(7, forKey: "floatingBar.autoHideSeconds")
        defaults.set(true, forKey: "floatingBar.pinByDefault")
        defaults.set("always", forKey: "app.dockIconMode")
        defaults.set(false, forKey: "notes.pasteKeepsBoldItalicOnly")
        defaults.set(0.8, forKey: "speech.rate")

        let settings = AppSettings(defaults: defaults)
        #expect(settings.enabledLanguages == [.nl, .de])
        #expect(settings.badgeStyle == .flag)
        #expect(settings.barHideAfterSeconds == 7)
        #expect(settings.barPinByDefault)
        #expect(settings.dockIconMode == .always)
        #expect(!settings.notesPasteKeepsBoldItalicOnly)
        // The old global speed becomes each enabled language's speed.
        #expect(settings.speed(for: .nl) == 0.8)
        #expect(settings.speed(for: .de) == 0.8)
        #expect(settings.speed(for: .ja) == 1)
    }

    @Test func barPositionSettingsPersist() {
        let defaults = makeDefaults()
        // Written by builds that only had Bottom center / Top center.
        defaults.set("topCenter", forKey: "floatingBar.position")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.barPlacement == .fixed)
        #expect(settings.barPosition == .topCenter)

        settings.barPlacement = .nearSelection
        settings.barPosition = .bottomLeft
        let drag = FloatingBarDragPosition(screenID: nil, horizontal: .left, horizontalInset: 12, vertical: .bottom, verticalInset: 300)
        settings.barDragPosition = drag
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.barPlacement == .nearSelection)
        #expect(reloaded.barPosition == .bottomLeft)
        #expect(reloaded.barDragPosition == drag)

        settings.barDragPosition = nil
        #expect(defaults.object(forKey: "floatingBar.dragPosition") == nil)
        // Unknown values fall back to the defaults.
        defaults.set("floating", forKey: "floatingBar.placement")
        defaults.set("middle", forKey: "floatingBar.position")
        #expect(AppSettings(defaults: defaults).barPlacement == .fixed)
        #expect(AppSettings(defaults: defaults).barPosition == .bottomCenter)
    }

    @Test func lastLanguageCannotBeDisabled() {
        let settings = AppSettings()
        settings.enabledLanguages = [.nl]
        settings.setEnabled(false, .nl)
        #expect(settings.enabledLanguages == [.nl])
    }

    @Test func clampsAndTrims() {
        let settings = AppSettings()
        settings.barHideAfterSeconds = 500
        #expect(settings.barHideAfterSeconds == 60)
        settings.barHideAfterSeconds = -2
        #expect(settings.barHideAfterSeconds == 0)
        settings.edgeExecutablePath = "  /opt/edge-tts \n"
        #expect(settings.edgeExecutablePath == "/opt/edge-tts")
        settings.edgeExecutablePath = "   "
        #expect(settings.edgeExecutablePath == nil)
    }

    @Test func addableLanguagesAreTheUnlistedOnesByName() {
        let settings = AppSettings()
        settings.enabledLanguages = [.nl, .de, .ja, .ko, .enUS, .zhCN]
        settings.listedLanguages = settings.enabledLanguages
        #expect(settings.addableLanguages.first == .da)
        #expect(!settings.addableLanguages.contains(.nl))
        #expect(settings.addableLanguages.count == LanguageCode.allCases.count - 6)
        #expect(settings.isEnglishEnabled)
        settings.enabledLanguages = [.nl]
        #expect(!settings.isEnglishEnabled)
        // Switched off, still listed.
        #expect(!settings.addableLanguages.contains(.de))
        #expect(Array(settings.listedLanguagesSorted.prefix(3)) == [.de, .enUS, .nl])
        #expect(settings.listedLanguagesSorted.count == 6)
    }

    @Test func addAndRemoveLanguages() {
        let settings = AppSettings()
        settings.add(.sv)
        #expect(settings.enabledLanguages.contains(.sv) && settings.listedLanguages.contains(.sv))
        settings.voices[.sv] = "sv-SE-MattiasNeural"
        settings.backupVoices[.sv] = "sv-SE-SofieNeural"
        settings.speeds[.sv] = 0.8
        settings.forcedLanguage = .sv
        settings.remove(.sv)
        #expect(!settings.enabledLanguages.contains(.sv) && !settings.listedLanguages.contains(.sv))
        #expect(settings.voices[.sv] == nil && settings.backupVoices[.sv] == nil && settings.speeds[.sv] == nil && settings.forcedLanguage == nil)

        settings.enabledLanguages = [.nl]
        #expect(!settings.canRemove(.nl))
        settings.remove(.nl)
        #expect(settings.enabledLanguages == [.nl] && settings.listedLanguages.contains(.nl))
        #expect(settings.canRemove(.de))
        settings.remove(.de)
        #expect(!settings.listedLanguages.contains(.de))
    }

    @Test func listedLanguagesPersistAndIncludeEnabled() throws {
        let defaults = try #require(UserDefaults(suiteName: "AppSettingsListed-\(UUID())"))
        defaults.set(["nl", "th"], forKey: AppSettings.Key.enabledLanguages)
        #expect(AppSettings(defaults: defaults).listedLanguages == [.nl, .th])
        let settings = AppSettings(defaults: defaults)
        settings.add(.fi)
        settings.setEnabled(false, .fi)
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.listedLanguages == [.nl, .th, .fi])
        #expect(reloaded.enabledLanguages == [.nl, .th])
    }

    @Test func detectionModeDecidesWhetherFolderLanguageWins() {
        let settings = AppSettings()
        #expect(settings.folderLanguage(.de) == .de)
        settings.detectionMode = .autoOnly
        #expect(settings.folderLanguage(.de) == nil)
    }
}

@MainActor
@Suite struct AppSettingsSpeechTests {
    private func makeController() -> SpeechController {
        SpeechController(
            chain: ProviderChain(primary: MockProvider(id: .edge), fallback: MockProvider(id: .system)),
            cache: AudioCache(root: temporaryDirectory("SettingsCache")), player: MockPlayer(), tickInterval: nil
        )
    }

    @Test func enablingAndDisablingLanguagesChangesDetection() {
        let speech = makeController()
        let settings = AppSettings()
        let german = "Ich möchte heute Abend mit meinen Freunden ins Kino gehen."

        settings.apply(to: speech)
        #expect(speech.prepare(text: german)?.detection.language == .de)

        settings.setEnabled(false, .de)
        settings.apply(to: speech)
        #expect(speech.enabledLanguages == settings.enabledLanguages)
        #expect(speech.prepare(text: german)?.detection.language != .de)

        settings.setEnabled(true, .de)
        settings.apply(to: speech)
        #expect(speech.prepare(text: german)?.detection.language == .de)
    }

    @Test func addingALanguageMakesItDetectable() {
        let speech = makeController()
        let settings = AppSettings()
        let italian = "Vorrei prenotare un tavolo per due persone stasera, per favore."
        settings.apply(to: speech)
        #expect(speech.prepare(text: italian)?.detection.language != .it)
        settings.add(.it)
        settings.apply(to: speech)
        #expect(speech.prepare(text: italian)?.detection.language == .it)
    }

    @Test func voiceAndSpeedPerLanguageReachTheRequest() {
        let speech = makeController()
        let settings = AppSettings()
        settings.voices[.nl] = "nl-NL-MaartenNeural"
        settings.speeds[.nl] = 0.85
        settings.backupVoices[.nl] = "nl-NL-ColetteNeural"
        settings.apply(to: speech)

        let request = speech.prepare(text: "Ik heb vandaag heel veel zin in een kopje koffie.")?.request
        #expect(request?.voiceID == "nl-NL-MaartenNeural")
        #expect(request?.backupVoiceID == "nl-NL-ColetteNeural")
        #expect(request?.rate == 0.85)
        // An explicit rate (Speak slower) still wins.
        #expect(speech.prepare(text: "Ik heb vandaag zin in koffie.", rate: 0.7)?.request.rate == 0.7)
        // Other languages keep their defaults.
        let german = speech.prepare(text: "Ich möchte heute Abend ins Kino gehen.")?.request
        #expect(german?.voiceID == "de-DE-KatjaNeural")
        #expect(german?.rate == 1)
    }

    @Test func tiePreferenceAndEnglishVariantReachTheController() {
        let speech = makeController()
        let settings = AppSettings()
        settings.nlDeTiePreference = .de
        settings.englishVariant = .enGB
        settings.enabledLanguages.insert(.enGB)
        settings.apply(to: speech)
        #expect(speech.preferOnNLDETie == .de)
        #expect(speech.prepare(text: "The weather is lovely today, isn't it?")?.detection.language == .enGB)
    }
}
