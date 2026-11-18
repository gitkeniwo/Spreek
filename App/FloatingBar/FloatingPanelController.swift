import AppKit
import SpreekCore
import SwiftUI

/// Borderless, non-activating panel: clicks don't take focus from the app the text came from.
/// It only becomes key while the user edits the note.
final class FloatingPanel: NSPanel {
    /// Set when the note editor is clicked; cleared when the panel resigns key.
    var allowsKey = false

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        // The SwiftUI view draws the shadow (0 16 44 black 30%).
        hasShadow = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        allowsKey = false
    }
}

/// Hosting view that reports hover over the glass (not the transparent shadow margins), even
/// though the panel is never active, and accepts the first click.
private final class BarHostingView<Content: View>: NSHostingView<Content> {
    var onHover: (Bool) -> Void = { _ in }
    private var hovering = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self && area.userInfo?["bar"] != nil {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self, userInfo: ["bar": true]
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        update(event)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        update(event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHovering(false)
    }

    private func update(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let margins = FloatingBarLayout.margins
        let glass = NSRect(
            x: margins.left, y: isFlipped ? margins.top : margins.bottom,
            width: bounds.width - margins.left - margins.right,
            height: bounds.height - margins.top - margins.bottom
        )
        setHovering(glass.contains(point))
    }

    private func setHovering(_ value: Bool) {
        guard value != hovering else { return }
        hovering = value
        onHover(value)
    }
}

/// Shows, hides, positions and resizes the floating bar from `FloatingBarModel`.
///
/// A new bar is placed by Settings › Position. The user can drag a showing bar anywhere; it stays
/// there, pinned or not, until it hides, and the spot is remembered for "Where I left it".
@MainActor
final class FloatingPanelController {
    private let model: AppModel
    private let panel = FloatingPanel()
    /// Glass size reported by SwiftUI (without margins).
    private var contentSize = CGSize(width: FloatingBarLayout.width, height: Metrics.floatingBarHeight)
    /// Screen chosen when the bar appeared; it stays there until hidden or dragged elsewhere.
    private var screen: NSScreen?
    /// The edge the bar keeps when it resizes.
    private var anchor = FloatingBarAnchor(x: 0, horizontal: .center, y: 0, vertical: .bottom)
    private var isShown = false
    /// The user dragged the bar since it appeared: settings and new speech no longer move it.
    private var wasDragged = false
    /// Set while the controller itself moves the panel, so `didMove` can tell a user drag apart.
    private var isPlacing = false

    init(model: AppModel) {
        self.model = model
        let hosting = BarHostingView(rootView: AnyView(
            FloatingBarRoot(onSize: { [weak self] size in self?.contentSizeChanged(size) })
                .environment(model)
                .environment(\.beginPanelEditing, { [weak self] in self?.beginEditing() })
        ))
        hosting.sizingOptions = []
        hosting.onHover = { [weak model] hovering in model?.bar.setHovering(hovering) }
        panel.contentView = hosting
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.panelMoved() }
        }
        observeVisibility()
        observeNewSpeech()
        observePositionSettings()
    }

    private func observeVisibility() {
        withObservationTracking {
            _ = model.bar.isVisible
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.model.bar.isVisible { self.show() } else { self.hide() }
                self.observeVisibility()
            }
        }
    }

    /// Near selection: a bar that is already showing follows the next selection it speaks.
    private func observeNewSpeech() {
        withObservationTracking {
            _ = model.bar.contentGeneration
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.model.settings.barPlacement == .nearSelection { self.replace() }
                self.observeNewSpeech()
            }
        }
    }

    /// Changing Settings › Position moves a showing bar, unless the user has dragged it.
    private func observePositionSettings() {
        withObservationTracking {
            _ = model.settings.barPlacement
            _ = model.settings.barPosition
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.replace()
                self.observePositionSettings()
            }
        }
    }

    private func show() {
        guard !isShown else { return }
        isShown = true
        wasDragged = false
        placeNewBar()
        setPanelFrame(animate: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard isShown else { return }
        isShown = false
        model.bar.setHovering(false)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, !self.isShown else { return }
                self.panel.orderOut(nil)
                if self.panel.isKeyWindow { self.panel.resignKey() }
            }
        }
    }

    /// Places a showing bar again (new selection, changed settings) unless the user moved it.
    private func replace() {
        guard isShown, !wasDragged else { return }
        placeNewBar()
        setPanelFrame(animate: true)
    }

    private func contentSizeChanged(_ size: CGSize) {
        guard size.width > 0, size.height > 0, size != contentSize else { return }
        contentSize = size
        guard isShown else { return }
        // The anchored edge stays put: a bar at the bottom grows upward, one at the top downward.
        setPanelFrame(animate: true)
    }

    private func beginEditing() {
        panel.allowsKey = true
        panel.makeKey()
    }

    // MARK: Placement

    /// Settings › Position for a bar that is just appearing.
    private func placeNewBar() {
        let settings = model.settings
        switch settings.barPlacement {
        case .fixed:
            place(at: settings.barPosition)
        case .lastDragged:
            if let drag = settings.barDragPosition {
                screen = drag.screenID.flatMap(NSScreen.screen(withDisplayUUID:)) ?? Self.screenWithMouse()
                anchor = FloatingBarPlacement.anchor(for: drag, in: visibleFrame)
            } else {
                place(at: settings.barPosition)
            }
        case .nearSelection:
            // Only speech that came from a selection has bounds; replays from the Dashboard,
            // Services and apps that don't report them use the pointer.
            if model.speech.source == .selection, let bounds = model.pipeline.lastCapture?.bounds {
                screen = Self.screen(containing: bounds) ?? Self.screenWithMouse()
                anchor = FloatingBarPlacement.anchor(nextTo: bounds, size: contentSize, in: visibleFrame)
            } else {
                screen = Self.screenWithMouse()
                anchor = FloatingBarPlacement.anchor(nearPointer: NSEvent.mouseLocation, size: contentSize, in: visibleFrame)
            }
        }
    }

    private func place(at position: FloatingBarPosition) {
        screen = Self.screenWithMouse()
        anchor = FloatingBarPlacement.anchor(for: position, in: visibleFrame)
    }

    private var visibleFrame: NSRect {
        (screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private func setPanelFrame(animate: Bool) {
        let glass = anchor.frame(for: contentSize, in: visibleFrame)
        let margins = FloatingBarLayout.margins
        let frame = NSRect(
            x: glass.minX - margins.left, y: glass.minY - margins.bottom,
            width: glass.width + margins.left + margins.right, height: glass.height + margins.top + margins.bottom
        )
        guard frame != panel.frame else { return }
        isPlacing = true
        defer { isPlacing = false }
        panel.setFrame(frame, display: true, animate: animate)
    }

    /// The user dragged the bar: it keeps this spot until it hides, grows away from the nearest
    /// screen edge, and the spot is saved for "Where I left it".
    private func panelMoved() {
        guard isShown, !isPlacing else { return }
        wasDragged = true
        let margins = FloatingBarLayout.margins
        let glass = NSRect(
            x: panel.frame.minX + margins.left, y: panel.frame.minY + margins.bottom,
            width: panel.frame.width - margins.left - margins.right, height: panel.frame.height - margins.top - margins.bottom
        )
        screen = Self.screen(containing: glass) ?? screen
        let drag = FloatingBarPlacement.dragPosition(for: glass, in: visibleFrame, screenID: screen?.displayUUID)
        anchor = FloatingBarPlacement.anchor(for: drag, in: visibleFrame)
        if model.settings.barDragPosition != drag { model.settings.barDragPosition = drag }
    }

    // MARK: Screens

    private static func screenWithMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    /// The screen showing most of `rect`.
    private static func screen(containing rect: NSRect) -> NSScreen? {
        NSScreen.screens
            .map { ($0, $0.frame.intersection(rect)) }
            .filter { !$0.1.isNull }
            .max { $0.1.width * $0.1.height < $1.1.width * $1.1.height }?.0
    }

}

extension NSScreen {
    /// The display's UUID: stable across reconnects and rearranging, unlike its display number.
    var displayUUID: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    static func screen(withDisplayUUID id: String) -> NSScreen? {
        screens.first { $0.displayUUID == id }
    }
}

/// Pads the bar by the shadow margins and reports the glass size so the panel can follow it.
private struct FloatingBarRoot: View {
    let onSize: (CGSize) -> Void

    var body: some View {
        let margins = FloatingBarLayout.margins
        FloatingBarView()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
            .padding(EdgeInsets(top: margins.top, leading: margins.left, bottom: margins.bottom, trailing: margins.right))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
