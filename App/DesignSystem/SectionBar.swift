import SwiftUI

/// Little-Snitch-style collapsible section: a 38 pt gray bar with chevron +
/// title, content below when expanded.
struct SectionBar<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    init(_ title: String, isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        _isExpanded = isExpanded
        self.content = content
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded, content: content) {
            Text(title)
        }
        .disclosureGroupStyle(SectionBarDisclosureStyle())
    }
}

/// A `DisclosureGroupStyle` drawing the section bar header.
struct SectionBarDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { configuration.isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.fg2)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                    configuration.label
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Color.fg)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: Metrics.sectionBarHeight, maxHeight: Metrics.sectionBarHeight)
                .background(Color.sectionBar, in: RoundedRectangle(cornerRadius: Radius.sectionBar, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")

            if configuration.isExpanded {
                configuration.content
                    .padding(.horizontal, 14)
            }
        }
    }
}

#Preview {
    @Previewable @State var pronunciation = true
    @Previewable @State var note = false
    VStack(spacing: 12) {
        SectionBar("Pronunciation", isExpanded: $pronunciation) {
            Text("nl-NL-FennaNeural").font(.spreekMono(size: 12)).foregroundStyle(Color.fg3)
        }
        SectionBar("Note", isExpanded: $note) {
            Text("Hidden until expanded")
        }
    }
    .padding()
    .frame(width: 420)
}
