import Foundation
import Testing
@testable import SpreekCore

/// Hand-driven clock.
@MainActor
final class TestClock {
    var date = Date(timeIntervalSinceReferenceDate: 0)
    func advance(_ seconds: TimeInterval) { date += seconds }
}

@MainActor
@Suite struct FloatingBarModelTests {
    let clock = TestClock()

    private func makeModel(_ settings: FloatingBarSettings = FloatingBarSettings()) -> FloatingBarModel {
        let clock = clock
        return FloatingBarModel(settings: settings, now: { clock.date }, tickInterval: nil)
    }

    /// Moves the clock and lets the model notice.
    private func pass(_ seconds: TimeInterval, _ model: FloatingBarModel) {
        clock.advance(seconds)
        model.tick()
    }

    @Test func startsHiddenAndUnpinned() {
        let model = makeModel()
        #expect(model.phase == .hidden)
        #expect(!model.isVisible)
        #expect(!model.isPinned)
        #expect(model.settings.autoHideSeconds == 3)
    }

    @Test func pinByDefaultStartsPinned() {
        #expect(makeModel(FloatingBarSettings(pinByDefault: true)).isPinned)
    }

    @Test func speechShowsBarThenCountsDownAndHides() {
        let model = makeModel()
        model.speechChanged(.active, isNewSpeech: true)
        #expect(model.phase == .playing)
        #expect(model.contentGeneration == 1)

        pass(10, model)  // playing never times out
        #expect(model.phase == .playing)

        model.speechChanged(.finished)
        #expect(model.phase == .finished)
        #expect(model.displayedSeconds == 3)
        #expect(model.countdownFraction == 1)

        pass(1.2, model)
        #expect(model.phase == .finished)
        #expect(model.displayedSeconds == 2)
        #expect(abs(model.countdownFraction - 0.6) < 0.001)

        pass(1.7, model)
        #expect(model.phase == .finished)
        #expect(model.displayedSeconds == 1)

        pass(0.2, model)
        #expect(model.phase == .hidden)
        #expect(!model.isVisible)
    }

    @Test func countdownUsesAutoHideSetting() {
        let model = makeModel(FloatingBarSettings(autoHideSeconds: 5))
        model.speechChanged(.active, isNewSpeech: true)
        model.speechChanged(.finished)
        #expect(model.displayedSeconds == 5)
        pass(4.9, model)
        #expect(model.isVisible)
        pass(0.2, model)
        #expect(!model.isVisible)
    }

    @Test func hoverPausesAndResumesCountdown() {
        let model = makeModel()
        model.speechChanged(.active, isNewSpeech: true)
        model.speechChanged(.finished)
        pass(1, model)
        #expect(model.remaining == 2)

        model.setHovering(true)
        #expect(!model.isCountingDown)
        pass(30, model)
        #expect(model.phase == .finished)
        #expect(model.remaining == 2)

        model.setHovering(false)
        #expect(model.isCountingDown)
        pass(1.5, model)
        #expect(model.remaining == 0.5)
        pass(0.5, model)
        #expect(model.phase == .hidden)
    }

    @Test func hoverBanksTimeElapsedBeforeTheNextTick() {
        let model = makeModel()
        model.speechChanged(.active, isNewSpeech: true)
        model.speechChanged(.finished)
        clock.advance(1)  // no tick in between
        model.setHovering(true)
        pass(10, model)
        #expect(model.remaining == 2)
    }

    @Test func hoverWhilePlayingDoesNotStartACountdown() {
        let model = makeModel()
        model.speechChanged(.active, isNewSpeech: true)
        model.setHovering(true)
        model.setHovering(false)
        pass(10, model)
        #expect(model.phase == .playing)
    }

    @Test func pinKeepsFinishedBarAndExpands() {
        let model = makeModel()
        model.speechChanged(.active, isNewSpeech: true)
        #expect(!model.isExpanded)
        model.setPinned(true)
        #expect(model.isExpanded)

        model.speechChanged(.finished)
        #expect(!model.isCountingDown)
        pass(60, model)
        #expect(model.phase == .finished)
        #expect(model.isExpanded)
    }

    @Test func pinningDuringCountdownStopsIt() {
        let model = makeModel()
        model.speechChanged(.active, isNewSpeech: true)
        model.speechChanged(.finished)
        pass(2, model)
        model.togglePin()
        #expect(model.isPinned)
        pass(60, model)
        #expect(model.phase == .finished)
    }

    @Test func unpinRestartsFullCountdown() {
        let model = makeModel(FloatingBarSettings(pinByDefault: true))
        model.speechChanged(.active, isNewSpeech: true)
        model.speechChanged(.finished)
        pass(60, model)

        model.setPinned(false)
        #expect(!model.isExpanded)
        #expect(model.isCountingDown)
        #expect(model.displayedSeconds == 3)
        pass(2.9, model)
        #expect(model.isVisible)
        pass(0.1, model)
        #expect(model.phase == .hidden)
    }

    @Test func unpinWhilePlayingKeepsPlaying() {
        let model = makeModel(FloatingBarSettings(pinByDefault: true))
        model.speechChanged(.active, isNewSpeech: true)
        model.setPinned(false)
        pass(30, model)
        #expect(model.phase == .playing)
        #expect(!model.isExpanded)
    }

    @Test func newSpeechWhilePinnedReplacesContentInPlace() {
        let model = makeModel()
        model.setPinned(true)
        model.speechChanged(.active, isNewSpeech: true)
        model.speechChanged(.finished)
        pass(30, model)

        model.speechChanged(.active, isNewSpeech: true)
        #expect(model.phase == .playing)
        #expect(model.isPinned)
        #expect(model.isExpanded)
        #expect(model.contentGeneration == 2)

        model.speechChanged(.finished)
        pass(30, model)
        #expect(model.isExpanded)
    }

    @Test func newSpeechDuringCountdownCancelsIt() {
        let model = makeModel()
        model.speechChanged(.active, isNewSpeech: true)
        model.speechChanged(.finished)
        pass(2.5, model)
        model.speechChanged(.active, isNewSpeech: true)
        pass(10, model)
        #expect(model.phase == .playing)
        model.speechChanged(.finished)
        #expect(model.displayedSeconds == 3)
    }

    @Test func pauseAndResumeKeepPlayingPhase() {
        let model = makeModel()
        model.speechChanged(.active, isNewSpeech: true)
        model.speechChanged(.active)  // paused
        model.speechChanged(.active)  // resumed
        #expect(model.phase == .playing)
        #expect(model.contentGeneration == 1)
    }

    @Test func stopHidesUnpinnedButKeepsPinned() {
        let model = makeModel()
        model.speechChanged(.active, isNewSpeech: true)
        model.speechChanged(.idle)
        #expect(model.phase == .hidden)

        model.setPinned(true)
        model.speechChanged(.active, isNewSpeech: true)
        model.speechChanged(.idle)
        #expect(model.phase == .finished)
        #expect(model.isExpanded)
    }

    @Test func closeHidesButKeepsPin() {
        let model = makeModel()
        model.setPinned(true)
        model.speechChanged(.active, isNewSpeech: true)
        model.close()
        #expect(model.phase == .hidden)
        #expect(model.isPinned)

        model.speechChanged(.active, isNewSpeech: true)
        #expect(model.isExpanded)
    }

    @Test func finishWhileHiddenStaysHidden() {
        let model = makeModel()
        model.speechChanged(.active, isNewSpeech: true)
        model.close()
        model.speechChanged(.finished)
        #expect(model.phase == .hidden)
    }

    @Test func revealShowsLastContent() {
        let model = makeModel()
        model.reveal(isPlaying: false)
        #expect(model.phase == .finished)
        #expect(model.isCountingDown)
        pass(3, model)
        #expect(model.phase == .hidden)

        model.setPinned(true)
        model.reveal(isPlaying: false)
        pass(30, model)
        #expect(model.isExpanded)
    }

    @Test func mapsPlaybackStates() {
        #expect(FloatingBarModel.SpeechActivity(.idle) == .idle)
        #expect(FloatingBarModel.SpeechActivity(.synthesizing) == .active)
        #expect(FloatingBarModel.SpeechActivity(.playing(progress: 0.4)) == .active)
        #expect(FloatingBarModel.SpeechActivity(.paused) == .active)
        #expect(FloatingBarModel.SpeechActivity(.finished) == .finished)
        #expect(FloatingBarModel.SpeechActivity(.failed(CancellationError())) == .finished)
    }

    @Test func ownTimerHidesTheBar() async throws {
        let model = FloatingBarModel(settings: FloatingBarSettings(autoHideSeconds: 0), tickInterval: .milliseconds(5))
        model.speechChanged(.active, isNewSpeech: true)
        model.speechChanged(.finished)
        // A deadline rather than an iteration count: under load each sleep can overshoot.
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.isVisible, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(model.phase == .hidden)
    }
}

@Suite struct HistoryCursorTests {
    @Test func stepsThroughSnapshot() {
        var cursor = HistoryCursor(items: ["c", "b", "a"], current: "c")
        #expect(cursor.newer() == nil)
        #expect(cursor.older() == "b")
        #expect(cursor.older() == "a")
        #expect(cursor.older() == nil)
        #expect(cursor.current == "a")
        #expect(cursor.newer() == "b")
        #expect(cursor.newer() == "c")
        #expect(cursor.newer() == nil)
    }

    @Test func unknownCurrentStartsBeforeNewest() {
        var cursor = HistoryCursor(items: ["c", "b"], current: "x")
        #expect(cursor.current == nil)
        #expect(cursor.newer() == nil)
        #expect(cursor.older() == "c")
    }

    @Test func emptyHistory() {
        var cursor = HistoryCursor<String>(items: [], current: nil)
        #expect(cursor.older() == nil)
        #expect(cursor.newer() == nil)
    }
}

@MainActor
@Suite struct FloatingBarShowModeTests {
    @Test func onlyWhenPinnedKeepsTheBarHiddenWhileSpeaking() {
        let bar = FloatingBarModel(settings: FloatingBarSettings(showsWhileSpeaking: false), tickInterval: nil)
        bar.speechChanged(.active, isNewSpeech: true)
        #expect(bar.phase == .hidden)
        bar.speechChanged(.finished)
        #expect(bar.phase == .hidden)

        bar.setPinned(true)
        bar.speechChanged(.active, isNewSpeech: true)
        #expect(bar.phase == .playing)
    }
}
