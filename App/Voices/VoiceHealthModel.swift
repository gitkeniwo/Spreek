import Foundation
import Observation
import OSLog
import SpreekCore

/// What the UI knows about Edge voice health: the shared `VoiceHealth` memory and voice list
/// catalog, plus "Check my voices" and "Refresh voice list".
@MainActor
@Observable
final class VoiceHealthModel {
    @ObservationIgnored let health: VoiceHealth
    @ObservationIgnored let catalog: EdgeVoiceCatalog
    /// Bumped whenever the health memory or the voice list changes, so views re-read them.
    private(set) var revision = 0
    private(set) var isChecking = false
    private(set) var isRefreshing = false
    /// Outcome of the last "Check my voices" or refresh, as one plain sentence.
    private(set) var note: String?
    /// The language an on-demand check is working on.
    @ObservationIgnored private var lastAutoRefresh = Date.distantPast
    @ObservationIgnored private let logger = Logger(subsystem: "nl.spreek.app", category: "speech")

    init(health: VoiceHealth = VoiceHealth(), catalog: EdgeVoiceCatalog = EdgeVoiceCatalog()) {
        self.health = health
        self.catalog = catalog
        health.onChange = { [weak self] in
            Task { @MainActor in self?.revision += 1 }
        }
    }

    var snapshot: EdgeVoiceCatalog.Snapshot? {
        _ = revision
        return catalog.snapshot()
    }

    func state(of voiceID: String) -> VoiceState {
        _ = revision
        return VoiceStatus.state(of: voiceID, health: health, snapshot: catalog.snapshot())
    }

    /// Word marks are off for this voice (it still reads).
    func hasWordMarksOff(_ voiceID: String) -> Bool {
        _ = revision
        return health.isFailing(voiceID, .wordMarks)
    }

    /// The Auto pick of backup voice for `voiceID`, from the cached voice list.
    func autoBackup(for voiceID: String, language: LanguageCode) -> String? {
        _ = revision
        guard let snapshot = catalog.snapshot() else {
            let fallback = language.info.defaultEdgeVoice
            return fallback == voiceID ? nil : fallback
        }
        var excluded = health.failingVoices(.voice).union(health.failingVoices(.nativeVoice))
        for voice in snapshot.voices where snapshot.isRetired(voice.id) { excluded.insert(voice.id) }
        return BackupVoice.auto(
            for: voiceID, language: language, in: snapshot.voices, knownGenders: snapshot.genders, excluding: excluded
        )
    }

    // MARK: Refreshing the voice list

    /// Shortly after launch: only when the list is older than a day. Never blocks speech.
    func refreshInBackgroundIfNeeded(mode: EdgeEngineMode, path: String?) {
        guard catalog.needsRefresh() else { return }
        Task { await refreshList(mode: mode, path: path, announce: false) }
    }

    /// After a voice-specific failure: at most once an hour.
    func refreshAfterFailure(mode: EdgeEngineMode, path: String?) {
        guard Date().timeIntervalSince(lastAutoRefresh) > 3600, catalog.needsRefresh(minimumAge: 3600) else { return }
        lastAutoRefresh = Date()
        Task { await refreshList(mode: mode, path: path, announce: false) }
    }

    func refreshList(mode: EdgeEngineMode, path: String?, announce: Bool = true) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false; revision += 1 }
        do {
            let voices = try await EdgeVoiceCatalog.refreshLive(
                mode: mode, edgeExecutablePath: path, native: EdgeNativeProvider(catalog: catalog)
            )
            if announce { note = "Voice list updated, \(voices.count) voices." }
        } catch {
            logger.error("voice list refresh failed: \(String(describing: error), privacy: .public)")
            if announce { note = "Couldn't reach Edge to update the list." }
        }
    }

    // MARK: Check my voices

    /// Probes each language's chosen voice (word marks, then sentence marks) and records the result.
    func checkVoices(_ languages: [(LanguageCode, String)], chain: ProviderChain) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false; revision += 1 }
        var problems = 0
        var down = false
        for (language, voice) in languages where EdgeCLIProvider.isEdgeVoiceID(voice) {
            let result = await chain.check(voiceID: voice, language: language, sampleText: VoiceStatus.sampleText(for: language))
            logger.info("check \(voice, privacy: .public): \(String(describing: result), privacy: .public)")
            switch result {
            case .works: break
            case .wordMarksOff, .unavailable: problems += 1
            case .serviceDown: down = true
            case .inconclusive: break
            }
        }
        if down {
            note = "Edge isn't reachable right now, so the voices couldn't be checked."
        } else if problems == 0 {
            note = "All your voices work."
        } else {
            note = problems == 1 ? "1 voice needs attention." : "\(problems) voices need attention."
        }
    }
}
