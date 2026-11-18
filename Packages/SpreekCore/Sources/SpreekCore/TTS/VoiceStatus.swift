import Foundation

/// How a configured Edge voice stands, for Settings.
public enum VoiceState: Sendable, Hashable {
    case ok
    /// No Edge route speaks with it right now (its backup voice reads instead).
    case unavailable
    /// The service no longer lists it, but it may still work.
    case retired
}

public enum VoiceStatus {
    /// `unavailable` wins over `retired`: a retired voice that stopped working is simply broken.
    /// Word-marks-only failures don't change the state (the voice still reads).
    public static func state(of voiceID: String, health: VoiceHealth, snapshot: EdgeVoiceCatalog.Snapshot?) -> VoiceState {
        guard EdgeCLIProvider.isEdgeVoiceID(voiceID) else { return .ok }
        if health.isFailing(voiceID, .voice) { return .unavailable }
        if snapshot?.isRetired(voiceID) == true { return .retired }
        return .ok
    }

    /// A short sentence for the voice check (one per language).
    public static func sampleText(for language: LanguageCode) -> String {
        switch language {
        case .nl: "Goedemorgen. Hoe gaat het met je?"
        case .de: "Guten Morgen. Wie geht es dir?"
        case .ja: "おはようございます。お元気ですか。"
        case .ko: "안녕하세요. 잘 지내세요?"
        case .zhCN, .zhTW, .zhHK: "早上好。你好吗？"
        case .es: "Buenos días. ¿Cómo estás?"
        case .fr: "Bonjour. Comment allez-vous ?"
        case .it: "Buongiorno. Come stai?"
        case .ru: "Доброе утро. Как дела?"
        case .ptBR: "Bom dia. Como você está?"
        default: "Good morning. How are you?"
        }
    }
}
