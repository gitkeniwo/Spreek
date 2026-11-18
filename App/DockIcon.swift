import AppKit
import SpreekCore

/// Keeps the activation policy in line with Settings › Show in Dock (`app.dockIconMode`) and the
/// open dashboard windows, and shows the icon chosen in Settings › App icon (`app.icon`).
/// Launch is always menu-bar only (`LSUIElement`).
@MainActor
final class DockIconController {
    private let settings: AppSettings
    private var openDashboards = 0
    private var appliedMode: DockIconMode?
    private var appliedIcon: AppIconChoice?
    /// The Dock shows an App icon other than the bundle's.
    private var showsCustomIcon = false
    /// `appliedIcon` hasn't reached `NSApp.applicationIconImage` yet (menu bar only).
    private var iconIsPending = false

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// At launch: `always` shows the Dock icon right away.
    func applyLaunchPolicy() {
        if settings.dockIconMode == .always { showInDock() }
    }

    /// Before the dashboard window opens: the app is already a regular app, so the window can
    /// come to the front and become key instead of racing the policy switch.
    func prepareForDashboard() {
        if settings.dockIconMode != .never, NSApp.activationPolicy() != .regular { showInDock() }
    }

    func dashboardOpened() {
        openDashboards += 1
        if settings.dockIconMode != .never, NSApp.activationPolicy() != .regular {
            showInDock()
        } else if iconIsPending {
            // Hidden from the Dock: the icon still shows in the dashboard's alerts.
            applyIconImage()
        }
        NSApp.activate()
    }

    func dashboardClosed() {
        openDashboards = max(openDashboards - 1, 0)
        guard openDashboards == 0, settings.dockIconMode != .always, NSApp.activationPolicy() != .accessory else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    /// The setting changed while running: apply it at once.
    func modeChanged(_ mode: DockIconMode) {
        guard mode != appliedMode else { return }
        let isFirst = appliedMode == nil
        appliedMode = mode
        guard !isFirst else { return }
        let regular = switch mode {
        case .always: true
        case .never: false
        case .whileDashboardOpen: openDashboards > 0
        }
        let policy: NSApplication.ActivationPolicy = regular ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        if policy == .regular { showInDock() } else { NSApp.setActivationPolicy(policy) }
        // Leaving `.regular` hides the app's windows; bring the dashboard back.
        if policy == .accessory, openDashboards > 0 { NSApp.activate() }
    }

    /// The App icon setting changed (or was loaded): the Dock shows it at once. Snavel is the
    /// bundle icon, which Finder and Launchpad keep showing for every choice.
    func iconChanged(_ icon: AppIconChoice) {
        guard icon != appliedIcon else { return }
        appliedIcon = icon
        iconIsPending = true
        // Menu bar only, nothing shows the icon: it's set when a dashboard opens.
        if openDashboards > 0 || NSApp.activationPolicy() == .regular { applyIconImage() }
    }

    private func showInDock() {
        NSApp.setActivationPolicy(.regular)
        // Becoming a regular app can bring back the bundle icon; set the chosen one again.
        applyIconImage()
    }

    /// Every assignment makes AppKit keep a bitmap snapshot of the image (4 MB for the 1024 px
    /// asset, or the bundle icon when set to nil), so the Dock image is only set when it differs
    /// from the bundle icon or replaces a custom one, and at 256 pt.
    private func applyIconImage() {
        iconIsPending = false
        let icon = appliedIcon ?? settings.appIcon
        guard icon != .snavel || showsCustomIcon else { return }
        showsCustomIcon = icon != .snavel
        NSApp.applicationIconImage = showsCustomIcon ? Self.dockImage(named: "AppIcon-\(icon.rawValue)") : nil
    }

    /// The Dock draws at most 256 pt (128 pt magnified ×2), so a 256 pt image is as sharp as the
    /// 512 pt asset at a quarter of the snapshot.
    private static func dockImage(named name: String) -> NSImage? {
        guard let source = NSImage(named: name) else { return nil }
        let size = NSSize(width: 256, height: 256)
        return NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
    }
}
