import Foundation
import Testing
@testable import SpreekCore

@Suite struct EdgeCLIProviderTests {
    let home = URL(fileURLWithPath: "/Users/test")

    // MARK: Rate

    @Test(arguments: [
        (1.0, "+0%"), (0.85, "-15%"), (0.8, "-20%"), (0.7, "-30%"), (1.2, "+20%"), (0.5, "-50%"), (2.0, "+100%"), (0.999, "+0%"),
    ])
    func rateFormatting(speed: Double, expected: String) {
        #expect(EdgeArguments.rate(speed) == expected)
    }

    @Test func synthesisArguments() {
        let args = EdgeArguments.synthesize(
            voice: "nl-NL-FennaNeural", speed: 0.85, text: "-5 graden vandaag",
            media: URL(fileURLWithPath: "/tmp/a.mp3"), subtitles: URL(fileURLWithPath: "/tmp/a.srt")
        )
        #expect(args == [
            "-v", "nl-NL-FennaNeural", "--rate=-15%", "--text=-5 graden vandaag",
            "--write-media", "/tmp/a.mp3", "--write-subtitles", "/tmp/a.srt",
        ])
    }

    // MARK: Path resolution

    @Test func candidateOrder() {
        let resolver = EdgeExecutableResolver(configuredPath: "~/bin/edge-tts", homeDirectory: home) { _ in false }
        #expect(resolver.candidates.map(\.executable.path) == [
            "/Users/test/bin/edge-tts",
            "/Users/test/.local/bin/edge-tts",
            "/opt/homebrew/bin/edge-tts",
            "/Users/test/.local/bin/uvx",
        ])
        #expect(resolver.candidates.last?.prefixArguments == ["edge-tts"])
        #expect(resolver.resolve() == nil)
    }

    @Test func configuredPathWins() {
        let resolver = EdgeExecutableResolver(configuredPath: "/custom/edge-tts", homeDirectory: home) { _ in true }
        #expect(resolver.resolve() == EdgeCommand(executable: URL(fileURLWithPath: "/custom/edge-tts")))
    }

    @Test func emptyConfiguredPathIsIgnored() {
        let resolver = EdgeExecutableResolver(configuredPath: "  ", homeDirectory: home) { _ in true }
        #expect(resolver.resolve()?.executable.path == "/Users/test/.local/bin/edge-tts")
    }

    @Test func fallsThroughToHomebrew() {
        let resolver = EdgeExecutableResolver(homeDirectory: home) { $0 == "/opt/homebrew/bin/edge-tts" }
        #expect(resolver.resolve() == EdgeCommand(executable: URL(fileURLWithPath: "/opt/homebrew/bin/edge-tts")))
    }

    @Test func fallsThroughToUVX() {
        let resolver = EdgeExecutableResolver(homeDirectory: home) { $0.hasSuffix("/uvx") }
        #expect(resolver.resolve() == EdgeCommand(
            executable: URL(fileURLWithPath: "/Users/test/.local/bin/uvx"), prefixArguments: ["edge-tts"]
        ))
    }

    @Test func configuredUVXGetsPrefix() {
        let resolver = EdgeExecutableResolver(configuredPath: "/opt/uv/uvx", homeDirectory: home) { _ in true }
        #expect(resolver.resolve()?.prefixArguments == ["edge-tts"])
    }

    // MARK: Synthesis with a fake process

    private func provider(runner: MockRunner, exists: @escaping @Sendable (String) -> Bool = { _ in true }) -> EdgeCLIProvider {
        EdgeCLIProvider(
            resolver: EdgeExecutableResolver(homeDirectory: home, isExecutable: exists),
            runner: runner,
            workDirectory: temporaryDirectory("EdgeWork"),
            catalog: EdgeVoiceCatalog(cacheURL: temporaryDirectory("Voices").appendingPathExtension("json"))
        )
    }

    @Test func synthesizeWritesFilesAndParsesMarks() async throws {
        let runner = MockRunner { call in
            let media = try #require(MockRunner.value(of: "--write-media", in: call.arguments))
            let subs = try #require(MockRunner.value(of: "--write-subtitles", in: call.arguments))
            try Data("mp3".utf8).write(to: URL(fileURLWithPath: media))
            try "1\n00:00:00,100 --> 00:00:01,000\nHallo.\n\n2\n00:00:01,000 --> 00:00:02,000\nDag!\n"
                .write(toFile: subs, atomically: true, encoding: .utf8)
            return ProcessOutput(status: 0)
        }
        let edge = provider(runner: runner, exists: { $0.hasSuffix("/uvx") })
        let result = try await edge.synthesize(SpeechRequest(text: "Hallo. Dag!", language: .nl, voiceID: nil, rate: 0.85))

        let call = try #require(runner.calls.first)
        #expect(call.executable.path == "/Users/test/.local/bin/uvx")
        #expect(Array(call.arguments.prefix(3)) == ["edge-tts", "-v", "nl-NL-FennaNeural"])
        #expect(call.arguments.contains("--rate=-15%"))
        #expect(result.provider == .edge)
        #expect(result.voiceID == "nl-NL-FennaNeural")
        #expect(result.marks.map(\.range) == [TextRange(location: 0, length: 6), TextRange(location: 7, length: 4)])
        #expect(result.subtitlesURL != nil)
    }

    @Test func nonEdgeVoiceIDUsesLanguageDefault() {
        let edge = provider(runner: MockRunner { _ in ProcessOutput(status: 0) })
        #expect(edge.voice(for: SpeechRequest(text: "x", language: .de, voiceID: "com.apple.voice.compact.de-DE.Anna")) == "de-DE-KatjaNeural")
        #expect(edge.voice(for: SpeechRequest(text: "x", language: .de, voiceID: "de-DE-ConradNeural")) == "de-DE-ConradNeural")
    }

    @Test func missingExecutableThrows() async {
        let edge = provider(runner: MockRunner { _ in ProcessOutput(status: 0) }, exists: { _ in false })
        await #expect(throws: TTSError.executableNotFound) {
            try await edge.synthesize(SpeechRequest(text: "Hallo", language: .nl))
        }
    }

    @Test func nonZeroExitThrows() async {
        let edge = provider(runner: MockRunner { _ in ProcessOutput(status: 1, stderr: Data("trace\nNoAudioReceived\n".utf8)) })
        await #expect(throws: TTSError.processFailed(status: 1, message: "NoAudioReceived")) {
            try await edge.synthesize(SpeechRequest(text: "Hallo", language: .nl))
        }
    }

    @Test func emptyMediaThrows() async {
        let edge = provider(runner: MockRunner { _ in ProcessOutput(status: 0) })
        await #expect(throws: TTSError.noAudioProduced) {
            try await edge.synthesize(SpeechRequest(text: "Hallo", language: .nl))
        }
    }

    @Test func realRunnerTimesOut() async {
        let runner = SystemProcessRunner()
        let start = Date()
        await #expect(throws: TTSError.timedOut(seconds: 0.3)) {
            _ = try await runner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], environment: nil, timeout: 0.3)
        }
        #expect(Date().timeIntervalSince(start) < 3)
    }

    @Test func realRunnerCapturesOutput() async throws {
        let output = try await SystemProcessRunner().run(
            executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["hoi"], environment: nil, timeout: 5
        )
        #expect(output.status == 0)
        #expect(String(decoding: output.stdout, as: UTF8.self) == "hoi\n")
    }

    // MARK: Voice list

    static let listing = """
    Name                               Gender    ContentCategories      VoicePersonalities
    ---------------------------------  --------  ---------------------  --------------------------------------
    de-DE-FlorianMultilingualNeural    Male      General                Friendly, Positive
    de-DE-KatjaNeural                  Female    General                Friendly, Positive
    nl-BE-DenaNeural                   Female    General                Friendly, Positive
    nl-NL-FennaNeural                  Female    General                Friendly, Positive
    zh-CN-XiaoxiaoNeural               Female    News, Novel            Warm
    """

    @Test func parsesVoiceList() {
        let voices = EdgeVoiceCatalog.parse(Self.listing)
        #expect(voices.count == 5)
        let fenna = voices[3]
        #expect(fenna == Voice(id: "nl-NL-FennaNeural", name: "Fenna", locale: "nl-NL", gender: "Female", quality: .neural, provider: .edge))
        #expect(fenna.language == .nl)
        #expect(voices[0].name == "Florian")
        #expect(voices[4].language == .zhCN)
        #expect(voices[2].language == .nl)
    }

    @Test func voiceLocalesMapToRegionalVariants() {
        #expect(LanguageCode(locale: "en-GB") == .enGB)
        #expect(LanguageCode(locale: "en_US") == .enUS)
        #expect(LanguageCode(locale: "zh-TW") == .zhTW)
        #expect(LanguageCode(locale: "pt-BR") == .ptBR)
        #expect(LanguageCode(locale: "es-ES") == .es)
        #expect(LanguageCode(locale: "nl-BE") == .nl)
        #expect(LanguageCode(locale: "en-AU") == nil)
        #expect(LanguageCode(locale: "pt-PT") == nil)
        #expect(LanguageCode(locale: "zh-HK") == .zhHK)
        #expect(LanguageCode(locale: "zh-SG") == nil)
    }

    @Test func voicesForLanguageAreCachedForADay() async throws {
        let runner = MockRunner { _ in ProcessOutput(status: 0, stdout: Data(Self.listing.utf8)) }
        let cacheURL = temporaryDirectory("Voices").appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        let clock = LockedBox(Date(timeIntervalSince1970: 1_000_000))
        var edge = provider(runner: runner)
        edge.catalog = EdgeVoiceCatalog(cacheURL: cacheURL, now: { clock.value })

        let nl = try await edge.voices(for: .nl)
        #expect(nl.map(\.id) == ["nl-BE-DenaNeural", "nl-NL-FennaNeural"])
        #expect(runner.calls.first?.arguments == ["--list-voices"])

        clock.value += 20 * 3600
        _ = try await edge.voices(for: .de)
        #expect(runner.calls.count == 1, "served from disk cache")

        clock.value += 5 * 3600
        _ = try await edge.voices(for: .de)
        #expect(runner.calls.count == 2, "refetched after a day")

        _ = try await edge.refreshVoices()
        #expect(runner.calls.count == 3, "a forced refresh always fetches")
    }

    @Test func staleVoiceCacheBeatsFailure() async throws {
        let cacheURL = temporaryDirectory("Voices").appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        let clock = LockedBox(Date(timeIntervalSince1970: 1_000_000))
        let catalog = EdgeVoiceCatalog(cacheURL: cacheURL, now: { clock.value })
        _ = try await catalog.voices { Self.listing }
        clock.value += 30 * 24 * 3600
        let voices = try await catalog.voices { throw TTSError.executableNotFound }
        #expect(voices.count == 5)
    }
}
