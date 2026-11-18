import SpreekCore
import SwiftUI

/// Folder Info sheet: creates a folder (`folder == nil`) or
/// edits one. Nothing is written until Save.
struct FolderInfoSheet: View {
    let folder: Folder?
    /// Called after Save with the created or edited folder.
    var onSave: (Folder) -> Void = { _ in }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.badgeStyle) private var badgeStyle

    @State private var name = ""
    @State private var color: FolderColor = .orange
    @State private var symbol = FolderIcon.previewSymbols[0]
    /// `nil` = no folder language: sentences keep their detected one.
    @State private var language: LanguageCode?
    @State private var voiceID: String?
    @State private var speed: Double?
    @State private var note = ""
    @State private var loaded = false

    static let speeds: [Double] = [0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 14) {
                GridRow {
                    FormLabel("Name:", width: 90)
                    TextField("Folder name", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 9)
                        .frame(height: 26)
                        .background(Color.field, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).strokeBorder(Color.separator, lineWidth: Metrics.hairline))
                }
                GridRow(alignment: .top) {
                    FormLabel("Icon:", width: 90).padding(.top, 3)
                    iconPicker
                }
                GridRow(alignment: .top) {
                    FormLabel("Language:", width: 90).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 6) {
                        languageMenu
                        Text(languageHint)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.fg3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                GridRow {
                    FormLabel("Voice:", width: 90)
                    voiceMenu.disabled(language == nil)
                }
                GridRow {
                    FormLabel("Speed:", width: 90)
                    speedMenu
                }
                GridRow(alignment: .top) {
                    FormLabel("Note:", width: 90).padding(.top, 6)
                    NoteEditor(markdown: note, onChange: { note = $0 }, showsHint: false, maxTextHeight: 180, debounce: .zero)
                }
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(CapsuleButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(CapsuleButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(EdgeInsets(top: 22, leading: 22, bottom: 18, trailing: 22))
        .frame(width: 452)
        .background(Color.windowBG)
        .onAppear(perform: load)
        .onChange(of: language) { _, newValue in
            guard let newValue else {
                voiceID = nil
                return
            }
            model.voices.load(newValue)
            if let voiceID, !voices(for: newValue).contains(where: { $0.id == voiceID }) { self.voiceID = nil }
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var languageHint: String {
        guard let language else { return "Sentences keep the language detected when they were spoken." }
        return "Sentences in this folder are read as \(language.info.englishName). Auto-detect is skipped when you replay from here."
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            FolderIcon(symbol: symbol, color: color, size: .large)
                .shadow(color: .black.opacity(0.2), radius: 6, y: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text("Folder Info")
                    .font(.spreekRounded(size: 20, weight: .black))
                    .foregroundStyle(Color.fg)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.fg3)
            }
        }
    }

    private var subtitle: String {
        guard let folder else { return "New folder" }
        let count = folder.sentences.count
        return "\(count) \(count == 1 ? "sentence" : "sentences") · created \(DashboardFormat.day(folder.createdAt))"
    }

    // MARK: Icon

    private var iconPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(FolderColor.allCases) { option in
                    Button { color = option } label: {
                        Circle()
                            .fill(option.color)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: Metrics.hairline))
                            .padding(3)
                            .overlay(Circle().strokeBorder(option == color ? option.color : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.rawValue.capitalized)
                    .accessibilityAddTraits(option == color ? .isSelected : [])
                }
            }
            .padding(.leading, -3)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
                ForEach(FolderIcon.previewSymbols, id: \.self) { option in
                    Button { symbol = option } label: {
                        Image(systemName: option)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(option == symbol ? Color.white : Color.fg2)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(option == symbol ? color.color : .clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option)
                    .accessibilityAddTraits(option == symbol ? .isSelected : [])
                }
            }
            .padding(6)
            .background(Color.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: Popups

    private var languageMenu: some View {
        Menu {
            Button("None") { language = nil }
            Divider()
            ForEach(model.pickerLanguages(including: language), id: \.self) { option in
                Button { language = option } label: {
                    Text("\(option.info.flagEmoji)  \(option.nativeName)")
                }
            }
        } label: {
            PopupLabel {
                if let language {
                    LanguageBadge(language: language, style: badgeStyle, size: .s)
                    Text(language.nativeName)
                } else {
                    Text("None").foregroundStyle(Color.fg2)
                }
            }
        }
        .plainMenu()
    }

    private func voices(for language: LanguageCode) -> [Voice] {
        model.voices.groups(for: language, selected: nil).flatMap(\.voices)
    }

    @ViewBuilder private var voiceMenu: some View {
        if let language {
            voiceMenu(for: language)
        } else {
            PopupLabel {
                Text("Detected language’s default")
                    .foregroundStyle(Color.fg3)
            }
            .opacity(0.6)
            .help("Pick a folder language to choose a voice")
        }
    }

    private func voiceMenu(for language: LanguageCode) -> some View {
        let defaultID = model.speech.defaultVoice(for: language)
        return Menu {
            Button("\(VoiceName.name(defaultID)) — language default") { voiceID = nil }
            ForEach(model.voices.groups(for: language, selected: voiceID)) { group in
                Section(group.title) {
                    ForEach(group.voices) { voice in
                        Button("\(voice.displayName)  \(voice.detail)") { voiceID = voice.id }
                    }
                }
            }
        } label: {
            PopupLabel {
                if let voiceID {
                    Text(VoiceName.name(voiceID))
                    Text(EdgeCLIProvider.isEdgeVoiceID(voiceID) ? voiceID : "macOS")
                        .font(.spreekMono(size: 11))
                        .foregroundStyle(Color.fg3)
                } else {
                    Text(VoiceName.name(defaultID))
                    Text("language default")
                        .font(.spreekMono(size: 11))
                        .foregroundStyle(Color.fg3)
                }
            }
        }
        .plainMenu()
    }

    private var speedMenu: some View {
        Menu {
            Button(language.map { "Default (\(PlaybackFormat.speed(model.settings.speed(for: $0))))" } ?? "Default") { speed = nil }
            Divider()
            ForEach(Self.speeds, id: \.self) { option in
                Button(PlaybackFormat.speed(option)) { speed = option }
            }
        } label: {
            PopupLabel {
                Text(speed.map(PlaybackFormat.speed) ?? "Default")
                    .font(.spreekMono(size: 12))
            }
        }
        .plainMenu()
    }

    // MARK: Load / save

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let folder {
            name = folder.name
            color = folder.color
            symbol = folder.symbol
            language = folder.language
            voiceID = folder.voiceID
            speed = folder.speed
            note = folder.note
        } else {
            // Unused color first, so new folders are easy to tell apart.
            let used = Set(model.library.folders().map(\.colorID))
            color = FolderColor.allCases.first { !used.contains($0.rawValue) } ?? .orange
        }
        if let language { model.voices.load(language) }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        let library = model.library
        let target = folder ?? library.createFolder(name: trimmedName, color: color.rawValue, symbol: symbol, language: language)
        library.updateFolder(
            target, name: trimmedName, color: color.rawValue, symbol: symbol, language: .some(language),
            voiceID: .some(voiceID), speed: .some(speed), note: note
        )
        onSave(target)
        dismiss()
    }
}

/// Display names for voice ids of either engine.
enum VoiceName {
    /// "Fenna" for `nl-NL-FennaNeural`, the macOS voice's name otherwise.
    static func name(_ voiceID: String) -> String {
        EdgeCLIProvider.isEdgeVoiceID(voiceID)
            ? EdgeVoiceCatalog.displayName(for: voiceID)
            : SystemProvider.voiceName(for: voiceID) ?? voiceID
    }
}
