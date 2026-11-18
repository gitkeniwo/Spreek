import SpreekCore
import SwiftUI

/// Debug gallery of every design-system component, light and dark side by side.
struct DesignPreview: View {
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 0) {
                DesignPreviewColumn()
                    .environment(\.colorScheme, .light)
                DesignPreviewColumn()
                    .environment(\.colorScheme, .dark)
            }
        }
        .frame(minWidth: 960, minHeight: 640)
    }
}

private struct DesignPreviewColumn: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var pronunciationExpanded = true
    @State private var noteExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(colorScheme == .dark ? "Dark" : "Light")
                .font(.spreekRounded(size: 28, weight: .black))
                .foregroundStyle(Color.fg)

            group("Language badge · code") {
                ForEach(LanguageBadge.Size.allCases, id: \.self) { size in
                    HStack(spacing: 10) {
                        ForEach(LanguageCode.allCases, id: \.self) { LanguageBadge(language: $0, size: size) }
                    }
                }
            }

            group("Language badge · flag") {
                ForEach(LanguageBadge.Size.allCases, id: \.self) { size in
                    HStack(spacing: 10) {
                        ForEach(LanguageCode.allCases, id: \.self) {
                            LanguageBadge(language: $0, style: .flag, size: size)
                        }
                    }
                }
            }

            group("Inverted (selected row)") {
                HStack(spacing: 10) {
                    LanguageBadge(language: .nl, size: .s, inverted: true)
                    Text("Ik heb er zin in.")
                        .font(.spreekBody)
                        .foregroundStyle(.white)
                    Spacer()
                    ForEach(LanguageCode.allCases, id: \.self) {
                        LanguageBadge(language: $0, size: .m, inverted: true)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 38)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            group("Folder icons") {
                HStack(spacing: 8) {
                    ForEach(Array(zip(FolderColor.allCases, FolderIcon.previewSymbols)), id: \.0) { color, symbol in
                        FolderIcon(symbol: symbol, color: color)
                    }
                }
                HStack(spacing: 12) {
                    FolderIcon(symbol: "bubble.left.fill", color: .orange, size: .large)
                    FolderIcon(symbol: "book.fill", color: .teal, size: .large)
                }
            }

            group("Tags") {
                HStack(spacing: 6) {
                    TagChip(name: "informeel", color: .pink)
                    TagChip(name: "uitdrukking", color: .blue)
                }
                HStack(spacing: 6) {
                    TagChip(name: "grammatica", color: .green)
                    TagChip(name: "keigo", color: .yellow)
                    AddTagChip()
                }
            }

            group("Section bars") {
                SectionBar("Pronunciation", isExpanded: $pronunciationExpanded) {
                    HStack {
                        Text("Fenna").font(.spreekRounded(size: 13))
                        Text("nl-NL-FennaNeural").font(.spreekMono(size: 11.5)).foregroundStyle(Color.fg3)
                        Spacer()
                        Text("Default").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.accentColor)
                    }
                    .foregroundStyle(Color.fg)
                }
                SectionBar("Note", isExpanded: $noteExpanded) {
                    Text("Bold and italic only.").foregroundStyle(Color.fg2)
                }
            }

            group("Pills") {
                HStack(spacing: 8) {
                    pill("listened", value: "23", bg: .pinkBG, fg: .pinkFG, strong: .pinkStrong)
                    pill("saved", value: "6", bg: .blueBG, fg: .blueFG, strong: .blueStrong)
                }
            }

            group("Typography") {
                Text("Library").font(.spreekRounded(size: 13, weight: .heavy)).foregroundStyle(Color.fg2)
                Text("Ik heb er echt zin in.").font(.system(size: 27, weight: .bold)).foregroundStyle(Color.fg)
                Text("Body · SF Pro 13").font(.spreekBody).foregroundStyle(Color.fg)
                HStack(spacing: 12) {
                    Text("nl-NL-FennaNeural")
                    Text("0:02")
                    Text("⌥ S")
                }
                .font(.spreekMono(size: 12))
                .foregroundStyle(Color.fg3)
            }

            group("Tokens") {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(96), spacing: 8), count: 4), alignment: .leading, spacing: 8) {
                    ForEach(Self.swatches, id: \.0) { name, color in
                        swatch(name, color)
                    }
                }
            }

            group("Glass") {
                ZStack {
                    LinearGradient(colors: [.orange, .pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    HStack(spacing: 12) {
                        LanguageBadge(language: .nl, size: .m)
                        Text("Ik heb er zin in.").font(.system(size: 13.5, weight: .semibold))
                        Spacer()
                        Image(systemName: "pause.fill").font(.system(size: 22))
                    }
                    .foregroundStyle(Color.fg)
                    .padding(.horizontal, 18)
                    .frame(width: 380, height: Metrics.floatingBarHeight)
                    .glassBackground(.hudWindow, in: Capsule(), liquidGlass: false)
                }
                .frame(height: 110)
                .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
            }
        }
        .padding(28)
        .frame(width: 480, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.windowBG)
    }

    @ViewBuilder
    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.spreekRounded(size: 11, weight: .heavy))
                .foregroundStyle(Color.fg3)
            content()
        }
    }

    private func pill(_ label: String, value: String, bg: Color, fg: Color, strong: Color) -> some View {
        HStack {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(fg)
            Spacer()
            Text(value).font(.spreekRounded(size: 19, weight: .black)).foregroundStyle(strong)
        }
        .padding(.horizontal, 12)
        .frame(width: 150, height: 36)
        .background(bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color)
                .frame(height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.separator, lineWidth: Metrics.hairline)
                )
            Text(name).font(.spreekMono(size: 10)).foregroundStyle(Color.fg3)
        }
    }

    private static let swatches: [(String, Color)] = [
        ("fg", .fg), ("fg2", .fg2), ("fg3", .fg3), ("windowBG", .windowBG),
        ("sidebarBG", .sidebarBG), ("sectionBar", .sectionBar), ("field", .field), ("separator", .separator),
        ("control", .control), ("chartTrack", .chartTrack), ("chartPink", .chartPink), ("chartBlue", .chartBlue),
        ("pinkBG", .pinkBG), ("blueBG", .blueBG), ("favorite", .favorite), ("wordHighlight", .wordHighlight),
    ]
}

#Preview("Design system") {
    DesignPreview()
}

#Preview("Light only") {
    DesignPreviewColumn().environment(\.colorScheme, .light)
}

#Preview("Dark only") {
    DesignPreviewColumn().environment(\.colorScheme, .dark)
}
