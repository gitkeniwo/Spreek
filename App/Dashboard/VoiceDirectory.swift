import Observation
import SpreekCore

/// Voices per language for the voice pickers (Settings, Folder Info, Pronunciation rows).
/// Edge voices come from the service's voice list, or `edge-tts --list-voices` when that fails
/// (cached on disk for 7 days by `EdgeVoiceCatalog`); macOS voices from `AVSpeechSynthesisVoice`.
@MainActor
@Observable
final class VoiceDirectory {
    private(set) var edgeVoices: [LanguageCode: [Voice]] = [:]
    private(set) var systemVoices: [LanguageCode: [Voice]] = [:]
    /// Settings › Engines path override; changing it reloads on the next `load`.
    @ObservationIgnored var edgeExecutablePath: String? {
        didSet { if edgeExecutablePath != oldValue { loading = [] } }
    }
    /// Settings › Engines › Edge engine; changing it reloads on the next `load`.
    @ObservationIgnored var edgeMode: EdgeEngineMode = .automatic {
        didSet { if edgeMode != oldValue { loading = [] } }
    }
    @ObservationIgnored private var loading: Set<LanguageCode> = []

    /// Starts loading `language`'s voices once; observers update when they arrive.
    func load(_ language: LanguageCode) {
        guard !loading.contains(language) else { return }
        loading.insert(language)
        let path = edgeExecutablePath
        let mode = edgeMode
        Task {
            async let edge = (try? EdgeVoiceCatalog.liveVoices(for: language, mode: mode, edgeExecutablePath: path)) ?? []
            async let system = (try? SystemProvider().voices(for: language)) ?? []
            let (edgeList, systemList) = await (edge, system)
            edgeVoices[language] = VoiceList.sortedEdgeVoices(edgeList, for: language)
            systemVoices[language] = systemList
        }
    }

    /// Edge then macOS voices for a popup, always including the default and `selected`.
    func groups(for language: LanguageCode, selected: String?) -> [VoiceGroup] {
        VoiceList.groups(
            for: language, edge: edgeVoices[language] ?? [], system: systemVoices[language] ?? [], selected: selected
        )
    }

    /// The best installed macOS voice for `language`.
    func bestSystemVoice(for language: LanguageCode) -> Voice? {
        systemVoices[language]?.first
    }
}

extension Voice {
    /// "Fenna" for Edge, the system voice's own name otherwise.
    var displayName: String {
        provider == .edge ? EdgeVoiceCatalog.displayName(for: id) : name
    }

    /// Mono detail: the Edge id, or "macOS · Premium".
    var detail: String {
        provider == .edge ? id : "macOS · \(quality.rawValue.capitalized)"
    }
}
