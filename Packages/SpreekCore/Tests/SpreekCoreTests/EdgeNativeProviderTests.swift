import Foundation
import Testing
@testable import SpreekCore

/// Expected values were computed with the edge-tts Python package (7.3.1), e.g.
/// `python -c "from edge_tts.drm import generate_sec_ms_gec_v2 as g; print(g(1760486400))"`.
@Suite struct EdgeTokenTests {
    @Test(arguments: [
        (0.0, "52BC7A17B50DFEC9-28C4394775C8751CD2F6859C030C06DB1489ACAB3B3A7651831FC26895177ED6"),
        (1_700_000_000, "2CD23A2CA0B2595A-F3C846C370E05F9CC83ACC5F995C5F5D87A4D0F14CE8936A0F902E64099E38A2"),
        (1_760_486_400, "C60BFE78BFD6AABC-073A7D7FE8DC2F60848EE2F8E2908EAD41087384C74C2172F895451AB5FA2688"),
        (1_760_486_700, "8D69428EE40B1702-1E07EC1FBEA7C8E9BD028F828FBC71E306AF09DEA5A8F52234E27756D93D859B"),
    ])
    func matchesPythonPackage(unixTime: Double, expected: String) {
        #expect(EdgeToken.secMSGEC(unixTime: unixTime) == expected)
    }

    @Test func roundsDownToFiveMinutes() {
        // 1760486699.9 is in the same 5-minute window as 1760486400.
        #expect(EdgeToken.secMSGEC(unixTime: 1_760_486_699.9) == EdgeToken.secMSGEC(unixTime: 1_760_486_400))
        #expect(EdgeToken.secMSGEC(unixTime: 1_760_486_700) != EdgeToken.secMSGEC(unixTime: 1_760_486_699))
    }

    @Test func clockSkewShiftsTheToken() {
        let clock = EdgeClock(now: { Date(timeIntervalSince1970: 1_760_486_400) })
        clock.adjust(toServerDate: Date(timeIntervalSince1970: 1_760_486_700))
        #expect(EdgeToken.secMSGEC(at: clock.now()) == EdgeToken.secMSGEC(unixTime: 1_760_486_700))
    }

    @Test func urlsCarryTokenAndVersion() {
        let url = EdgeEndpoint.synthesisURL(connectionID: "abc", token: "T-1").absoluteString
        #expect(url.hasPrefix("wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1?"))
        #expect(url.contains("TrustedClientToken=6A5AA1D4EAFF4E9FB37E23D68491D6F4")) // gitleaks:allow
        #expect(url.contains("ConnectionId=abc&Sec-MS-GEC=T-1&Sec-MS-GEC-Version=2-143.0.3650.75"))
        #expect(EdgeEndpoint.voicesURL(token: "T").absoluteString.contains("/voices/list?trustedclienttoken="))
    }
}

@Suite struct EdgeSSMLTests {
    @Test func escapesMarkupAndQuotes() {
        #expect(EdgeMessages.escape(#"Tom & Jerry <3 "hi" 'yo'"#) == "Tom &amp; Jerry &lt;3 &quot;hi&quot; &apos;yo&apos;")
        #expect(EdgeMessages.escape("a > b") == "a &gt; b")
    }

    @Test func keepsJapaneseAndKorean() {
        #expect(EdgeMessages.escape("今日は寒いです。") == "今日は寒いです。")
        #expect(EdgeMessages.escape("좋은 아침이에요 & 커피") == "좋은 아침이에요 &amp; 커피")
    }

    @Test func replacesControlCharactersOneForOne() {
        #expect(EdgeMessages.escape("a\u{B}b\u{1}c\nd\te") == "a b c\nd\te")
    }

    @Test func unescapeReversesEscape() {
        let text = #"<a href="x">Tom & 'Jerry'</a> 日本"#
        #expect(EdgeMessages.unescape(EdgeMessages.escape(text)) == text)
        #expect(EdgeMessages.unescape("&amp;lt;") == "&lt;")
    }

    @Test func ssmlDocument() {
        let ssml = EdgeMessages.ssml(voice: "nl-NL-FennaNeural", rate: "-15%", escapedText: "Hoi &amp; dag.")
        #expect(ssml == "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>"
            + "<voice name='Microsoft Server Speech Text to Speech Voice (nl-NL, FennaNeural)'>"
            + "<prosody pitch='+0Hz' rate='-15%' volume='+0%'>Hoi &amp; dag.</prosody></voice></speak>")
    }

    @Test(arguments: [
        ("nl-NL-FennaNeural", "Microsoft Server Speech Text to Speech Voice (nl-NL, FennaNeural)"),
        ("de-DE-FlorianMultilingualNeural", "Microsoft Server Speech Text to Speech Voice (de-DE, FlorianMultilingualNeural)"),
        ("zh-CN-liaoning-XiaobeiNeural", "Microsoft Server Speech Text to Speech Voice (zh-CN-liaoning, XiaobeiNeural)"),
        ("fil-PH-AngeloNeural", "Microsoft Server Speech Text to Speech Voice (fil-PH, AngeloNeural)"),
        ("com.apple.voice.compact.nl-NL.Xander", "com.apple.voice.compact.nl-NL.Xander"),
    ])
    func serviceVoiceName(short: String, long: String) {
        #expect(EdgeMessages.serviceVoiceName(short) == long)
    }

    @Test func requestMessages() {
        let date = Date(timeIntervalSince1970: 1_760_486_400) // Wed 15 Oct 2025 00:00:00 UTC
        #expect(EdgeMessages.timestamp(date) == "Wed Oct 15 2025 00:00:00 GMT+0000 (Coordinated Universal Time)")
        let config = EdgeMessages.speechConfig(date: date)
        #expect(config.hasPrefix("X-Timestamp:Wed Oct 15 2025 00:00:00 GMT+0000 (Coordinated Universal Time)\r\n"))
        #expect(config.contains("Path:speech.config\r\n\r\n"))
        #expect(config.contains(#""sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"true""#))
        #expect(config.contains(#""outputFormat":"audio-24khz-48kbitrate-mono-mp3""#))
        #expect(EdgeMessages.speechConfig(date: date, wordBoundaries: true) == config)
        let sentenceConfig = EdgeMessages.speechConfig(date: date, wordBoundaries: false)
        #expect(sentenceConfig.contains(#""sentenceBoundaryEnabled":"true","wordBoundaryEnabled":"false""#))
        #expect(sentenceConfig.hasSuffix(#""outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}"# + "\r\n"))
        let ssml = EdgeMessages.ssmlRequest(requestID: "r1", date: date, voice: "nl-NL-FennaNeural", rate: "+0%", escapedText: "x")
        #expect(ssml.hasPrefix("X-RequestId:r1\r\nContent-Type:application/ssml+xml\r\nX-Timestamp:Wed Oct 15 2025 00:00:00 GMT+0000 (Coordinated Universal Time)Z\r\nPath:ssml\r\n\r\n<speak "))
    }

    @Test func shortTextIsOneChunk() {
        #expect(EdgeMessages.split("  Hoi &amp; dag.  ") == ["Hoi &amp; dag."])
        #expect(EdgeMessages.split("   ") == [])
    }

    @Test func splitsAtSpacesWithinByteLimit() {
        let chunks = EdgeMessages.split("aaaa bbbb cccc", maxBytes: 10)
        #expect(chunks == ["aaaa bbbb", "cccc"])
        #expect(EdgeMessages.split("one\ntwo three", maxBytes: 10) == ["one", "two three"])
    }

    @Test func neverSplitsEntitiesOrCharacters() {
        // The space-free cut at 8 bytes would land inside "&amp;".
        #expect(EdgeMessages.split("abcd&amp;efgh", maxBytes: 8) == ["abcd", "&amp;efg", "h"])
        // Japanese is 3 bytes per character: 8 bytes fit two characters.
        let chunks = EdgeMessages.split("今日は寒い", maxBytes: 8)
        #expect(chunks == ["今日", "は寒", "い"])
        #expect(chunks.allSatisfy { $0.utf8.count <= 8 })
    }

    @Test func longJapaneseStaysUnderServiceLimit() {
        let text = String(repeating: "今日は寒いですね。", count: 300) // 8,100 bytes
        let chunks = EdgeMessages.split(EdgeMessages.escape(text))
        #expect(chunks.count == 2)
        #expect(chunks.allSatisfy { $0.utf8.count <= EdgeEndpoint.maxChunkBytes })
        #expect(chunks.joined() == text)
    }
}

@Suite struct EdgeFrameTests {
    @Test func parsesRecordedDutchTurn() throws {
        let frames = try Fixture.frames("edge-nl-hoi-dag")
        var audio = Data()
        var words: [EdgeWordBoundary] = []
        var paths: [String] = []
        for message in frames {
            let frame = switch message {
            case .text(let text): try EdgeFrame.parse(text: text)
            case .binary(let data): try EdgeFrame.parse(binary: data)
            }
            switch frame {
            case .audio(let data): audio += data
            case .wordBoundaries(let w): words += w
            case .turnStart: paths.append("turn.start")
            case .response: paths.append("response")
            case .turnEnd: paths.append("turn.end")
            case .ignored: paths.append("ignored")
            }
        }
        #expect(paths == ["turn.start", "response", "ignored", "turn.end"])
        #expect(words == [
            EdgeWordBoundary(offset: 1_000_000, duration: 3_625_000, text: "Hoi"),
            EdgeWordBoundary(offset: 4_750_000, duration: 1_375_000, text: "&"),
            EdgeWordBoundary(offset: 6_250_000, duration: 4_500_000, text: "dag"),
        ])
        #expect(audio.count == 16 * 720 + 144)
        // MPEG audio frame sync.
        #expect(audio.prefix(2) == Data([0xFF, 0xF3]) || audio.prefix(3) == Data("ID3".utf8))
    }

    @Test func binaryFrameHeaderLength() throws {
        let header = Data("X-RequestId:1\r\nContent-Type:audio/mpeg\r\nPath:audio\r\n".utf8)
        let frame = Data([0, UInt8(header.count)]) + header + Data([1, 2, 3])
        #expect(try EdgeFrame.parse(binary: frame) == .audio(Data([1, 2, 3])))
        #expect(throws: EdgeNativeError.self) { try EdgeFrame.parse(binary: Data([0, 200, 1])) }
        #expect(throws: EdgeNativeError.self) { try EdgeFrame.parse(binary: Data([0])) }
    }

    @Test func endOfStreamFrameIsIgnored() throws {
        let header = Data("X-RequestId:1\r\nPath:audio\r\n".utf8)
        #expect(try EdgeFrame.parse(binary: Data([0, UInt8(header.count)]) + header) == .ignored)
    }

    @Test func unknownTextPathThrows() {
        #expect(throws: EdgeNativeError.self) { try EdgeFrame.parse(text: "Path:surprise\r\n\r\n{}") }
    }
}

@Suite struct EdgeBoundaryTests {
    @Test func ticksBecomeSecondsAndWordsBecomeRanges() {
        let text = "Hoi & dag."
        let marks = EdgeWordBoundary.marks(from: [
            EdgeWordBoundary(offset: 1_000_000, duration: 3_625_000, text: "Hoi"),
            EdgeWordBoundary(offset: 4_750_000, duration: 1_375_000, text: "&"),
            EdgeWordBoundary(offset: 6_250_000, duration: 4_500_000, text: "dag"),
        ], in: text)
        #expect(marks.map { $0.range.range(in: text).map { String(text[$0]) } } == ["Hoi", "&", "dag"])
        #expect(marks.map(\.start) == [0.1, 0.475, 0.625])
        #expect(marks.map(\.end) == [0.4625, 0.6125, 1.075])
        #expect(marks.allSatisfy { $0.granularity == .word })
    }

    @Test func repeatedWordsMapInOrder() {
        let text = "de kat en de hond"
        let marks = EdgeWordBoundary.marks(from: ["de", "kat", "en", "de", "hond"].enumerated().map {
            EdgeWordBoundary(offset: Int64($0) * 1_000_000, duration: 500_000, text: $1)
        }, in: text)
        #expect(marks.map(\.range.location) == [0, 3, 7, 10, 13])
    }

    @Test func unknownWordIsSkippedWithoutLosingPlace() {
        let text = "Ik heb 3 katten."
        let marks = EdgeWordBoundary.marks(from: [
            EdgeWordBoundary(offset: 0, duration: 1, text: "Ik"),
            EdgeWordBoundary(offset: 1, duration: 1, text: "heb"),
            EdgeWordBoundary(offset: 2, duration: 1, text: "drie"),
            EdgeWordBoundary(offset: 3, duration: 1, text: "katten"),
        ], in: text)
        #expect(marks.map { $0.range.range(in: text).map { String(text[$0]) } } == ["Ik", "heb", "katten"])
    }

    @Test func caseAndWidthInsensitiveFallback() {
        let text = "ＡＢＣ news"
        let marks = EdgeWordBoundary.marks(from: [EdgeWordBoundary(offset: 0, duration: 1, text: "ABC")], in: text)
        #expect(marks.first?.range == TextRange(location: 0, length: 3))
    }

    @Test func utf16RangesForJapaneseAndEmoji() {
        let text = "😀 今日は寒い"
        let marks = EdgeWordBoundary.marks(from: [
            EdgeWordBoundary(offset: 0, duration: 1, text: "今日"),
            EdgeWordBoundary(offset: 1, duration: 1, text: "は"),
        ], in: text)
        #expect(marks.map(\.range) == [TextRange(location: 3, length: 2), TextRange(location: 5, length: 1)])
    }

    @Test func audioBytesToTicks() {
        // 48 kbit/s: 6,000 bytes = 1 s.
        #expect(EdgeWordBoundary.ticks(forAudioBytes: 6_000) == 10_000_000)
        #expect(EdgeWordBoundary.ticks(forAudioBytes: 720) == 1_200_000)
    }
}

@Suite struct EdgeNativeProviderTests {
    @Test func synthesizesFromRecordedFrames() async throws {
        let transport = ReplayTransport(turns: [try Fixture.frames("edge-nl-hoi-dag")])
        let provider = EdgeNativeProvider(transport: transport, workDirectory: temporaryDirectory("Native"))
        let text = "Hoi & dag."
        let result = try await provider.synthesize(SpeechRequest(text: text, language: .nl, rate: 0.85))
        defer { try? FileManager.default.removeItem(at: result.audioURL) }

        #expect(result.provider == .edge)
        #expect(result.voiceID == "nl-NL-FennaNeural")
        #expect(result.audioURL.pathExtension == "mp3")
        #expect(try Data(contentsOf: result.audioURL).count == 16 * 720 + 144)
        #expect(result.marks.map { $0.range.range(in: text).map { String(text[$0]) } } == ["Hoi", "&", "dag"])

        let sent = transport.sent
        #expect(sent.count == 2)
        #expect(sent[0].contains("Path:speech.config"))
        #expect(sent[1].contains("rate='-15%'"))
        #expect(sent[1].contains(">Hoi &amp; dag.</prosody>"))
        let url = try #require(transport.urls.first)
        #expect(url.absoluteString.contains("Sec-MS-GEC="))
        #expect(transport.headers.first?["Cookie"]?.hasPrefix("muid=") == true)
    }

    @Test func japaneseWordsFromRecordedFrames() async throws {
        let transport = ReplayTransport(turns: [try Fixture.frames("edge-ja-kyou")])
        let provider = EdgeNativeProvider(transport: transport, workDirectory: temporaryDirectory("Native"))
        let text = "今日は寒いです。"
        let result = try await provider.synthesize(SpeechRequest(text: text, language: .ja))
        defer { try? FileManager.default.removeItem(at: result.audioURL) }
        #expect(result.voiceID == "ja-JP-NanamiNeural")
        let words = result.marks.compactMap { $0.range.range(in: text).map { String(text[$0]) } }
        #expect(words.joined() == "今日は寒いです")
        #expect(words.count >= 3)
        #expect(zip(result.marks, result.marks.dropFirst()).allSatisfy { $0.start < $1.start })
    }

    @Test func secondChunkOffsetsFollowFirstChunkAudio() async throws {
        let turn = try Fixture.frames("edge-nl-hoi-dag")
        let transport = ReplayTransport(turns: [turn, turn])
        let provider = EdgeNativeProvider(transport: transport, workDirectory: temporaryDirectory("Native"))
        // Two chunks: each > half of 4096 bytes so they can't share one request.
        let half = String(repeating: "Hoi & dag. ", count: 200)
        let result = try await provider.synthesize(SpeechRequest(text: half + "\n" + half, language: .nl))
        defer { try? FileManager.default.removeItem(at: result.audioURL) }
        #expect(transport.urls.count == 2)
        let firstAudioSeconds = Double(16 * 720 + 144) * 8 / 48_000
        #expect(result.marks.count == 6)
        #expect(abs(result.marks[3].start - (firstAudioSeconds + 0.1)) < 0.0001)
    }

    @Test func retriesOnceWithServerClockWhenRejected() async throws {
        let serverDate = Date(timeIntervalSince1970: 1_760_486_700)
        let transport = ReplayTransport(
            turns: [try Fixture.frames("edge-nl-hoi-dag")],
            rejections: [EdgeNativeError.rejected(status: 403, serverDate: serverDate)]
        )
        let clock = EdgeClock(now: { Date(timeIntervalSince1970: 1_760_000_000) })
        let provider = EdgeNativeProvider(transport: transport, clock: clock, workDirectory: temporaryDirectory("Native"))
        let result = try await provider.synthesize(SpeechRequest(text: "Hoi & dag.", language: .nl))
        defer { try? FileManager.default.removeItem(at: result.audioURL) }
        #expect(transport.urls.count == 2)
        #expect(transport.urls[1].absoluteString.contains("Sec-MS-GEC=\(EdgeToken.secMSGEC(unixTime: 1_760_486_700))"))
    }

    @Test func rejectionWithoutDateFails() async throws {
        let transport = ReplayTransport(turns: [], rejections: [EdgeNativeError.rejected(status: 403, serverDate: nil)])
        let provider = EdgeNativeProvider(transport: transport, workDirectory: temporaryDirectory("Native"))
        await #expect(throws: EdgeNativeError.rejected(status: 403, serverDate: nil)) {
            try await provider.synthesize(SpeechRequest(text: "Hoi", language: .nl))
        }
    }

    @Test func timesOutWhenTheServiceStalls() async throws {
        let transport = ReplayTransport(turns: [[]], stallWhenEmpty: true)
        let provider = EdgeNativeProvider(transport: transport, timeout: 0.2, workDirectory: temporaryDirectory("Native"))
        await #expect(throws: TTSError.timedOut(seconds: 0.2)) {
            try await provider.synthesize(SpeechRequest(text: "Hoi", language: .nl))
        }
    }

    @Test func emptyTextThrows() async {
        let provider = EdgeNativeProvider(transport: ReplayTransport(turns: []))
        await #expect(throws: TTSError.emptyText) { try await provider.synthesize(SpeechRequest(text: "  ", language: .nl)) }
    }

    @Test func voicesFromServiceListShareTheCatalogCache() async throws {
        let cacheURL = temporaryDirectory("NativeVoices").appendingPathExtension("json")
        let transport = ReplayTransport(turns: [], voiceList: try Fixture.data("edge-voices", ext: "json"))
        let provider = EdgeNativeProvider(transport: transport, catalog: EdgeVoiceCatalog(cacheURL: cacheURL))
        let dutch = try await provider.voices(for: .nl)
        #expect(dutch.map(\.id) == ["nl-NL-FennaNeural"])
        #expect(dutch.first?.name == "Fenna")
        #expect(dutch.first?.gender == "Female")
        #expect(dutch.first?.quality == .neural)

        // The CLI provider reads the same cache without running anything.
        let cli = EdgeCLIProvider(
            resolver: EdgeExecutableResolver(isExecutable: { _ in false }),
            catalog: EdgeVoiceCatalog(cacheURL: cacheURL)
        )
        #expect(try await cli.voices(for: .de).map(\.name) == ["Florian"])
        #expect(transport.getCount == 1)
    }

    @Test func voiceListJSONParsing() throws {
        let voices = EdgeVoiceCatalog.parseJSON(try Fixture.data("edge-voices", ext: "json"))
        #expect(Set(voices.map(\.id)) == Set(["nl-NL-FennaNeural", "ja-JP-NanamiNeural", "de-DE-FlorianMultilingualNeural"]))
        #expect(voices.first { $0.id == "ja-JP-NanamiNeural" }?.locale == "ja-JP")
        #expect(EdgeVoiceCatalog.parseJSON(Data("not json".utf8)).isEmpty)
    }
}

@Suite struct ProviderOrderTests {
    @Test func nativeThenCLIThenSystem() async throws {
        let native = MockProvider(id: .edge, error: EdgeNativeError.connectionClosed)
        let cli = MockProvider(id: .edge, error: TTSError.executableNotFound)
        let system = MockProvider(id: .system)
        let errors = LockedBox<[String]>([])
        let chain = ProviderChain(providers: [native, cli, system]) { error in errors.withLock { $0.append("\(error)") } }
        let result = try await chain.synthesize(SpeechRequest(text: "Hallo", language: .nl, voiceID: "nl-NL-FennaNeural"))
        #expect(result.provider == .system)
        let calls: [Int] = [native.callCount, cli.callCount, system.callCount]
        #expect(calls == [1, 1, 1])
        #expect(errors.value.count == 2)
    }

    @Test func cliSpeaksWhenNativeFails() async throws {
        let native = MockProvider(id: .edge, error: EdgeNativeError.rejected(status: 403, serverDate: nil))
        let cli = MockProvider(id: .edge)
        let system = MockProvider(id: .system)
        let result = try await ProviderChain(providers: [native, cli, system])
            .synthesize(SpeechRequest(text: "Hallo", language: .nl))
        #expect(result.provider == .edge)
        #expect(system.callCount == 0)
    }

    /// Provider kinds in chain order.
    private static func kinds(_ chain: ProviderChain) -> [String] {
        chain.providers.map { provider in
            switch provider {
            case is EdgeNativeProvider: "native"
            case is EdgeCLIProvider: "cli"
            case is SystemProvider: "system"
            default: "other"
            }
        }
    }

    @Test(arguments: [
        (EdgeEngineMode.automatic, ["native", "cli", "system"]),
        (.nativeOnly, ["native", "system"]),
        (.cliOnly, ["cli", "system"]),
    ])
    func liveChainOrder(mode: EdgeEngineMode, expected: [String]) {
        #expect(Self.kinds(.live(mode: mode)) == expected)
    }

    @Test func defaultModeIsAutomatic() {
        #expect(Self.kinds(.live()) == ["native", "cli", "system"])
    }

    @Test func cliOnlyChainUsesTheConfiguredPath() throws {
        let cli = try #require(ProviderChain.live(mode: .cliOnly, edgeExecutablePath: "/opt/x/edge-tts").providers.first as? EdgeCLIProvider)
        #expect(cli.resolver.candidates.first?.executable.path == "/opt/x/edge-tts")
    }

    @Test func systemIsTheLastResortInEveryMode() async throws {
        // Mirrors each mode's shape with failing Edge mocks: System still speaks.
        for edgeCount in [2, 1] {
            let edge = (0..<edgeCount).map { _ in MockProvider(id: .edge, error: EdgeNativeError.connectionClosed) }
            let system = MockProvider(id: .system)
            let result = try await ProviderChain(providers: edge + [system])
                .synthesize(SpeechRequest(text: "Hallo", language: .nl, voiceID: "nl-NL-FennaNeural"))
            #expect(result.provider == .system)
            #expect(edge.allSatisfy { $0.callCount == 1 })
        }
    }
}

/// Talks to the real service. Opt in with `SPREEK_LIVE_TTS=1 swift test`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SPREEK_LIVE_TTS"] == "1"))
struct LiveEdgeNativeTests {
    @Test func speaksDutchWithFennaWordByWord() async throws {
        let provider = EdgeNativeProvider(workDirectory: temporaryDirectory("LiveNative"))
        let text = "Goedemorgen. Hoe gaat het met je?"
        let result = try await provider.synthesize(SpeechRequest(text: text, language: .nl, rate: 0.85))
        defer { try? FileManager.default.removeItem(at: result.audioURL) }
        #expect(result.voiceID == "nl-NL-FennaNeural")
        #expect(try Data(contentsOf: result.audioURL).count > 1000)
        let words = result.marks.compactMap { $0.range.range(in: text).map { String(text[$0]) } }
        #expect(words == ["Goedemorgen", "Hoe", "gaat", "het", "met", "je"])
    }

    @Test func speaksQuotesAndAmpersands() async throws {
        let provider = EdgeNativeProvider(workDirectory: temporaryDirectory("LiveNative"))
        let text = #"Hij zei: "Tom & Jerry" — 'leuk'."#
        let result = try await provider.synthesize(SpeechRequest(text: text, language: .nl))
        defer { try? FileManager.default.removeItem(at: result.audioURL) }
        #expect(result.marks.count >= 4)
    }

    @Test func speaksKorean() async throws {
        let provider = EdgeNativeProvider(workDirectory: temporaryDirectory("LiveNative"))
        let text = "좋은 아침이에요! 이따가 같이 커피 마실래요?"
        let result = try await provider.synthesize(SpeechRequest(text: text, language: .ko))
        defer { try? FileManager.default.removeItem(at: result.audioURL) }
        #expect(result.marks.count >= 4)
    }

    @Test func listsVoicesFromService() async throws {
        let provider = EdgeNativeProvider(catalog: EdgeVoiceCatalog(cacheURL: temporaryDirectory("LiveNativeVoices").appendingPathExtension("json")))
        let voices = try await provider.allVoices()
        #expect(voices.count > 100)
        #expect(voices.contains { $0.id == "nl-NL-FennaNeural" })
    }
}

// MARK: Support

enum Fixture {
    static func data(_ name: String, ext: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    /// Recorded WebSocket messages: per message 1 byte kind (1 text, 2 binary), 4-byte big-endian
    /// length, payload. Recorded from the live service with word boundaries on.
    static func frames(_ name: String) throws -> [EdgeSocketMessage] {
        let bytes = [UInt8](try data(name, ext: "frames"))
        var messages: [EdgeSocketMessage] = []
        var index = 0
        while index + 5 <= bytes.count {
            let length = bytes[index + 1 ..< index + 5].reduce(0) { $0 << 8 | Int($1) }
            let payload = Data(bytes[index + 5 ..< index + 5 + length])
            messages.append(bytes[index] == 1 ? .text(String(decoding: payload, as: UTF8.self)) : .binary(payload))
            index += 5 + length
        }
        return messages
    }
}

/// Replays one recorded turn per connection and records what was sent.
final class ReplayTransport: EdgeTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var turns: [[EdgeSocketMessage]]
    private var rejections: [EdgeNativeError]
    private let stallWhenEmpty: Bool
    private let delay: Duration?
    private let voiceList: Data?
    private var _urls: [URL] = []
    private var _headers: [[String: String]] = []
    private var _sent: [String] = []
    private var _getCount = 0

    init(
        turns: [[EdgeSocketMessage]], rejections: [EdgeNativeError] = [], stallWhenEmpty: Bool = false,
        delay: Duration? = nil, voiceList: Data? = nil
    ) {
        self.delay = delay
        self.turns = turns
        self.rejections = rejections
        self.stallWhenEmpty = stallWhenEmpty
        self.voiceList = voiceList
    }

    var urls: [URL] { lock.withLock { _urls } }
    var headers: [[String: String]] { lock.withLock { _headers } }
    var sent: [String] { lock.withLock { _sent } }
    var getCount: Int { lock.withLock { _getCount } }

    func connect(url: URL, headers: [String: String]) async throws -> any EdgeSocket {
        let (rejection, turn): (EdgeNativeError?, [EdgeSocketMessage]) = lock.withLock {
            _urls.append(url)
            _headers.append(headers)
            if !rejections.isEmpty { return (rejections.removeFirst(), []) }
            return (nil, turns.isEmpty ? [] : turns.removeFirst())
        }
        if let rejection { throw rejection }
        return ReplaySocket(messages: LockedBox(turn), stall: stallWhenEmpty, delay: delay) { [weak self] text in
            self?.lock.withLock { self?._sent.append(text) }
        }
    }

    func get(url: URL, headers: [String: String]) async throws -> Data {
        lock.withLock { _getCount += 1 }
        guard let voiceList else { throw EdgeNativeError.connectionClosed }
        return voiceList
    }

    private struct ReplaySocket: EdgeSocket {
        let messages: LockedBox<[EdgeSocketMessage]>
        let stall: Bool
        let delay: Duration?
        let onSend: @Sendable (String) -> Void

        func send(_ text: String) async throws { onSend(text) }

        func receive() async throws -> EdgeSocketMessage {
            if let delay { try await Task.sleep(for: delay) }
            if let next = messages.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) { return next }
            if stall { try await Task.sleep(for: .seconds(30)) }
            throw EdgeNativeError.connectionClosed
        }

        func close() {}
    }
}
