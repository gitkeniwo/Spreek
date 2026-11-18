import AppKit
import SwiftUI

extension View {
    /// Makes the enclosing scroll view use overlay scrollers: a thin bar that appears while
    /// scrolling and fades out afterwards, whatever the system "Show scroll bars" setting says
    /// (with a mouse that setting is usually "Always", which keeps a permanent track).
    /// Apply it to the content *inside* the `ScrollView`.
    func overlayScrollers() -> some View {
        background(OverlayScrollerStyle())
    }
}

private struct OverlayScrollerStyle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ view: NSView, context: Context) { (view as? Probe)?.apply() }

    /// Finds the `NSScrollView` the SwiftUI content sits in once the view is in a window.
    private final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
            // SwiftUI may build its scroll view a moment after the content is attached.
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        func apply() {
            guard let scrollView = enclosingScrollView else { return }
            if scrollView.scrollerStyle != .overlay { scrollView.scrollerStyle = .overlay }
            scrollView.autohidesScrollers = true
        }
    }
}
