import Foundation
import Testing
@testable import SpreekCore

// MARK: Helpers

private let maarten = "nl-NL-MaartenNeural"
private let fenna = "nl-NL-FennaNeural"
private let colette = "nl-NL-ColetteNeural"

private func voice(_ id: String, gender: String = "Female") -> Voice {
    Voice(
        id: id, name: EdgeVoiceCatalog.displayName(for: id), locale: id.split(separator: "-").prefix(2).joined(separator: "-"),
        gender: gender, quality: .neural, provider: .edge
    )
}

private let dutchVoices = [
    voice(fenna), voice(colette), voice(maarten, gender: "Male"), voice("nl-BE-ArnaudNeural", gender: "Male"),
    voice("nl-BE-DenaNeural"),
]

/// A provider that fails when `failure` returns an error for the request, else writes audio
/// with one mark of the granularity the request asked for.
final class ScriptedProvider: TTSProvider, @unchecked Sendable {
    let id: ProviderID
    var displayName: String { "Scripted \(id.rawValue)" }
    private let lock = NSLock()
    private var _requests: [SpeechRequest] = []
    private var _failure: @Sendable (SpeechRequest) -> (any Error)?

    init(id: ProviderID, failure: @escaping @Sendable (SpeechRequest) -> (any Error)? = { _ in nil }) {
        self.id = id
        _failure = failure
    }

    var failure: @Sendable (SpeechRequest) -> (any Error)? {
        get { lock.withLock { _failure } }
        set { lock.withLock { _failure = newValue } }
    }

    var requests: [SpeechRequest] { lock.withLock { _requests } }
    var calls: [String] {
        requests.map { "\($0.voiceID ?? "-"):\($0.boundaryMode.rawValue)" }
    }

    func voices(for language: LanguageCode) async throws -> [Voice] { [] }

    func synthesize(_ request: SpeechRequest) async throws -> SynthesisResult {
        lock.withLock { _requests.append(request) }
        if let error = failure(request) { throw error }
        let url = temporaryDirectory("Scripted").appendingPathExtension(id == .edge ? "mp3" : "caf")
        try Data("audio".utf8).write(to: url)
        let granularity: BoundaryMark.Granularity = request.boundaryMode == .word ? .word : .sentence
        let marks = [BoundaryMark(start: 0, end: 1, range: TextRange(location: 0, length: 1), granularity: granularity)]
        return SynthesisResult(
            audioURL: url, marks: marks, provider: id, voiceID: id == .edge ? request.voiceID ?? "?" : "system-voice"
        )
    }
}

/// What the service does after a successful handshake.
private let reset = EdgeAfterHandshakeError(NSError(domain: NSPOSIXErrorDomain, code: 54))
private let refused = EdgeNativeError.rejected(status: 403, serverDate: nil)
private let offline = URLError(.notConnectedToInternet)

private final class Clock: @unchecked Sendable {
    private let box = LockedBox(Date(timeIntervalSince1970: 1_800_000_000))
    var now: Date { box.value }
    func advance(_ seconds: TimeInterval) { box.value = box.value.addingTimeInterval(seconds) }
}

private struct Rig {
    let native: ScriptedProvider
    let cli: ScriptedProvider
    let system: ScriptedProvider
    let health: VoiceHealth
    let clock = Clock()
    var chain: ProviderChain

    init(
        mode: EdgeEngineMode = .automatic,
        native: @escaping @Sendable (SpeechRequest) -> (any Error)? = { _ in nil },
        cli: @escaping @Sendable (SpeechRequest) -> (any Error)? = { _ in nil },
        catalog: [Voice] = dutchVoices
    ) {
        self.native = ScriptedProvider(id: .edge, failure: native)
        self.cli = ScriptedProvider(id: .edge, failure: cli)
        system = ScriptedProvider(id: .system)
        let clock = clock
        health = VoiceHealth(url: nil, now: { clock.now })
        let snapshot = EdgeVoiceCatalog.Snapshot(voices: catalog, fetchedAt: clock.now, genders: [:])
        chain = ProviderChain(
            mode: mode, native: self.native, cli: self.cli, system: system, health: health, catalog: { snapshot }
        )
    }

    func speak(_ voiceID: String? = maarten, backup: String? = nil) async throws -> SynthesisResult {
        try await chain.synthesize(SpeechRequest(text: "Ik vind het leuk.", language: .nl, voiceID: voiceID, backupVoiceID: backup))
    }
}

// MARK: Classification

@Suite struct EdgeFailureTests {
    @Test func resetAfterTheHandshakeIsTheVoice() {
        #expect(EdgeFailure.classify(reset) == .voice)
        #expect(EdgeFailure.classify(EdgeAfterHandshakeError(TTSError.timedOut(seconds: 10))) == .voice)
        #expect(EdgeFailure.classify(EdgeAfterHandshakeError(EdgeNativeError.connectionClosed)) == .voice)
        #expect(EdgeFailure.classify(EdgeNativeError.connectionClosed) == .voice)
    }

    @Test func noAudioIsTheVoice() {
        #expect(EdgeFailure.classify(TTSError.noAudioProduced) == .voice)
    }

    @Test func refusalIsTheServiceAndRemembered() {
        #expect(EdgeFailure.classify(refused) == .service(.refused))
        #expect(EdgeFailure.classify(EdgeNativeError.unexpectedResponse("unknown path x")) == .service(.refused))
        #expect(EdgeFailure.classify(EdgeAfterHandshakeError(refused)) == .service(.refused))
        #expect(EdgeFailure.service(.refused).isRemembered)
    }

    @Test(arguments: [
        URLError(.notConnectedToInternet), URLError(.cannotFindHost), URLError(.dnsLookupFailed),
        URLError(.cannotConnectToHost), URLError(.networkConnectionLost), URLError(.timedOut),
    ])
    func noNetworkIsTheServiceButPasses(error: URLError) {
        #expect(EdgeFailure.classify(error) == .service(.unreachable))
        #expect(!EdgeFailure.classify(error).isRemembered)
    }

    @Test func posixErrorsBeforeAnyHandshakeAreTheNetwork() {
        #expect(EdgeFailure.classify(NSError(domain: NSPOSIXErrorDomain, code: 50)) == .service(.unreachable))
        #expect(EdgeFailure.classify(NSError(domain: NSPOSIXErrorDomain, code: 65)) == .service(.unreachable))
    }

    @Test func aStallBeforeAnyFrameIsTheNetwork() {
        #expect(EdgeFailure.classify(TTSError.timedOut(seconds: 10)) == .service(.unreachable))
    }

    @Test func unrelatedErrorsTeachNothing() {
        #expect(EdgeFailure.classify(CancellationError()) == .unrelated)
        #expect(EdgeFailure.classify(TTSError.emptyText) == .unrelated)
        #expect(EdgeFailure.classify(TTSError.executableNotFound) == .unrelated)
        #expect(EdgeFailure.classify(NSError(domain: "x", code: 1)) == .unrelated)
        #expect(!EdgeFailure.unrelated.isRemembered)
        #expect(EdgeFailure.voice.isRemembered)
    }
}

// MARK: Layered chain

@Suite struct LayeredChainTests {
    @Test func everythingWorksWithoutAHint() async throws {
        let rig = Rig()
        let result = try await rig.speak()
        #expect(result.voiceID == maarten)
        #expect(result.fallback == nil)
        #expect(result.marks.first?.granularity == .word)
        #expect(rig.native.calls == ["\(maarten):word"])
        #expect(rig.cli.requests.isEmpty && rig.system.requests.isEmpty)
    }

    @Test func wordMarksFailThenSentenceMarksSpeak() async throws {
        let rig = Rig(native: { $0.boundaryMode == .word ? reset : nil })
        let result = try await rig.speak()
        #expect(result.voiceID == maarten)
        #expect(result.marks.first?.granularity == .sentence)
        #expect(result.fallback == FallbackInfo(requestedVoiceID: maarten, reason: .wordMarksUnavailable))
        #expect(rig.native.calls == ["\(maarten):word", "\(maarten):sentence"])
        #expect(rig.cli.requests.isEmpty)
        #expect(rig.health.isFailing(maarten, .wordMarks))
        #expect(!rig.health.isFailing(maarten, .voice))
    }

    @Test func aKnownBadStepIsSkippedUntilItIsTimeToRetry() async throws {
        let rig = Rig(native: { $0.boundaryMode == .word ? reset : nil })
        _ = try await rig.speak()

        // The next sentence goes straight to sentence marks: no wait on the broken step.
        let second = try await rig.speak()
        #expect(second.fallback?.reason == .wordMarksUnavailable)
        #expect(rig.native.calls.suffix(1) == ["\(maarten):sentence"])
        #expect(rig.native.calls.count == 3)

        // Just before the retry time: still skipped.
        rig.clock.advance(3 * 3600 - 60)
        _ = try await rig.speak()
        #expect(rig.native.calls.count == 4)

        // After it: the next real request tries word marks again; still broken → wait doubles.
        rig.clock.advance(120)
        _ = try await rig.speak()
        #expect(rig.native.calls.suffix(2) == ["\(maarten):word", "\(maarten):sentence"])
        #expect(rig.health.entry(maarten, .wordMarks)?.failures == 2)
        #expect(rig.health.isBlocked(maarten, .wordMarks))
    }

    @Test func aSuccessClearsTheEntryAndTheHintGoesAway() async throws {
        let rig = Rig(native: { $0.boundaryMode == .word ? reset : nil })
        _ = try await rig.speak()
        rig.native.failure = { _ in nil } // Microsoft fixed it
        rig.clock.advance(3 * 3600 + 1)
        let result = try await rig.speak()
        #expect(result.fallback == nil)
        #expect(result.marks.first?.granularity == .word)
        #expect(!rig.health.isFailing(maarten, .wordMarks))
    }

    @Test func voiceFailsEverywhereSoTheBackupVoiceSpeaks() async throws {
        let rig = Rig(native: { $0.voiceID == maarten ? reset : nil }, cli: { $0.voiceID == maarten ? TTSError.processFailed(status: 1, message: "x") : nil })
        let result = try await rig.speak()
        // Same gender isn't possible for the Dutch locale beyond Maarten: Auto picks the locale's default voice.
        #expect(result.voiceID == fenna)
        #expect(result.fallback == FallbackInfo(requestedVoiceID: maarten, reason: .voiceUnavailable))
        #expect(rig.native.calls == ["\(maarten):word", "\(maarten):sentence", "\(fenna):word"])
        #expect(rig.cli.calls == ["\(maarten):sentence"])
        #expect(rig.system.requests.isEmpty)
        #expect(rig.health.isFailing(maarten, .voice))

        // Next sentence: the failed voice is not tried at all.
        _ = try await rig.speak()
        #expect(rig.native.calls.suffix(1) == ["\(fenna):word"])
        #expect(rig.native.calls.count == 4)
        #expect(rig.cli.requests.count == 1)
    }

    @Test func aVoiceThatOnlyWorksThroughTheCLISpeaksWithoutRetryingNative() async throws {
        let rig = Rig(native: { $0.voiceID == maarten ? reset : nil })
        let first = try await rig.speak()
        #expect(first.voiceID == maarten)
        #expect(first.fallback?.reason == .wordMarksUnavailable)
        #expect(rig.native.calls == ["\(maarten):word", "\(maarten):sentence"])
        #expect(rig.cli.calls == ["\(maarten):sentence"])
        #expect(rig.health.isFailing(maarten, .nativeVoice))

        _ = try await rig.speak()
        #expect(rig.native.calls.count == 2)
        #expect(rig.cli.requests.count == 2)
    }

    @Test func aFailedServiceSkipsTheRemainingNativeSteps() async throws {
        let rig = Rig(native: { _ in refused })
        let result = try await rig.speak()
        // One refused word attempt; sentence marks and the backup voice's native steps are skipped.
        #expect(rig.native.calls == ["\(maarten):word"])
        #expect(rig.cli.calls == ["\(maarten):sentence"])
        #expect(result.voiceID == maarten)
        #expect(result.fallback?.reason == .wordMarksUnavailable)
        #expect(rig.health.isServiceFailing)

        // And the next request doesn't even try.
        _ = try await rig.speak()
        #expect(rig.native.calls.count == 1)
        #expect(rig.cli.requests.count == 2)
    }

    @Test func serviceDownThenCLIThenBackupThenSystem() async throws {
        let rig = Rig(native: { _ in refused }, cli: { _ in TTSError.processFailed(status: 1, message: "offline") })
        let result = try await rig.speak()
        #expect(rig.native.calls == ["\(maarten):word"])
        #expect(rig.cli.calls == ["\(maarten):sentence", "\(fenna):sentence"])
        #expect(result.provider == .system)
        #expect(result.fallback == FallbackInfo(requestedVoiceID: maarten, reason: .edgeUnavailable))
        // The CLI failing while the service is down says nothing about the voices.
        #expect(!rig.health.isFailing(maarten, .voice) && !rig.health.isFailing(fenna, .voice))
    }

    @Test func noNetworkSkipsNativeThisTimeButIsNotRemembered() async throws {
        let rig = Rig(native: { _ in offline }, cli: { _ in TTSError.processFailed(status: 1, message: "offline") })
        let result = try await rig.speak()
        #expect(result.provider == .system)
        #expect(rig.native.calls == ["\(maarten):word"])
        #expect(!rig.health.isServiceFailing)
        // Back online: native is tried again straight away.
        rig.native.failure = { _ in nil }
        let again = try await rig.speak()
        #expect(again.fallback == nil)
        #expect(again.voiceID == maarten)
    }

    @Test func anExplicitBackupVoiceWinsOverAuto() async throws {
        let rig = Rig(native: { $0.voiceID == maarten ? reset : nil }, cli: { $0.voiceID == maarten ? TTSError.noAudioProduced : nil })
        let result = try await rig.speak(backup: "nl-BE-DenaNeural")
        #expect(result.voiceID == "nl-BE-DenaNeural")
        #expect(result.fallback?.reason == .voiceUnavailable)
    }

    @Test func aBrokenBackupLeavesTheMacVoice() async throws {
        let rig = Rig(native: { _ in reset }, cli: { _ in TTSError.processFailed(status: 1, message: "x") })
        let result = try await rig.speak()
        #expect(result.provider == .system)
        #expect(result.fallback?.reason == .edgeUnavailable)
        #expect(rig.health.isFailing(maarten, .voice) && rig.health.isFailing(fenna, .voice))
    }

    @Test func nativeOnlyKeepsItsMeaningButStillHasABackup() async throws {
        let rig = Rig(mode: .nativeOnly, native: { $0.voiceID == maarten ? reset : nil })
        let result = try await rig.speak()
        #expect(rig.native.calls == ["\(maarten):word", "\(maarten):sentence", "\(fenna):word"])
        #expect(rig.cli.requests.isEmpty)
        #expect(result.voiceID == fenna)
    }

    @Test func cliOnlyUsesNoNativeStepsAndHasABackup() async throws {
        let rig = Rig(mode: .cliOnly, cli: { $0.voiceID == maarten ? TTSError.processFailed(status: 1, message: "x") : nil })
        let result = try await rig.speak()
        #expect(rig.native.requests.isEmpty)
        #expect(rig.cli.calls == ["\(maarten):sentence", "\(fenna):sentence"])
        #expect(result.voiceID == fenna)
        #expect(result.fallback?.reason == .voiceUnavailable)
        // The CLI alone can't tell a bad voice from a bad network, so nothing is remembered.
        #expect(!rig.health.isFailing(maarten, .voice))

        // The CLI speaking its own way is not a degraded mode.
        let working = Rig(mode: .cliOnly)
        #expect(try await working.speak().fallback == nil)
    }

    @Test func aMacVoiceSkipsEdgeEntirely() async throws {
        let rig = Rig()
        let result = try await rig.speak("com.apple.voice.premium.nl-NL.Xander")
        #expect(result.provider == .system)
        #expect(result.fallback == nil)
        #expect(rig.native.requests.isEmpty && rig.cli.requests.isEmpty)
    }

    @Test func aMissingVoiceUsesTheLanguageDefault() async throws {
        let rig = Rig()
        let result = try await rig.speak(nil)
        #expect(result.voiceID == fenna)
    }

    @Test func cancellationStopsTheChain() async {
        let rig = Rig(native: { _ in CancellationError() })
        await #expect(throws: CancellationError.self) { try await rig.speak() }
        #expect(rig.cli.requests.isEmpty && rig.system.requests.isEmpty)
    }

    @Test func aVoiceFailureAsksForAFreshVoiceList() async throws {
        let asked = LockedBox(0)
        var rig = Rig(native: { $0.voiceID == maarten ? reset : nil }, cli: { $0.voiceID == maarten ? TTSError.noAudioProduced : nil })
        rig.chain.onVoiceFailure = { asked.value += 1 }
        _ = try await rig.speak()
        #expect(asked.value == 1)
    }

    @Test func checkProbesIgnoringWhatIsRemembered() async throws {
        let rig = Rig(native: { $0.boundaryMode == .word ? reset : nil })
        _ = try await rig.speak()
        #expect(rig.health.isBlocked(maarten, .wordMarks))
        #expect(await rig.chain.check(voiceID: maarten, language: .nl, sampleText: "Hoi.") == .wordMarksOff)
        #expect(rig.native.calls.suffix(2) == ["\(maarten):word", "\(maarten):sentence"])

        rig.native.failure = { _ in nil }
        #expect(await rig.chain.check(voiceID: maarten, language: .nl, sampleText: "Hoi.") == .works)
        #expect(!rig.health.isFailing(maarten, .wordMarks))

        rig.native.failure = { _ in reset }
        rig.cli.failure = { _ in TTSError.processFailed(status: 1, message: "x") }
        #expect(await rig.chain.check(voiceID: maarten, language: .nl, sampleText: "Hoi.") == .unavailable)
        #expect(rig.health.isFailing(maarten, .voice))

        rig.native.failure = { _ in refused }
        #expect(await rig.chain.check(voiceID: fenna, language: .nl, sampleText: "Hoi.") == .serviceDown)
    }

    @Test func theFlatChainKeepsWorking() async throws {
        let edge = ScriptedProvider(id: .edge, failure: { _ in refused })
        let system = ScriptedProvider(id: .system)
        let result = try await ProviderChain(primary: edge, fallback: system)
            .synthesize(SpeechRequest(text: "Hoi", language: .nl, voiceID: maarten))
        #expect(result.provider == .system)
        #expect(result.fallback == nil)
    }
}

// MARK: Health memory

@Suite struct VoiceHealthTests {
    private func makeHealth(_ clock: Clock, url: URL? = nil) -> VoiceHealth {
        VoiceHealth(url: url, now: { clock.now })
    }

    @Test func backoffDoublesFromThreeHoursAndCapsAtADay() {
        #expect([1, 2, 3, 4, 5, 9].map { VoiceHealth.delay(afterFailures: $0) / 3600 } == [3, 6, 12, 24, 24, 24])
    }

    @Test func retryTimeFollowsTheClock() {
        let clock = Clock()
        let health = makeHealth(clock)
        health.recordFailure(maarten, .voice)
        #expect(health.isBlocked(maarten, .voice) && health.isFailing(maarten, .voice))
        clock.advance(3 * 3600 - 1)
        #expect(health.isBlocked(maarten, .voice))
        clock.advance(2)
        // Time to try again, but the failure stays on record until a success.
        #expect(!health.isBlocked(maarten, .voice) && health.isFailing(maarten, .voice))
        #expect(health.entry(maarten, .voice)?.failures == 1)
    }

    @Test func aFailedRetryDoublesTheWait() throws {
        let clock = Clock()
        let health = makeHealth(clock)
        health.recordFailure(maarten, .wordMarks)
        let since = try #require(health.entry(maarten, .wordMarks)?.failingSince)
        for expected in [6.0, 12, 24, 24] {
            clock.advance(25 * 3600)
            health.recordFailure(maarten, .wordMarks)
            let entry = try #require(health.entry(maarten, .wordMarks))
            #expect(entry.retryAfter.timeIntervalSince(clock.now) == expected * 3600)
            #expect(entry.failingSince == since)
        }
    }

    @Test func aRepeatWhileBlockedChangesNothing() {
        let clock = Clock()
        let health = makeHealth(clock)
        health.recordFailure(maarten, .voice)
        let first = health.entry(maarten, .voice)
        clock.advance(60)
        health.recordFailure(maarten, .voice)
        #expect(health.entry(maarten, .voice) == first)
    }

    @Test func aSuccessClearsOnlyThatStep() {
        let health = makeHealth(Clock())
        health.recordFailure(maarten, .voice)
        health.recordFailure(maarten, .wordMarks)
        health.recordSuccess(maarten, .voice)
        #expect(!health.isFailing(maarten, .voice) && health.isFailing(maarten, .wordMarks))
        health.clear(voiceID: maarten)
        #expect(!health.isFailing(maarten, .wordMarks))
    }

    @Test func survivesARelaunch() {
        let clock = Clock()
        let url = temporaryDirectory("Health").appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        let first = makeHealth(clock, url: url)
        first.recordFailure(maarten, .voice)
        first.recordFailure(VoiceHealth.serviceKey, .service)
        let reloaded = makeHealth(clock, url: url)
        #expect(reloaded.isBlocked(maarten, .voice))
        #expect(reloaded.isServiceFailing)
        #expect(reloaded.failingVoices(.voice) == [maarten])
        #expect(reloaded.entry(maarten, .voice)?.failures == 1)
        #expect(abs((reloaded.entry(maarten, .voice)?.retryAfter.timeIntervalSince(clock.now) ?? 0) - 3 * 3600) < 1)
        _ = first
    }

    @Test(arguments: ["", "not json", "{\"items\": 3}", "{\"items\": [{\"voiceID\": 1}]}"])
    func toleratesAMissingOrCorruptFile(content: String) throws {
        let missing = temporaryDirectory("Health").appendingPathExtension("json")
        #expect(makeHealth(Clock(), url: missing).failingVoices(.voice).isEmpty)

        let url = temporaryDirectory("Health").appendingPathExtension("json")
        try Data(content.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let health = makeHealth(Clock(), url: url)
        #expect(health.failingVoices(.voice).isEmpty)
        health.recordFailure(maarten, .voice) // and it can write over the damage
        #expect(makeHealth(Clock(), url: url).isFailing(maarten, .voice))
    }

    @Test func concurrentUpdatesAreSafe() async {
        let health = makeHealth(Clock())
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<200 {
                group.addTask {
                    let id = "nl-NL-Voice\(index % 10)Neural"
                    if index.isMultiple(of: 3) { health.recordSuccess(id, .voice) } else { health.recordFailure(id, .voice) }
                    _ = health.isBlocked(id, .voice)
                }
            }
        }
        #expect(health.failingVoices(.voice).count <= 10)
    }

    @Test func reportsChanges() {
        let health = makeHealth(Clock())
        let changes = LockedBox(0)
        health.onChange = { changes.value += 1 }
        health.recordFailure(maarten, .voice)
        health.recordFailure(maarten, .voice) // blocked: nothing changes
        health.recordSuccess(maarten, .voice)
        health.recordSuccess(maarten, .voice) // already clear
        #expect(changes.value == 2)
    }
}

// MARK: Backup voice

@Suite struct BackupVoiceTests {
    @Test func sameLocaleAndGenderComesFirst() {
        let voices = [voice("de-DE-KatjaNeural"), voice("de-DE-ConradNeural", gender: "Male"), voice("de-AT-JonasNeural", gender: "Male"), voice("de-AT-IngridNeural")]
        #expect(BackupVoice.auto(for: "de-DE-FlorianNeural", language: .de, in: voices + [voice("de-DE-FlorianNeural", gender: "Male")]) == "de-DE-ConradNeural")
    }

    @Test func sameLocaleWhenNoVoiceHasTheGender() {
        let voices = [voice("nl-NL-FennaNeural"), voice("nl-NL-ColetteNeural"), voice(maarten, gender: "Male"), voice("nl-BE-ArnaudNeural", gender: "Male")]
        // Maarten is the only man in nl-NL: same locale beats the male voice from nl-BE.
        #expect(BackupVoice.auto(for: maarten, language: .nl, in: voices) == fenna)
    }

    @Test func sameLanguageAndGenderWhenTheLocaleHasNoOtherVoice() {
        let voices = [voice("de-DE-KatjaNeural"), voice("de-AT-IngridNeural"), voice("de-AT-JonasNeural", gender: "Male"), voice("de-CH-JanNeural", gender: "Male")]
        // Killian (male) is gone and de-DE has no other man: the same locale beats a man from another one.
        #expect(BackupVoice.auto(for: "de-DE-KillianNeural", language: .de, in: voices, knownGenders: ["de-DE-KillianNeural": "Male"]) == "de-DE-KatjaNeural")
        // Without a de-DE voice at all: same language and gender.
        let austrian = [voice("de-AT-IngridNeural"), voice("de-AT-JonasNeural", gender: "Male"), voice("de-CH-JanNeural", gender: "Male")]
        #expect(BackupVoice.auto(for: "de-DE-KillianNeural", language: .de, in: austrian, knownGenders: ["de-DE-KillianNeural": "Male"]) == "de-AT-JonasNeural")
    }

    @Test func aRetiredVoiceKeepsItsRememberedGender() {
        // Killian is gone from the list; Christoph is the male voice left, Tanja the female one.
        let list = [voice("de-DE-ChristophNeural", gender: "Male"), voice("de-DE-TanjaNeural")]
        #expect(BackupVoice.auto(for: "de-DE-KillianNeural", language: .de, in: list, knownGenders: ["de-DE-KillianNeural": "Male"]) == "de-DE-ChristophNeural")
        // Gender unknown: the language's default voice if it qualifies, else alphabetical.
        #expect(BackupVoice.auto(for: "de-DE-KillianNeural", language: .de, in: list) == "de-DE-ChristophNeural")
    }

    @Test func tiesGoToTheLanguageDefaultThenAlphabetical() {
        let women = [voice("nl-NL-ColetteNeural"), voice(fenna), voice("nl-NL-AnnaNeural")]
        // Fenna is the registry default for Dutch.
        #expect(BackupVoice.auto(for: maarten, language: .nl, in: women + [voice(maarten, gender: "Male")]) == fenna)
        // Without the default in the running: alphabetical.
        #expect(BackupVoice.auto(for: maarten, language: .nl, in: [voice("nl-NL-ColetteNeural"), voice("nl-NL-AnnaNeural"), voice(maarten, gender: "Male")]) == "nl-NL-AnnaNeural")
    }

    @Test func excludesTheChosenVoiceAndAnythingBroken() {
        let voices = [voice(fenna), voice(colette), voice(maarten, gender: "Male")]
        #expect(BackupVoice.auto(for: maarten, language: .nl, in: voices, excluding: [fenna]) == colette)
        #expect(BackupVoice.auto(for: fenna, language: .nl, in: voices) == colette)
        #expect(BackupVoice.auto(for: maarten, language: .nl, in: voices, excluding: [fenna, colette]) == nil)
    }

    @Test func fallsBackToTheLanguageDefaultWithoutACatalog() {
        #expect(BackupVoice.auto(for: maarten, language: .nl, in: []) == fenna)
        #expect(BackupVoice.auto(for: fenna, language: .nl, in: []) == nil)
        #expect(BackupVoice.auto(for: maarten, language: .nl, in: [], excluding: [fenna]) == nil)
    }

    @Test func ignoresOtherLanguages() {
        let voices = [voice("de-DE-KatjaNeural"), voice(maarten, gender: "Male")]
        #expect(BackupVoice.auto(for: maarten, language: .nl, in: voices) == fenna)
    }
}

// MARK: Catalog

@Suite struct EdgeVoiceCatalogFreshnessTests {
    private func makeCatalog(_ clock: Clock) -> EdgeVoiceCatalog {
        EdgeVoiceCatalog(cacheURL: temporaryDirectory("Catalog").appendingPathExtension("json"), now: { clock.now })
    }

    @Test func listsAreUsedForADay() async throws {
        #expect(EdgeVoiceCatalog.maxAge == 24 * 3600)
        let clock = Clock()
        let catalog = makeCatalog(clock)
        let fetches = LockedBox(0)
        let fetch: @Sendable () async throws -> [Voice] = { fetches.value += 1; return dutchVoices }
        _ = try await catalog.cachedVoices(fetch)
        clock.advance(23 * 3600)
        _ = try await catalog.cachedVoices(fetch)
        #expect(fetches.value == 1)
        clock.advance(2 * 3600)
        _ = try await catalog.cachedVoices(fetch)
        #expect(fetches.value == 2)
    }

    @Test func aForcedRefreshIgnoresAge() async throws {
        let catalog = makeCatalog(Clock())
        _ = try await catalog.cachedVoices { [voice(fenna)] }
        let refreshed = try await catalog.refresh { dutchVoices }
        #expect(refreshed.count == 5)
        #expect(catalog.snapshot()?.count == 5)
    }

    @Test func aFailedOrEmptyRefreshKeepsTheStoredList() async throws {
        let catalog = makeCatalog(Clock())
        _ = try await catalog.refresh { dutchVoices }
        await #expect(throws: EdgeNativeError.self) { try await catalog.refresh { throw EdgeNativeError.connectionClosed } }
        await #expect(throws: TTSError.self) { try await catalog.refresh { [] } }
        #expect(catalog.snapshot()?.count == 5)
    }

    @Test func aStaleListStillServesWhenFetchingFails() async throws {
        let clock = Clock()
        let catalog = makeCatalog(clock)
        _ = try await catalog.refresh { dutchVoices }
        clock.advance(3 * 24 * 3600)
        let voices = try await catalog.cachedVoices { throw EdgeNativeError.connectionClosed }
        #expect(voices.count == 5)
    }

    @Test func exposesFetchTimeCountAndNeedForRefresh() async throws {
        let clock = Clock()
        let catalog = makeCatalog(clock)
        #expect(catalog.snapshot() == nil && catalog.needsRefresh(minimumAge: 3600))
        let fetchedAt = clock.now
        _ = try await catalog.refresh { dutchVoices }
        #expect(catalog.snapshot()?.fetchedAt.timeIntervalSince(fetchedAt) ?? 99 < 1)
        #expect(catalog.snapshot()?.count == 5)
        #expect(!catalog.needsRefresh(minimumAge: 3600))
        clock.advance(3601)
        #expect(catalog.needsRefresh(minimumAge: 3600) && !catalog.needsRefresh())
    }

    @Test func aVoiceIsRetiredOnlyAfterASuccessfulFetchThatLacksIt() async throws {
        let catalog = makeCatalog(Clock())
        // Nothing fetched yet: nothing is retired.
        #expect(catalog.snapshot()?.isRetired("de-DE-KillianNeural") == nil)
        let german = [voice("de-DE-ChristophNeural", gender: "Male"), voice("de-DE-TanjaNeural"), voice(fenna)]
        _ = try await catalog.refresh { german }
        let snapshot = try #require(catalog.snapshot())
        #expect(snapshot.isRetired("de-DE-KillianNeural"))
        #expect(!snapshot.isRetired("de-DE-TanjaNeural"))
        // The service lists no voice for the language at all: that is a hole in the list, not a retirement.
        #expect(!snapshot.isRetired("ko-KR-InJoonNeural"))
        // macOS voices are never retired.
        #expect(!snapshot.isRetired("com.apple.voice.premium.nl-NL.Xander"))

        // A failed refresh doesn't retire anything.
        _ = try? await catalog.refresh { throw EdgeNativeError.connectionClosed }
        #expect(catalog.snapshot()?.count == 3)
    }

    @Test func gendersOutliveTheVoicesThatHadThem() async throws {
        let catalog = makeCatalog(Clock())
        _ = try await catalog.refresh { [voice("de-DE-KillianNeural", gender: "Male"), voice("de-DE-TanjaNeural")] }
        _ = try await catalog.refresh { [voice("de-DE-ChristophNeural", gender: "Male"), voice("de-DE-TanjaNeural")] }
        let snapshot = try #require(catalog.snapshot())
        #expect(snapshot.genders["de-DE-KillianNeural"] == "Male")
        #expect(BackupVoice.auto(for: "de-DE-KillianNeural", language: .de, in: snapshot.voices, knownGenders: snapshot.genders) == "de-DE-ChristophNeural")
    }

    @Test func statusCombinesHealthAndRetirement() async throws {
        let catalog = makeCatalog(Clock())
        _ = try await catalog.refresh { [voice("de-DE-ChristophNeural", gender: "Male")] }
        let snapshot = catalog.snapshot()
        let health = VoiceHealth(url: nil)
        #expect(VoiceStatus.state(of: "de-DE-KillianNeural", health: health, snapshot: snapshot) == .retired)
        #expect(VoiceStatus.state(of: "de-DE-ChristophNeural", health: health, snapshot: snapshot) == .ok)
        health.recordFailure("de-DE-KillianNeural", .voice)
        #expect(VoiceStatus.state(of: "de-DE-KillianNeural", health: health, snapshot: snapshot) == .unavailable)
        // Word marks alone don't make a voice unavailable.
        health.recordFailure("de-DE-ChristophNeural", .wordMarks)
        #expect(VoiceStatus.state(of: "de-DE-ChristophNeural", health: health, snapshot: snapshot) == .ok)
        #expect(VoiceStatus.state(of: "com.apple.voice.premium.de-DE.Anna", health: health, snapshot: snapshot) == .ok)
    }
}

// MARK: Native sentence mode

@Suite struct EdgeSentenceModeTests {
    private static func sentenceTurn(text: String, audioBytes: Int = 720) -> [EdgeSocketMessage] {
        let header = Data("X-RequestId:1\r\nContent-Type:audio/mpeg\r\nPath:audio\r\n".utf8)
        let metadata = """
        X-Timestamp:t\r\nContent-Type:application/json; charset=utf-8\r\nPath:audio.metadata\r\n\r\n\
        {"Metadata":[{"Type":"SentenceBoundary","Data":{"Offset":1000000,"Duration":9000000,"text":{"Text":"\(text)","Length":\(text.count),"BoundaryType":"SentenceBoundary"}}}]}
        """
        return [
            .text("Path:turn.start\r\n\r\n{}"),
            .text(metadata),
            .binary(Data([0, UInt8(header.count)]) + header + Data(repeating: 0xFF, count: audioBytes)),
            .text("Path:turn.end\r\n\r\n{}"),
        ]
    }

    @Test func sentenceModeAsksForSentenceBoundariesAndMakesSentenceMarks() async throws {
        let text = "Ik vind het leuk."
        let transport = ReplayTransport(turns: [Self.sentenceTurn(text: text)])
        let provider = EdgeNativeProvider(transport: transport, workDirectory: temporaryDirectory("Native"))
        let result = try await provider.synthesize(SpeechRequest(text: text, language: .nl, voiceID: maarten, boundaryMode: .sentence))
        defer { try? FileManager.default.removeItem(at: result.audioURL) }
        #expect(transport.sent[0].contains(#""sentenceBoundaryEnabled":"true","wordBoundaryEnabled":"false""#))
        #expect(result.marks.count == 1)
        #expect(result.marks.first?.granularity == .sentence)
        #expect(result.marks.first?.range == TextRange(location: 0, length: text.utf16.count))
        #expect(result.marks.first?.start == 0.1)
        #expect(result.voiceID == maarten)
    }

    @Test func wordModeIsTheDefault() async throws {
        let transport = ReplayTransport(turns: [try Fixture.frames("edge-nl-hoi-dag")])
        let provider = EdgeNativeProvider(transport: transport, workDirectory: temporaryDirectory("Native"))
        let result = try await provider.synthesize(SpeechRequest(text: "Hoi & dag.", language: .nl))
        defer { try? FileManager.default.removeItem(at: result.audioURL) }
        #expect(transport.sent[0].contains(#""wordBoundaryEnabled":"true""#))
        #expect(result.marks.allSatisfy { $0.granularity == .word })
    }

    @Test func aResetAfterFramesIsTaggedAsAfterTheHandshake() async throws {
        // One frame arrives, then the connection drops: what Maarten does with word marks.
        let transport = ReplayTransport(turns: [[.text("Path:turn.start\r\n\r\n{}")]])
        let provider = EdgeNativeProvider(transport: transport, workDirectory: temporaryDirectory("Native"))
        do {
            _ = try await provider.synthesize(SpeechRequest(text: "Hoi", language: .nl))
            Issue.record("expected a failure")
        } catch {
            #expect(EdgeFailure.classify(error) == .voice)
        }
    }

    @Test func aTurnEndWithoutAudioIsTheVoice() async throws {
        let transport = ReplayTransport(turns: [[.text("Path:turn.start\r\n\r\n{}"), .text("Path:turn.end\r\n\r\n{}")]])
        let provider = EdgeNativeProvider(transport: transport, workDirectory: temporaryDirectory("Native"))
        do {
            _ = try await provider.synthesize(SpeechRequest(text: "Hoi", language: .nl))
            Issue.record("expected a failure")
        } catch {
            #expect(error as? TTSError == .noAudioProduced)
            #expect(EdgeFailure.classify(error) == .voice)
        }
    }

    @Test func aRejectedHandshakeIsTheService() async throws {
        let transport = ReplayTransport(turns: [], rejections: [.rejected(status: 403, serverDate: nil)])
        let provider = EdgeNativeProvider(transport: transport, workDirectory: temporaryDirectory("Native"))
        do {
            _ = try await provider.synthesize(SpeechRequest(text: "Hoi", language: .nl))
            Issue.record("expected a failure")
        } catch {
            #expect(EdgeFailure.classify(error) == .service(.refused))
        }
    }

    @Test func everyTurnGetsItsOwnTimeout() async throws {
        // Each chunk takes about 0.6 s (under the 1 s limit, with room for a slow CI runner): together
        // the two take about 1.2 s and exceed it.
        let turn = Self.sentenceTurn(text: "Hoi.")
        let transport = ReplayTransport(turns: [turn, turn], delay: .milliseconds(150))
        let provider = EdgeNativeProvider(transport: transport, timeout: 1.0, workDirectory: temporaryDirectory("Native"))
        let half = String(repeating: "Hoi dag. ", count: 300)
        let result = try await provider.synthesize(SpeechRequest(text: half + "\n" + half, language: .nl, boundaryMode: .sentence))
        defer { try? FileManager.default.removeItem(at: result.audioURL) }
        #expect(transport.urls.count == 2)
    }
}
