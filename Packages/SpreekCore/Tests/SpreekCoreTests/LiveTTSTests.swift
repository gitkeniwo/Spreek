import Foundation
import Testing
@testable import SpreekCore

/// Calls the real edge-tts (network) and system synthesizer. Opt in with `SPREEK_LIVE_TTS=1 swift test`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SPREEK_LIVE_TTS"] == "1"))
struct LiveTTSTests {
    @Test func speaksDutchWithFenna() async throws {
        let edge = EdgeCLIProvider(workDirectory: temporaryDirectory("LiveEdge"))
        let text = "Goedemorgen. Hoe gaat het met je?"
        let result = try await edge.synthesize(SpeechRequest(text: text, language: .nl, rate: 0.85))
        defer { try? FileManager.default.removeItem(at: result.audioURL) }
        #expect(result.voiceID == "nl-NL-FennaNeural")
        let size = try FileManager.default.attributesOfItem(atPath: result.audioURL.path)[.size] as? Int ?? 0
        #expect(size > 1000)
        #expect(result.marks.count == 2)
        #expect(result.marks.first?.range.range(in: text).map { String(text[$0]) } == "Goedemorgen.")
    }

    @Test func listsDutchVoices() async throws {
        let edge = EdgeCLIProvider(catalog: EdgeVoiceCatalog(cacheURL: temporaryDirectory("LiveVoices").appendingPathExtension("json")))
        let voices = try await edge.voices(for: .nl)
        #expect(voices.contains { $0.id == "nl-NL-FennaNeural" })
    }

    @Test func systemVoiceRendersWordMarks() async throws {
        let text = "Goedemorgen, hoe gaat het?"
        let result = try await SystemProvider(workDirectory: temporaryDirectory("LiveSystem"))
            .synthesize(SpeechRequest(text: text, language: .nl))
        defer { try? FileManager.default.removeItem(at: result.audioURL) }
        #expect(result.provider == .system)
        #expect(result.marks.count >= 4)
        #expect(result.marks.allSatisfy { $0.granularity == .word && $0.end >= $0.start })
        #expect(result.marks.first?.range.range(in: text).map { text[$0].hasPrefix("Goedemorgen") } == true)
        let size = try FileManager.default.attributesOfItem(atPath: result.audioURL.path)[.size] as? Int ?? 0
        #expect(size > 1000)
    }
}

/// Every language's default voice, spoken by the native client in both boundary modes. Prints a
/// table; fails only when every voice fails, so one Microsoft-side breakage doesn't turn the suite red.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SPREEK_LIVE_TTS"] == "1"))
struct LiveVoiceTableTests {
    private struct Row { let language: LanguageCode; let voice: String; let word: String; let sentence: String }

    private static func outcome(_ provider: EdgeNativeProvider, _ language: LanguageCode, _ mode: BoundaryMode) async -> String {
        let text = VoiceStatus.sampleText(for: language)
        let started = Date()
        do {
            let result = try await provider.synthesize(SpeechRequest(
                text: text, language: language, voiceID: language.info.defaultEdgeVoice, boundaryMode: mode
            ))
            defer { try? FileManager.default.removeItem(at: result.audioURL) }
            return String(format: "ok %.1fs (%d marks)", Date().timeIntervalSince(started), result.marks.count)
        } catch {
            return "FAIL \(String(format: "%.1fs", Date().timeIntervalSince(started))) \(EdgeFailure.classify(error))"
        }
    }

    @Test func defaultVoicesInBothModes() async {
        let provider = EdgeNativeProvider(timeout: 10, workDirectory: temporaryDirectory("LiveNative"))
        var rows: [Row] = []
        for language in LanguageCode.allCases {
            rows.append(Row(
                language: language, voice: language.info.defaultEdgeVoice,
                word: await Self.outcome(provider, language, .word), sentence: await Self.outcome(provider, language, .sentence)
            ))
        }
        let width = rows.map(\.voice.count).max() ?? 0
        print("\nLanguage  " + "Voice".padding(toLength: width, withPad: " ", startingAt: 0) + "  Word marks                        Sentence marks")
        for row in rows {
            print(row.language.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0) + "  "
                + row.voice.padding(toLength: width, withPad: " ", startingAt: 0) + "  "
                + row.word.padding(toLength: 32, withPad: " ", startingAt: 0) + "  " + row.sentence)
        }
        let working = rows.filter { $0.word.hasPrefix("ok") || $0.sentence.hasPrefix("ok") }
        #expect(!working.isEmpty, "every default voice failed in both modes")
    }
}

/// Fast, no audio: only queries installed voices.
@Suite struct SystemVoiceSelectionTests {
    @Test func edgeIDIsNotASystemVoice() {
        #expect(SystemProvider.installedVoice(identifier: "de-DE-KatjaNeural") == nil)
    }

    @Test func voicesMatchLanguageBestFirst() {
        let voices = SystemProvider.systemVoices(for: .de)
        #expect(voices.allSatisfy { $0.language.hasPrefix("de") })
        let qualities = voices.map(\.quality.rawValue)
        #expect(qualities == qualities.sorted(by: >))
    }

    /// TextToSpeech aborts ("Unlock of an os_unfair_lock not owned by current thread") when
    /// voices are looked up from several threads at once; this used to crash parallel test runs.
    @Test func concurrentLookupsDoNotCrash() {
        DispatchQueue.concurrentPerform(iterations: 64) { index in
            if index.isMultiple(of: 2) {
                _ = SystemProvider.installedVoice(identifier: "de-DE-KatjaNeural")
            } else {
                _ = SystemProvider.voiceName(for: "com.apple.voice.compact.nl-NL.Xander")
            }
        }
    }
}
