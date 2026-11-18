import SpreekCore
import SwiftUI

// Small pieces shared by the dashboard columns and the Folder Info sheet.

/// Field-styled popup button label: content + small chevron.
struct PopupLabel<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
        HStack(spacing: 7) {
            content()
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.fg2)
        }
        .font(.system(size: 13))
        .foregroundStyle(Color.fg)
        .padding(.leading, 8)
        .padding(.trailing, 9)
        .frame(height: 26)
        .background(Color.field, in: shape)
        .overlay(shape.strokeBorder(Color.separator, lineWidth: Metrics.hairline))
        .shadow(color: .black.opacity(0.06), radius: 0.5, y: 1)
        .contentShape(shape)
    }
}

extension View {
    /// Borderless `Menu` presentation used with `PopupLabel` and chips.
    func plainMenu() -> some View {
        menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
    }
}

/// Little-Snitch form label: right-aligned "Folder:" in `fg3`.
struct FormLabel: View {
    let text: String
    var width: CGFloat = 150

    init(_ text: String, width: CGFloat = 150) {
        self.text = text
        self.width = width
    }

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Color.fg3)
            .frame(width: width, alignment: .trailing)
    }
}

/// Pink "listened" / blue "saved" stat pill.
struct StatPill: View {
    enum Tint { case pink, blue, gray }

    let tint: Tint
    let label: String
    let value: String
    var symbol: String?
    var height: CGFloat = 36
    var valueSize: CGFloat = 19

    var body: some View {
        let colors: (bg: Color, fg: Color, strong: Color) = switch tint {
        case .pink: (.pinkBG, .pinkFG, .pinkStrong)
        case .blue: (.blueBG, .blueFG, .blueStrong)
        case .gray: (.control, .fg2, .fg)
        }
        // Narrow (the dashboard at its minimum width): the symbol goes before the label wraps.
        PillRowLayout(hasSymbol: symbol != nil) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(minWidth: 0)
                    .clipped()
            }
            Text(label).font(.system(size: 13, weight: .medium)).lineLimit(1).fixedSize()
            Text(value)
                .font(.spreekRounded(size: valueSize, weight: .black))
                .foregroundStyle(colors.strong)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(colors.fg)
        .padding(.horizontal, height > 40 ? 16 : 12)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(colors.bg, in: RoundedRectangle(cornerRadius: height > 40 ? 12 : 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// [symbol], label, ≥ 8 pt gap, value (trailing). Without room for the symbol it's laid out at zero
/// width; the value gets what's left. One layout pass per frame: a `ViewThatFits` over a row with
/// and without the symbol cost ~2 ms per live-resize frame across the pills.
private struct PillRowLayout: Layout {
    let hasSymbol: Bool
    private let symbolSpacing: CGFloat = 7
    private let gap: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let idealWidth = sizes.reduce(0) { $0 + $1.width } + gap + (hasSymbol ? symbolSpacing : 0)
        return CGSize(width: proposal.width ?? idealWidth, height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let label = subviews.dropLast().last, let value = subviews.last else { return }
        let labelSize = label.sizeThatFits(.unspecified)
        let valueSize = value.sizeThatFits(.unspecified)
        var x = bounds.minX
        if hasSymbol, let symbol = subviews.first {
            let symbolSize = symbol.sizeThatFits(.unspecified)
            let fits = bounds.width >= symbolSize.width + symbolSpacing + labelSize.width + gap + valueSize.width
            symbol.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                         proposal: fits ? ProposedViewSize(symbolSize) : .zero)
            if fits { x += symbolSize.width + symbolSpacing }
        }
        label.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(labelSize))
        let room = max(0, bounds.maxX - (x + labelSize.width + gap))
        value.place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing,
                    proposal: ProposedViewSize(width: min(valueSize.width, room), height: valueSize.height))
    }
}

/// 30×28 toolbar icon button with a rounded hover fill.
struct ToolbarIconButtonStyle: ButtonStyle {
    var isOn = false

    func makeBody(configuration: Configuration) -> some View {
        IconBody(configuration: configuration, isOn: isOn)
    }

    private struct IconBody: View {
        let configuration: Configuration
        let isOn: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isOn ? Color.accentColor : Color.fg2)
                .frame(width: 30, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hovering || configuration.isPressed ? Color.glassHover : .clear)
                )
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering = $0 && isEnabled }
        }
    }
}

extension ButtonStyle where Self == ToolbarIconButtonStyle {
    static var toolbarIcon: ToolbarIconButtonStyle { ToolbarIconButtonStyle() }
    static func toolbarIcon(isOn: Bool) -> ToolbarIconButtonStyle { ToolbarIconButtonStyle(isOn: isOn) }
}

/// Capsule push buttons of the Folder Info sheet.
struct CapsuleButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        CapsuleBody(configuration: configuration, prominent: prominent)
    }

    private struct CapsuleBody: View {
        let configuration: Configuration
        let prominent: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: prominent ? .semibold : .medium))
                .foregroundStyle(prominent ? Color.white : Color.fg)
                .padding(.horizontal, prominent ? 18 : 16)
                .frame(height: 30)
                .background(Capsule().fill(prominent ? Color.accentColor : Color.control))
                .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
                .contentShape(Capsule())
        }
    }
}

extension LanguageCode {
    /// "Nederlands".
    var nativeName: String { info.nativeName }
}

extension Sentence {
    /// Folder color / tag color helpers for views.
    var folderColor: FolderColor { folder.flatMap { FolderColor(rawValue: $0.colorID) } ?? .gray }
}

extension Folder {
    var color: FolderColor { FolderColor(rawValue: colorID) ?? .gray }
}

extension Tag {
    var color: TagColor { TagColor(rawValue: colorID) ?? .pink }
}

enum DashboardFormat {
    /// "2026-10-14 21:20" in the local time zone.
    static func timestamp(_ date: Date) -> String {
        format(date, "yyyy-MM-dd HH:mm")
    }

    /// "2026-09-02".
    static func day(_ date: Date) -> String {
        format(date, "yyyy-MM-dd")
    }

    private static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    /// "24 KB".
    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}

/// Left-aligned wrapping layout for tag chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 5
    var lineSpacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
