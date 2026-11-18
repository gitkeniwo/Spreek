import Foundation

public enum EdgeNativeError: Error, Sendable, Equatable, LocalizedError {
    /// The handshake or HTTP request was refused. `serverDate` is the response's `Date` header,
    /// used to correct clock skew (the token is time-based).
    case rejected(status: Int, serverDate: Date?)
    case unexpectedResponse(String)
    case connectionClosed

    public var errorDescription: String? {
        switch self {
        case .rejected(let status, _): "The Edge speech service refused the request (HTTP \(status))."
        case .unexpectedResponse(let detail): "Unexpected response from the Edge speech service: \(detail)."
        case .connectionClosed: "The Edge speech service closed the connection early."
        }
    }
}

/// A failure after the service accepted the connection (the 101 upgrade): a reset, a stall, a
/// close without audio. These point at the voice (or the boundary mode), not at the network.
public struct EdgeAfterHandshakeError: Error, Sendable, LocalizedError {
    public let underlying: any Error

    public init(_ underlying: any Error) {
        self.underlying = underlying
    }

    public var errorDescription: String? { underlying.localizedDescription }
}

// MARK: Transport

public enum EdgeSocketMessage: Sendable, Equatable {
    case text(String)
    case binary(Data)
}

/// One WebSocket connection; abstract so tests can replay recorded frames.
public protocol EdgeSocket: Sendable {
    func send(_ text: String) async throws
    func receive() async throws -> EdgeSocketMessage
    func close()
}

/// Opens connections and makes plain GET requests (the voice list).
public protocol EdgeTransport: Sendable {
    func connect(url: URL, headers: [String: String]) async throws -> any EdgeSocket
    func get(url: URL, headers: [String: String]) async throws -> Data
}

/// `URLSessionWebSocketTask` / `URLSession.data` transport.
public struct URLSessionEdgeTransport: EdgeTransport {
    public init() {}

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 10
        return URLSession(configuration: configuration)
    }()

    public func connect(url: URL, headers: [String: String]) async throws -> any EdgeSocket {
        var request = URLRequest(url: url)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let task = Self.session.webSocketTask(with: request)
        task.maximumMessageSize = 4 << 20
        task.resume()
        return Socket(task: task)
    }

    public func get(url: URL, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await Self.session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw EdgeNativeError.rejected(status: http.statusCode, serverDate: Self.serverDate(http))
        }
        return data
    }

    static func serverDate(_ response: HTTPURLResponse) -> Date? {
        guard let value = response.value(forHTTPHeaderField: "Date") else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value)
    }

    private struct Socket: EdgeSocket {
        let task: URLSessionWebSocketTask

        func send(_ text: String) async throws {
            do { try await task.send(.string(text)) } catch { throw mapped(error) }
        }

        func receive() async throws -> EdgeSocketMessage {
            do {
                // Cancelling the Swift task (timeout) must also abort the pending receive.
                let message = try await withTaskCancellationHandler {
                    try await task.receive()
                } onCancel: { [task] in
                    task.cancel(with: .goingAway, reason: nil)
                }
                switch message {
                case .string(let text): return .text(text)
                case .data(let data): return .binary(data)
                @unknown default: throw EdgeNativeError.unexpectedResponse("unknown WebSocket message")
                }
            } catch {
                throw mapped(error)
            }
        }

        func close() {
            task.cancel(with: .normalClosure, reason: nil)
        }

        /// A failed handshake surfaces as a generic error; the HTTP status is on the task. An error
        /// after a 101 is tagged, so callers can tell a misbehaving voice from a broken network.
        private func mapped(_ error: any Error) -> any Error {
            if let http = task.response as? HTTPURLResponse {
                if http.statusCode != 101 {
                    return EdgeNativeError.rejected(status: http.statusCode, serverDate: serverDate(http))
                }
                if !(error is CancellationError), !(error is EdgeAfterHandshakeError) { return EdgeAfterHandshakeError(error) }
            }
            return error
        }
    }
}

// MARK: Clock

/// Wall clock plus the skew learned from a rejected request's `Date` header (shared by all
/// providers in the process, like the token it feeds).
public final class EdgeClock: @unchecked Sendable {
    public static let shared = EdgeClock()

    private let lock = NSLock()
    private var skew: TimeInterval = 0
    private let base: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.base = now
    }

    public func now() -> Date {
        base().addingTimeInterval(lock.withLock { skew })
    }

    public func adjust(toServerDate serverDate: Date) {
        let local = base()
        lock.withLock { skew = serverDate.timeIntervalSince(local) }
    }
}

// MARK: Provider

/// Microsoft Edge neural voices spoken directly over the read-aloud WebSocket (no Python).
/// Unlike the CLI, it can ask for word boundaries (`SpeechRequest.boundaryMode`), so Edge voices
/// highlight word by word.
public struct EdgeNativeProvider: TTSProvider {
    public let id = ProviderID.edge
    public let displayName = "Edge Neural"

    public var transport: any EdgeTransport
    public var clock: EdgeClock
    public var timeout: TimeInterval
    /// Where audio files are written before the cache takes them.
    public var workDirectory: URL
    public var catalog: EdgeVoiceCatalog

    public init(
        transport: any EdgeTransport = URLSessionEdgeTransport(),
        clock: EdgeClock = .shared,
        timeout: TimeInterval = 10,
        workDirectory: URL = FileManager.default.temporaryDirectory.appending(path: "Spreek-Edge"),
        catalog: EdgeVoiceCatalog = EdgeVoiceCatalog()
    ) {
        self.transport = transport
        self.clock = clock
        self.timeout = timeout
        self.workDirectory = workDirectory
        self.catalog = catalog
    }

    public func supports(voiceID: String) -> Bool { EdgeCLIProvider.isEdgeVoiceID(voiceID) }

    public func voice(for request: SpeechRequest) -> String {
        if let voiceID = request.voiceID, EdgeCLIProvider.isEdgeVoiceID(voiceID) { return voiceID }
        return request.language.info.defaultEdgeVoice
    }

    public func synthesize(_ request: SpeechRequest) async throws -> SynthesisResult {
        guard !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TTSError.emptyText }
        let voice = voice(for: request)
        let rate = EdgeArguments.rate(request.rate)
        let chunks = EdgeMessages.split(EdgeMessages.escape(request.text))

        let mode = request.boundaryMode
        var audio = Data()
        var words: [EdgeWordBoundary] = []
        for chunk in chunks {
            // Each chunk's offsets restart at zero; shift them by the audio received so far.
            let shift = EdgeWordBoundary.ticks(forAudioBytes: audio.count)
            let turn = try await timedTurn(chunk, voice: voice, rate: rate, mode: mode)
            audio += turn.audio
            words += turn.words.map { EdgeWordBoundary(offset: $0.offset + shift, duration: $0.duration, text: $0.text) }
        }
        guard !audio.isEmpty else { throw TTSError.noAudioProduced }

        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        let media = workDirectory.appending(path: UUID().uuidString).appendingPathExtension("mp3")
        try audio.write(to: media)
        return SynthesisResult(
            audioURL: media,
            marks: EdgeWordBoundary.marks(from: words, in: request.text, granularity: mode == .word ? .word : .sentence),
            provider: .edge, voiceID: voice
        )
    }

    /// One turn with its own timeout (so a retry in another mode still fits). An error after the
    /// service had started answering (a frame arrived) is tagged as such.
    private func timedTurn(
        _ escapedChunk: String, voice: String, rate: String, mode: BoundaryMode
    ) async throws -> (audio: Data, words: [EdgeWordBoundary]) {
        let answered = LockedBox(false)
        do {
            return try await withTimeout(timeout) {
                try await retryingOnSkew {
                    answered.value = false
                    return try await speak(escapedChunk, voice: voice, rate: rate, mode: mode, answered: answered)
                }
            }
        } catch {
            if answered.value, !(error is CancellationError), !(error is EdgeAfterHandshakeError),
               !(error is EdgeNativeError) {
                throw EdgeAfterHandshakeError(error)
            }
            throw error
        }
    }

    /// One request/response turn on a fresh connection.
    func speak(
        _ escapedChunk: String, voice: String, rate: String, mode: BoundaryMode = .word,
        answered: LockedBox<Bool> = LockedBox(false)
    ) async throws -> (audio: Data, words: [EdgeWordBoundary]) {
        let url = EdgeEndpoint.synthesisURL(
            connectionID: EdgeEndpoint.randomHexID(uppercase: false), token: EdgeToken.secMSGEC(at: clock.now())
        )
        let socket = try await transport.connect(url: url, headers: EdgeEndpoint.socketHeaders(muid: EdgeEndpoint.randomHexID()))
        defer { socket.close() }
        try await socket.send(EdgeMessages.speechConfig(date: Date(), wordBoundaries: mode == .word))
        try await socket.send(EdgeMessages.ssmlRequest(
            requestID: EdgeEndpoint.randomHexID(uppercase: false), date: Date(),
            voice: voice, rate: rate, escapedText: escapedChunk
        ))

        var audio = Data()
        var words: [EdgeWordBoundary] = []
        while true {
            try Task.checkCancellation()
            let frame: EdgeFrame = switch try await socket.receive() {
            case .text(let text): try EdgeFrame.parse(text: text)
            case .binary(let data): try EdgeFrame.parse(binary: data)
            }
            answered.value = true
            switch frame {
            case .audio(let data): audio += data
            case .wordBoundaries(let boundaries): words += boundaries
            case .turnEnd: return (audio, words)
            case .turnStart, .response, .ignored: continue
            }
        }
    }

    /// Fetches the voice list from the service whatever the cache says, and stores it.
    public func refreshVoices() async throws -> [Voice] {
        try await catalog.refresh { try await fetchVoices() }
    }

    private func fetchVoices() async throws -> [Voice] {
        let data = try await retryingOnSkew {
            try await transport.get(
                url: EdgeEndpoint.voicesURL(token: EdgeToken.secMSGEC(at: clock.now())),
                headers: EdgeEndpoint.voiceListHeaders(muid: EdgeEndpoint.randomHexID())
            )
        }
        return EdgeVoiceCatalog.parseJSON(data)
    }

    /// A rejected handshake usually means the token's clock is off: adopt the server's clock and
    /// try once more.
    private func retryingOnSkew<T: Sendable>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch EdgeNativeError.rejected(_, let serverDate?) {
            clock.adjust(toServerDate: serverDate)
            return try await operation()
        }
    }

    // MARK: Voices

    public func voices(for language: LanguageCode) async throws -> [Voice] {
        try await allVoices().filter { $0.language == language }
    }

    /// Every Edge voice, from the shared disk cache (a day old at most) or the service's voice list.
    public func allVoices() async throws -> [Voice] {
        try await catalog.cachedVoices { try await fetchVoices() }
    }
}

/// Runs `operation`, throwing `TTSError.timedOut` if it takes longer than `seconds`.
func withTimeout<T: Sendable>(_ seconds: TimeInterval, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TTSError.timedOut(seconds: seconds)
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}
