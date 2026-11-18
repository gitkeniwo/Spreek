import Foundation

/// Debug aid (UserDefaults `SpreekDebugFailWordMarks` = a voice id): the native client fails for
/// that voice in word mode the way Maarten does (reset after the handshake), and works in
/// sentence mode. Lets the fallback be tried by hand when the real service behaves.
struct DebugFailingProvider: TTSProvider {
    let base: any TTSProvider
    let voiceID: String

    var id: ProviderID { base.id }
    var displayName: String { base.displayName }

    func voices(for language: LanguageCode) async throws -> [Voice] { try await base.voices(for: language) }
    func supports(voiceID: String) -> Bool { base.supports(voiceID: voiceID) }

    func synthesize(_ request: SpeechRequest) async throws -> SynthesisResult {
        if request.voiceID == voiceID, request.boundaryMode == .word {
            try await Task.sleep(for: .milliseconds(300))
            throw EdgeAfterHandshakeError(URLError(.networkConnectionLost))
        }
        return try await base.synthesize(request)
    }
}
