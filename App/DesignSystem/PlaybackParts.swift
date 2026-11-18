import SpreekCore
import SwiftUI

// Pieces shared by the popover's Now-speaking tile and the floating bar.

enum PlaybackFormat {
    /// "0:02".
    static func time(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0).rounded(.down))
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    /// "-0:01".
    static func remaining(current: TimeInterval, duration: TimeInterval) -> String {
        "-" + time((max(duration - current, 0)).rounded(.up))
    }

    /// "0.8×", "1.25×".
    static func speed(_ rate: Double) -> String {
        var text = String(format: "%.2f", rate)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text += "0" }
        return text + "×"
    }
}

/// The sentence with the spoken word highlighted (the whole sentence for audio cached from the
/// edge-tts CLI, which only reports sentences).
func highlightedSentence(_ text: String, range: Range<String.Index>?) -> AttributedString {
    var attributed = AttributedString(text)
    if let range,
       let lower = AttributedString.Index(range.lowerBound, within: attributed),
       let upper = AttributedString.Index(range.upperBound, within: attributed) {
        attributed[lower..<upper].foregroundColor = Color.wordHighlightText
        attributed[lower..<upper].backgroundColor = Color.wordHighlight
    }
    return attributed
}

/// Thin rounded progress line.
struct ProgressLine: View {
    var fraction: Double
    var height: CGFloat = 4
    var fill: Color = .fg2
    /// Makes the line scrubbable: click or drag anywhere on it (a taller hit area than drawn).
    var onSeek: ((Double) -> Void)?
    @State private var hovering = false

    var body: some View {
        GeometryReader { proxy in
            let drawn = hovering && onSeek != nil ? height + 2 : height
            Capsule()
                .fill(Color.track)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(fill)
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
                .frame(height: drawn)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    guard let onSeek, proxy.size.width > 0 else { return }
                    onSeek(min(max(value.location.x / proxy.size.width, 0), 1))
                }, including: onSeek == nil ? .none : .all)
        }
        .frame(height: onSeek == nil ? height : 14)
        .onHover { hovering = $0 }
        .animation(.linear(duration: 0.05), value: fraction)
        .animation(.snappy(duration: 0.15), value: hovering)
    }
}

/// Progress line with mono elapsed / remaining times on either side.
struct TimedProgress: View {
    var current: TimeInterval
    var duration: TimeInterval
    var fraction: Double
    var onSeek: ((Double) -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Text(PlaybackFormat.time(current))
            ProgressLine(fraction: fraction, onSeek: onSeek)
            Text(PlaybackFormat.remaining(current: current, duration: duration))
        }
        .font(.spreekMono(size: 10.5))
        .foregroundStyle(Color.fg3)
        .monospacedDigit()
    }
}

/// Borderless glyph button with a round hover highlight.
struct GlyphButtonStyle: ButtonStyle {
    var size: CGFloat = 32
    var color: Color = .fg

    func makeBody(configuration: Configuration) -> some View {
        GlyphButtonBody(configuration: configuration, size: size, color: color)
    }

    private struct GlyphButtonBody: View {
        let configuration: Configuration
        let size: CGFloat
        let color: Color
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(color)
                .frame(minWidth: size, minHeight: size)
                .background(Circle().fill(hovering ? Color.glassHover : .clear))
                .contentShape(Circle())
                .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.35)
                .onHover { hovering = $0 && isEnabled }
        }
    }
}

extension ButtonStyle where Self == GlyphButtonStyle {
    static func glyph(size: CGFloat = 32, color: Color = .fg) -> GlyphButtonStyle {
        GlyphButtonStyle(size: size, color: color)
    }
}

/// "1.0×" — the current sentence's speed; picking another plays it again at that speed.
/// Rounded heavy 12.
struct SpeedPill: View {
    var rate: Double
    /// Gray capsule behind the label (popover, pinned card); none in the compact bar.
    var filled = true
    var select: (Double) -> Void

    var body: some View {
        Menu {
            ForEach(SpeechController.speedChoices, id: \.self) { speed in
                Button { select(speed) } label: {
                    let title = PlaybackFormat.speed(speed)
                    if abs(speed - rate) < 0.001 { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
        } label: {
            Text(PlaybackFormat.speed(rate))
                .font(.spreekRounded(size: 12, weight: .heavy))
                .foregroundStyle(filled ? Color.fg : Color.fg2)
                .padding(.horizontal, filled ? 9 : 7)
                .frame(height: filled ? 24 : 32)
                .background(Capsule().fill(filled ? Color.glassCircle : .clear))
                .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Speed: \(PlaybackFormat.speed(rate)) — choose another to play again")
        .accessibilityLabel("Speed \(PlaybackFormat.speed(rate))")
    }
}

/// Favorite star: outline in `fg2`, filled yellow when saved.
struct FavoriteGlyph: View {
    var isFavorite: Bool
    var size: CGFloat = 16

    var body: some View {
        Image(systemName: isFavorite ? "star.fill" : "star")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(isFavorite ? Color.favorite : Color.fg2)
    }
}
