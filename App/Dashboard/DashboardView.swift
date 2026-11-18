import SpreekCore
import SwiftData
import SwiftUI

/// The dashboard window: sidebar (see `SidebarContainer`), sentence list,
/// detail; Settings routes show the settings page (`SettingsView`), Storage its own page (`StorageView`).
struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var dashboard = model.dashboard
        HStack(spacing: 0) {
            DashboardSidebar()
                .frame(width: 232)
            switch dashboard.route {
            case .settings(let section):
                SettingsView(section: section)
            case .storage:
                StorageView()
            default:
                SentenceListColumn()
                    .frame(width: dashboard.showsInspector ? 430 : nil)
                    .frame(maxWidth: dashboard.showsInspector ? 430 : .infinity)
                if dashboard.showsInspector {
                    Rectangle().fill(Color.separator).frame(width: Metrics.hairline)
                    // minWidth 0: the column takes the width that's left, so a wide sentence or voice row
                    // can't push the whole window sideways at the minimum size.
                    SentenceDetailColumn()
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .clipped()
                }
            }
        }
        .frame(minWidth: 1000, minHeight: 700)
        .background(Color.windowBG)
        .environment(\.badgeStyle, model.settings.badgeStyle)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear { model.dockIcon.dashboardOpened() }
        .onDisappear { model.dockIcon.dashboardClosed() }
        .sheet(item: $dashboard.folderSheet) { target in
            FolderInfoSheet(folder: target.folder) { folder in
                if let sentence = target.moving { model.library.move(sentence, to: folder) }
            }
            .environment(model)
            .environment(\.badgeStyle, model.settings.badgeStyle)
        }
    }
}

/// The dashboard window's content, mounted only while the window is open. SwiftUI keeps a closed
/// `Window` scene's views alive (every query, row and the activity chart, observing the library
/// in the background); dropping them on close returns that memory. Selection and route live in
/// `DashboardState`, so reopening shows the same place.
struct DashboardWindowRoot: View {
    @State private var isOpen = true

    var body: some View {
        ZStack {
            if isOpen { DashboardView() }
        }
        .onAppear { isOpen = true }
        .onDisappear { isOpen = false }
    }
}
