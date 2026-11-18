import SwiftUI

/// Squircle filled with the folder color and a white SF Symbol glyph.
struct FolderIcon: View {
    enum Size: Sendable {
        /// 18 pt — inside folder chips on glass (floating bar).
        case small
        /// 22 pt — sidebar rows, chips.
        case regular
        /// 30 pt — the folder title above the sentence list.
        case medium
        /// 56 pt — Folder Info sheet.
        case large

        var side: CGFloat {
            switch self {
            case .small: 18
            case .regular: 22
            case .medium: 30
            case .large: 56
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .small: 6
            case .regular: Radius.folderIcon
            case .medium: 9
            case .large: Radius.folderIconLarge
            }
        }

        var glyphSize: CGFloat {
            switch self {
            case .small: 10
            case .regular: 12
            case .medium: 15
            case .large: 28
            }
        }
    }

    let symbol: String
    let color: FolderColor
    var size: Size = .regular

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size.glyphSize, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.white)
            .frame(width: size.side, height: size.side)
            .background(color.color, in: shape)
            .overlay(shape.strokeBorder(.black.opacity(0.12), lineWidth: Metrics.hairline))
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        HStack {
            ForEach(Array(zip(FolderColor.allCases, FolderIcon.previewSymbols)), id: \.0) { color, symbol in
                FolderIcon(symbol: symbol, color: color)
            }
        }
        HStack {
            FolderIcon(symbol: "bubble.left.fill", color: .orange, size: .large)
            FolderIcon(symbol: "graduationcap.fill", color: .purple, size: .large)
        }
    }
    .padding()
}

extension FolderIcon {
    /// Glyph choices for the folder sheet, also used in previews.
    static let previewSymbols = [
        "bubble.left.fill", "briefcase.fill", "book.fill", "sparkles",
        "music.note", "film.fill", "heart.fill", "graduationcap.fill",
    ]
}
