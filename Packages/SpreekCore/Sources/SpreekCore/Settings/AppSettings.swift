import Foundation
import Observation

/// "Language badge": upper-case code or flag emoji, everywhere badges appear.
public enum BadgeStyle: String, Codable, CaseIterable, Sendable {
    case code, flag
}

/// "Detect language:".
public enum DetectionMode: String, Codable, CaseIterable, Sendable {
    /// A folder's language wins when replaying from it; everything else is detected.
    case folderThenAuto
    /// Always detect, even for sentences in a folder.
    case autoOnly
}

/// "Show bar:".
public enum FloatingBarShowMode: String, Codable, CaseIterable, Sendable {
    case whileSpeaking
    /// Only a pinned bar is shown.
    case onlyWhenPinned
}

/// "Appearance:"; applied app-wide.
public enum AppearanceMode: String, Codable, CaseIterable, Sendable {
    case system, light, dark
}

/// "App icon:" the Dock icon and its paired menu-bar glyph, always switched together. Raw values
/// name the `AppIcon-<id>` / `MenuBar-<id>` assets.
public enum AppIconChoice: String, Codable, CaseIterable, Sendable {
    /// The bundle icon.
    case snavel
    case ara, beo, nachtegaal, merel, raaf
}

/// "Show in Dock:". Launch is always menu-bar only (`LSUIElement`); the app switches the
/// activation policy at runtime.
public enum DockIconMode: String, Codable, CaseIterable, Sendable {
    case whileDashboardOpen, always, never
}

/// "Remove unkept sentences:" how long a sentence that isn't a favorite, in a folder, tagged or
/// annotated stays in History after it was last played.
public enum HistoryRetention: String, Codable, CaseIterable, Sendable {
    case never, oneWeek, oneMonth, twoMonths, threeMonths, sixMonths, oneYear

    /// Sentences last played before this date may be removed; `nil` = keep forever.
    public func cutoff(now: Date = .now, calendar: Calendar = .current) -> Date? {
        let age: DateComponents
        switch self {
        case .never: return nil
        case .oneWeek: age = DateComponents(day: -7)
        case .oneMonth: age = DateComponents(month: -1)
        case .twoMonths: age = DateComponents(month: -2)
        case .threeMonths: age = DateComponents(month: -3)
        case .sixMonths: age = DateComponents(month: -6)
        case .oneYear: age = DateComponents(year: -1)
        }
        return calendar.date(byAdding: age, to: now)
    }
}

/// "Limit audio cache:" the most audio the cache keeps; over it, the clips played longest ago
/// go first (favorites last).
public enum AudioCacheLimit: String, Codable, CaseIterable, Sendable {
    case none, mb100, mb250, mb500, gb1

    /// `nil` = no limit.
    public var bytes: Int64? {
        switch self {
        case .none: nil
        case .mb100: 100_000_000
        case .mb250: 250_000_000
        case .mb500: 500_000_000
        case .gb1: 1_000_000_000
        }
    }
}

/// Every user setting, backed by `UserDefaults` (one key per setting, so keys written by earlier
/// builds keep working). Changing a property writes it through immediately.
///
/// `Codable` for round-trips and tests; a decoded instance isn't attached to any defaults.
@Observable
public final class AppSettings: Codable {
    // MARK: Languages & Voices

    /// Never empty: the last enabled language can't be turned off.
    public var enabledLanguages: Set<LanguageCode> {
        didSet {
            if enabledLanguages.isEmpty { enabledLanguages = oldValue }
            write(enabledLanguages.map(\.rawValue).sorted(), Key.enabledLanguages)
            if !enabledLanguages.isSubset(of: listedLanguages) { listedLanguages.formUnion(enabledLanguages) }
        }
    }
    /// Rows of Settings › Languages & Voices: the enabled languages plus any switched off but not
    /// removed. "+ Add language…" offers the rest.
    public var listedLanguages: Set<LanguageCode> {
        didSet { write(listedLanguages.map(\.rawValue).sorted(), Key.listedLanguages) }
    }
    /// Chosen voice per language (Edge short name or macOS voice identifier); missing = the
    /// registry's default Edge voice.
    public var voices: [LanguageCode: String] {
        didSet { write(Self.raw(voices), Key.voices) }
    }
    /// Backup Edge voice per language, read when the chosen voice fails; missing = Auto
    /// (`BackupVoice.auto`).
    public var backupVoices: [LanguageCode: String] {
        didSet { write(Self.raw(backupVoices), Key.backupVoices) }
    }
    /// Speed multiplier per language; missing = 1.0.
    public var speeds: [LanguageCode: Double] {
        didSet { write(Self.raw(speeds), Key.speeds) }
    }
    /// The variant detected English is read in.
    public var englishVariant: LanguageCode {
        didSet { write(englishVariant.rawValue, Key.englishVariant) }
    }
    public var detectionMode: DetectionMode {
        didSet { write(detectionMode.rawValue, Key.detectionMode) }
    }
    /// "When Dutch vs. German is unclear:" — `.nl` or `.de`.
    public var nlDeTiePreference: LanguageCode {
        didSet { write(nlDeTiePreference.rawValue, Key.nlDeTiePreference) }
    }
    public var badgeStyle: BadgeStyle {
        didSet { write(badgeStyle.rawValue, Key.badgeStyle) }
    }

    // MARK: Floating bar

    public var barShowMode: FloatingBarShowMode {
        didSet { write(barShowMode.rawValue, Key.barShowMode) }
    }
    /// Seconds the finished bar stays before fading out (0…60).
    public var barHideAfterSeconds: Int {
        didSet {
            let clamped = min(max(barHideAfterSeconds, 0), Self.hideAfterRange.upperBound)
            if clamped != barHideAfterSeconds { barHideAfterSeconds = clamped }
            write(barHideAfterSeconds, Key.barHideAfterSeconds)
        }
    }
    public var barPinByDefault: Bool {
        didSet { write(barPinByDefault, Key.barPinByDefault) }
    }
    /// "Position:" mode.
    public var barPlacement: FloatingBarPlacementMode {
        didSet { write(barPlacement.rawValue, Key.barPlacement) }
    }
    /// The screen-map spot: where Fixed puts the bar, and where Where I left it starts.
    public var barPosition: FloatingBarPosition {
        didSet { write(barPosition.rawValue, Key.barPosition) }
    }
    /// Where a bar was last dragged (recorded in every mode); `nil` until the first drag.
    public var barDragPosition: FloatingBarDragPosition? {
        didSet { write(barDragPosition.flatMap { try? JSONEncoder().encode($0) }, Key.barDragPosition) }
    }
    public var highlightSpokenWord: Bool {
        didSet { write(highlightSpokenWord, Key.highlightSpokenWord) }
    }

    // MARK: Appearance

    public var appearance: AppearanceMode {
        didSet { write(appearance.rawValue, Key.appearance) }
    }
    public var appIcon: AppIconChoice {
        didSet { write(appIcon.rawValue, Key.appIcon) }
    }

    // MARK: General

    public var dockIconMode: DockIconMode {
        didSet { write(dockIconMode.rawValue, Key.dockIconMode) }
    }
    /// Opening Spreek from Spotlight, Raycast or Finder (launch or reopen) shows the Dashboard.
    /// Launch at login never does.
    public var openDashboardOnLaunch: Bool {
        didSet { write(openDashboardOnLaunch, Key.openDashboardOnLaunch) }
    }
    public var historyRetention: HistoryRetention {
        didSet { write(historyRetention.rawValue, Key.historyRetention) }
    }
    public var audioCacheLimit: AudioCacheLimit {
        didSet { write(audioCacheLimit.rawValue, Key.audioCacheLimit) }
    }
    /// Pasted rich text in notes keeps only bold and italic.
    public var notesPasteKeepsBoldItalicOnly: Bool {
        didSet { write(notesPasteKeepsBoldItalicOnly, Key.notesPasteKeepsBoldItalicOnly) }
    }
    /// edge-tts executable (or `uvx`) to try before the standard locations; `nil` = auto.
    public var edgeExecutablePath: String? {
        didSet {
            let trimmed = edgeExecutablePath?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, trimmed.isEmpty || trimmed != edgeExecutablePath {
                edgeExecutablePath = trimmed.isEmpty ? nil : trimmed
            }
            write(edgeExecutablePath, Key.edgeExecutablePath)
        }
    }
    /// "Edge engine:" which way Edge voices are reached; System is the last resort in every mode.
    public var edgeEngineMode: EdgeEngineMode {
        didSet { write(edgeEngineMode.rawValue, Key.edgeEngineMode) }
    }

    // MARK: Menu bar tiles

    public var isMuted: Bool {
        didSet { write(isMuted, Key.isMuted) }
    }
    /// Popover language tile; `nil` = auto-detect.
    public var forcedLanguage: LanguageCode? {
        didSet { write(forcedLanguage?.rawValue, Key.forcedLanguage) }
    }

    public static let hideAfterRange: ClosedRange<Int> = 0...60

    @ObservationIgnored private var defaults: UserDefaults?

    // MARK: Keys

    /// UserDefaults keys. Several predate `AppSettings` and are kept as they were.
    public enum Key {
        public static let enabledLanguages = LanguagePreferences.enabledKey
        public static let listedLanguages = "languages.listed"
        public static let voices = "languages.voices"
        public static let speeds = "languages.speeds"
        public static let backupVoices = "languages.backupVoices"
        public static let englishVariant = LanguagePreferences.englishVariantKey
        public static let detectionMode = "languages.detectionMode"
        public static let nlDeTiePreference = "languages.nlDeTiePreference"
        public static let badgeStyle = "languageBadgeStyle"
        public static let barShowMode = "floatingBar.showMode"
        public static let barHideAfterSeconds = "floatingBar.autoHideSeconds"
        public static let barPinByDefault = "floatingBar.pinByDefault"
        public static let barPlacement = "floatingBar.placement"
        public static let barPosition = "floatingBar.position"
        public static let barDragPosition = "floatingBar.dragPosition"
        public static let highlightSpokenWord = "floatingBar.highlightWord"
        public static let appearance = "app.appearance"
        public static let appIcon = "app.icon"
        public static let dockIconMode = "app.dockIconMode"
        public static let openDashboardOnLaunch = "app.openDashboardOnLaunch"
        public static let historyRetention = "library.retention"
        public static let audioCacheLimit = "storage.audioCacheLimit"
        public static let notesPasteKeepsBoldItalicOnly = "notes.pasteKeepsBoldItalicOnly"
        public static let edgeExecutablePath = "engines.edgeExecutablePath"
        public static let edgeEngineMode = "edge.engineMode"
        public static let isMuted = "speech.muted"
        public static let forcedLanguage = "speech.forcedLanguage"
        /// Global speed of early versions; becomes every enabled language's speed on first load.
        public static let legacyRate = "speech.rate"
    }

    // MARK: Init

    /// Defaults for everything, not attached to any `UserDefaults`.
    public init() {
        enabledLanguages = LanguageCode.defaultEnabled
        listedLanguages = LanguageCode.defaultEnabled
        voices = [:]
        backupVoices = [:]
        speeds = [:]
        englishVariant = .enUS
        detectionMode = .folderThenAuto
        nlDeTiePreference = .nl
        badgeStyle = .code
        barShowMode = .whileSpeaking
        barHideAfterSeconds = 3
        barPinByDefault = false
        barPlacement = .fixed
        barPosition = .bottomCenter
        barDragPosition = nil
        highlightSpokenWord = true
        appearance = .system
        appIcon = .snavel
        dockIconMode = .whileDashboardOpen
        openDashboardOnLaunch = false
        historyRetention = .never
        audioCacheLimit = .none
        notesPasteKeepsBoldItalicOnly = true
        edgeExecutablePath = nil
        edgeEngineMode = .automatic
        isMuted = false
        forcedLanguage = nil
    }

    /// Loads from `defaults` (missing keys get their default) and writes changes back to it.
    public convenience init(defaults: UserDefaults) {
        self.init()
        load(from: defaults)
        self.defaults = defaults
    }

    private func load(from defaults: UserDefaults) {
        enabledLanguages = LanguagePreferences.enabled(in: defaults)
        listedLanguages = Set((defaults.stringArray(forKey: Key.listedLanguages) ?? []).compactMap(LanguageCode.init(rawValue:)))
            .union(enabledLanguages)
        englishVariant = LanguagePreferences.englishVariant(in: defaults)
        voices = Self.decodeDictionary(defaults.dictionary(forKey: Key.voices)) { $0 as? String }
        backupVoices = Self.decodeDictionary(defaults.dictionary(forKey: Key.backupVoices)) { $0 as? String }
        speeds = Self.decodeDictionary(defaults.dictionary(forKey: Key.speeds)) { ($0 as? NSNumber)?.doubleValue }
            .mapValues(Self.clampSpeed)
        if defaults.object(forKey: Key.speeds) == nil, defaults.object(forKey: Key.legacyRate) != nil {
            let legacy = Self.clampSpeed(defaults.double(forKey: Key.legacyRate))
            if abs(legacy - 1) > 0.001 {
                speeds = Dictionary(uniqueKeysWithValues: enabledLanguages.map { ($0, legacy) })
            }
        }
        detectionMode = Self.enumValue(defaults, Key.detectionMode) ?? detectionMode
        if let tie = defaults.string(forKey: Key.nlDeTiePreference).flatMap(LanguageCode.init(rawValue:)),
           [.nl, .de].contains(tie) {
            nlDeTiePreference = tie
        }
        badgeStyle = Self.enumValue(defaults, Key.badgeStyle) ?? badgeStyle
        barShowMode = Self.enumValue(defaults, Key.barShowMode) ?? barShowMode
        if defaults.object(forKey: Key.barHideAfterSeconds) != nil {
            barHideAfterSeconds = defaults.integer(forKey: Key.barHideAfterSeconds)
        }
        barPinByDefault = defaults.bool(forKey: Key.barPinByDefault)
        barPlacement = Self.enumValue(defaults, Key.barPlacement) ?? barPlacement
        barPosition = Self.enumValue(defaults, Key.barPosition) ?? barPosition
        barDragPosition = defaults.data(forKey: Key.barDragPosition)
            .flatMap { try? JSONDecoder().decode(FloatingBarDragPosition.self, from: $0) }
        highlightSpokenWord = defaults.object(forKey: Key.highlightSpokenWord) as? Bool ?? highlightSpokenWord
        appearance = Self.enumValue(defaults, Key.appearance) ?? appearance
        appIcon = Self.enumValue(defaults, Key.appIcon) ?? appIcon
        dockIconMode = Self.enumValue(defaults, Key.dockIconMode) ?? dockIconMode
        openDashboardOnLaunch = defaults.bool(forKey: Key.openDashboardOnLaunch)
        historyRetention = Self.enumValue(defaults, Key.historyRetention) ?? historyRetention
        audioCacheLimit = Self.enumValue(defaults, Key.audioCacheLimit) ?? audioCacheLimit
        notesPasteKeepsBoldItalicOnly = defaults.object(forKey: Key.notesPasteKeepsBoldItalicOnly) as? Bool
            ?? notesPasteKeepsBoldItalicOnly
        edgeExecutablePath = defaults.string(forKey: Key.edgeExecutablePath)
        edgeEngineMode = Self.enumValue(defaults, Key.edgeEngineMode) ?? edgeEngineMode
        isMuted = defaults.bool(forKey: Key.isMuted)
        forcedLanguage = defaults.string(forKey: Key.forcedLanguage).flatMap(LanguageCode.init(rawValue:))
    }

    // MARK: Derived

    /// The voice `language` is read with.
    public func voice(for language: LanguageCode) -> String {
        voices[language] ?? language.info.defaultEdgeVoice
    }

    public func speed(for language: LanguageCode) -> Double {
        speeds[language] ?? 1
    }

    /// Either English variant is enabled (shows the "English variant" row).
    public var isEnglishEnabled: Bool {
        LanguageCode.englishVariants.contains(where: enabledLanguages.contains)
    }

    /// Settings rows, by native name.
    public var listedLanguagesSorted: [LanguageCode] {
        LanguageCode.sortedByName.filter(listedLanguages.contains)
    }

    /// Languages not listed yet, by native name ("+ Add language…").
    public var addableLanguages: [LanguageCode] {
        LanguageCode.sortedByName.filter { !listedLanguages.contains($0) }
    }

    public func setEnabled(_ enabled: Bool, _ language: LanguageCode) {
        if enabled { enabledLanguages.insert(language) } else { enabledLanguages.remove(language) }
    }

    /// Lists and enables `language`.
    public func add(_ language: LanguageCode) {
        listedLanguages.insert(language)
        enabledLanguages.insert(language)
    }

    /// The last enabled language can't be removed.
    public func canRemove(_ language: LanguageCode) -> Bool {
        enabledLanguages != [language]
    }

    /// Unlists and disables `language` and forgets its voice and speed.
    public func remove(_ language: LanguageCode) {
        guard canRemove(language) else { return }
        enabledLanguages.remove(language)
        listedLanguages.remove(language)
        voices[language] = nil
        backupVoices[language] = nil
        speeds[language] = nil
        if forcedLanguage == language { forcedLanguage = nil }
    }

    /// The folder language to pass to detection for a sentence in a folder with `language`.
    public func folderLanguage(_ language: LanguageCode?) -> LanguageCode? {
        detectionMode == .folderThenAuto ? language : nil
    }

    public var floatingBarSettings: FloatingBarSettings {
        FloatingBarSettings(
            autoHideSeconds: barHideAfterSeconds, pinByDefault: barPinByDefault,
            showsWhileSpeaking: barShowMode == .whileSpeaking
        )
    }

    /// Pushes the speech-related settings into `speech` (detection constraints, voices, speeds).
    @MainActor
    public func apply(to speech: SpeechController) {
        speech.enabledLanguages = enabledLanguages
        speech.englishVariant = englishVariant
        speech.preferOnNLDETie = nlDeTiePreference
        speech.voiceOverrides = voices
        speech.backupVoiceOverrides = backupVoices
        speech.rateOverrides = speeds
        speech.forcedLanguage = forcedLanguage
        speech.isMuted = isMuted
    }

    public static func clampSpeed(_ speed: Double) -> Double {
        min(max(speed, SpeechController.rateRange.lowerBound), SpeechController.rateRange.upperBound)
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case enabledLanguages, listedLanguages, voices, backupVoices, speeds, englishVariant, detectionMode, nlDeTiePreference, badgeStyle
        case barShowMode, barHideAfterSeconds, barPinByDefault, barPlacement, barPosition, barDragPosition, highlightSpokenWord
        case appearance, appIcon, dockIconMode, openDashboardOnLaunch, historyRetention, audioCacheLimit, notesPasteKeepsBoldItalicOnly, edgeExecutablePath, edgeEngineMode, isMuted, forcedLanguage
    }

    /// Missing keys decode to their defaults, so older payloads still load.
    public required convenience init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let codes = try c.decodeIfPresent(Set<LanguageCode>.self, forKey: .enabledLanguages), !codes.isEmpty {
            enabledLanguages = codes
        }
        listedLanguages = (try c.decodeIfPresent(Set<LanguageCode>.self, forKey: .listedLanguages) ?? [])
            .union(enabledLanguages)
        voices = Self.languageKeyed(try c.decodeIfPresent([String: String].self, forKey: .voices))
        backupVoices = Self.languageKeyed(try c.decodeIfPresent([String: String].self, forKey: .backupVoices))
        speeds = Self.languageKeyed(try c.decodeIfPresent([String: Double].self, forKey: .speeds))
        englishVariant = try c.decodeIfPresent(LanguageCode.self, forKey: .englishVariant) ?? englishVariant
        detectionMode = try c.decodeIfPresent(DetectionMode.self, forKey: .detectionMode) ?? detectionMode
        nlDeTiePreference = try c.decodeIfPresent(LanguageCode.self, forKey: .nlDeTiePreference) ?? nlDeTiePreference
        badgeStyle = try c.decodeIfPresent(BadgeStyle.self, forKey: .badgeStyle) ?? badgeStyle
        barShowMode = try c.decodeIfPresent(FloatingBarShowMode.self, forKey: .barShowMode) ?? barShowMode
        barHideAfterSeconds = try c.decodeIfPresent(Int.self, forKey: .barHideAfterSeconds) ?? barHideAfterSeconds
        barPinByDefault = try c.decodeIfPresent(Bool.self, forKey: .barPinByDefault) ?? barPinByDefault
        barPlacement = try c.decodeIfPresent(FloatingBarPlacementMode.self, forKey: .barPlacement) ?? barPlacement
        barPosition = try c.decodeIfPresent(FloatingBarPosition.self, forKey: .barPosition) ?? barPosition
        barDragPosition = try c.decodeIfPresent(FloatingBarDragPosition.self, forKey: .barDragPosition)
        highlightSpokenWord = try c.decodeIfPresent(Bool.self, forKey: .highlightSpokenWord) ?? highlightSpokenWord
        appearance = try c.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? appearance
        appIcon = try c.decodeIfPresent(AppIconChoice.self, forKey: .appIcon) ?? appIcon
        dockIconMode = try c.decodeIfPresent(DockIconMode.self, forKey: .dockIconMode) ?? dockIconMode
        openDashboardOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .openDashboardOnLaunch) ?? openDashboardOnLaunch
        historyRetention = try c.decodeIfPresent(HistoryRetention.self, forKey: .historyRetention) ?? historyRetention
        audioCacheLimit = try c.decodeIfPresent(AudioCacheLimit.self, forKey: .audioCacheLimit) ?? audioCacheLimit
        notesPasteKeepsBoldItalicOnly = try c.decodeIfPresent(Bool.self, forKey: .notesPasteKeepsBoldItalicOnly)
            ?? notesPasteKeepsBoldItalicOnly
        edgeExecutablePath = try c.decodeIfPresent(String.self, forKey: .edgeExecutablePath)
        edgeEngineMode = try c.decodeIfPresent(EdgeEngineMode.self, forKey: .edgeEngineMode) ?? edgeEngineMode
        isMuted = try c.decodeIfPresent(Bool.self, forKey: .isMuted) ?? isMuted
        forcedLanguage = try c.decodeIfPresent(LanguageCode.self, forKey: .forcedLanguage)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabledLanguages.map(\.rawValue).sorted(), forKey: .enabledLanguages)
        try c.encode(listedLanguages.map(\.rawValue).sorted(), forKey: .listedLanguages)
        try c.encode(Self.raw(voices), forKey: .voices)
        try c.encode(Self.raw(backupVoices), forKey: .backupVoices)
        try c.encode(Self.raw(speeds), forKey: .speeds)
        try c.encode(englishVariant, forKey: .englishVariant)
        try c.encode(detectionMode, forKey: .detectionMode)
        try c.encode(nlDeTiePreference, forKey: .nlDeTiePreference)
        try c.encode(badgeStyle, forKey: .badgeStyle)
        try c.encode(barShowMode, forKey: .barShowMode)
        try c.encode(barHideAfterSeconds, forKey: .barHideAfterSeconds)
        try c.encode(barPinByDefault, forKey: .barPinByDefault)
        try c.encode(barPlacement, forKey: .barPlacement)
        try c.encode(barPosition, forKey: .barPosition)
        try c.encodeIfPresent(barDragPosition, forKey: .barDragPosition)
        try c.encode(highlightSpokenWord, forKey: .highlightSpokenWord)
        try c.encode(appearance, forKey: .appearance)
        try c.encode(appIcon, forKey: .appIcon)
        try c.encode(dockIconMode, forKey: .dockIconMode)
        try c.encode(openDashboardOnLaunch, forKey: .openDashboardOnLaunch)
        try c.encode(historyRetention, forKey: .historyRetention)
        try c.encode(audioCacheLimit, forKey: .audioCacheLimit)
        try c.encode(notesPasteKeepsBoldItalicOnly, forKey: .notesPasteKeepsBoldItalicOnly)
        try c.encodeIfPresent(edgeExecutablePath, forKey: .edgeExecutablePath)
        try c.encode(edgeEngineMode, forKey: .edgeEngineMode)
        try c.encode(isMuted, forKey: .isMuted)
        try c.encodeIfPresent(forcedLanguage, forKey: .forcedLanguage)
    }

    // MARK: Helpers

    private func write(_ value: Any?, _ key: String) {
        guard let defaults else { return }
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    private static func raw<V>(_ dictionary: [LanguageCode: V]) -> [String: V] {
        Dictionary(uniqueKeysWithValues: dictionary.map { ($0.key.rawValue, $0.value) })
    }

    private static func languageKeyed<V>(_ dictionary: [String: V]?) -> [LanguageCode: V] {
        var result: [LanguageCode: V] = [:]
        for (key, value) in dictionary ?? [:] {
            if let code = LanguageCode(rawValue: key) { result[code] = value }
        }
        return result
    }

    private static func decodeDictionary<V>(_ dictionary: [String: Any]?, _ cast: (Any) -> V?) -> [LanguageCode: V] {
        languageKeyed(dictionary?.compactMapValues(cast))
    }

    private static func enumValue<E: RawRepresentable>(_ defaults: UserDefaults, _ key: String) -> E? where E.RawValue == String {
        defaults.string(forKey: key).flatMap(E.init(rawValue:))
    }
}
