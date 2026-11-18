import Foundation
import Testing
@testable import SpreekCore

/// In-memory pasteboard with `NSPasteboard`-like change counting.
@MainActor
final class FakePasteboard: PasteboardAccess {
    private(set) var items: [[String: Data]]
    private(set) var changeCount = 0
    private(set) var restoreCount = 0

    init(items: [[String: Data]] = []) {
        self.items = items
    }

    /// Like `clearContents` + `writeObjects`: bumps the change count.
    func write(_ items: [[String: Data]]) {
        self.items = items
        changeCount += 1
    }

    func snapshot() -> PasteboardSnapshot { PasteboardSnapshot(items: items) }

    func restore(_ snapshot: PasteboardSnapshot) {
        restoreCount += 1
        write(snapshot.items)
    }

    func readString() -> String? {
        items.lazy.compactMap { $0[Self.text].flatMap { String(data: $0, encoding: .utf8) } }.first
    }

    static let text = "public.utf8-plain-text"
    static let rtf = "public.rtf"
    static let png = "public.png"
}

@MainActor
@Suite struct CopyCaptureTests {
    let original: [[String: Data]] = [
        [FakePasteboard.text: Data("my clipboard".utf8), FakePasteboard.rtf: Data("{\\rtf1 my clipboard}".utf8)],
        [FakePasteboard.png: Data([0x89, 0x50, 0x4E, 0x47])],
    ]

    @Test func readsCopiedTextAndRestoresAllItems() async {
        let pasteboard = FakePasteboard(items: original)
        let text = await CopyCapture.capture(from: pasteboard) {
            pasteboard.write([[FakePasteboard.text: Data("Goedemorgen".utf8)]])
        }
        #expect(text == "Goedemorgen")
        #expect(pasteboard.items == original)
        #expect(pasteboard.restoreCount == 1)
    }

    @Test func restoresEmptyClipboard() async {
        let pasteboard = FakePasteboard()
        let text = await CopyCapture.capture(from: pasteboard) {
            pasteboard.write([[FakePasteboard.text: Data("Hallo".utf8)]])
        }
        #expect(text == "Hallo")
        #expect(pasteboard.items.isEmpty)
    }

    @Test func doesNotClobberWhenCopyProducedNothing() async {
        let pasteboard = FakePasteboard(items: original)
        let countBefore = pasteboard.changeCount
        let text = await CopyCapture.capture(from: pasteboard, timeout: .milliseconds(30)) {}
        #expect(text == nil)
        #expect(pasteboard.restoreCount == 0)
        #expect(pasteboard.changeCount == countBefore)
        #expect(pasteboard.items == original)
    }

    @Test func nonTextCopyReturnsNilButStillRestores() async {
        let pasteboard = FakePasteboard(items: original)
        let text = await CopyCapture.capture(from: pasteboard) {
            pasteboard.write([[FakePasteboard.png: Data([1, 2, 3])]])
        }
        #expect(text == nil)
        #expect(pasteboard.items == original)
    }

    @Test func waitsForLateCopy() async {
        let pasteboard = FakePasteboard(items: original)
        let text = await CopyCapture.capture(from: pasteboard, timeout: .seconds(2)) {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(40))
                pasteboard.write([[FakePasteboard.text: Data("Spät".utf8)]])
            }
        }
        #expect(text == "Spät")
        #expect(pasteboard.items == original)
    }
}

@MainActor
final class FakeReader: SelectionCapturing {
    var next: CapturedSelection?
    private(set) var calls = 0

    init(_ next: CapturedSelection?) {
        self.next = next
    }

    func captureSelection() async -> CapturedSelection? {
        calls += 1
        return next
    }
}

@MainActor
@Suite struct SpeakPipelineTests {
    let edge = MockProvider(id: .edge)
    let player = MockPlayer()
    let speech: SpeechController

    init() {
        speech = SpeechController(
            chain: ProviderChain(primary: edge, fallback: MockProvider(id: .system)),
            cache: AudioCache(root: temporaryDirectory("PipelineCache")), player: player, tickInterval: nil
        )
    }

    @Test func prepareNormalizesDetectsAndPicksVoice() throws {
        let prepared = try #require(speech.prepare(text: "  Goedemorgen,\n\n hoe\u{200B} gaat het met je?  "))
        #expect(prepared.text == "Goedemorgen, hoe gaat het met je?")
        #expect(prepared.request.language == .nl)
        #expect(prepared.request.voiceID == "nl-NL-FennaNeural")
        #expect(prepared.request.rate == 1.0)
        #expect(prepared.detection.reason == .recognizer || prepared.detection.reason == .tiePreference)

        let german = try #require(speech.prepare(text: "Ich möchte heute Abend ins Kino gehen.", rate: 0.8))
        #expect(german.request.language == .de)
        #expect(german.request.voiceID == "de-DE-KatjaNeural")
        #expect(german.request.rate == 0.8)

        #expect(speech.prepare(text: " \n ") == nil)
    }

    @Test func selectionIsSpokenWithFenna() async throws {
        let capture = CapturedSelection(
            text: "Zullen we\nstraks koffie drinken?", method: .accessibility,
            appName: "Safari", bundleID: "com.apple.Safari", url: URL(string: "https://nos.nl")
        )
        let pipeline = SpeakPipeline(reader: FakeReader(capture), speech: speech)
        let outcome = await pipeline.speakSelection()

        guard case .speaking(let prepared) = outcome else { Issue.record("not speaking: \(outcome)"); return }
        #expect(prepared.text == "Zullen we straks koffie drinken?")
        #expect(pipeline.lastCapture == capture)
        #expect(speech.source == .selection)
        #expect(speech.detection == prepared.detection)

        // Let synthesis run, then check what reached the provider.
        while speech.state.name == "synthesizing" { await Task.yield() }
        let request = try #require(edge.requests.last)
        #expect(request == SpeechRequest(text: "Zullen we straks koffie drinken?", language: .nl, voiceID: "nl-NL-FennaNeural", rate: 1.0))
    }

    @Test func slowerShortcutUsesReducedRateOnce() async throws {
        let pipeline = SpeakPipeline(reader: FakeReader(CapturedSelection(text: "Guten Morgen, wie geht es dir?", method: .copy)), speech: speech)
        let outcome = await pipeline.speakSelection(rate: SpeakPipeline.slowerRate)
        guard case .speaking(let prepared) = outcome else { Issue.record("not speaking"); return }
        #expect(prepared.request.rate == 0.8)
        #expect(speech.rate == 1.0) // the controller's own rate is unchanged
    }

    @Test func nothingSelectedDoesNotSpeak() async {
        let pipeline = SpeakPipeline(reader: FakeReader(nil), speech: speech)
        #expect(await pipeline.speakSelection() == .nothingSelected)
        #expect(pipeline.lastOutcome == .nothingSelected)
        #expect(speech.state.name == "idle")
        #expect(edge.callCount == 0)
    }

    @Test func whitespaceSelectionIsEmpty() async {
        let pipeline = SpeakPipeline(reader: FakeReader(CapturedSelection(text: "\u{200B} \n", method: .accessibility)), speech: speech)
        #expect(await pipeline.speakSelection() == .empty)
        #expect(pipeline.lastCapture == nil)
        #expect(speech.state.name == "idle")
    }

    @Test func servicesTextIsTaggedAsServices() {
        let pipeline = SpeakPipeline(reader: FakeReader(nil), speech: speech)
        let outcome = pipeline.speak(CapturedSelection(text: "Hallo wereld, dit is een test.", method: .services))
        guard case .speaking = outcome else { Issue.record("not speaking"); return }
        #expect(speech.source == .services)
    }
}
