import AppKit
import SpreekCore
import SwiftData
import SwiftUI

@main
struct SpreekApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover()
                .environment(appDelegate.model)
                .modelContainer(appDelegate.model.container)
        } label: {
            MenuBarLabel(model: appDelegate.model)
        }
        .menuBarExtraStyle(.window)

        Window("Spreek", id: "dashboard") {
            DashboardWindowRoot()
                .environment(appDelegate.model)
                .modelContainer(appDelegate.model.container)
        }
        .defaultSize(width: 1220, height: 1020)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .windowList) {
                OpenDashboardCommand(model: appDelegate.model)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { appDelegate.model.openDashboard(.settings(.voices)) }
                    .keyboardShortcut(",")
            }
            CommandGroup(after: .textEditing) {
                Button("Find") { appDelegate.model.focusSearch() }
                    .keyboardShortcut("f")
            }
        }

        #if DEBUG
        Window("Design Preview", id: "design-preview") {
            DesignPreview()
        }
        .defaultSize(width: 1000, height: 900)
        #endif
    }
}

/// Menu bar icon: the glyph paired with Settings › App icon. It lives as long as the app, so it
/// hands `openWindow` to the model for AppKit-hosted views (the floating bar's dashboard button).
private struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image("MenuBar-\(model.settings.appIcon.rawValue)")
            .renderingMode(.template)
            .accessibilityLabel("Spreek")
            .task { model.openWindowAction = openWindow }
    }
}

/// Window › Dashboard (⌘D) while one of Spreek's windows is key.
private struct OpenDashboardCommand: View {
    let model: AppModel

    var body: some View {
        Button("Dashboard") { model.openDashboard() }
            .keyboardShortcut("d")
    }
}
