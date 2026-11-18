import Foundation
@testable import SpreekCore

func temporaryDirectory(_ label: String = "Spreek") -> URL {
    FileManager.default.temporaryDirectory.appending(path: "\(label)-\(UUID().uuidString)")
}

/// A provider that writes a dummy audio file, or throws.
final class MockProvider: TTSProvider, @unchecked Sendable {
    let id: ProviderID
    var displayName: String { "Mock \(id.rawValue)" }
    let error: (any Error)?
    let marks: [BoundaryMark]
    let delay: Duration?
    private let lock = NSLock()
    private var _requests: [SpeechRequest] = []

    init(id: ProviderID, error: (any Error)? = nil, marks: [BoundaryMark] = [], delay: Duration? = nil) {
        self.id = id
        self.error = error
        self.marks = marks
        self.delay = delay
    }

    var requests: [SpeechRequest] { lock.withLock { _requests } }
    var callCount: Int { requests.count }

    func voices(for language: LanguageCode) async throws -> [Voice] { [] }

    func synthesize(_ request: SpeechRequest) async throws -> SynthesisResult {
        lock.withLock { _requests.append(request) }
        if let delay { try await Task.sleep(for: delay) }
        if let error { throw error }
        let url = temporaryDirectory("MockAudio").appendingPathExtension(id == .edge ? "mp3" : "caf")
        try Data("audio for \(request.text)".utf8).write(to: url)
        return SynthesisResult(audioURL: url, marks: marks, provider: id, voiceID: id == .edge ? request.voiceID ?? "edge-voice" : "system-voice")
    }
}

/// Player with a hand-driven clock.
@MainActor
final class MockPlayer: AudioPlaying {
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 4
    private(set) var isPlaying = false
    var isMuted = false
    var onFinish: (@MainActor () -> Void)?
    private(set) var loaded: [URL] = []
    var loadError: (any Error)?

    func load(_ url: URL) throws {
        if let loadError { throw loadError }
        loaded.append(url)
        currentTime = 0
    }

    func play() { isPlaying = true }
    func pause() { isPlaying = false }
    func seek(to time: TimeInterval) { currentTime = time }

    func stop() {
        isPlaying = false
        currentTime = 0
    }

    /// Simulates reaching the end of the file.
    func finish() {
        currentTime = duration
        isPlaying = false
        onFinish?()
    }
}

/// Records invocations; returns a canned output or writes media files like edge-tts would.
final class MockRunner: ProcessRunning, @unchecked Sendable {
    struct Call: Sendable {
        let executable: URL
        let arguments: [String]
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    let handler: @Sendable (Call) throws -> ProcessOutput

    init(handler: @escaping @Sendable (Call) throws -> ProcessOutput) {
        self.handler = handler
    }

    var calls: [Call] { lock.withLock { _calls } }

    func run(executable: URL, arguments: [String], environment: [String: String]?, timeout: TimeInterval) async throws -> ProcessOutput {
        let call = Call(executable: executable, arguments: arguments)
        lock.withLock { _calls.append(call) }
        return try handler(call)
    }

    /// Value following `flag` in `arguments`.
    static func value(of flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
