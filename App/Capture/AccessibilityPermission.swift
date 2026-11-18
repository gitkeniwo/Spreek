import AppKit
import ApplicationServices
import Observation

/// Tracks whether Spreek may read other apps' selection (and post ⌘C), which both need
/// Privacy & Security › Accessibility.
@MainActor
@Observable
final class AccessibilityPermission {
    private(set) var isTrusted = AccessibilityPermission.checkTrusted(prompt: false)
    /// The popover explainer was closed for this launch.
    var explainerDismissed = false

    var showsExplainer: Bool { !isTrusted && !explainerDismissed }

    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init() {
        startPollingIfNeeded()
    }

    func refresh() {
        isTrusted = Self.checkTrusted(prompt: false)
        startPollingIfNeeded()
    }

    /// Shows the system "would like to control this computer" alert (macOS shows it only
    /// until the user has answered once).
    func requestWithSystemPrompt() {
        isTrusted = Self.checkTrusted(prompt: true)
        startPollingIfNeeded()
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        startPollingIfNeeded()
    }

    /// The grant takes effect without relaunching; poll until it appears.
    private func startPollingIfNeeded() {
        guard !isTrusted, pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                if Self.checkTrusted(prompt: false) {
                    self.isTrusted = true
                    self.pollTask = nil
                    return
                }
            }
        }
    }

    private static func checkTrusted(prompt: Bool) -> Bool {
        // The literal value of kAXTrustedCheckOptionPrompt (a mutable C global Swift 6 rejects).
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": prompt] as CFDictionary)
    }
}
