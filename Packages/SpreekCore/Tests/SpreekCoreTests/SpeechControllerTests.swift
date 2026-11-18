import Foundation
import Testing
@testable import SpreekCore

@MainActor
@Suite struct SpeechControllerTests {
    let cacheRoot = temporaryDirectory("ControllerCache")
    let player = MockPlayer()

    private func makeController(edge: MockProvider, system: MockProvider = MockProvider(id: .system)) -> SpeechController {
        SpeechController(
            chain: ProviderChain(primary: edge, fallback: system),
            cache: AudioCache(root: cacheRoot), player: player, tickInterval: nil
        )
    }

    /// A provider whose results always carry a fallback hint.
    private struct HintingProvider: TTSProvider {
        let inner = MockProvider(id: .edge)
        var id: ProviderID { .edge }
        var displayName: String { "Hinting" }
        func voices(for language: LanguageCode) async throws -> [Voice] { [] }
        func synthesize(_ request: SpeechRequest) async throws -> SynthesisResult {
            var result = try await inner.synthesize(request)
            result.fallback = FallbackInfo(requestedVoiceID: request.voiceID ?? "", reason: .voiceUnavailable)
            return result
        }
    }

    @Test func fallbackIsSetOnFreshSynthesisAndClearedOnTheNextSpeak() async {
        let controller = SpeechController(
            chain: ProviderChain(primary: HintingProvider(), fallback: nil),
            cache: AudioCache(root: cacheRoot), player: player, tickInterval: nil
        )
        #expect(controller.fallback == nil)
        let task = controller.speak(text: "Goedemorgen. Hoe gaat het?", source: .debug)
        #expect(controller.fallback == nil, "nothing to say while synthesizing")
        await task.value
        #expect(controller.fallback == FallbackInfo(requestedVoiceID: "nl-NL-FennaNeural", reason: .voiceUnavailable))

        // Same text again: the cache has the clip (stored under the voice that spoke), so no hint.
        await controller.speak(text: "Goedemorgen. Hoe gaat het?", source: .debug).value
        #expect(controller.fallback == nil)
        #expect(controller.state.name == "playing")
    }

    @Test func replayingAClipFromTheCacheShowsNoHint() async {
        let controller = SpeechController(
            chain: ProviderChain(primary: HintingProvider(), fallback: nil),
            cache: AudioCache(root: cacheRoot), player: player, tickInterval: nil
        )
        await controller.speak(text: "Goedemorgen. Hoe gaat het?", source: .debug).value
        #expect(controller.fallback != nil)
        await controller.replay().value
        #expect(controller.fallback == nil)
    }

    @Test func fallbackIsAbsentWhenNothingWentWrong() async {
        let controller = makeController(edge: MockProvider(id: .edge))
        await controller.speak(text: "Goedemorgen. Hoe gaat het?", source: .debug).value
        #expect(controller.fallback == nil)
    }

    @Test func idleToSynthesizingToPlayingToFinished() async {
        let text = "Goedemorgen. Hoe gaat het?"
        let marks = [
            BoundaryMark(start: 0, end: 1.5, range: TextRange(location: 0, length: 12), granularity: .sentence),
            BoundaryMark(start: 1.5, end: 4, range: TextRange(location: 13, length: 13), granularity: .sentence),
        ]
        let edge = MockProvider(id: .edge, marks: marks)
        let controller = makeController(edge: edge)
        #expect(controller.state.name == "idle")

        let task = controller.speak(text: text, source: .debug)
        #expect(controller.state.name == "synthesizing")
        #expect(controller.language == .nl)
        #expect(controller.currentText == text)
        await task.value

        #expect(controller.state.name == "playing")
        #expect(player.isPlaying)
        #expect(controller.provider == .edge)
        #expect(controller.voiceID == "nl-NL-FennaNeural")
        #expect(controller.voiceName == "Fenna")
        #expect(edge.requests.first?.voiceID == "nl-NL-FennaNeural")

        player.currentTime = 2
        controller.refreshProgress()
        #expect(controller.progress == 0.5)
        if case .playing(let progress) = controller.state { #expect(progress == 0.5) } else { Issue.record("not playing") }
        #expect(controller.highlightedRange.map { String(text[$0]) } == "Hoe gaat het?")
        #expect(controller.highlightGranularity == .sentence)

        player.finish()
        #expect(controller.state.name == "finished")
        #expect(controller.progress == 1)
        #expect(controller.highlightedRange == nil)
    }

    @Test func seekWhilePlayingPausedAndFinished() async {
        let controller = makeController(edge: MockProvider(id: .edge))
        await controller.speak(text: "Goedemorgen allemaal", source: .debug).value
        controller.seek(toFraction: 0.5)
        #expect(player.currentTime == 2)
        #expect(controller.progress == 0.5)
        #expect(controller.state.name == "playing")

        controller.pause()
        controller.seek(toFraction: 0.25)
        #expect(player.currentTime == 1)
        #expect(controller.state.name == "paused")
        #expect(!player.isPlaying)

        controller.resume()
        player.finish()
        #expect(controller.state.name == "finished")
        controller.seek(toFraction: 0.75)
        #expect(player.currentTime == 3)
        #expect(controller.state.name == "playing")
        #expect(player.isPlaying)
    }

    @Test func replayAtAnotherRateKeepsVoiceAndLanguage() async {
        let edge = MockProvider(id: .edge)
        let controller = makeController(edge: edge)
        await controller.speak(text: "Goedemorgen allemaal", source: .debug).value
        #expect(controller.currentRate == 1)
        await controller.replay(rate: 0.7).value
        #expect(controller.currentRate == 0.7)
        #expect(edge.requests.last?.rate == 0.7)
        #expect(edge.requests.last?.voiceID == "nl-NL-FennaNeural")
        #expect(edge.requests.last?.language == .nl)
        #expect(controller.state.name == "playing")
    }

    @Test func seekWithoutAudioDoesNothing() {
        let controller = makeController(edge: MockProvider(id: .edge))
        controller.seek(toFraction: 0.5)
        #expect(controller.state.name == "idle")
        #expect(player.currentTime == 0)
    }

    @Test func pauseAndResume() async {
        let controller = makeController(edge: MockProvider(id: .edge))
        await controller.speak(text: "Ich bin müde").value
        #expect(controller.language == .de)

        player.currentTime = 1
        controller.refreshProgress()
        controller.pause()
        #expect(controller.state.name == "paused")
        #expect(!player.isPlaying)

        // Ticks while paused don't move anything.
        player.currentTime = 3
        controller.refreshProgress()
        #expect(controller.progress == 0.25)

        controller.togglePause()
        #expect(controller.state.name == "playing")
        #expect(player.isPlaying)
        controller.togglePause()
        #expect(controller.state.name == "paused")
        controller.resume()
        #expect(controller.state.name == "playing")
    }

    @Test func replayUsesCache() async {
        let edge = MockProvider(id: .edge)
        let controller = makeController(edge: edge)
        await controller.speak(text: "De kat slaapt.").value
        player.finish()

        await controller.replay().value
        #expect(controller.state.name == "playing")
        #expect(edge.callCount == 1, "replay must not synthesize again")
        #expect(player.loaded.count == 2)
        #expect(player.loaded[0] == player.loaded[1])

        // Speaking the same text again (e.g. from history) also hits the cache.
        player.finish()
        controller.togglePause() // finished → replay
        await Task.yield()
        await controller.speak(text: "  De kat slaapt. ").value
        #expect(edge.callCount == 1)
    }

    @Test func replayAfterFallbackUsesCachedSystemAudio() async {
        let edge = MockProvider(id: .edge, error: TTSError.executableNotFound)
        let system = MockProvider(id: .system)
        let controller = makeController(edge: edge, system: system)
        await controller.speak(text: "De kat slaapt.").value
        #expect(controller.provider == .system)
        await controller.replay().value
        #expect(system.callCount == 1)
        #expect(edge.callCount == 1)
        #expect(controller.state.name == "playing")
    }

    @Test func rateChangeMissesCache() async {
        let edge = MockProvider(id: .edge)
        let controller = makeController(edge: edge)
        await controller.speak(text: "Hallo daar").value
        controller.setRate(0.85)
        await controller.speak(text: "Hallo daar").value
        #expect(edge.requests.map(\.rate) == [1.0, 0.85])
        controller.setRate(9)
        #expect(controller.rate == 2.0)
    }

    @Test func failureWhenAllProvidersFail() async {
        let controller = makeController(
            edge: MockProvider(id: .edge, error: TTSError.executableNotFound),
            system: MockProvider(id: .system, error: TTSError.noVoice(.nl))
        )
        await controller.speak(text: "Hallo daar").value
        guard case .failed(let error) = controller.state else {
            Issue.record("expected failed, got \(controller.state.name)")
            return
        }
        #expect(error as? TTSError == .noVoice(.nl))
    }

    @Test func playerLoadFailureFails() async {
        player.loadError = TTSError.noAudioProduced
        let controller = makeController(edge: MockProvider(id: .edge))
        await controller.speak(text: "Hallo daar").value
        #expect(controller.state.name == "failed")
    }

    @Test func folderLanguageSkipsDetection() async {
        let edge = MockProvider(id: .edge)
        let controller = makeController(edge: edge)
        await controller.speak(text: "Die Katze schläft.", folderLanguage: .nl, source: .folder).value
        #expect(controller.language == .nl)
        #expect(controller.detection?.reason == .folder)
        #expect(edge.requests.first?.voiceID == "nl-NL-FennaNeural")
    }

    @Test func voiceOverrideIsRequested() async {
        let edge = MockProvider(id: .edge)
        let controller = makeController(edge: edge)
        controller.voiceOverrides[.de] = "de-DE-ConradNeural"
        await controller.speak(text: "Ich bin müde").value
        #expect(edge.requests.first?.voiceID == "de-DE-ConradNeural")
    }

    @Test func newSpeechSupersedesSlowSynthesis() async {
        let edge = MockProvider(id: .edge, delay: .milliseconds(200))
        let controller = makeController(edge: edge)
        let first = controller.speak(text: "Eerste zin")
        let second = controller.speak(text: "Ich bin müde")
        await first.value
        await second.value
        #expect(controller.currentText == "Ich bin müde")
        #expect(controller.state.name == "playing")
        #expect(player.loaded.count == 1)
    }

    @Test func stopReturnsToIdle() async {
        let controller = makeController(edge: MockProvider(id: .edge))
        await controller.speak(text: "Hallo daar").value
        controller.stop()
        #expect(controller.state.name == "idle")
        #expect(!player.isPlaying)
        // A finish callback after stop is ignored.
        player.finish()
        #expect(controller.state.name == "idle")
    }

    @Test func emptyTextIsNoOp() async {
        let edge = MockProvider(id: .edge)
        let controller = makeController(edge: edge)
        await controller.speak(text: "  \n ").value
        #expect(controller.state.name == "idle")
        #expect(edge.callCount == 0)
    }

    @Test func forcedLanguageSkipsDetectionButFolderWins() async {
        let edge = MockProvider(id: .edge)
        let controller = makeController(edge: edge)
        controller.forcedLanguage = .de
        #expect(controller.prepare(text: "Goedemorgen, hoe gaat het met jou?")?.request.language == .de)
        #expect(controller.prepare(text: "Goedemorgen", folderLanguage: .nl)?.request.language == .nl)
        controller.forcedLanguage = nil
        #expect(controller.prepare(text: "Goedemorgen, hoe gaat het met jou?")?.request.language == .nl)
    }

    @Test func muteReachesPlayer() async {
        let controller = makeController(edge: MockProvider(id: .edge))
        controller.isMuted = true
        #expect(player.isMuted)
        await controller.speak(text: "Hallo daar").value
        #expect(controller.state.name == "playing")
        controller.isMuted = false
        #expect(!player.isMuted)
    }
}

/// The global ⌥P shortcut calls `togglePause`.
@MainActor
@Suite struct PauseResumeShortcutTests {
    @Test func doesNothingWhenNothingIsLoaded() {
        let edge = MockProvider(id: .edge)
        let controller = SpeechController(
            chain: ProviderChain(primary: edge, fallback: MockProvider(id: .system)),
            cache: AudioCache(root: temporaryDirectory("PauseCache")), player: MockPlayer(), tickInterval: nil
        )
        controller.togglePause()
        #expect(controller.state.name == "idle")
        #expect(edge.callCount == 0)
    }

    @Test func pausesAndResumesWithoutSynthesizingAgain() async {
        let edge = MockProvider(id: .edge)
        let player = MockPlayer()
        let controller = SpeechController(
            chain: ProviderChain(primary: edge, fallback: MockProvider(id: .system)),
            cache: AudioCache(root: temporaryDirectory("PauseCache")), player: player, tickInterval: nil
        )
        await controller.speak(text: "Goedemorgen, hoe gaat het met je?").value
        player.currentTime = 1.5
        controller.togglePause()
        #expect(controller.state.name == "paused")
        #expect(!player.isPlaying)
        controller.togglePause()
        #expect(controller.state.name == "playing")
        #expect(player.isPlaying)
        #expect(player.currentTime == 1.5)
        #expect(edge.callCount == 1)
    }
}
