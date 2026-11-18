import SpreekCore
import SwiftUI

/// Small language marker: an upper-case code ("NL") or a flat-drawn flag in a
/// rounded rect.
struct LanguageBadge: View {
    /// Settings › Language badge; views read it from `\.badgeStyle`.
    typealias Style = BadgeStyle

    enum Size: CaseIterable, Sendable {
        case s, m, xl

        var dimensions: CGSize {
            switch self {
            case .s: CGSize(width: 24, height: 16)
            case .m: CGSize(width: 30, height: 20)
            case .xl: CGSize(width: 56, height: 56)
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .s: 4
            case .m: 6
            case .xl: 14
            }
        }

        var codeFontSize: CGFloat {
            switch self {
            case .s: 10
            case .m: 11.5
            case .xl: 20
            }
        }
    }

    let language: LanguageCode
    var style: Style = .code
    var size: Size = .s
    var inverted = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
        Group {
            switch style {
            case .code: codeBody
            case .flag: flagBody
            }
        }
        .frame(width: size.dimensions.width, height: size.dimensions.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(ringColor, lineWidth: inverted ? 1 : Metrics.hairline))
        .accessibilityElement()
        .accessibilityLabel(language.info.nativeName)
    }

    private var codeBody: some View {
        let colors = inverted ? LanguageCode.invertedBadgeColors : language.badgeColors
        return Text(language.badgeLabel)
            .font(.spreekRounded(size: size.codeFontSize, weight: .heavy))
            .tracking(0.4)
            .foregroundStyle(colors.fg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(colors.bg)
    }

    private var flagBody: some View {
        FlatFlag(language: language)
    }

    private var ringColor: Color {
        if inverted { return .white.opacity(0.7) }
        guard style == .flag else { return .clear }
        return colorScheme == .dark ? .white.opacity(0.25) : .black.opacity(0.2)
    }
}

/// Simplified flat flag (stripes, discs, stars; no fine detail) that fills its frame.
/// Used instead of the emoji so flags read as one consistent set at 16 pt.
private struct FlatFlag: View {
    let language: LanguageCode

    /// Flags too detailed to draw by hand: flag-icons artwork (MIT, see Assets.xcassets/Flags).
    private var asset: String? {
        switch language {
        case .ko: "flag-kr"
        case .es: "flag-es"
        case .fa: "flag-ir"
        case .zhHK: "flag-hk"
        default: nil
        }
    }

    var body: some View {
        if let asset {
            Image(asset)
                .resizable()
                .scaledToFill()
        } else {
            Canvas { ctx, size in
                Self.draw(language, in: &ctx, size: size)
            }
        }
    }

    private static func draw(_ language: LanguageCode, in ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        let full = CGRect(origin: .zero, size: size)
        func fill(_ rect: CGRect, _ hex: UInt32) { ctx.fill(Path(rect), with: .color(Color(hex: hex))) }
        func rows(_ colors: [UInt32], weights: [CGFloat]? = nil) {
            let weights = weights ?? colors.map { _ in 1 }
            let total = weights.reduce(0, +)
            var y: CGFloat = 0
            for (color, weight) in zip(colors, weights) {
                let height = h * weight / total
                fill(CGRect(x: 0, y: y, width: w, height: height), color)
                y += height
            }
        }
        func columns(_ colors: [UInt32]) {
            for (i, color) in colors.enumerated() {
                let width = w / CGFloat(colors.count)
                fill(CGRect(x: CGFloat(i) * width, y: 0, width: width, height: h), color)
            }
        }
        func disc(_ center: CGPoint, _ radius: CGFloat, _ hex: UInt32) {
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(Color(hex: hex)))
        }
        func star(_ center: CGPoint, _ radius: CGFloat, _ hex: UInt32) {
            var path = Path()
            for i in 0..<10 {
                let r = i.isMultiple(of: 2) ? radius : radius * 0.382
                let angle = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
                let point = CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
                i == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            path.closeSubpath()
            ctx.fill(path, with: .color(Color(hex: hex)))
        }
        func nordicCross(_ background: UInt32, _ cross: UInt32, outline: UInt32? = nil) {
            fill(full, background)
            let x = w * 0.3, y = h / 2
            if let outline {
                fill(CGRect(x: x - h * 0.2, y: 0, width: h * 0.4, height: h), outline)
                fill(CGRect(x: 0, y: y - h * 0.2, width: w, height: h * 0.4), outline)
            }
            fill(CGRect(x: x - h * 0.11, y: 0, width: h * 0.22, height: h), cross)
            fill(CGRect(x: 0, y: y - h * 0.11, width: w, height: h * 0.22), cross)
        }
        let center = CGPoint(x: w / 2, y: h / 2)

        switch language {
        case .ko, .es, .fa, .zhHK: break  // asset-backed, see `asset`
        case .nl: rows([0xAE1C28, 0xFFFFFF, 0x21468B])
        case .de: rows([0x000000, 0xDD0000, 0xFFCC00])
        case .ru: rows([0xFFFFFF, 0x0039A6, 0xD52B1E])
        case .fr: columns([0x002654, 0xFFFFFF, 0xCE1126])
        case .it: columns([0x009246, 0xFFFFFF, 0xCE2B37])
        case .pl: rows([0xFFFFFF, 0xDC143C])
        case .th: rows([0xA51931, 0xF4F5F8, 0x2D2A4A, 0xF4F5F8, 0xA51931], weights: [1, 1, 2, 1, 1])
        case .sv: nordicCross(0x006AA7, 0xFECC00)
        case .da: nordicCross(0xC8102E, 0xFFFFFF)
        case .fi: nordicCross(0xFFFFFF, 0x002F6C)

        case .vi:
            fill(full, 0xDA251D)
            star(center, h * 0.32, 0xFFFF00)

        case .tr:
            fill(full, 0xE30A17)
            let r = h * 0.27
            let moon = CGPoint(x: w * 0.4, y: h / 2)
            disc(moon, r, 0xFFFFFF)
            disc(CGPoint(x: moon.x + r * 0.28, y: moon.y), r * 0.8, 0xE30A17)
            star(CGPoint(x: moon.x + r * 1.15, y: moon.y), r * 0.45, 0xFFFFFF)

        case .ar:
            // Saudi green with the sword reduced to a bar.
            fill(full, 0x006C35)
            fill(CGRect(x: w * 0.22, y: h * 0.62, width: w * 0.56, height: h * 0.08), 0xFFFFFF)
            fill(CGRect(x: w * 0.3, y: h * 0.32, width: w * 0.4, height: h * 0.14), 0xFFFFFF)

        case .ja:
            fill(full, 0xFFFFFF)
            disc(center, min(w, h) * 0.3, 0xBC002D)

        case .enUS:
            rows((0..<7).map { $0.isMultiple(of: 2) ? 0xB22234 : 0xFFFFFF })
            fill(CGRect(x: 0, y: 0, width: w * 0.45, height: h * 4 / 7), 0x3C3B6E)

        case .enGB:
            fill(full, 0x012169)
            var diagonals = Path()
            diagonals.move(to: .zero); diagonals.addLine(to: CGPoint(x: w, y: h))
            diagonals.move(to: CGPoint(x: w, y: 0)); diagonals.addLine(to: CGPoint(x: 0, y: h))
            ctx.stroke(diagonals, with: .color(.white), lineWidth: h * 0.2)
            ctx.stroke(diagonals, with: .color(Color(hex: 0xC8102E)), lineWidth: h * 0.08)
            var cross = Path()
            cross.move(to: CGPoint(x: w / 2, y: 0)); cross.addLine(to: CGPoint(x: w / 2, y: h))
            cross.move(to: CGPoint(x: 0, y: h / 2)); cross.addLine(to: CGPoint(x: w, y: h / 2))
            ctx.stroke(cross, with: .color(.white), lineWidth: h / 3)
            ctx.stroke(cross, with: .color(Color(hex: 0xC8102E)), lineWidth: h / 5)

        case .zhCN:
            fill(full, 0xEE1C25)
            let u = h / 20
            star(CGPoint(x: 5 * u, y: 5 * u), 3 * u, 0xFFFF00)
            for p in [(10.0, 2.0), (12.0, 4.0), (12.0, 7.0), (10.0, 9.0)] {
                star(CGPoint(x: p.0 * u, y: p.1 * u), u, 0xFFFF00)
            }

        case .zhTW:
            fill(full, 0xFE0000)
            let canton = CGRect(x: 0, y: 0, width: w / 2, height: h / 2)
            fill(canton, 0x000095)
            disc(CGPoint(x: canton.midX, y: canton.midY), canton.height * 0.27, 0xFFFFFF)

        case .ptBR:
            fill(full, 0x009C3B)
            var rhombus = Path()
            let inset = min(w, h) * 0.12
            rhombus.addLines([
                CGPoint(x: w / 2, y: inset), CGPoint(x: w - inset, y: h / 2),
                CGPoint(x: w / 2, y: h - inset), CGPoint(x: inset, y: h / 2),
            ])
            rhombus.closeSubpath()
            ctx.fill(rhombus, with: .color(Color(hex: 0xFFDF00)))
            disc(center, min(w, h) * 0.24, 0x002776)
        }
    }
}

extension EnvironmentValues {
    /// Settings › Language badge (Code / Flag), injected at each window root from `AppSettings`
    /// so every badge updates live.
    @Entry var badgeStyle: BadgeStyle = .code
}

#Preview("Code") {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(LanguageBadge.Size.allCases, id: \.self) { size in
            HStack {
                ForEach(LanguageCode.allCases, id: \.self) { LanguageBadge(language: $0, size: size) }
            }
        }
    }
    .padding()
}

#Preview("Flag") {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(LanguageBadge.Size.allCases, id: \.self) { size in
            HStack {
                ForEach(LanguageCode.allCases, id: \.self) { LanguageBadge(language: $0, style: .flag, size: size) }
            }
        }
    }
    .padding()
}

#Preview("Inverted") {
    HStack {
        ForEach(LanguageCode.allCases, id: \.self) { LanguageBadge(language: $0, size: .m, inverted: true) }
    }
    .padding()
    .background(Color.accentColor)
}
