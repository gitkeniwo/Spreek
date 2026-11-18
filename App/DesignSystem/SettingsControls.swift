import SwiftUI

/// Segmented control: `control` track, the selected segment raised on
/// a `field` pill. Options can be disabled ("Near selection").
struct SegmentedControl<Value: Hashable, Label: View>: View {
    let options: [Value]
    @Binding var selection: Value
    var isDisabled: (Value) -> Bool = { _ in false }
    var accessibilityName: String
    @ViewBuilder var label: (Value) -> Label

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button { selection = option } label: {
                    label(option)
                        .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                        .foregroundStyle(Color.fg)
                        .padding(.horizontal, 11)
                        .frame(height: 24)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.field)
                                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isDisabled(option))
                .opacity(isDisabled(option) ? 0.45 : 1)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.control, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityName)
    }
}

extension SegmentedControl where Label == Text {
    init(_ accessibilityName: String, options: [Value], selection: Binding<Value>, isDisabled: @escaping (Value) -> Bool = { _ in false }, title: @escaping (Value) -> String) {
        self.init(options: options, selection: selection, isDisabled: isDisabled, accessibilityName: accessibilityName) { Text(title($0)) }
    }
}

/// Small macOS switch without a visible label (the form label names it).
struct SettingsSwitch: View {
    let accessibilityName: String
    @Binding var isOn: Bool

    init(_ accessibilityName: String, isOn: Binding<Bool>) {
        self.accessibilityName = accessibilityName
        _isOn = isOn
    }

    var body: some View {
        Toggle(accessibilityName, isOn: $isOn)
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .accessibilityLabel(accessibilityName)
    }
}

/// Gray hint after a value.
struct SettingsHint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Color.fg3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Small rounded button.
struct SmallButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SmallButtonBody(configuration: configuration)
    }

    private struct SmallButtonBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
            configuration.label
                .font(.system(size: 12.5))
                .foregroundStyle(Color.fg)
                .padding(.horizontal, 11)
                .frame(height: 24)
                .background(Color.field, in: shape)
                .overlay(shape.strokeBorder(Color.separator, lineWidth: Metrics.hairline))
                .shadow(color: .black.opacity(0.06), radius: 0.5, y: 1)
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
                .contentShape(shape)
        }
    }
}

extension ButtonStyle where Self == SmallButtonStyle {
    static var small: SmallButtonStyle { SmallButtonStyle() }
}
