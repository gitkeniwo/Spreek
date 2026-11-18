import AppKit
import Observation
import OSLog
import SpreekCore
import SwiftData
import SwiftUI

/// App-wide objects shared by the menu bar, hotkeys and the Services provider.
@MainActor
@Observable
final class AppModel {
    /// Every user setting (UserDefaults-backed); changes are pushed to speech, bar, Dock and
    /// appearance by `observeSettings()`.
    let settings = AppSettings(defaults: .standard)
    let speech: SpeechController
    /// Edge voice health memory and voice list (Settings, floating bar hints).
    let voiceHealth: VoiceHealthModel
    let permission = AccessibilityPermission()
    let pipeline: SpeakPipeline
    /// The one shared SwiftData container (Application Support/Spreek/Library.store).
    let container: ModelContainer
    let library: LibraryStore
    /// Floating bar visibility and countdown; also the shared pin state.
    let bar: FloatingBarModel
    /// The sentence spoken most recently in this session (⌥F target).
    private(set) var lastSentence: Sentence?
    /// Short feedback for the popover ("Nothing selected", …).
    private(set) var statusMessage: String?
    /// Dashboard route, selection and filters.
    let dashboard = DashboardState()
    /// Edge / macOS voices per language for pickers (loaded lazily).
    let voices = VoiceDirectory()
    /// Settings › Engines status (Edge test synthesis).
    let engines = EngineStatus()
    /// Settings › General › Launch at login.
    let loginItem = LoginItem()
    /// Settings › Storage report, clean-ups and the audio cache limit.
    let storage: StorageModel
    /// Dock icon while the dashboard is open (`app.dockIconMode`).
    @ObservationIgnored let dockIcon: DockIconController
    /// Captured from the always-present menu bar label so AppKit-hosted views (the floating
    /// panel) can open SwiftUI windows.
    @ObservationIgnored var openWindowAction: OpenWindowAction?
    /// The menu bar popover's window, recorded by the popover itself (SwiftUI offers no way to
    /// dismiss a `MenuBarExtra(.window)`).
    @ObservationIgnored weak var menuBarWindow: NSWindow?

    @ObservationIgnored private let logger = Logger(subsystem: "nl.spreek.app", category: "capture")
    @ObservationIgnored private var historyCursor: HistoryCursor<PersistentIdentifier>?
    /// "Play all" playlist: sentences still to play, next first.
    @ObservationIgnored private var playlist: [PersistentIdentifier] = []
    @ObservationIgnored private var appliedRetention: HistoryRetention?
    @ObservationIgnored private var appliedCacheLimit: AudioCacheLimit?

    init() {
        let voiceHealth = VoiceHealthModel()
        self.voiceHealth = voiceHealth
        speech = SpeechController.live(
            edgeMode: settings.edgeEngineMode, edgeExecutablePath: settings.edgeExecutablePath,
            health: voiceHealth.health, catalog: voiceHealth.catalog
        )
        dockIcon = DockIconController(settings: settings)
        voices.edgeExecutablePath = settings.edgeExecutablePath
        voices.edgeMode = settings.edgeEngineMode
        pipeline = SpeakPipeline(reader: SelectionReader(), speech: speech)
        let isFirstRun = !FileManager.default.fileExists(atPath: LibraryStore.defaultStoreURL.path)
        container = Self.makeContainer()
        let audioRemover = CachedAudioRemover()
        library = LibraryStore(context: container.mainContext, removeCachedAudio: { text, voiceID in
            audioRemover.remove(text: text, voiceID: voiceID)
        })
        storage = StorageModel(library: library, speech: speech, settings: settings)
        // A library that didn't exist yet gets one example sentence per language (once: later
        // launches find the store, even if the user has deleted them all).
        #if DEBUG
        let seedsSamples = isFirstRun && !UserDefaults.standard.bool(forKey: "SpreekDebugInMemoryLibrary")
        #else
        let seedsSamples = isFirstRun
        #endif
        if seedsSamples { library.insertFirstRunSamples() }
        bar = FloatingBarModel(settings: settings.floatingBarSettings)
        NoteSettings.settings = settings
        speech.onSpoken = { [weak self] utterance in
            guard let self else { return }
            // A new clip may have pushed the cache over its limit.
            if self.settings.audioCacheLimit != .none { self.storage.applyCacheLimit() }
            guard utterance.source != .preview else { return }
            self.record(utterance)
            self.bar.speechChanged(.active, isNewSpeech: true)
        }
        storage.pruneHistory = { [weak self] in self?.pruneHistory() }
        installVoiceFailureHook()
        observeSpeechState()
        observeSettings()
        // A fresh voice list a few seconds after launch, off the speech path.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self else { return }
            self.voiceHealth.refreshInBackgroundIfNeeded(mode: self.settings.edgeEngineMode, path: self.settings.edgeExecutablePath)
        }
    }

    /// After a voice fails on its own, the voice list may have changed: refresh it (at most hourly).
    private func installVoiceFailureHook() {
        speech.chain.onVoiceFailure = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.voiceHealth.refreshAfterFailure(mode: self.settings.edgeEngineMode, path: self.settings.edgeExecutablePath)
            }
        }
    }

    /// Applies the settings now and again after every change.
    private func observeSettings() {
        withObservationTracking {
            applySettings()
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeSettings()
            }
        }
    }

    private func applySettings() {
        settings.apply(to: speech)
        if bar.settings != settings.floatingBarSettings { bar.settings = settings.floatingBarSettings }
        let path = settings.edgeExecutablePath
        let mode = settings.edgeEngineMode
        if voices.edgeExecutablePath != path || voices.edgeMode != mode {
            voices.edgeExecutablePath = path
            voices.edgeMode = mode
            speech.chain = .live(mode: mode, edgeExecutablePath: path, health: voiceHealth.health, catalog: voiceHealth.catalog)
            installVoiceFailureHook()
        }
        dockIcon.modeChanged(settings.dockIconMode)
        dockIcon.iconChanged(settings.appIcon)
        if settings.historyRetention != appliedRetention {
            appliedRetention = settings.historyRetention
            pruneHistory()
        }
        if settings.audioCacheLimit != appliedCacheLimit {
            appliedCacheLimit = settings.audioCacheLimit
            storage.applyCacheLimit()
        }
        Self.applyAppearance(settings.appearance)
    }

    static func applyAppearance(_ mode: AppearanceMode) {
        let appearance: NSAppearance? = switch mode {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        if NSApp.appearance?.name != appearance?.name { NSApp.appearance = appearance }
    }

    /// Feeds every playback state change to the floating bar.
    private func observeSpeechState() {
        withObservationTracking {
            _ = speech.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.bar.speechChanged(FloatingBarModel.SpeechActivity(self.speech.state))
                if case .finished = self.speech.state { self.playNextInPlaylist() }
                self.observeSpeechState()
            }
        }
    }

    private static func makeContainer() -> ModelContainer {
        #if DEBUG
        // Screenshots and manual checks without touching the real library.
        if UserDefaults.standard.bool(forKey: "SpreekDebugInMemoryLibrary"),
           let container = try? LibraryStore.makeContainer(inMemory: true) {
            return container
        }
        #endif
        do {
            return try LibraryStore.makeContainer()
        } catch {
            // Keep the app usable (speech still works); history just won't persist this run.
            Logger(subsystem: "nl.spreek.app", category: "library").error("Opening the library failed: \(error)")
            do {
                return try LibraryStore.makeContainer(inMemory: true)
            } catch {
                fatalError("Cannot create an in-memory library: \(error)")
            }
        }
    }

    /// Every playback that actually starts is saved (or bumps the existing row).
    private func record(_ utterance: SpokenUtterance) {
        var source = SpokenSource(kind: utterance.source)
        if let capture = pipeline.lastCapture,
           utterance.source == .selection || utterance.source == .services,
           TextNormalizer.normalize(capture.text) == utterance.text {
            source.appName = capture.appName
            source.url = capture.url
            source.bundleID = capture.bundleID
        }
        lastSentence = library.recordSpoken(
            text: utterance.text, language: utterance.language, voiceID: utterance.voiceID, source: source
        )
    }

    /// Speaks a library sentence; a folder's language, voice speed and source win over detection
    /// (unless Settings › Detect language is "Always auto-detect").
    /// `rate` (the dashboard's practice speed) overrides the folder's and language's speed.
    func replay(_ sentence: Sentence, rate: Double? = nil) {
        let folder = sentence.folder
        if let folder, settings.detectionMode == .folderThenAuto, let language = folder.language, let voiceID = folder.voiceID {
            speech.speak(text: sentence.text, language: language, voiceID: voiceID, rate: rate ?? folder.speed, source: .folder)
        } else {
            speech.speak(
                text: sentence.text, folderLanguage: settings.folderLanguage(folder?.language),
                rate: rate ?? folder?.speed, source: folder == nil ? .history : .folder
            )
        }
    }

    /// `sentence` is the one playing or paused right now.
    func isPlayingOrPaused(_ sentence: Sentence) -> Bool {
        guard currentSentence?.persistentModelID == sentence.persistentModelID else { return false }
        switch speech.state {
        case .playing, .paused: return true
        default: return false
        }
    }

    /// Space / the detail play button: pauses or resumes `sentence` where it is when it's the
    /// current one (no new synthesis), otherwise plays it from the start.
    func playOrPause(_ sentence: Sentence) {
        if isPlayingOrPaused(sentence) {
            speech.togglePause()
        } else {
            replay(sentence, rate: practiceSpeed)
        }
    }

    /// New tag with the next color in the palette.
    @discardableResult
    func createTag(named name: String) -> Tag {
        let colors = TagColor.allCases
        return library.createTag(name: name, color: colors[library.tags().count % colors.count].rawValue)
    }

    /// Deletes sentences (and their cached audio), dropping any reference the app still holds.
    func delete(_ sentences: [Sentence]) {
        let ids = Set(sentences.map(\.persistentModelID))
        if let last = lastSentence, ids.contains(last.persistentModelID) { lastSentence = nil }
        historyCursor = nil
        playlist.removeAll { ids.contains($0) }
        dashboard.selection.subtract(ids)
        if let focused = dashboard.focused, ids.contains(focused) { dashboard.focused = nil }
        for sentence in sentences { library.delete(sentence) }
    }

    /// Removes sentences the History retention setting no longer keeps (with their audio).
    /// Runs at launch, when the setting changes and when the Dashboard opens.
    func pruneHistory() {
        guard let cutoff = settings.historyRetention.cutoff() else { return }
        let stale = library.unkeptSentences(lastPlayedBefore: cutoff)
        if !stale.isEmpty { delete(stale) }
    }

    /// Plays `sentences` one after another (dashboard "Play all").
    func playAll(_ sentences: [Sentence]) {
        playlist = sentences.map(\.persistentModelID)
        playNextInPlaylist()
    }

    private func playNextInPlaylist() {
        while !playlist.isEmpty {
            let id = playlist.removeFirst()
            if let sentence = library.context.model(for: id) as? Sentence, !sentence.isDeleted {
                replay(sentence)
                return
            }
        }
    }

    func speakSelection(slower: Bool = false) {
        playlist = []
        permission.refresh()
        guard permission.isTrusted else {
            statusMessage = "Spreek needs Accessibility access to read the selection."
            permission.requestWithSystemPrompt()
            return
        }
        Task {
            let outcome = await pipeline.speakSelection(rate: slower ? SpeakPipeline.slowerRate : nil)
            report(outcome)
        }
    }

    func speakServiceText(_ text: String) {
        playlist = []
        let source = SelectionReader.frontmostSource()
        report(pipeline.speak(CapturedSelection(text: text, method: .services, appName: source.name, bundleID: source.bundleID)))
    }

    /// Speaks the clipboard's text; no Accessibility access needed.
    func speakClipboard() {
        playlist = []
        let outcome = NSPasteboard.general.string(forType: .string)
            .map { pipeline.speak(CapturedSelection(text: $0, method: .clipboard)) } ?? .empty
        report(outcome)
        if case .empty = outcome { statusMessage = "The clipboard has no text to speak." }
    }

    func replayLast() {
        speech.replay()
    }

    // MARK: Now speaking

    /// The library row of what the speech controller is (or was last) speaking.
    var currentSentence: Sentence? {
        guard let sentence = lastSentence, let text = speech.currentText,
              LibraryStore.normalizedKey(for: sentence.text) == LibraryStore.normalizedKey(for: text)
        else { return nil }
        return sentence
    }

    /// Both engines failed on the current sentence (floating bar toast).
    var speechFailure: String? {
        guard case .failed(let error) = speech.state else { return nil }
        return "Edge and macOS voices both failed — \(error.localizedDescription)"
    }

    /// The spoken word in the floating bar, unless Settings › Highlight spoken word is off.
    var barHighlightRange: Range<String.Index>? {
        settings.highlightSpokenWord ? speech.highlightedRange : nil
    }

    /// Language shown on the popover tile: the current / last detected one.
    var displayLanguage: LanguageCode {
        speech.language ?? speech.forcedLanguage ?? lastSentence?.effectiveLanguage ?? library.recent(limit: 1).first?.effectiveLanguage ?? .nl
    }

    /// Big pause / play glyph.
    func togglePlayback() {
        switch speech.state {
        case .playing, .paused, .finished: speech.togglePause()
        case .idle, .failed:
            if let sentence = currentSentence ?? lastSentence { replay(sentence) }
        case .synthesizing: break
        }
    }

    /// Speed pill: the current sentence again at `rate`, same voice.
    func replayCurrent(at rate: Double) {
        speech.replay(rate: rate)
    }

    /// Bar voice menu: makes `voiceID` the voice for `language` and plays the current sentence
    /// again with it, same speed.
    func useVoice(_ voiceID: String, for language: LanguageCode) {
        settings.voices[language] = voiceID == language.info.defaultEdgeVoice ? nil : voiceID
        guard let text = speech.currentText, speech.language == language else { return }
        speech.speak(text: text, language: language, voiceID: voiceID, rate: speech.currentRate, source: speech.source ?? .history)
    }

    /// Speed shown on the speed pills: the loaded sentence's, else the configured one.
    var playbackRate: Double { speech.currentRate ?? rate }

    /// Dashboard "Practice speed"; `nil` = the folder's or language's own speed.
    var practiceSpeed: Double? {
        get {
            access(keyPath: \.practiceSpeed)
            let value = UserDefaults.standard.double(forKey: "dashboard.practiceSpeed")
            return SpeechController.speedChoices.contains(value) ? value : nil
        }
        set {
            withMutation(keyPath: \.practiceSpeed) {
                UserDefaults.standard.set(newValue ?? 0, forKey: "dashboard.practiceSpeed")
            }
        }
    }

    func toggleFavorite(_ sentence: Sentence) {
        library.toggleFavorite(sentence)
    }

    /// Backward: the previous (older) sentence in the history.
    func playPrevious() { step(older: true) }

    /// Forward: the next (newer) sentence in the history.
    func playNext() { step(older: false) }

    private func step(older: Bool) {
        let currentID = (currentSentence ?? lastSentence)?.persistentModelID
        if historyCursor == nil || historyCursor?.current != currentID {
            historyCursor = HistoryCursor(items: library.recent(limit: 500).map(\.persistentModelID), current: currentID)
        }
        guard let id = older ? historyCursor?.older() : historyCursor?.newer(),
              let sentence = library.context.model(for: id) as? Sentence
        else { return }
        lastSentence = sentence
        replay(sentence)
    }

    var canPlayPrevious: Bool { !library.recent(limit: 2).isEmpty }

    // MARK: Popover tiles

    var isMuted: Bool {
        get { settings.isMuted }
        set { settings.isMuted = newValue }
    }

    /// Enabled languages by name for pickers, plus `current` if it's disabled
    /// (so an existing choice stays visible).
    func pickerLanguages(including current: LanguageCode? = nil) -> [LanguageCode] {
        LanguageCode.sortedByName.filter { settings.enabledLanguages.contains($0) || $0 == current }
    }

    /// `nil` = auto-detect.
    var forcedLanguage: LanguageCode? {
        get { settings.forcedLanguage }
        set { settings.forcedLanguage = newValue }
    }

    /// Popover speed tile: the speed of the language shown on the language tile (the same value
    /// as its Speed popup in Settings › Languages & Voices).
    var rate: Double {
        get { settings.speed(for: forcedLanguage ?? displayLanguage) }
        set { settings.speeds[forcedLanguage ?? displayLanguage] = AppSettings.clampSpeed(newValue) }
    }

    /// Settings › Test ▶: a sample in `language` with its configured voice and speed, not recorded.
    func testVoice(for language: LanguageCode) {
        speech.speak(
            text: LanguageSamples.sentence(for: language), language: language,
            voiceID: settings.voice(for: language), rate: settings.speed(for: language), source: .preview
        )
    }

    /// Menu-bar pin tile and the bar's pin button.
    func setBarPinned(_ pinned: Bool) {
        bar.setPinned(pinned)
        if pinned, speech.currentText != nil {
            bar.reveal(isPlaying: FloatingBarModel.SpeechActivity(speech.state) == .active)
        }
    }

    /// Bar close button: hides the bar and stops speaking.
    func closeBar() {
        bar.close()
        if FloatingBarModel.SpeechActivity(speech.state) == .active { speech.stop() }
    }

    // MARK: Windows

    func openDashboard(_ route: DashboardRoute? = nil) {
        pruneHistory()
        if let route { dashboard.show(route) }
        dockIcon.prepareForDashboard()
        openWindowAction?(id: "dashboard")
        bringDashboardToFront()
    }

    /// LSUIElement apps don't come to the front on their own. While the popover is still the key
    /// window the app is active, so the dashboard is brought forward and made key first; only
    /// then is the popover closed. Closing it first leaves the app without a key window, macOS
    /// hands the focus back to the previous app, and a background app can't take it again.
    private func bringDashboardToFront() {
        @MainActor func front() -> Bool {
            NSApp.activate(ignoringOtherApps: true)
            guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("dashboard") == true }) else {
                return false
            }
            window.makeKeyAndOrderFront(nil)
            logger.info("dashboard front: active=\(NSApp.isActive) key=\(window.isKeyWindow)")
            return window.isKeyWindow
        }
        _ = front()
        Task { @MainActor in
            // The window appears a moment after `openWindow`.
            for _ in 0..<20 {
                if front() { break }
                try? await Task.sleep(for: .milliseconds(25))
            }
            closeMenuBarPopover()
            for delay in [50, 150, 400] {
                try? await Task.sleep(for: .milliseconds(delay))
                if NSApp.isActive, NSApp.keyWindow?.identifier?.rawValue.hasPrefix("dashboard") == true { return }
                _ = front()
            }
        }
    }

    /// Closes the menu bar popover if it's open. Clicking the status item (rather than ordering
    /// the window out) keeps the icon's highlight and the next click in sync.
    func closeMenuBarPopover() {
        guard let window = menuBarWindow, window.isVisible else { return }
        if let button = Self.statusItemButton() {
            button.performClick(nil)
        } else {
            window.orderOut(nil)
        }
    }

    /// The Spreek status item's button.
    static func statusItemButton() -> NSStatusBarButton? {
        func find(in view: NSView) -> NSStatusBarButton? {
            if let button = view as? NSStatusBarButton { return button }
            for subview in view.subviews { if let found = find(in: subview) { return found } }
            return nil
        }
        for window in NSApp.windows where String(describing: type(of: window)).contains("StatusBar") {
            if let view = window.contentView, let button = find(in: view) { return button }
        }
        return nil
    }

    /// ⌘F in the dashboard.
    func focusSearch() {
        dashboard.focusSearch()
        openDashboard()
    }

    /// Floating bar button: the dashboard's History with `sentence` selected and visible.
    func openDashboard(selecting sentence: Sentence?) {
        guard let sentence else { return openDashboard() }
        dashboard.show(.history)
        dashboard.query.text = ""
        dashboard.query.language = nil
        dashboard.onlyWithNotes = false
        dashboard.collapsedDays.remove(library.calendar.startOfDay(for: dashboard.query.sort.date(of: sentence)))
        dashboard.select(sentence.persistentModelID)
        openDashboard()
    }

    /// ⌥F: toggles the favorite of the current / last spoken sentence.
    func saveFavorite() {
        guard let sentence = lastSentence ?? library.recent(limit: 1).first else {
            statusMessage = "Nothing to save yet."
            return
        }
        library.toggleFavorite(sentence)
        statusMessage = sentence.isFavorite ? "Added to Favorites." : "Removed from Favorites."
    }

    private func report(_ outcome: SpeakPipeline.Outcome) {
        switch outcome {
        case .speaking(let prepared):
            statusMessage = nil
            let capture = pipeline.lastCapture
            logger.info("Speaking \(prepared.text.count) chars via \(capture?.method.rawValue ?? "?") from \(capture?.bundleID ?? "?")")
        case .nothingSelected:
            statusMessage = "Nothing selected."
        case .empty:
            statusMessage = "The selection has no text to speak."
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var services: ServicesProvider?
    private var floatingBar: FloatingPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.dockIcon.applyLaunchPolicy()
        Hotkeys.register(model)
        floatingBar = FloatingPanelController(model: model)
        #if DEBUG
        runDebugLaunchActions()
        #endif
        let services = ServicesProvider(model: model)
        self.services = services
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
        if model.settings.openDashboardOnLaunch, !Self.launchedAsLoginItem {
            Task { @MainActor in
                // The menu bar label hands over `openWindow` once it's on screen.
                for _ in 0..<40 where model.openWindowAction == nil {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                model.openDashboard()
            }
        }
    }

    /// Opening Spreek again (Spotlight, Raycast, Finder, or the Dock icon) brings the dashboard
    /// forward. Without a Dock icon that only happens when "Open Dashboard on launch" is on.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if model.settings.openDashboardOnLaunch || NSApp.activationPolicy() == .regular {
            model.openDashboard()
        }
        return false
    }

    /// Launched by Launch at login rather than by the user.
    private static var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}

#if DEBUG
extension AppDelegate {
    /// Launch arguments for manual checks and screenshots, e.g.
    /// `-SpreekDebugSpeak "Dit. Gezeik blijft maar doorgaan." -SpreekDebugOpenPopover YES`.
    /// (`-floatingBar.autoHideSeconds 30`, `-floatingBar.pinByDefault YES` and
    /// `-AppleInterfaceStyle Dark` work through the argument defaults domain.)
    fileprivate func runDebugLaunchActions() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "SpreekDebugSeed") { SampleLibrary.seed(into: model.library) }
        if defaults.bool(forKey: "SpreekDebugSeedLongSentences") { SampleLibrary.seedLongSentences(into: model.library) }
        if let count = Int(defaults.string(forKey: "SpreekDebugSeedBulk") ?? ""), count > 0 {
            SampleLibrary.seedBulk(count, into: model.library)
        }
        if defaults.bool(forKey: "SpreekDebugHideExplainer") { model.permission.explainerDismissed = true }
        switch defaults.string(forKey: "SpreekDebugAppearance") {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        if let days = Int(defaults.string(forKey: "SpreekDebugChartRange") ?? ""), let range = ChartRange(rawValue: days) {
            // `-SpreekDebugChartRange 90`: footer chart window for screenshots.
            model.dashboard.chartRange = range
        }
        if defaults.bool(forKey: "SpreekDebugDumpMenu") {
            // Lists menu items with ⌘ key equivalents (checks ⌘D / ⌘, / ⌘F don't collide).
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                func dump(_ menu: NSMenu, _ path: String) {
                    for item in menu.items {
                        if !item.keyEquivalent.isEmpty { NSLog("%@", "menu \(path)\(item.title) ⌘\(item.keyEquivalent)") }
                        if let submenu = item.submenu { dump(submenu, path + item.title + " › ") }
                    }
                }
                if let menu = NSApp.mainMenu { dump(menu, "") }
            }
        }
        if defaults.bool(forKey: "SpreekDebugToggleLoginItem") {
            // Settings › Launch at login round trip; prints the status after each step.
            let login = model.loginItem
            for enabled in [true, false] {
                login.setEnabled(enabled)
                NSLog("%@", "loginItem set \(enabled) → enabled=\(login.isEnabled) needsApproval=\(login.needsApproval) error=\(login.error ?? "none")")
            }
        }
        if defaults.bool(forKey: "SpreekDebugFrontTest") {
            // Opens the popover after 6 s (put another app in front), then the dashboard as the ⌘D row does.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(6))
                AppModel.statusItemButton()?.performClick(nil)
                try? await Task.sleep(for: .seconds(1.5))
                self.model.openDashboard()
            }
        }
        if let text = defaults.string(forKey: "SpreekDebugSpeak") {
            model.speech.speak(text: text, source: .debug)
        }
        if let count = Int(defaults.string(forKey: "SpreekDebugCycleDashboard") ?? ""), count > 0 {
            // `-SpreekDebugCycleDashboard 10`: opens and closes the Dashboard and the menu bar
            // popover `count` times (memory growth checks).
            Task { @MainActor in
                for _ in 0..<count {
                    try? await Task.sleep(for: .seconds(1))
                    self.model.openDashboard()
                    try? await Task.sleep(for: .seconds(1.5))
                    NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("dashboard") == true }?.close()
                    try? await Task.sleep(for: .seconds(0.5))
                    AppModel.statusItemButton()?.performClick(nil)
                    try? await Task.sleep(for: .seconds(1))
                    self.model.closeMenuBarPopover()
                }
                print("SpreekCycle done")
                fflush(stdout)
            }
        }
        if let count = Int(defaults.string(forKey: "SpreekDebugPlayAll") ?? ""), count > 0 {
            // `-SpreekDebugPlayAll 8`: plays the newest history sentences in a row (memory checks).
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                self.model.playAll(Array(self.model.library.sentences(in: .history).prefix(count)))
            }
        }
        if let directory = defaults.string(forKey: "SpreekDebugSnapshotDir") {
            // Renders Spreek's own visible windows to PNGs every second (no Screen Recording needed).
            Task { @MainActor in
                for index in 1...30 {
                    try? await Task.sleep(for: .seconds(1))
                    Self.snapshotWindows(to: URL(filePath: directory), suffix: "\(index)")
                }
            }
        }
        if let target = defaults.string(forKey: "SpreekDebugOpenDashboard") {
            // `history`, `favorites`, `settings[:section]`, `storage`, a folder name, or `#tag`; `+sheet` opens Folder Info,
            // `+multi` selects several rows, `+cycle` steps through sentences at the minimum window size, `+resize` times live resizing.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                let model = self.model
                let parts = target.components(separatedBy: "+")
                let name = parts[0]
                if name == "favorites" {
                    model.dashboard.show(.favorites)
                } else if name == "storage" {
                    model.dashboard.show(.storage)
                } else if name.hasPrefix("settings") {
                    let section = SettingsSection(rawValue: String(name.dropFirst("settings:".count))) ?? .voices
                    model.dashboard.show(.settings(section))
                } else if name.hasPrefix("#"), let tag = model.library.tags().first(where: { "#" + $0.name == name }) {
                    model.dashboard.show(.tag(tag.persistentModelID))
                } else if let folder = model.library.folders().first(where: { $0.name == name }) {
                    model.dashboard.show(.folder(folder.persistentModelID))
                }
                let scope: LibraryScope? = switch model.dashboard.route {
                case .history: .history
                case .favorites: .favorites
                case .folder(let id): (model.library.context.model(for: id) as? Folder).map { .folder($0) }
                case .tag(let id): (model.library.context.model(for: id) as? Tag).map { .tag($0) }
                case .settings, .storage: nil
                }
                if let scope, let first = model.library.sentences(in: scope).first {
                    model.dashboard.select(first.persistentModelID)
                    if parts.contains("multi") {
                        // Rows 1–2 and 4 selected: one joined run plus a lone row.
                        let rows = model.library.sentences(in: scope).prefix(4).map(\.persistentModelID)
                        model.dashboard.selection = Set(rows.enumerated().filter { $0.offset != 2 }.map(\.element))
                    }
                }
                model.openDashboard()
                if parts.contains("cycle"), let scope {
                    // Minimum window size, then a different sentence each second: checks the columns stay put.
                    try? await Task.sleep(for: .milliseconds(500))
                    NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("dashboard") == true }?
                        .setContentSize(NSSize(width: 1000, height: 700))
                    for sentence in model.library.sentences(in: scope).prefix(8) {
                        model.dashboard.select(sentence.persistentModelID)
                        try? await Task.sleep(for: .seconds(1))
                    }
                }
                if parts.contains("resize"),
                   let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("dashboard") == true }) {
                    // Live-resize benchmark: 1000 → 1600 → 1000 pt in 4 pt steps, layout + display timed
                    // per step (one frame at 120 Hz is 8.3 ms). Prints to stdout.
                    try? await Task.sleep(for: .seconds(1))
                    var times: [Double] = []
                    let widths = Array(stride(from: 1000, through: 1600, by: 4)) + Array(stride(from: 1600, through: 1000, by: -4))
                    for _ in 0..<2 {
                        for width in widths {
                            var frame = window.frame
                            frame.size.width = CGFloat(width)
                            let start = ContinuousClock.now
                            window.setFrame(frame, display: false)
                            window.contentView?.layoutSubtreeIfNeeded()
                            window.displayIfNeeded()
                            times.append((ContinuousClock.now - start) / .milliseconds(1))
                            await Task.yield()
                        }
                    }
                    times.sort()
                    let mean = times.reduce(0, +) / Double(times.count)
                    print(String(format: "SpreekResize steps=%d mean=%.2fms p50=%.2fms p90=%.2fms max=%.2fms",
                                 times.count, mean, times[times.count / 2], times[times.count * 9 / 10], times.last ?? 0))
                    fflush(stdout)
                }
                if parts.contains("sheet") {
                    try? await Task.sleep(for: .seconds(1))
                    let folders = model.library.folders()
                    let folder = folders.first { $0.name == name } ?? folders.first { $0.name == "Reddit" }
                    model.dashboard.folderSheet = FolderSheetTarget(folder: folder)
                }
            }
        }
        if defaults.double(forKey: "SpreekDebugCloseDashboardAfter") > 0 {
            // Checks the Dock icon going away (`lsappinfo info -only ApplicationType <pid>`).
            let delay = defaults.double(forKey: "SpreekDebugCloseDashboardAfter")
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("dashboard") == true }?.close()
            }
        }
        if let kinds = defaults.string(forKey: "SpreekDebugStorageCleanup") {
            // `-SpreekDebugStorageCleanup unlinked,extraSpeeds,all`: runs Settings › Storage clean-ups
            // without their alerts and prints what each announced and freed.
            Task { @MainActor in
                let storage = self.model.storage
                let names: [String: CleanupKind] = [
                    "unlinked": .unlinked, "extraSpeeds": .extraSpeeds, "idle": .idle,
                    "temporary": .temporary, "oldSentences": .oldSentences, "all": .all,
                ]
                @MainActor func settle() async {
                    try? await Task.sleep(for: .seconds(1))
                    while storage.isScanning || storage.isWorking { try? await Task.sleep(for: .milliseconds(100)) }
                }
                storage.refresh()
                await settle()
                for name in kinds.components(separatedBy: ",") {
                    guard let kind = names[name] else { continue }
                    let announced = storage.amount(kind)
                    let before = storage.report?.totalBytes ?? 0
                    storage.ask(kind)
                    if let pending = storage.pending { storage.confirm(pending) }
                    await settle()
                    let after = storage.report?.totalBytes ?? 0
                    print("SpreekStorage \(name): announced \(announced) → \(storage.state(kind)), total \(before) → \(after) (−\(before - after)), reclaimable now \(storage.reclaimableBytes), clips \(storage.report?.usage(.audio).count ?? 0)")
                    fflush(stdout)
                }
            }
        }
        if defaults.bool(forKey: "SpreekDebugOpenPopover") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                AppModel.statusItemButton()?.performClick(nil)
            }
        }
    }

    private static func snapshotWindows(to directory: URL, suffix: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for window in NSApp.windows where window.isVisible && window.frame.width > 100 {
            guard let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let name = String(describing: type(of: window)).filter(\.isLetter)
            NSLog("%@", "snapshot \(name)-\(suffix) frame \(NSStringFromRect(window.frame)) on \(NSStringFromRect(window.screen?.visibleFrame ?? .zero))")
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "\(name)-\(suffix).png"))
        }
        // Settings › App icon: what the Dock and the menu bar currently show.
        if let button = AppModel.statusItemButton(), let rep = button.bitmapImageRepForCachingDisplay(in: button.bounds) {
            button.cacheDisplay(in: button.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "MenuBarIcon-\(suffix).png"))
        }
        if let tiff = NSApp.applicationIconImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "DockIcon-\(suffix).png"))
        }
    }
}
#endif
