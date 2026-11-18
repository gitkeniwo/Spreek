import Foundation
import Testing
@testable import SpreekCore

@Suite struct ProviderChainTests {
    let request = SpeechRequest(text: "Hallo", language: .nl, voiceID: "nl-NL-FennaNeural")

    @Test func usesPrimaryWhenItWorks() async throws {
        let edge = MockProvider(id: .edge)
        let system = MockProvider(id: .system)
        let result = try await ProviderChain(primary: edge, fallback: system).synthesize(request)
        #expect(result.provider == .edge)
        #expect(edge.callCount == 1)
        #expect(system.callCount == 0)
    }

    @Test(arguments: [TTSError.executableNotFound, .timedOut(seconds: 10), .processFailed(status: 1, message: "x")])
    func fallsBackOnError(error: TTSError) async throws {
        let edge = MockProvider(id: .edge, error: error)
        let system = MockProvider(id: .system)
        let reported = LockedBox<String?>(nil)
        let chain = ProviderChain(primary: edge, fallback: system) { reported.value = "\($0)" }
        let result = try await chain.synthesize(request)
        #expect(result.provider == .system)
        #expect(system.requests == [request])
        #expect(reported.value == "\(error)")
    }

    @Test func throwsFallbackErrorWhenBothFail() async {
        let chain = ProviderChain(
            primary: MockProvider(id: .edge, error: TTSError.executableNotFound),
            fallback: MockProvider(id: .system, error: TTSError.noVoice(.nl))
        )
        await #expect(throws: TTSError.noVoice(.nl)) { try await chain.synthesize(request) }
    }

    @Test func noFallbackRethrows() async {
        let chain = ProviderChain(primary: MockProvider(id: .edge, error: TTSError.executableNotFound), fallback: nil)
        await #expect(throws: TTSError.executableNotFound) { try await chain.synthesize(request) }
    }

    @Test func cancellationDoesNotFallBack() async {
        let system = MockProvider(id: .system)
        let chain = ProviderChain(primary: MockProvider(id: .edge, error: CancellationError()), fallback: system)
        await #expect(throws: CancellationError.self) { try await chain.synthesize(request) }
        #expect(system.callCount == 0)
    }

    @Test func voiceOnlyTheFallbackKnowsSkipsThePrimary() async throws {
        let edge = VoiceAwareProvider(id: .edge) { EdgeCLIProvider.isEdgeVoiceID($0) }
        let system = VoiceAwareProvider(id: .system) { !EdgeCLIProvider.isEdgeVoiceID($0) }
        let chain = ProviderChain(primary: edge, fallback: system)
        let macVoice = SpeechRequest(text: "Hallo", language: .nl, voiceID: "com.apple.voice.premium.nl-NL.Xander")
        #expect(try await chain.synthesize(macVoice).provider == .system)
        #expect(edge.inner.callCount == 0)
        #expect(try await chain.synthesize(request).provider == .edge)
    }
}

/// `MockProvider` that only recognizes some voice ids.
private struct VoiceAwareProvider: TTSProvider {
    let inner: MockProvider
    let recognizes: @Sendable (String) -> Bool
    var id: ProviderID { inner.id }
    var displayName: String { inner.displayName }

    init(id: ProviderID, recognizes: @escaping @Sendable (String) -> Bool) {
        inner = MockProvider(id: id)
        self.recognizes = recognizes
    }

    func voices(for language: LanguageCode) async throws -> [Voice] { [] }
    func synthesize(_ request: SpeechRequest) async throws -> SynthesisResult { try await inner.synthesize(request) }
    func supports(voiceID: String) -> Bool { recognizes(voiceID) }
}
