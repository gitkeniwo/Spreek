import Foundation

import OSLog

/// Turns a request into audio, trying steps in order until one works and saying how it went.
///
/// A **flat** chain (`init(providers:)`) tries each provider in order and moves on at any error.
///
/// The **layered** chain (`init(mode:native:cli:system:…)`) is what the app uses for Edge voices.
/// For the chosen voice, in Automatic mode: native client with word marks, native client with
/// sentence marks, the edge-tts CLI. Then the backup voice through the same three steps, then the
/// macOS voice. Native-only and CLI-only modes drop the steps they don't allow but keep the rest.
/// `VoiceHealth` remembers what failed so the next request skips it; a failure of the whole service
/// skips the remaining native steps. Everything about the order lives here.
public struct ProviderChain: Sendable {
    public let providers: [any TTSProvider]
    /// Called with a step's error when moving on to the next (for logging).
    public var onFallback: (@Sendable (any Error) -> Void)?
    /// Layered chains only: called after a request found a voice failing on its own, so the voice
    /// list can be refreshed (the voice may have been retired).
    public var onVoiceFailure: (@Sendable () -> Void)?

    private var layers: Layers?

    private struct Layers: Sendable {
        let mode: EdgeEngineMode
        let native: (any TTSProvider)?
        let cli: (any TTSProvider)?
        let system: any TTSProvider
        let health: VoiceHealth
        let catalog: @Sendable () -> EdgeVoiceCatalog.Snapshot?
    }

    private static let logger = Logger(subsystem: "nl.spreek.app", category: "speech")

    public init(providers: [any TTSProvider], onFallback: (@Sendable (any Error) -> Void)? = nil) {
        precondition(!providers.isEmpty, "a chain needs at least one provider")
        self.providers = providers
        self.onFallback = onFallback
    }

    public init(primary: any TTSProvider, fallback: (any TTSProvider)?, onFallback: (@Sendable (any Error) -> Void)? = nil) {
        self.init(providers: [primary] + [fallback].compactMap { $0 }, onFallback: onFallback)
    }

    /// A layered chain. `native` / `cli` are ignored when `mode` doesn't allow them. `catalog`
    /// supplies the voice list for the Auto backup voice.
    public init(
        mode: EdgeEngineMode = .automatic, native: (any TTSProvider)?, cli: (any TTSProvider)?, system: any TTSProvider,
        health: VoiceHealth = VoiceHealth(url: nil),
        catalog: @escaping @Sendable () -> EdgeVoiceCatalog.Snapshot? = { nil },
        onFallback: (@Sendable (any Error) -> Void)? = nil
    ) {
        let native = mode == .cliOnly ? nil : native
        let cli = mode == .nativeOnly ? nil : cli
        self.providers = ([native, cli].compactMap { $0 }) + [system]
        self.onFallback = onFallback
        self.layers = Layers(mode: mode, native: native, cli: cli, system: system, health: health, catalog: catalog)
    }

    public var primary: any TTSProvider { providers[0] }

    public func synthesize(_ request: SpeechRequest) async throws -> SynthesisResult {
        if let layers { return try await synthesizeLayered(request, layers) }
        return try await synthesizeFlat(request)
    }

    // MARK: Flat

    /// A voice only a later provider knows (a macOS voice picked explicitly) skips the
    /// providers before it.
    private func synthesizeFlat(_ request: SpeechRequest) async throws -> SynthesisResult {
        var candidates = providers[...]
        if let voiceID = request.voiceID, let first = providers.firstIndex(where: { $0.supports(voiceID: voiceID) }) {
            candidates = providers[first...]
        }
        var lastError: (any Error)?
        for (index, provider) in zip(candidates.indices, candidates) {
            do {
                return try await provider.synthesize(request)
            } catch {
                if error is CancellationError || Task.isCancelled { throw error }
                lastError = error
                if index < candidates.endIndex - 1 { onFallback?(error) }
            }
        }
        throw lastError!
    }

    // MARK: Layered

    private enum Route: String { case nativeWord, nativeSentence, cli }

    private enum Attempt {
        case spoke(SynthesisResult, degraded: Bool)
        case failed((any Error)?)
    }

    /// What one request has learned so far.
    private struct Run {
        var serviceDown = false
        var lastError: (any Error)?
    }

    private func synthesizeLayered(_ request: SpeechRequest, _ layers: Layers) async throws -> SynthesisResult {
        let chosen = request.voiceID ?? request.language.info.defaultEdgeVoice
        // A macOS voice picked explicitly: no Edge, no fallback story.
        guard EdgeCLIProvider.isEdgeVoiceID(chosen) else { return try await layers.system.synthesize(request) }

        var run = Run()
        if case .spoke(var result, let degraded) = try await attempt(voice: chosen, request, layers, &run) {
            if degraded { result.fallback = FallbackInfo(requestedVoiceID: chosen, reason: .wordMarksUnavailable) }
            return result
        }
        if let backup = backupVoice(for: chosen, request, layers),
           case .spoke(var result, _) = try await attempt(voice: backup, request, layers, &run) {
            result.fallback = FallbackInfo(requestedVoiceID: chosen, reason: .voiceUnavailable)
            return result
        }
        var result = try await layers.system.synthesize(request)
        result.fallback = FallbackInfo(requestedVoiceID: chosen, reason: .edgeUnavailable)
        return result
    }

    private func backupVoice(for chosen: String, _ request: SpeechRequest, _ layers: Layers) -> String? {
        if let explicit = request.backupVoiceID, EdgeCLIProvider.isEdgeVoiceID(explicit), explicit != chosen { return explicit }
        let snapshot = layers.catalog()
        return BackupVoice.auto(
            for: chosen, language: request.language, in: snapshot?.voices ?? [], knownGenders: snapshot?.genders ?? [:],
            excluding: layers.health.failingVoices(.voice)
        )
    }

    private func routes(_ layers: Layers) -> [Route] {
        switch layers.mode {
        case .automatic: [.nativeWord, .nativeSentence, .cli]
        case .nativeOnly: [.nativeWord, .nativeSentence]
        case .cliOnly: [.cli]
        }
    }

    /// Runs `voice` through the Edge steps. `force` ignores what is remembered (Check my voices).
    private func attempt(
        voice: String, _ request: SpeechRequest, _ layers: Layers, _ run: inout Run, force: Bool = false
    ) async throws -> Attempt {
        let health = layers.health
        if !force, health.isBlocked(voice, .voice) { return .failed(nil) }

        var degraded = false
        var nativeVoiceFailures = 0
        var voiceFailures = 0
        var wordMarksFailed = false
        for route in routes(layers) {
            let isNative = route != .cli
            if isNative {
                if run.serviceDown || (!force && health.isBlocked(HealthKey.service, .service)) {
                    if route == .nativeWord { degraded = true }
                    continue
                }
                let blocked: [VoiceHealth.Step] = route == .nativeWord ? [.wordMarks, .nativeVoice] : [.nativeVoice]
                if !force, blocked.contains(where: { health.isBlocked(voice, $0) }) {
                    if route == .nativeWord { degraded = true }
                    continue
                }
            }
            guard let provider = isNative ? layers.native : layers.cli else { continue }

            let stepRequest = SpeechRequest(
                text: request.text, language: request.language, voiceID: voice, rate: request.rate,
                boundaryMode: route == .nativeWord ? .word : .sentence, backupVoiceID: request.backupVoiceID
            )
            do {
                var result = try await provider.synthesize(stepRequest)
                result.fallback = nil
                switch route {
                case .nativeWord:
                    for step in [VoiceHealth.Step.wordMarks, .nativeVoice, .voice] { health.recordSuccess(voice, step) }
                    health.recordSuccess(HealthKey.service, .service)
                case .nativeSentence:
                    if wordMarksFailed { health.recordFailure(voice, .wordMarks) }
                    for step in [VoiceHealth.Step.nativeVoice, .voice] { health.recordSuccess(voice, step) }
                    health.recordSuccess(HealthKey.service, .service)
                case .cli:
                    if nativeVoiceFailures > 0 { health.recordFailure(voice, .nativeVoice) }
                    health.recordSuccess(voice, .voice)
                }
                return .spoke(result, degraded: degraded || route == .nativeSentence || (route == .cli && layers.mode != .cliOnly))
            } catch {
                if error is CancellationError || Task.isCancelled { throw error }
                let failure = Self.classify(error, route: route, serviceDown: run.serviceDown)
                Self.logger.error("""
                    \(route.rawValue, privacy: .public) failed for \(voice, privacy: .public) \
                    (\(String(describing: failure), privacy: .public)): \(String(describing: error), privacy: .public)
                    """)
                run.lastError = error
                onFallback?(error)
                switch failure {
                case .service(let problem):
                    run.serviceDown = true
                    if problem == .refused, isNative { health.recordFailure(HealthKey.service, .service) }
                case .voice:
                    if route == .nativeWord { degraded = true; wordMarksFailed = true }
                    if isNative { nativeVoiceFailures += 1 }
                    if route != .cli || layers.mode != .cliOnly { voiceFailures += 1 }
                case .unrelated:
                    break
                }
            }
        }
        // Nothing spoke. When the voice itself was at fault (not the service), remember it.
        if !run.serviceDown, voiceFailures > 0 {
            health.recordFailure(voice, .voice)
            onVoiceFailure?()
        }
        return .failed(run.lastError)
    }

    /// The chain's reading of an error: a CLI failure says little by itself, so it counts against
    /// the voice only when the service itself seemed fine.
    private static func classify(_ error: any Error, route: Route, serviceDown: Bool) -> EdgeFailure {
        guard route == .cli else { return EdgeFailure.classify(error) }
        switch EdgeFailure.classify(error) {
        case .unrelated:
            if case TTSError.processFailed = error { return serviceDown ? .service(.unreachable) : .voice }
            return .unrelated
        case .service(let problem): return .service(problem)
        case .voice: return serviceDown ? .service(.unreachable) : .voice
        }
    }

    /// Where `Check my voices` and the app ask whether a voice works, ignoring what is remembered.
    /// The outcome is also recorded in `VoiceHealth`.
    public func check(voiceID: String, language: LanguageCode, sampleText: String) async -> VoiceCheck {
        guard let layers else { return .inconclusive }
        guard EdgeCLIProvider.isEdgeVoiceID(voiceID) else { return .works }
        var run = Run()
        let request = SpeechRequest(text: sampleText, language: language, voiceID: voiceID, rate: 1)
        do {
            switch try await attempt(voice: voiceID, request, layers, &run, force: true) {
            case .spoke(let result, let degraded):
                try? FileManager.default.removeItem(at: result.audioURL)
                if let srt = result.subtitlesURL { try? FileManager.default.removeItem(at: srt) }
                return degraded ? .wordMarksOff : .works
            case .failed:
                if run.serviceDown { return .serviceDown }
                return run.lastError == nil ? .inconclusive : .unavailable
            }
        } catch {
            return .inconclusive
        }
    }
}

/// What `ProviderChain.check` found out about one voice.
public enum VoiceCheck: Sendable, Equatable {
    /// Speaks with word marks.
    case works
    /// Speaks, but only with sentence marks.
    case wordMarksOff
    /// No Edge route speaks with it.
    case unavailable
    /// The Edge service can't be reached or refuses requests, so nothing was learned about the voice.
    case serviceDown
    case inconclusive
}

enum HealthKey {
    static let service = VoiceHealth.serviceKey
}

/// Which way Edge voices are reached (Settings › Engines › Edge engine).
public enum EdgeEngineMode: String, Codable, CaseIterable, Sendable {
    /// Native client, then the edge-tts CLI.
    case automatic
    /// Only Spreek's own client.
    case nativeOnly
    /// Only the edge-tts CLI.
    case cliOnly

    public var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .nativeOnly: "Native only"
        case .cliOnly: "edge-tts only"
        }
    }
}

extension ProviderChain {
    /// The layered chain for `mode`, ending in the macOS System voice (the last resort in every
    /// mode). The CLI is resolved from `edgeExecutablePath`, then the standard locations, and
    /// fails fast when not installed. `health` and `catalog` are shared with the UI.
    public static func live(
        mode: EdgeEngineMode = .automatic, edgeExecutablePath: String? = nil,
        health: VoiceHealth = VoiceHealth(), catalog: EdgeVoiceCatalog = EdgeVoiceCatalog()
    ) -> ProviderChain {
        var native: any TTSProvider = EdgeNativeProvider(catalog: catalog)
        #if DEBUG
        if let voice = UserDefaults.standard.string(forKey: "SpreekDebugFailWordMarks") {
            native = DebugFailingProvider(base: native, voiceID: voice)
        }
        #endif
        return ProviderChain(
            mode: mode,
            native: native,
            cli: EdgeCLIProvider(resolver: EdgeExecutableResolver(configuredPath: edgeExecutablePath), catalog: catalog),
            system: SystemProvider(),
            health: health,
            catalog: { catalog.snapshot() }
        )
    }
}
