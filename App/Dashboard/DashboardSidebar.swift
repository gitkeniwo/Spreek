import SpreekCore
import SwiftData
import SwiftUI

/// Sidebar: Library, Folders, Tags, then Settings at the bottom. `SidebarContainer` decides
/// its chrome per OS version. Folders, tags and History accept dragged sentences.
struct DashboardSidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.badgeStyle) private var badgeStyle

    @Query(sort: [SortDescriptor(\Folder.createdAt), SortDescriptor(\Folder.name)]) private var folders: [Folder]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query private var sentences: [Sentence]

    /// Puts the + glyph (11 pt in a 20 pt button) over the row counts: rows inset their trailing
    /// content 8 pt, so the glyph's right edge lands there too.
    private static let plusTrailing: CGFloat = 4

    @State private var folderToDelete: Folder?
    @State private var tagToRename: Tag?
    @State private var tagName = ""
    @State private var creatingTag = false
    /// The row or chip a drag is hovering over.
    @State private var dropTarget: DropTarget?

    private enum DropTarget: Hashable {
        case history
        case folder(PersistentIdentifier)
        case tag(PersistentIdentifier)
    }

    private func isTargeted(_ target: DropTarget) -> Binding<Bool> {
        Binding(
            get: { dropTarget == target },
            set: { hovering in
                if hovering { dropTarget = target } else if dropTarget == target { dropTarget = nil }
            }
        )
    }

    var body: some View {
        let dashboard = model.dashboard
        SidebarContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GroupLabel("Library")
                    NavRow(isSelected: dashboard.route == .history, action: { dashboard.show(.history) }) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 15))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                        Text("History").fontWeight(.semibold)
                    } trailing: {
                        Count(sentences.count)
                    }
                    .modifier(DropHighlight(isActive: dropTarget == .history))
                    .sentenceDropDestination(model, action: { .move(nil) }, isTargeted: isTargeted(.history))
                    .help("Drop sentences here to remove them from their folder")
                    NavRow(isSelected: dashboard.route == .favorites, action: { dashboard.show(.favorites) }) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.favorite)
                        Text("Favorites")
                    } trailing: {
                        Count(sentences.filter(\.isFavorite).count)
                    }

                    HStack {
                        GroupLabel("Folders")
                        Spacer()
                        Button { dashboard.folderSheet = FolderSheetTarget(folder: nil) } label: {
                            Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        }
                        .buttonStyle(.glyph(size: 20, color: .fg2))
                        .help("New Folder…")
                        .accessibilityLabel("New Folder")
                        .padding(.trailing, Self.plusTrailing)
                        .padding(.top, 10)
                    }
                    ForEach(folders) { folder in
                        let route = DashboardRoute.folder(folder.persistentModelID)
                        NavRow(isSelected: dashboard.route == route, action: { dashboard.show(route) }) {
                            FolderIcon(symbol: folder.symbol, color: folder.color)
                            Text(folder.name).lineLimit(1).truncationMode(.tail)
                        } trailing: {
                            if let language = folder.language {
                                LanguageBadge(language: language, style: badgeStyle, size: .s)
                            }
                            Count(folder.sentences.count).frame(width: 20, alignment: .trailing)
                        }
                        .modifier(DropHighlight(isActive: dropTarget == .folder(folder.persistentModelID)))
                        .sentenceDropDestination(model, action: { .move(folder) }, isTargeted: isTargeted(.folder(folder.persistentModelID)))
                        .contextMenu {
                            Button("Get Info…") { dashboard.folderSheet = FolderSheetTarget(folder: folder) }
                            Divider()
                            Button("Delete “\(folder.name)”…", role: .destructive) { folderToDelete = folder }
                        }
                    }

                    HStack {
                        GroupLabel("Tags")
                        Spacer()
                        Button {
                            tagName = ""
                            creatingTag = true
                        } label: {
                            Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        }
                        .buttonStyle(.glyph(size: 20, color: .fg2))
                        .help("New Tag…")
                        .accessibilityLabel("New Tag")
                        .padding(.trailing, Self.plusTrailing)
                        .padding(.top, 10)
                    }
                    FlowLayout(spacing: 5, lineSpacing: 5) {
                        ForEach(tags) { tag in
                            tagChip(tag)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
                }
            }
            .scrollIndicators(.never)

            Spacer(minLength: 8)
            GroupLabel("Settings")
            ForEach(SettingsSection.allCases) { section in
                let route = DashboardRoute.settings(section)
                NavRow(isSelected: dashboard.route == route, prominent: true, action: { dashboard.show(route) }) {
                    Image(systemName: section.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 17)
                    Text(section.title)
                } trailing: {
                    EmptyView()
                }
            }
            NavRow(isSelected: dashboard.route == .storage, prominent: true, action: { dashboard.show(.storage) }) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 17)
                Text("Storage")
            } trailing: {
                EmptyView()
            }
        }
        #if DEBUG
        // `-SpreekDebugDropHover <folder name>`: shows a folder's drop highlight for screenshots.
        .task {
            if let name = UserDefaults.standard.string(forKey: "SpreekDebugDropHover"),
               let folder = folders.first(where: { $0.name == name }) {
                dropTarget = .folder(folder.persistentModelID)
            }
        }
        #endif
        .confirmationDialog(
            "Delete the folder “\(folderToDelete?.name ?? "")”?",
            isPresented: Binding(get: { folderToDelete != nil }, set: { if !$0 { folderToDelete = nil } })
        ) {
            Button("Delete Folder", role: .destructive) {
                if let folder = folderToDelete {
                    if dashboard.route == .folder(folder.persistentModelID) { dashboard.show(.history) }
                    model.library.deleteFolder(folder)
                }
                folderToDelete = nil
            }
        } message: {
            Text("Its sentences stay in History.")
        }
        .alert("Rename Tag", isPresented: Binding(get: { tagToRename != nil }, set: { if !$0 { tagToRename = nil } })) {
            TextField("Name", text: $tagName)
            Button("Rename") {
                let name = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
                if let tag = tagToRename, !name.isEmpty { model.library.updateTag(tag, name: name) }
                tagToRename = nil
            }
            Button("Cancel", role: .cancel) { tagToRename = nil }
        }
        .alert("New Tag", isPresented: $creatingTag) {
            TextField("Name", text: $tagName)
            Button("Create") {
                let name = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { model.createTag(named: name) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func tagChip(_ tag: Tag) -> some View {
        let dashboard = model.dashboard
        let route = DashboardRoute.tag(tag.persistentModelID)
        let selected = dashboard.route == route
        return Button { dashboard.show(selected ? .history : route) } label: {
            TagChip(name: tag.name, color: tag.color)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .modifier(DropHighlight(isActive: dropTarget == .tag(tag.persistentModelID), cornerRadius: Radius.chip + 2))
        .sentenceDropDestination(model, action: { .tag(tag) }, isTargeted: isTargeted(.tag(tag.persistentModelID)))
        .help(selected ? "Show all sentences" : "Show sentences tagged “\(tag.name)”")
        .contextMenu {
            Button("Rename…") {
                tagName = tag.name
                tagToRename = tag
            }
            Menu("Color") {
                ForEach(TagColor.allCases) { color in
                    Button {
                        model.library.updateTag(tag, color: color.rawValue)
                    } label: {
                        if tag.color == color { Label(color.rawValue.capitalized, systemImage: "checkmark") } else { Text(color.rawValue.capitalized) }
                    }
                }
            }
            Divider()
            Button("Delete Tag", role: .destructive) {
                if selected { dashboard.show(.history) }
                model.library.deleteTag(tag)
            }
        }
    }
}

/// The one place the sidebar's chrome depends on the OS version.
///
/// - macOS 26+: an inset floating rounded panel with the traffic lights inside it (matches Tahoe).
/// - macOS 15: flush and full height, square corners, a hairline on the right edge, and the
///   content pushed below the traffic lights ("Library" starts ≈ 52 pt from the top).
struct SidebarContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26, *) {
            column(topInset: 22)
                .background(Color.sidebarBG, in: RoundedRectangle(cornerRadius: Radius.sidebarPanel, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.sidebarPanel, style: .continuous).strokeBorder(Color.separator, lineWidth: Metrics.hairline))
                .padding(8)
        } else {
            // 12 + 26 + the group label's 14 pt top padding ≈ 52 pt to "Library".
            column(topInset: 26)
                .background(Color.sidebarBG)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Color.separator).frame(width: Metrics.hairline)
                }
        }
    }

    private func column(topInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Room for the traffic lights.
            Color.clear.frame(height: topInset)
            content
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// "Library", "Folders" … in rounded heavy `fg3`.
private struct GroupLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.spreekRounded(size: 11.5, weight: .heavy))
            .foregroundStyle(Color.fg3)
            .padding(EdgeInsets(top: 14, leading: 10, bottom: 4, trailing: 10))
    }
}

private struct Count: View {
    let value: Int

    init(_ value: Int) {
        self.value = value
    }

    var body: some View {
        Text("\(value)")
            .font(.spreekRounded(size: 12, weight: .bold))
            .foregroundStyle(Color.fg3)
            .monospacedDigit()
    }
}

/// Sidebar row: 30 pt, radius 9; gray fill when selected (accent fill for `prominent` rows).
private struct NavRow<Leading: View, Trailing: View>: View {
    var isSelected: Bool
    var prominent = false
    var action: () -> Void
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                leading()
                Spacer(minLength: 4)
                trailing()
            }
            .font(.system(size: 13))
            .foregroundStyle(isSelected && prominent ? Color.white : Color.fg)
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(fill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var fill: Color {
        if isSelected { return prominent ? .accentColor : Color(light: .black.opacity(0.08), dark: .white.opacity(0.1)) }
        return hovering ? Color(light: .black.opacity(0.05), dark: .white.opacity(0.06)) : .clear
    }
}
