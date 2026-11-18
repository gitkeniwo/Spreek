import AppKit
import SwiftUI

/// `NSVisualEffectView` wrapper — the macOS 15 baseline material.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.isEmphasized = false
        update(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        update(view)
    }

    private func update(_ view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
    }
}

/// Glass background clipped to `shape`: Liquid Glass on macOS 26+, an
/// `NSVisualEffectView` material on macOS 15 (which must look finished on its own).
struct GlassBackground<S: InsettableShape>: ViewModifier {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var shape: S
    /// Opt into Liquid Glass when the OS supports it.
    var useLiquidGlass: Bool

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if #available(macOS 26, *), useLiquidGlass {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(
                    VisualEffectView(material: material, blendingMode: blendingMode)
                        .clipShape(shape)
                )
                .overlay(
                    shape.strokeBorder(
                        Color.white.opacity(colorScheme == .dark ? 0.16 : 0.6),
                        lineWidth: Metrics.hairline
                    )
                )
        }
    }
}

extension View {
    func glassBackground<S: InsettableShape>(
        _ material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        in shape: S,
        liquidGlass: Bool = true
    ) -> some View {
        modifier(GlassBackground(material: material, blendingMode: blendingMode, shape: shape, useLiquidGlass: liquidGlass))
    }
}

#Preview {
    HStack(spacing: 16) {
        Text("HUD capsule")
            .padding(.horizontal, 24)
            .frame(height: Metrics.floatingBarHeight)
            .glassBackground(.hudWindow, in: Capsule(), liquidGlass: false)
        Text("Popover")
            .padding(24)
            .glassBackground(.popover, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous), liquidGlass: false)
    }
    .padding(40)
    .background(LinearGradient(colors: [.orange, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
}
