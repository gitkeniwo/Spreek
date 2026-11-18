import Foundation

/// One section of a voice popup ("Edge Neural", "macOS System").
public struct VoiceGroup: Sendable, Hashable, Identifiable {
    public let provider: ProviderID
    public let voices: [Voice]

    public var id: ProviderID { provider }

    public var title: String {
        switch provider {
        case .edge: "Edge Neural"
        case .system: "macOS System"
        }
    }
}

/// Merges the Edge catalog and the installed macOS voices into the grouped list the voice
/// popups show.
public enum VoiceList {
    /// Edge first, then macOS. Only voices for `language`, without duplicates. Edge voices of the
    /// language's own locale (nl-NL) come before regional ones (nl-BE); macOS voices best quality
    /// first. The registry default and `selected` are always present, even when the catalog
    /// couldn't be loaded, so the current choice stays visible. Empty groups are dropped.
    public static func groups(
        for language: LanguageCode,
        edge: [Voice],
        system: [Voice],
        selected: String? = nil
    ) -> [VoiceGroup] {
        var edgeVoices = unique(edge.filter { $0.language == language && $0.provider == .edge })
        var systemVoices = unique(system.filter { $0.language == language && $0.provider == .system })

        var required = [language.info.defaultEdgeVoice]
        if let selected { required.append(selected) }
        for id in required where !(edgeVoices + systemVoices).contains(where: { $0.id == id }) {
            if EdgeCLIProvider.isEdgeVoiceID(id) {
                edgeVoices.append(placeholder(id: id, provider: .edge, language: language))
            } else {
                systemVoices.append(placeholder(id: id, provider: .system, language: language))
            }
        }

        edgeVoices = sortedEdgeVoices(edgeVoices, for: language)
        systemVoices.sort { ($0.quality, $1.name) > ($1.quality, $0.name) }

        return [
            VoiceGroup(provider: .edge, voices: edgeVoices),
            VoiceGroup(provider: .system, voices: systemVoices),
        ].filter { !$0.voices.isEmpty }
    }

    /// Edge voices for `language`, own locale first (Pronunciation rows).
    public static func sortedEdgeVoices(_ voices: [Voice], for language: LanguageCode) -> [Voice] {
        let primary = language.info.bcp47
        return voices.sorted { ($0.locale == primary ? 0 : 1, $0.id) < ($1.locale == primary ? 0 : 1, $1.id) }
    }

    private static func unique(_ voices: [Voice]) -> [Voice] {
        var seen: Set<String> = []
        return voices.filter { seen.insert($0.id).inserted }
    }

    private static func placeholder(id: String, provider: ProviderID, language: LanguageCode) -> Voice {
        Voice(
            id: id,
            name: provider == .edge ? EdgeVoiceCatalog.displayName(for: id) : (SystemProvider.voiceName(for: id) ?? id),
            locale: language.info.bcp47, gender: nil,
            quality: provider == .edge ? .neural : .standard, provider: provider
        )
    }
}
