import SwiftUI

/// Finder-style tag: colored dot + name, 24 pt high, radius 8.
struct TagChip: View {
    let name: String
    let color: TagColor

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color.color)
                .frame(width: 8, height: 8)
            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.fg)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .frame(height: Metrics.tagChipHeight)
        .background(Color.tagBG, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                .strokeBorder(Color.separator, lineWidth: Metrics.hairline)
        )
        .shadow(color: .black.opacity(0.05), radius: 0.5, y: 1)
    }
}

/// "+ Tag" — same shape as `TagChip`, transparent.
struct AddTagChip: View {
    var title = "Tag"
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.fg2)
            .padding(.horizontal, 9)
            .frame(height: Metrics.tagChipHeight)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .strokeBorder(Color.separator, lineWidth: Metrics.hairline)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HStack {
        TagChip(name: "informeel", color: .pink)
        TagChip(name: "uitdrukking", color: .blue)
        TagChip(name: "grammatica", color: .green)
        TagChip(name: "keigo", color: .yellow)
        AddTagChip()
    }
    .padding()
}
