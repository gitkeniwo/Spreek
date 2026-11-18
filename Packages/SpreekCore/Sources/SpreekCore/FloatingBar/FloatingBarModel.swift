import Foundation
import Observation

/// The parts of Settings › Floating Bar the model needs (see `AppSettings.floatingBarSettings`).
public struct FloatingBarSettings: Sendable, Hashable {
    /// Seconds the finished bar stays before fading out.
    public var autoHideSeconds: Int
    /// Whether the bar starts pinned at launch.
    public var pinByDefault: Bool
    /// "Show bar: While speaking"; when off only a pinned bar appears.
    public var showsWhileSpeaking: Bool

    public init(autoHideSeconds: Int = 3, pinByDefault: Bool = false, showsWhileSpeaking: Bool = true) {
        self.autoHideSeconds = autoHideSeconds
        self.pinByDefault = pinByDefault
        self.showsWhileSpeaking = showsWhileSpeaking
    }
}

/// When the floating bar is visible and how it counts down after speech finishes.
///
/// hidden → playing (speech starts) → finished (counting down N s) → hidden.
/// Hovering pauses the countdown; pinning keeps the bar (and expands it to the card);
/// new speech replaces the content in place.
///
/// Time comes from `now` and advances on `tick()`; the app drives `tick()` from a timer
/// (`tickInterval`), tests call it after moving their clock.
@MainActor
@Observable
public final class FloatingBarModel {
    public enum Phase: Equatable, Sendable {
        case hidden
        /// Synthesizing, playing or paused.
        case playing
        /// Speech ended; the bar fades after the countdown unless pinned or hovered.
        case finished
    }

    /// What the speech controller is doing, reduced to what the bar cares about.
    public enum SpeechActivity: Sendable {
        case idle, active, finished
    }

    public private(set) var phase: Phase = .hidden
    /// Shared by the bar's pin button and the menu-bar pin tile.
    public private(set) var isPinned: Bool
    public private(set) var isHovering = false
    /// Countdown left in the finished phase, in seconds.
    public private(set) var remaining: TimeInterval = 0
    /// Bumped every time new speech starts, so views can tell content was replaced.
    public private(set) var contentGeneration = 0
    public var settings: FloatingBarSettings {
        didSet { if phase == .finished, !isCountingDown { remaining = countdownTotal } }
    }

    public var isVisible: Bool { phase != .hidden }
    /// Pinned bars show the expanded card.
    public var isExpanded: Bool { isVisible && isPinned }
    /// Whole seconds shown inside the countdown ring.
    public var displayedSeconds: Int { Int(remaining.rounded(.up)) }
    /// 1 → 0 while counting down; drives the accent ring.
    public var countdownFraction: Double { countdownTotal > 0 ? max(0, min(1, remaining / countdownTotal)) : 0 }
    /// Counting down right now (finished, not pinned, not hovered).
    public var isCountingDown: Bool { phase == .finished && !isPinned && !isHovering }

    private var countdownTotal: TimeInterval { TimeInterval(max(settings.autoHideSeconds, 0)) }

    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let tickInterval: Duration?
    @ObservationIgnored private var lastTick: Date?
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    /// - Parameters:
    ///   - now: clock, injectable for tests.
    ///   - tickInterval: how often the countdown advances on its own; `nil` disables the timer.
    public init(settings: FloatingBarSettings = FloatingBarSettings(), now: @escaping () -> Date = Date.init, tickInterval: Duration? = .milliseconds(50)) {
        self.settings = settings
        self.isPinned = settings.pinByDefault
        self.now = now
        self.tickInterval = tickInterval
    }

    // MARK: Inputs

    /// Feed every speech state change. `isNewSpeech` marks the start of a new sentence or replay.
    public func speechChanged(_ activity: SpeechActivity, isNewSpeech: Bool = false) {
        switch activity {
        case .active:
            if isNewSpeech { contentGeneration += 1 }
            guard settings.showsWhileSpeaking || isPinned || phase != .hidden else { return }
            phase = .playing
            stopCountdown()
        case .finished:
            guard phase != .hidden || isPinned else { return }
            phase = .finished
            remaining = countdownTotal
            startCountdown()
        case .idle:
            // Stopped: an unpinned bar goes away; a pinned one keeps its content.
            if isPinned {
                if phase != .hidden { phase = .finished; remaining = countdownTotal }
            } else {
                hide()
            }
        }
    }

    public func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        if hovering { advance() }  // bank the time elapsed before the pointer arrived
        isHovering = hovering
        lastTick = now()
        if !hovering, phase == .finished { startCountdown() }
    }

    public func setPinned(_ pinned: Bool) {
        guard pinned != isPinned else { return }
        isPinned = pinned
        if phase == .finished {
            // Unpinning a finished bar restarts the full countdown.
            remaining = countdownTotal
            if !pinned { startCountdown() }
        }
    }

    public func togglePin() { setPinned(!isPinned) }

    /// Close button: hides immediately. The pin preference is kept.
    public func close() { hide() }

    /// Shows the bar again with the last content (e.g. pinning from the menu bar).
    public func reveal(isPlaying: Bool) {
        guard phase == .hidden else { return }
        phase = isPlaying ? .playing : .finished
        remaining = countdownTotal
        if !isPlaying { startCountdown() }
    }

    /// Advances the countdown to `now()`; hides the bar when it runs out.
    public func tick() {
        advance()
        if phase == .finished, remaining <= 0, !isPinned, !isHovering { hide() }
    }

    // MARK: Countdown

    private func advance() {
        let date = now()
        defer { lastTick = date }
        guard isCountingDown, let lastTick else { return }
        remaining = max(0, remaining - date.timeIntervalSince(lastTick))
    }

    private func startCountdown() {
        lastTick = now()
        guard isCountingDown, tickTask == nil, let tickInterval else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: tickInterval)
                guard let self, !Task.isCancelled else { return }
                self.tick()
                if self.phase != .finished { self.stopCountdown(); return }
            }
        }
    }

    private func stopCountdown() {
        tickTask?.cancel()
        tickTask = nil
        lastTick = nil
    }

    private func hide() {
        stopCountdown()
        phase = .hidden
        remaining = 0
    }
}

extension FloatingBarModel.SpeechActivity {
    /// Maps the controller's playback state.
    public init(_ state: PlaybackState) {
        switch state {
        case .idle: self = .idle
        case .synthesizing, .playing, .paused: self = .active
        case .finished, .failed: self = .finished
        }
    }
}
