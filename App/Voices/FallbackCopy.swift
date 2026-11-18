import SpreekCore
import SwiftUI

/// The quiet hint shown when another voice (or no word highlighting) is used. Plain sentences,
/// no codes or times.
struct FallbackHint {
    let first: String
    let second: String?

    /// Two lines for the tooltip.
    var tooltip: String { second.map { "\(first)\n\($0)" } ?? first }

    @MainActor
    init?(speech: SpeechController) {
        guard let info = speech.fallback else { return nil }
        let wanted = VoiceName.name(info.requestedVoiceID)
        switch info.reason {
        case .wordMarksUnavailable:
            first = "Word highlighting is off for \(wanted) right now."
            second = nil
        case .voiceUnavailable:
            first = "\(wanted) isn't available right now"
            second = "\(speech.voiceName ?? "Another voice") is reading instead."
        case .edgeUnavailable:
            first = "Edge is offline right now"
            second = "A Mac voice is reading instead."
        }
    }
}

/// 7 pt orange dot with the hint as a tooltip.
struct FallbackDot: View {
    let hint: FallbackHint
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(Color.attention)
            .frame(width: size, height: size)
            .help(hint.tooltip)
            .accessibilityLabel(hint.tooltip.replacingOccurrences(of: "\n", with: ". "))
    }
}

extension Color {
    /// Orange dot of the fallback hints.
    static let attention = Color(lightHex: 0xFF9500, darkHex: 0xFF9F0A)
    /// Text of the Unavailable tag (`--warn`).
    static let attentionText = Color(lightHex: 0xB35C00, darkHex: 0xFFB54D)
}
