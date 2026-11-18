@preconcurrency import AVFoundation

/// The macOS system voice via `AVSpeechSynthesizer`, rendered to a `.caf` file with
/// word-level boundary marks.
public struct SystemProvider: TTSProvider {
    public let id = ProviderID.system
    public let displayName = "macOS System"

    public var workDirectory: URL
    public var timeout: TimeInterval

    public init(
        workDirectory: URL = FileManager.default.temporaryDirectory.appending(path: "Spreek-System"),
        timeout: TimeInterval = 30
    ) {
        self.workDirectory = workDirectory
        self.timeout = timeout
    }

    public func voices(for language: LanguageCode) async throws -> [Voice] {
        Self.systemVoices(for: language).map(Self.voice(from:))
    }

    /// Voices for a language, best quality first (Premium → Enhanced → default),
    /// exact locale (`nl-NL`) before regional variants (`nl-BE`).
    static func systemVoices(for language: LanguageCode) -> [AVSpeechSynthesisVoice] {
        let locale = language.info.systemVoiceLanguage
        return voiceLookup.withLock { AVSpeechSynthesisVoice.speechVoices() }
            .filter { $0.language.hasPrefix(language.rawValue + "-") || $0.language == language.rawValue }
            .sorted { lhs, rhs in
                let lq = lhs.quality.rawValue, rq = rhs.quality.rawValue
                if lq != rq { return lq > rq }
                let lExact = lhs.language == locale, rExact = rhs.language == locale
                if lExact != rExact { return lExact }
                return lhs.name < rhs.name
            }
    }

    static func voice(from voice: AVSpeechSynthesisVoice) -> Voice {
        let quality: Voice.Quality = switch voice.quality {
        case .premium: .premium
        case .enhanced: .enhanced
        default: .standard
        }
        return Voice(
            id: voice.identifier, name: voice.name, locale: voice.language,
            gender: voice.gender == .female ? "Female" : voice.gender == .male ? "Male" : nil,
            quality: quality, provider: .system
        )
    }

    public func supports(voiceID: String) -> Bool { !EdgeCLIProvider.isEdgeVoiceID(voiceID) }

    public static func voiceName(for identifier: String) -> String? {
        installedVoice(identifier: identifier)?.name
    }

    /// `AVSpeechSynthesisVoice(identifier:)` returns a default voice for unknown ids (e.g. an
    /// Edge id), so check that it really is the requested one.
    static func installedVoice(identifier: String) -> AVSpeechSynthesisVoice? {
        guard let voice = voiceLookup.withLock({ AVSpeechSynthesisVoice(identifier: identifier) }),
              voice.identifier == identifier else { return nil }
        return voice
    }

    /// TextToSpeech's voice lookups are not thread-safe: two concurrent calls can abort the
    /// process ("Unlock of an os_unfair_lock not owned by current thread"). Serialize them.
    private static let voiceLookup = NSLock()

    /// Maps a speed multiplier onto `AVSpeechUtterance.rate` (default 0.5).
    static func utteranceRate(for speed: Double) -> Float {
        let rate = AVSpeechUtteranceDefaultSpeechRate * Float(speed)
        return min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
    }

    public func synthesize(_ request: SpeechRequest) async throws -> SynthesisResult {
        guard !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TTSError.emptyText }
        let selected = request.voiceID.flatMap(Self.installedVoice(identifier:))
            ?? Self.systemVoices(for: request.language).first
        guard let voice = selected else { throw TTSError.noVoice(request.language) }

        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        let url = workDirectory.appending(path: UUID().uuidString).appendingPathExtension("caf")
        let session = await SystemSynthesisSession(text: request.text, voice: voice, rate: Self.utteranceRate(for: request.rate), url: url)
        let marks = try await session.run(timeout: timeout)
        return SynthesisResult(audioURL: url, marks: marks, provider: .system, voiceID: voice.identifier)
    }
}

/// Owns one `AVSpeechSynthesizer.write` run and collects word ranges as they are synthesized.
/// The delegate fires during `write`, interleaved with buffers, so the frame count written so far
/// timestamps each word.
@MainActor
private final class SystemSynthesisSession: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let utterance: AVSpeechUtterance
    private let url: URL
    private let text: String

    private let lock = NSLock()
    nonisolated(unsafe) private var file: AVAudioFile?
    nonisolated(unsafe) private var framesWritten: AVAudioFramePosition = 0
    nonisolated(unsafe) private var sampleRate: Double = 22_050
    nonisolated(unsafe) private var wordStarts: [(range: NSRange, frame: AVAudioFramePosition)] = []
    nonisolated(unsafe) private var continuation: CheckedContinuation<[BoundaryMark], Error>?
    nonisolated(unsafe) private var writeError: Error?

    init(text: String, voice: AVSpeechSynthesisVoice, rate: Float, url: URL) {
        self.text = text
        self.url = url
        utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = rate
        super.init()
        synthesizer.delegate = self
    }

    func run(timeout: TimeInterval) async throws -> [BoundaryMark] {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock { self.continuation = continuation }
            synthesizer.write(utterance) { [self] buffer in
                self.handle(buffer)
            }
            Task { @MainActor [self] in
                try? await Task.sleep(for: .seconds(timeout))
                self.synthesizer.stopSpeaking(at: .immediate)
                self.finish(.failure(TTSError.timedOut(seconds: timeout)))
            }
        }
    }

    nonisolated private func handle(_ buffer: AVAudioBuffer) {
        guard let pcm = buffer as? AVAudioPCMBuffer else { return }
        if pcm.frameLength == 0 {
            finish(nil)
            return
        }
        lock.withLock {
            do {
                if file == nil {
                    sampleRate = pcm.format.sampleRate
                    file = try AVAudioFile(
                        forWriting: url, settings: pcm.format.settings,
                        commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved
                    )
                }
                try file?.write(from: pcm)
                framesWritten += AVAudioFramePosition(pcm.frameLength)
            } catch {
                writeError = error
            }
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance
    ) {
        lock.withLock { wordStarts.append((characterRange, framesWritten)) }
    }

    /// `result == nil` means synthesis completed: build marks from what was collected.
    nonisolated private func finish(_ result: Result<[BoundaryMark], Error>?) {
        let (continuation, outcome): (CheckedContinuation<[BoundaryMark], Error>?, Result<[BoundaryMark], Error>) = lock.withLock {
            let continuation = self.continuation
            self.continuation = nil
            let outcome: Result<[BoundaryMark], Error>
            if let result {
                outcome = result
            } else if let writeError {
                outcome = .failure(writeError)
            } else if file == nil || framesWritten == 0 {
                outcome = .failure(TTSError.noAudioProduced)
            } else {
                outcome = .success(Self.marks(from: wordStarts, totalFrames: framesWritten, sampleRate: sampleRate))
            }
            file = nil // closes the file
            return (continuation, outcome)
        }
        continuation?.resume(with: outcome)
    }

    nonisolated static func marks(
        from starts: [(range: NSRange, frame: AVAudioFramePosition)], totalFrames: AVAudioFramePosition, sampleRate: Double
    ) -> [BoundaryMark] {
        starts.enumerated().map { index, start in
            let endFrame = index + 1 < starts.count ? starts[index + 1].frame : totalFrames
            return BoundaryMark(
                start: Double(start.frame) / sampleRate,
                end: Double(endFrame) / sampleRate,
                range: TextRange(start.range),
                granularity: .word
            )
        }
    }
}
