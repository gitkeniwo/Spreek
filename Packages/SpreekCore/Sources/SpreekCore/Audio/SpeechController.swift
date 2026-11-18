import Foundation
import Observation

/// Where a speak request came from.
public enum SpeechSource: String, Sendable, Hashable {
    case selection, services, history, folder, debug
    /// Settings › Test ▶: played but not recorded in the library.
    case preview
}

/// A sentence whose playback just started.
public struct SpokenUtterance: Sendable, Hashable {
    public let text: String
    public let language: LanguageCode
    /// The voice that actually speaks (after any fallback).
    public let voiceID: String
    public let source: SpeechSource
    public let rate: Double
}

public enum PlaybackState: Sendable {
    case idle
    case synthesizing
    case playing(progress: Double)
    case paused
    case finished
    case failed(any Error)

    /// Short name without associated values, handy for debug UI and tests.
    public var name: String {
        switch self {
        case .idle: "idle"
        case .synthesizing: "synthesizing"
        case .playing: "playing"
        case .paused: "paused"
        case .finished: "finished"
        case .failed: "failed"
        }
    }

    public var isPlaying: Bool {
        if case .playing = self { true } else { false }
    }
}

/// Speaks text: detect language → cache or synthesize (Edge, falling back to System) → play,
/// publishing progress and the highlighted range.
@MainActor
@Observable
public final class SpeechController {
    // MARK: Published state

    public private(set) var state: PlaybackState = .idle
    /// The sentence being spoken.
    public private(set) var currentText: String?
    public private(set) var source: SpeechSource?
    public private(set) var detection: DetectionResult?
    public var language: LanguageCode? { detection?.language }
    /// Voice that actually speaks (after any fallback).
    public private(set) var voiceID: String?
    public private(set) var provider: ProviderID?
    /// Set when the clip just synthesized for this utterance isn't what was asked for (backup
    /// voice, sentence marks only, macOS voice). Cleared by the next speak; a replay from the
    /// cache has none.
    public private(set) var fallback: FallbackInfo?
    /// 0…1.
    public private(set) var progress: Double = 0
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    /// Range in `currentText` being spoken now: a word for System voices, a sentence for Edge.
    /// Speed of the sentence loaded now (`nil` before anything was spoken).
    public private(set) var currentRate: Double?
    public private(set) var highlightedRange: Range<String.Index>?
    public private(set) var highlightGranularity: BoundaryMark.Granularity?

    // MARK: Configuration

    /// Speed multiplier for the next synthesis; Edge bakes it into the audio.
    public private(set) var rate: Double = 1.0
    public var enabledLanguages: Set<LanguageCode> = LanguageCode.defaultEnabled
    public var preferOnNLDETie: LanguageCode = .nl
    /// Variant used when the recognizer says English.
    public var englishVariant: LanguageCode = .enUS
    /// Skips detection and reads everything in this language (popover language tile);
    /// `nil` = auto-detect. A folder's language still wins.
    public var forcedLanguage: LanguageCode?
    /// Silences playback without pausing it.
    public var isMuted = false {
        didSet { player.isMuted = isMuted }
    }
    /// Per-language voice; missing languages use the registry's default Edge voice.
    public var voiceOverrides: [LanguageCode: String] = [:]
    /// Per-language backup voice; missing languages use Auto.
    public var backupVoiceOverrides: [LanguageCode: String] = [:]
    /// Per-language speed used when a request doesn't pass its own; missing = `rate`.
    public var rateOverrides: [LanguageCode: Double] = [:]
    /// Called each time playback actually starts (new speech and replays), e.g. to record the
    /// sentence in the library.
    @ObservationIgnored public var onSpoken: ((SpokenUtterance) -> Void)?

    nonisolated public static let rateRange: ClosedRange<Double> = 0.5...2.0
    /// The speeds offered by the speed menus (floating bar, popover, dashboard).
    nonisolated public static let speedChoices: [Double] = [0.5, 0.7, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5]

    // MARK: Dependencies

    /// Replaceable so a new edge-tts path from Settings takes effect without a restart.
    @ObservationIgnored public var chain: ProviderChain
    private let cache: AudioCache
    private let player: any AudioPlaying
    private let tickInterval: Duration?

    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var workTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var lastRequest: SpeechRequest?
    @ObservationIgnored private var currentAudio: CachedAudio?

    /// - Parameter tickInterval: how often progress is refreshed while playing; `nil` disables
    ///   the timer (tests call `refreshProgress()` themselves).
    public init(chain: ProviderChain, cache: AudioCache, player: any AudioPlaying, tickInterval: Duration? = .milliseconds(50)) {
        self.chain = chain
        self.cache = cache
        self.player = player
        self.tickInterval = tickInterval
        player.onFinish = { [weak self] in self?.playbackFinished() }
    }

    /// Edge (per `edgeMode`) with System fallback, cache in Application Support, `AVAudioPlayer`.
    public static func live(
        edgeMode: EdgeEngineMode = .automatic, edgeExecutablePath: String? = nil,
        health: VoiceHealth = VoiceHealth(), catalog: EdgeVoiceCatalog = EdgeVoiceCatalog()
    ) -> SpeechController {
        SpeechController(
            chain: .live(mode: edgeMode, edgeExecutablePath: edgeExecutablePath, health: health, catalog: catalog),
            cache: AudioCache(), player: AudioPlayer()
        )
    }

    // MARK: Commands

    /// Normalizes `text`, detects its language (unless `folderLanguage` is given) and builds the
    /// request with the configured voice. `rate` overrides `self.rate` for this request.
    /// Returns `nil` when nothing speakable is left after normalizing.
    public func prepare(text: String, folderLanguage: LanguageCode? = nil, rate: Double? = nil) -> PreparedSpeech? {
        guard let text = TextNormalizer.normalize(text) else { return nil }
        let detection = LanguageDetector.detect(
            text, enabled: enabledLanguages, preferOnNLDETie: preferOnNLDETie, englishVariant: englishVariant,
            folderLanguage: folderLanguage ?? forcedLanguage
        )
        let request = SpeechRequest(
            text: text, language: detection.language,
            voiceID: voiceOverrides[detection.language] ?? detection.language.info.defaultEdgeVoice,
            rate: Self.clampRate(rate ?? defaultRate(for: detection.language)),
            backupVoiceID: backupVoiceOverrides[detection.language]
        )
        return PreparedSpeech(detection: detection, request: request)
    }

    /// Speaks `text`. `folderLanguage` (when replaying from a folder) overrides detection.
    /// The returned task completes once playback has started or failed.
    @discardableResult
    public func speak(text: String, folderLanguage: LanguageCode? = nil, rate: Double? = nil, source: SpeechSource = .selection) -> Task<Void, Never> {
        guard let prepared = prepare(text: text, folderLanguage: folderLanguage, rate: rate) else { return Task {} }
        return speak(prepared, source: source)
    }

    /// Speaks `text` in `language` with a specific voice (Edge or macOS), skipping detection:
    /// the dashboard's pronunciation rows.
    @discardableResult
    public func speak(text: String, language: LanguageCode, voiceID: String, rate: Double? = nil, source: SpeechSource) -> Task<Void, Never> {
        guard let text = TextNormalizer.normalize(text) else { return Task {} }
        let request = SpeechRequest(
            text: text, language: language, voiceID: voiceID, rate: Self.clampRate(rate ?? defaultRate(for: language)),
            backupVoiceID: backupVoiceOverrides[language]
        )
        detection = DetectionResult(language: language, confidence: 1, reason: .folder)
        self.source = source
        return start(request, cachedKey: nil)
    }

    /// The voice used for `language` when nothing more specific is chosen.
    public func defaultVoice(for language: LanguageCode) -> String {
        voiceOverrides[language] ?? language.info.defaultEdgeVoice
    }

    /// The speed used for `language` when a request doesn't pass its own.
    public func defaultRate(for language: LanguageCode) -> Double {
        rateOverrides[language] ?? rate
    }

    /// Speaks a request built by `prepare`.
    @discardableResult
    public func speak(_ prepared: PreparedSpeech, source: SpeechSource) -> Task<Void, Never> {
        detection = prepared.detection
        self.source = source
        return start(prepared.request, cachedKey: nil)
    }

    public func pause() {
        guard state.isPlaying else { return }
        player.pause()
        stopTicker()
        state = .paused
    }

    public func resume() {
        guard case .paused = state else { return }
        player.play()
        state = .playing(progress: progress)
        startTicker()
    }

    public func togglePause() {
        switch state {
        case .playing: pause()
        case .paused: resume()
        case .finished: replay()
        default: break
        }
    }

    /// Jumps to `fraction` (0…1) of the loaded audio. Playing and paused keep their state;
    /// a finished sentence plays on from there.
    public func seek(toFraction fraction: Double) {
        guard currentAudio != nil, duration > 0 else { return }
        switch state {
        case .playing, .paused, .finished: break
        default: return
        }
        // Stay just short of the end so the player still reports finishing on its own.
        let time = min(max(fraction, 0), 1) * duration
        let clamped = min(time, max(duration - 0.05, 0))
        player.seek(to: clamped)
        currentTime = clamped
        progress = clamped / duration
        if case .finished = state {
            player.play()
            startTicker()
        }
        if case .paused = state {} else { state = .playing(progress: progress) }
        updateHighlight(at: clamped)
    }

    /// Plays the last sentence again from the start at `rate`, same language and voice.
    @discardableResult
    public func replay(rate: Double) -> Task<Void, Never> {
        guard let last = lastRequest else { return Task {} }
        let request = SpeechRequest(
            text: last.text, language: last.language, voiceID: last.voiceID, rate: Self.clampRate(rate),
            backupVoiceID: last.backupVoiceID
        )
        return start(request, cachedKey: nil)
    }

    /// Plays the last sentence again from the start, from cache when possible.
    @discardableResult
    public func replay() -> Task<Void, Never> {
        guard let lastRequest else { return Task {} }
        return start(lastRequest, cachedKey: currentAudio?.key)
    }

    public func stop() {
        generation += 1
        workTask?.cancel()
        stopTicker()
        player.stop()
        state = .idle
        progress = 0
        currentTime = 0
        clearHighlight()
    }

    public func setRate(_ rate: Double) {
        self.rate = Self.clampRate(rate)
    }

    private static func clampRate(_ rate: Double) -> Double {
        min(max(rate, rateRange.lowerBound), rateRange.upperBound)
    }

    // MARK: Pipeline

    private func start(_ request: SpeechRequest, cachedKey: String?) -> Task<Void, Never> {
        generation += 1
        let generation = generation
        workTask?.cancel()
        stopTicker()
        player.stop()

        lastRequest = request
        fallback = nil
        currentRate = request.rate
        if cachedKey == nil { currentAudio = nil }
        currentText = request.text
        progress = 0
        currentTime = 0
        duration = 0
        clearHighlight()
        state = .synthesizing

        let task = Task { [weak self] in
            guard let self else { return }
            await self.run(request, cachedKey: cachedKey, generation: generation)
        }
        workTask = task
        return task
    }

    private func run(_ request: SpeechRequest, cachedKey: String?, generation: Int) async {
        do {
            let audio: CachedAudio
            var newFallback: FallbackInfo?
            if let hit = cachedKey.flatMap(cache.lookup(key:))
                ?? cache.lookup(text: request.text, voiceID: request.voiceID ?? "", rate: request.rate) {
                audio = hit
            } else {
                let result = try await chain.synthesize(request)
                guard generation == self.generation else {
                    try? FileManager.default.removeItem(at: result.audioURL)
                    return
                }
                audio = try cache.store(result, text: request.text, rate: request.rate)
                newFallback = result.fallback
            }
            guard generation == self.generation else { return }
            try player.load(audio.audioURL)
            currentAudio = audio
            voiceID = audio.voiceID
            provider = audio.provider
            fallback = newFallback
            duration = player.duration
            player.play()
            state = .playing(progress: 0)
            refreshProgress()
            startTicker()
            onSpoken?(SpokenUtterance(
                text: request.text, language: request.language, voiceID: audio.voiceID,
                source: source ?? .selection, rate: request.rate
            ))
        } catch {
            guard generation == self.generation, !(error is CancellationError) else { return }
            state = .failed(error)
        }
    }

    /// Reads the player clock and updates progress and highlight. Called by the ticker.
    public func refreshProgress() {
        guard state.isPlaying else { return }
        let time = player.currentTime
        let total = player.duration
        currentTime = time
        duration = total
        progress = total > 0 ? min(max(time / total, 0), 1) : 0
        state = .playing(progress: progress)
        updateHighlight(at: time)
    }

    private func updateHighlight(at time: TimeInterval) {
        guard let text = currentText,
              let mark = BoundaryMark.active(in: currentAudio?.marks ?? [], at: time)
        else {
            clearHighlight()
            return
        }
        highlightedRange = mark.range.range(in: text)
        highlightGranularity = mark.granularity
    }

    private func clearHighlight() {
        highlightedRange = nil
        highlightGranularity = nil
    }

    private func playbackFinished() {
        guard state.isPlaying else { return }
        stopTicker()
        progress = 1
        currentTime = duration
        clearHighlight()
        state = .finished
    }

    private func startTicker() {
        stopTicker()
        guard let tickInterval else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: tickInterval)
                guard let self, !Task.isCancelled else { return }
                self.refreshProgress()
            }
        }
    }

    private func stopTicker() {
        tickTask?.cancel()
        tickTask = nil
    }

    /// The cached clip loaded in the player (playing, paused or finished). Storage clean-ups
    /// leave it alone.
    public var currentAudioURL: URL? { currentAudio?.audioURL }

    // MARK: Display helpers

    /// "Fenna" for Edge ids; the system voice's name otherwise.
    public var voiceName: String? {
        guard let voiceID else { return nil }
        if EdgeCLIProvider.isEdgeVoiceID(voiceID) { return EdgeVoiceCatalog.displayName(for: voiceID) }
        return SystemProvider.voiceName(for: voiceID)
    }
}
