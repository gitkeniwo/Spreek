import AppKit
import ApplicationServices
import Carbon.HIToolbox
import SpreekCore

/// Reads the selection in the frontmost app: Accessibility first, then ⌘C with the
/// clipboard restored. Both paths need the Accessibility permission.
@MainActor
final class SelectionReader: SelectionCapturing {
    private let pasteboard: SystemPasteboard
    /// Don't let a hung app stall the hotkey.
    private static let axTimeout: Float = 0.25

    init(pasteboard: SystemPasteboard = SystemPasteboard()) {
        self.pasteboard = pasteboard
    }

    func captureSelection() async -> CapturedSelection? {
        guard AXIsProcessTrusted() else { return nil }
        let app = NSWorkspace.shared.frontmostApplication
        let appElement = app.map { AXUIElementCreateApplication($0.processIdentifier) }
        if let appElement { AXUIElementSetMessagingTimeout(appElement, Self.axTimeout) }
        let focused = focusedElement(fallback: appElement)

        let text: String
        let method: CaptureMethod
        if let selected = focused.flatMap({ Self.string($0, kAXSelectedTextAttribute) }),
           !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = selected
            method = .accessibility
        } else if let copied = await CopyCapture.capture(from: pasteboard, sendCopy: Self.postCommandC) {
            text = copied
            method = .copy
        } else {
            return nil
        }

        return CapturedSelection(
            text: text, method: method,
            appName: app?.localizedName, bundleID: app?.bundleIdentifier,
            url: Self.browserURL(focused: focused, app: appElement),
            bounds: focused.flatMap(Self.selectionBounds)
        )
    }

    /// Source app of the frontmost window, for selections that arrive another way (Services).
    static func frontmostSource() -> (name: String?, bundleID: String?) {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.localizedName, app?.bundleIdentifier)
    }

    // MARK: Accessibility

    private func focusedElement(fallback appElement: AXUIElement?) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, Self.axTimeout)
        return Self.element(systemWide, kAXFocusedUIElementAttribute)
            ?? appElement.flatMap { Self.element($0, kAXFocusedUIElementAttribute) }
    }

    /// Where the selection is on screen, in Cocoa coordinates: `AXBoundsForRange` of the selected
    /// range, else the text-marker pair Safari and Chromium web areas use. `nil` when the app
    /// reports neither (many Electron apps) or a rect that isn't on any screen.
    private static func selectionBounds(_ element: AXUIElement) -> CGRect? {
        var rect: CGRect?
        if let range = copyValue(element, kAXSelectedTextRangeAttribute) {
            rect = parameterizedRect(element, kAXBoundsForRangeParameterizedAttribute, range)
        }
        if rect == nil, let markers = copyValue(element, "AXSelectedTextMarkerRange") {
            rect = parameterizedRect(element, "AXBoundsForTextMarkerRange", markers)
        }
        // AX rects have a top-left origin on the primary screen; Cocoa's is bottom-left.
        guard let rect, rect.width > 0 || rect.height > 0,
              let primaryHeight = NSScreen.screens.first?.frame.height
        else { return nil }
        let flipped = CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
        return NSScreen.screens.contains { $0.frame.intersects(flipped) } ? flipped : nil
    }

    private static func parameterizedRect(_ element: AXUIElement, _ attribute: String, _ parameter: CFTypeRef) -> CGRect? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgRect, &rect) ? rect : nil
    }

    /// The page URL: the enclosing `AXWebArea`'s `AXURL` (Safari, Chromium), else the focused
    /// window's `AXDocument`. Bounded walk; returns nil when the app doesn't expose either.
    private static func browserURL(focused: AXUIElement?, app: AXUIElement?) -> URL? {
        var current = focused
        for _ in 0..<30 {
            guard let element = current else { break }
            if string(element, kAXRoleAttribute) == "AXWebArea", let url = url(element, kAXURLAttribute) {
                return url
            }
            current = self.element(element, kAXParentAttribute)
        }
        if let window = app.flatMap({ element($0, kAXFocusedWindowAttribute) }),
           let document = string(window, kAXDocumentAttribute) {
            return URL(string: document)
        }
        return nil
    }

    private static func copyValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copyValue(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copyValue(element, attribute) as? String
    }

    private static func url(_ element: AXUIElement, _ attribute: String) -> URL? {
        copyValue(element, attribute) as? URL
    }

    // MARK: ⌘C

    /// Posts ⌘C. A private event source with explicit flags keeps a still-held ⌥ (from the
    /// ⌥S hotkey) from turning it into ⌥⌘C.
    private static func postCommandC() {
        let source = CGEventSource(stateID: .privateState)
        let key = CGKeyCode(kVK_ANSI_C)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: keyDown) else { continue }
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
        }
    }
}
