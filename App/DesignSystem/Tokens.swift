import AppKit
import SpreekCore
import SwiftUI

// Design tokens. Token names are the contract: use these,
// never hard-coded light-only colors.

// MARK: - Color helpers

extension Color {
    /// A dynamic color resolved against the current appearance (light/dark).
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
    }

    /// `Color(hex: 0x1D1D1F)` — sRGB, optional opacity.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    init(lightHex: UInt32, darkHex: UInt32) {
        self.init(light: Color(hex: lightHex), dark: Color(hex: darkHex))
    }
}

// MARK: - Semantic tokens

extension Color {
    static let fg = Color(lightHex: 0x1D1D1F, darkHex: 0xF2F2F7)
    static let fg2 = Color(lightHex: 0x45454B, darkHex: 0xC7C7CC)
    static let fg3 = Color(lightHex: 0x6B6B72, darkHex: 0x9A9AA1)
    static let windowBG = Color(lightHex: 0xF4F4F6, darkHex: 0x252527)
    static let sidebarBG = Color(lightHex: 0xE7E7EB, darkHex: 0x2E2E31)
    static let sectionBar = Color(lightHex: 0xE5E5E9, darkHex: 0x37373A)
    static let field = Color(lightHex: 0xFFFFFF, darkHex: 0x3A3A3D)
    static let separator = Color(light: .black.opacity(0.12), dark: .white.opacity(0.12))
    static let control = Color(lightHex: 0xE4E4E8, darkHex: 0x3A3A3D)

    static let pinkBG = Color(lightHex: 0xEBD5F5, darkHex: 0x6C4A7C)
    static let pinkFG = Color(lightHex: 0x6A1F80, darkHex: 0xF0D7F8)
    static let pinkStrong = Color(lightHex: 0x3F0F4D, darkHex: 0xFFFFFF)
    static let blueBG = Color(lightHex: 0xCFDDF5, darkHex: 0x33507B)
    static let blueFG = Color(lightHex: 0x1D4E9E, darkHex: 0xD4E3FA)
    static let blueStrong = Color(lightHex: 0x0E2C63, darkHex: 0xFFFFFF)

    static let chartPink = Color(hex: 0xD063E8)
    static let chartBlue = Color(hex: 0x2F7BF6)
    static let chartTrack = Color(lightHex: 0xE2E2E7, darkHex: 0x38383C)

    static let wordHighlight = Color(
        light: Color.accentColor.opacity(0.18),
        dark: Color(.sRGB, red: 90 / 255, green: 150 / 255, blue: 1, opacity: 0.38)
    )
    static let wordHighlightText = Color(light: Color(hex: 0x0B3A80), dark: .white)

    static let favorite = Color(hex: 0xF5B524)

    /// Tag chip background (Finder-style).
    static let tagBG = Color(lightHex: 0xFFFFFF, darkHex: 0x36363A)

    // Glass surfaces (popover, floating bar).

    /// Translucent Control-Center tile on the popover glass.
    static let tile = Color(light: .white.opacity(0.3), dark: .white.opacity(0.08))
    /// Inner hairline of a tile.
    static let tileBorder = Color(light: .white.opacity(0.55), dark: .white.opacity(0.13))
    /// Darkening tint over the popover material (Control-Center "darker glass").
    static let popoverTint = Color(light: Color(hex: 0xD6D6DC, opacity: 0.45), dark: Color(hex: 0x34343A, opacity: 0.35))
    /// Gray circle behind tile glyphs, speed pills.
    static let glassCircle = Color(light: .black.opacity(0.1), dark: .white.opacity(0.14))
    /// Unfilled part of progress bars and sliders on glass.
    static let track = Color(light: .black.opacity(0.14), dark: .white.opacity(0.18))
    /// Hover highlight for glyph buttons and menu rows on glass.
    static let glassHover = Color(light: .black.opacity(0.07), dark: .white.opacity(0.09))
    /// Glass inner hairline (floating bar, popover).
    static let glassInnerLine = Color(light: .white.opacity(0.6), dark: .white.opacity(0.16))
    /// Glass outer hairline.
    static let glassOuterLine = Color(light: .black.opacity(0.16), dark: .black.opacity(0.55))
    /// Note box on the pinned card.
    static let noteGlass = Color(light: .white.opacity(0.4), dark: .white.opacity(0.07))
    /// Tag chip on glass.
    static let tagGlass = Color(light: .white.opacity(0.55), dark: .white.opacity(0.1))
    /// Slider fill / knob on glass.
    static let knob = Color(lightHex: 0xFFFFFF, darkHex: 0xF2F2F7)
}

// MARK: - Language badge colors

extension LanguageCode {
    /// Background / foreground for the code-style `LanguageBadge`.
    var badgeColors: (bg: Color, fg: Color) {
        switch self {
        case .nl: (Color(lightHex: 0xFDE3D3, darkHex: 0x5A3421), Color(lightHex: 0x8A3304, darkHex: 0xFFD3B8))
        case .de: (Color(lightHex: 0xE3E3E8, darkHex: 0x4A4A4F), Color(lightHex: 0x2C2C2E, darkHex: 0xF2F2F7))
        case .ja: (Color(lightHex: 0xF9D9DD, darkHex: 0x5C2630), Color(lightHex: 0x8E1A2E, darkHex: 0xFFC9D2))
        case .ko: (Color(lightHex: 0xD9E6FB, darkHex: 0x253F66), Color(lightHex: 0x1C4791, darkHex: 0xCFE0FF))
        // Added in 5b: one hue each, all ≥ 5.7:1 (light) / ≥ 7.8:1 (dark) text contrast.
        case .enUS: (Color(lightHex: 0xE3E0FA, darkHex: 0x342D63), Color(lightHex: 0x3D2E9C, darkHex: 0xDAD4FF))
        case .enGB: (Color(lightHex: 0xE0E5EE, darkHex: 0x3A4352), Color(lightHex: 0x34445F, darkHex: 0xDCE4F2))
        case .zhCN: (Color(lightHex: 0xFBEBC6, darkHex: 0x54401A), Color(lightHex: 0x7A5200, darkHex: 0xFFE3A6))
        case .zhTW: (Color(lightHex: 0xD3EFEC, darkHex: 0x1F4A46), Color(lightHex: 0x0B5F58, darkHex: 0xC3F0EA))
        case .es: (Color(lightHex: 0xF8D9EE, darkHex: 0x5A2449), Color(lightHex: 0x8A1A66, darkHex: 0xFFCDEE))
        case .fr: (Color(lightHex: 0xD2ECF7, darkHex: 0x1E4556), Color(lightHex: 0x0B5874, darkHex: 0xC4EBFA))
        case .it: (Color(lightHex: 0xE8F0CC, darkHex: 0x3E4720), Color(lightHex: 0x4D5E0F, darkHex: 0xE5F2B8))
        case .ru: (Color(lightHex: 0xEDDDF8, darkHex: 0x4A2D63), Color(lightHex: 0x6B2290, darkHex: 0xEBD6FF))
        case .ptBR: (Color(lightHex: 0xD9F0D6, darkHex: 0x26472A), Color(lightHex: 0x25672A, darkHex: 0xCDEFC8))
        case .zhHK: (Color(lightHex: 0xF9DCD3, darkHex: 0x5A2C22), Color(lightHex: 0x8E2F14, darkHex: 0xFFCFC2))
        case .ar: (Color(lightHex: 0xD6EEDF, darkHex: 0x1F4A33), Color(lightHex: 0x1A6640, darkHex: 0xC6F0D8))
        case .pl: (Color(lightHex: 0xF6D6DA, darkHex: 0x5A2229), Color(lightHex: 0x9A1B2C, darkHex: 0xFFC9D0))
        case .sv: (Color(lightHex: 0xFFF0B8, darkHex: 0x4F4416), Color(lightHex: 0x6B5600, darkHex: 0xFFEB99))
        case .da: (Color(lightHex: 0xF5DCD5, darkHex: 0x56302A), Color(lightHex: 0x92301F, darkHex: 0xFFD0C5))
        case .fi: (Color(lightHex: 0xDCE7F5, darkHex: 0x2B3D57), Color(lightHex: 0x2A4E85, darkHex: 0xD3E3FF))
        case .vi: (Color(lightHex: 0xFBE3C2, darkHex: 0x5A3D17), Color(lightHex: 0x8A4B00, darkHex: 0xFFDDAA))
        case .tr: (Color(lightHex: 0xF9D6D3, darkHex: 0x5C2420), Color(lightHex: 0x9E1B12, darkHex: 0xFFC8C2))
        case .th: (Color(lightHex: 0xDEDDF3, darkHex: 0x36345C), Color(lightHex: 0x3A3790, darkHex: 0xD9D7FF))
        case .fa: (Color(lightHex: 0xD9EFE3, darkHex: 0x24493A), Color(lightHex: 0x1D6346, darkHex: 0xC9F0DD))
        }
    }

    /// Badge colors on an accent-selected row (same in light and dark).
    static let invertedBadgeColors: (bg: Color, fg: Color) = (.white.opacity(0.25), .white)
}

// MARK: - Folder & tag colors

enum FolderColor: String, CaseIterable, Codable, Sendable, Identifiable {
    case orange, yellow, green, teal, blue, purple, pink, gray

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .orange: Color(hex: 0xFF6B2C)
        case .yellow: Color(hex: 0xF5B524)
        case .green: Color(hex: 0x30A46C)
        case .teal: Color(hex: 0x14A3B8)
        case .blue: Color(hex: 0x3B82F6)
        case .purple: Color(hex: 0x7A5AF8)
        case .pink: Color(hex: 0xE0447C)
        case .gray: Color(hex: 0x8E8E93)
        }
    }
}

enum TagColor: String, CaseIterable, Codable, Sendable, Identifiable {
    case pink, blue, green, yellow

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .pink: .chartPink
        case .blue: .chartBlue
        case .green: FolderColor.green.color
        case .yellow: .favorite
        }
    }
}

// MARK: - Typography

extension Font {
    /// SF Pro Rounded — headings, tile titles, group labels, big numbers, speed pills.
    static func spreekRounded(size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// SF Mono — voice IDs, times, shortcuts, file names, sizes.
    static func spreekMono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Default body text (SF Pro 13).
    static let spreekBody = Font.system(size: 13)
}

// MARK: - Shape

enum Radius {
    static let window: CGFloat = 18
    static let sidebarPanel: CGFloat = 13
    static let sectionBar: CGFloat = 10
    static let tile: CGFloat = 18
    static let menuPopover: CGFloat = 24
    static let pinnedCard: CGFloat = 26
    static let chip: CGFloat = 8
    static let field: CGFloat = 7
    static let noteEditor: CGFloat = 12
    static let folderIcon: CGFloat = 7
    static let folderIconLarge: CGFloat = 16
}

enum Metrics {
    static let hairline: CGFloat = 0.5
    static let sectionBarHeight: CGFloat = 38
    static let floatingBarHeight: CGFloat = 56
    static let tagChipHeight: CGFloat = 24
}
