import Observation
import SpreekCore
import SwiftData
import SwiftUI

/// Settings pages reachable from the dashboard sidebar.
enum SettingsSection: String, CaseIterable, Hashable, Identifiable {
    case voices, floatingBar, shortcuts, appearance, general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .voices: "Voices & Engines"
        case .floatingBar: "Floating Bar"
        case .shortcuts: "Shortcuts"
        case .appearance: "Appearance"
        case .general: "General"
        }
    }

    var symbol: String {
        switch self {
        case .voices: "waveform"
        case .floatingBar: "capsule"
        case .shortcuts: "keyboard"
        case .appearance: "paintpalette"
        case .general: "slider.horizontal.3"
        }
    }
}

/// Which page the dashboard window shows.
enum DashboardRoute: Hashable {
    case history
    case favorites
    case folder(PersistentIdentifier)
    case tag(PersistentIdentifier)
    case settings(SettingsSection)
    /// Storage manager: its own page, not part of the scrolling Settings page.
    case storage

    /// A page of sentences (History, Favorites, a folder or tag) rather than Settings or Storage.
    var isLibrary: Bool {
        switch self {
        case .history, .favorites, .folder, .tag: true
        case .settings, .storage: false
        }
    }
}

/// Dashboard window state that outlives the window (the window can be closed and reopened)
/// and that other parts of the app drive (the floating bar selects the current sentence).
@MainActor
@Observable
final class DashboardState {
    var route: DashboardRoute = .history
    /// Selected rows; the detail shows `focused` when it is selected.
    var selection: Set<PersistentIdentifier> = []
    /// The row last clicked (anchor for shift-click and the detail when several are selected).
    var focused: PersistentIdentifier?
    var query = LibraryQuery(
        range: .week,
        sort: UserDefaults.standard.string(forKey: DashboardState.sortKey).flatMap(LibrarySort.init(rawValue:)) ?? .firstRecorded
    )
    /// Remembers the list order across launches.
    static let sortKey = "dashboard.sort"
    /// Collapsed day headers (start of day).
    var collapsedDays: Set<Date> = []
    var showsInspector = true
    /// Activity footer expanded (pills + chart) or collapsed to a one-line status bar;
    /// the footer's own toggle and the list toolbar's chart button both flip it.
    var showsChart = UserDefaults.standard.object(forKey: DashboardState.showsChartKey) == nil
        || UserDefaults.standard.bool(forKey: DashboardState.showsChartKey) {
        didSet { UserDefaults.standard.set(showsChart, forKey: Self.showsChartKey) }
    }
    /// Remembers whether the activity footer is collapsed across launches.
    static let showsChartKey = "dashboard.showsActivity"
    /// Only sentences with a note (filter toolbar button).
    var onlyWithNotes = false
    /// Footer chart window length; independent of the list's `query.range`.
    var chartRange: ChartRange = .days30
    /// Footer chart paging: 0 = the window ending today, 1 = the one before, …
    var chartOffset = 0
    /// Folder Info sheet: `.some(nil)` creates a folder.
    var folderSheet: FolderSheetTarget?
    /// Bumped by ⌘F; the search field takes focus when it changes.
    private(set) var searchFocusRequest = 0

    /// ⌘F: leaves Settings or Storage for History if needed and focuses the search field.
    func focusSearch() {
        if !route.isLibrary { show(.history) }
        searchFocusRequest += 1
    }

    func select(_ id: PersistentIdentifier?) {
        selection = id.map { [$0] } ?? []
        focused = id
    }

    func setSort(_ sort: LibrarySort) {
        query.sort = sort
        collapsedDays = []
        UserDefaults.standard.set(sort.rawValue, forKey: Self.sortKey)
    }

    func show(_ route: DashboardRoute) {
        guard route != self.route else { return }
        self.route = route
        select(nil)
    }
}

/// What the Folder Info sheet edits.
struct FolderSheetTarget: Identifiable {
    /// `nil` creates a folder.
    let folder: Folder?
    /// A sentence to file in the folder once it's saved ("New Folder…" from a sentence).
    var moving: Sentence?
    let id = UUID()
}
