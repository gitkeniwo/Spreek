import Foundation

/// How to invoke edge-tts: an absolute executable plus arguments that precede the edge-tts ones
/// (`["edge-tts"]` when going through `uvx`).
public struct EdgeCommand: Sendable, Hashable {
    public let executable: URL
    public let prefixArguments: [String]

    public init(executable: URL, prefixArguments: [String] = []) {
        self.executable = executable
        self.prefixArguments = prefixArguments
    }
}

/// Finds edge-tts. GUI apps don't inherit the shell PATH, so only absolute paths are tried, in
/// this order: path from Settings → `~/.local/bin/edge-tts` → `/opt/homebrew/bin/edge-tts` →
/// `~/.local/bin/uvx edge-tts`.
public struct EdgeExecutableResolver: Sendable {
    public var configuredPath: String?
    public var homeDirectory: URL
    public var isExecutable: @Sendable (String) -> Bool

    public init(
        configuredPath: String? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.configuredPath = configuredPath
        self.homeDirectory = homeDirectory
        self.isExecutable = isExecutable
    }

    /// All candidates in lookup order, whether or not they exist.
    public var candidates: [EdgeCommand] {
        var result: [EdgeCommand] = []
        if let configuredPath, !configuredPath.trimmingCharacters(in: .whitespaces).isEmpty {
            let expanded = expandTilde(configuredPath.trimmingCharacters(in: .whitespaces))
            let url = URL(fileURLWithPath: expanded)
            result.append(EdgeCommand(
                executable: url,
                prefixArguments: url.lastPathComponent == "uvx" ? ["edge-tts"] : []
            ))
        }
        let localBin = homeDirectory.appending(path: ".local/bin")
        result.append(EdgeCommand(executable: localBin.appending(path: "edge-tts")))
        result.append(EdgeCommand(executable: URL(fileURLWithPath: "/opt/homebrew/bin/edge-tts")))
        result.append(EdgeCommand(executable: localBin.appending(path: "uvx"), prefixArguments: ["edge-tts"]))
        return result
    }

    /// First candidate that exists and is executable.
    public func resolve() -> EdgeCommand? {
        candidates.first { isExecutable($0.executable.path) }
    }

    private func expandTilde(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        return homeDirectory.path + path.dropFirst()
    }
}

/// Builds edge-tts command lines.
public enum EdgeArguments {
    /// Speed multiplier → edge-tts `--rate` value: 0.85 → `-15%`, 1.0 → `+0%`, 1.2 → `+20%`.
    public static func rate(_ speed: Double) -> String {
        let percent = Int(((speed - 1) * 100).rounded())
        return percent >= 0 ? "+\(percent)%" : "\(percent)%"
    }

    /// `--text=` (rather than `-t <text>`) so text starting with `-` isn't read as an option.
    public static func synthesize(voice: String, speed: Double, text: String, media: URL, subtitles: URL) -> [String] {
        [
            "-v", voice,
            "--rate=\(rate(speed))",
            "--text=\(text)",
            "--write-media", media.path,
            "--write-subtitles", subtitles.path,
        ]
    }

    public static let listVoices = ["--list-voices"]
}

/// Microsoft Edge neural voices through the `edge-tts` CLI.
public struct EdgeCLIProvider: TTSProvider {
    public let id = ProviderID.edge
    public let displayName = "Edge Neural"

    public var resolver: EdgeExecutableResolver
    public var runner: any ProcessRunning
    public var timeout: TimeInterval
    /// Where audio and subtitle files are written before the cache takes them.
    public var workDirectory: URL
    public var catalog: EdgeVoiceCatalog

    public init(
        resolver: EdgeExecutableResolver = EdgeExecutableResolver(),
        runner: any ProcessRunning = SystemProcessRunner(),
        timeout: TimeInterval = 10,
        workDirectory: URL = FileManager.default.temporaryDirectory.appending(path: "Spreek-Edge"),
        catalog: EdgeVoiceCatalog = EdgeVoiceCatalog()
    ) {
        self.resolver = resolver
        self.runner = runner
        self.timeout = timeout
        self.workDirectory = workDirectory
        self.catalog = catalog
    }

    /// Edge short names look like `nl-NL-FennaNeural`.
    public static func isEdgeVoiceID(_ id: String) -> Bool {
        id.hasSuffix("Neural") && id.split(separator: "-").count >= 3
    }

    public func supports(voiceID: String) -> Bool { Self.isEdgeVoiceID(voiceID) }

    public func voice(for request: SpeechRequest) -> String {
        if let voiceID = request.voiceID, Self.isEdgeVoiceID(voiceID) { return voiceID }
        return request.language.info.defaultEdgeVoice
    }

    public func synthesize(_ request: SpeechRequest) async throws -> SynthesisResult {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TTSError.emptyText }
        guard let command = resolver.resolve() else { throw TTSError.executableNotFound }

        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        let base = workDirectory.appending(path: UUID().uuidString)
        let media = base.appendingPathExtension("mp3")
        let subtitles = base.appendingPathExtension("srt")
        let voice = voice(for: request)
        let arguments = command.prefixArguments
            + EdgeArguments.synthesize(voice: voice, speed: request.rate, text: request.text, media: media, subtitles: subtitles)

        let output = try await runner.run(
            executable: command.executable, arguments: arguments,
            environment: Self.environment(home: resolver.homeDirectory), timeout: timeout
        )
        guard output.status == 0 else {
            try? FileManager.default.removeItem(at: media)
            try? FileManager.default.removeItem(at: subtitles)
            throw TTSError.processFailed(status: output.status, message: Self.lastLine(of: output.stderr))
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: media.path)[.size] as? Int) ?? 0
        guard size > 0 else { throw TTSError.noAudioProduced }

        let srt = (try? String(contentsOf: subtitles, encoding: .utf8)) ?? ""
        let marks = SRTParser.marks(from: SRTParser.parse(srt), in: request.text)
        return SynthesisResult(
            audioURL: media, marks: marks, provider: .edge, voiceID: voice,
            subtitlesURL: FileManager.default.fileExists(atPath: subtitles.path) ? subtitles : nil
        )
    }

    public func voices(for language: LanguageCode) async throws -> [Voice] {
        try await allVoices().filter { $0.language == language }
    }

    /// Every Edge voice, from the disk cache (a day old at most) or `edge-tts --list-voices`.
    public func allVoices() async throws -> [Voice] {
        try await catalog.voices { try await listing() }
    }

    /// Fetches the list with `edge-tts --list-voices` whatever the cache says, and stores it.
    public func refreshVoices() async throws -> [Voice] {
        try await catalog.refresh { EdgeVoiceCatalog.parse(try await listing()) }
    }

    private func listing() async throws -> String {
        guard let command = resolver.resolve() else { throw TTSError.executableNotFound }
        let output = try await runner.run(
            executable: command.executable, arguments: command.prefixArguments + EdgeArguments.listVoices,
            environment: Self.environment(home: resolver.homeDirectory), timeout: 30
        )
        guard output.status == 0 else {
            throw TTSError.processFailed(status: output.status, message: Self.lastLine(of: output.stderr))
        }
        return String(decoding: output.stdout, as: UTF8.self)
    }

    /// Minimal environment with a PATH that reaches uv-installed tools.
    static func environment(home: URL) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = [home.appending(path: ".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        env["PATH"] = (extra + [env["PATH"]].compactMap { $0 }).joined(separator: ":")
        env["HOME"] = env["HOME"] ?? home.path
        return env
    }

    private static func lastLine(of data: Data) -> String {
        String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .last
            .map(String.init) ?? ""
    }
}
