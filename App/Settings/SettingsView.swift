import KeyboardShortcuts
import SpreekCore
import SwiftUI

/// Settings page in the dashboard: one scrolling page; the
/// sidebar's Settings items scroll to their section.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    let section: SettingsSection

    @State private var showsLanguages = true
    @State private var showsEngines = true
    @State private var showsBar = true
    @State private var showsShortcuts = true
    @State private var showsAppearance = true
    @State private var showsGeneral = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    // Voices & Engines is the first section: land on the page header.
                    header
                        .padding(.top, 26)
                        .id(SettingsSection.voices)
                    SectionBar("Languages & Voices", isExpanded: $showsLanguages) {
                        LanguagesSection()
                    }
                    SectionBar("Engines", isExpanded: $showsEngines) {
                        EnginesSection()
                    }
                    SectionBar("Floating Bar", isExpanded: $showsBar) {
                        FloatingBarSection()
                    }
                    .id(SettingsSection.floatingBar)
                    SectionBar("Shortcuts", isExpanded: $showsShortcuts) {
                        ShortcutsSection()
                    }
                    .id(SettingsSection.shortcuts)
                    SectionBar("Appearance", isExpanded: $showsAppearance) {
                        AppearanceSection()
                    }
                    .id(SettingsSection.appearance)
                    SectionBar("General", isExpanded: $showsGeneral) {
                        GeneralSection()
                    }
                    .id(SettingsSection.general)
                }
                .padding(EdgeInsets(top: 0, leading: 28, bottom: 40, trailing: 40))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .onAppear { scroll(proxy, to: section, animated: false) }
            .onChange(of: section) { _, section in scroll(proxy, to: section, animated: true) }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            // The icon art sits on Apple's 824/1024 grid with its own shadow: 58 pt shows a ~47 pt squircle.
            Image("AppIcon-\(model.settings.appIcon.rawValue)")
                .resizable()
                .frame(width: 58, height: 58)
                .padding(-5)
                .accessibilityHidden(true)
            Text("Settings")
                .font(.spreekRounded(size: 28, weight: .black))
                .foregroundStyle(Color.fg)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(EdgeInsets(top: 0, leading: 4, bottom: 8, trailing: 4))
    }

    private func scroll(_ proxy: ScrollViewProxy, to section: SettingsSection, animated: Bool) {
        // Expand the target so there's something to land on.
        switch section {
        case .voices: showsLanguages = true
        case .floatingBar: showsBar = true
        case .shortcuts: showsShortcuts = true
        case .appearance: showsAppearance = true
        case .general: showsGeneral = true
        }
        Task { @MainActor in
            if animated {
                withAnimation(.snappy(duration: 0.3)) { proxy.scrollTo(section, anchor: .top) }
            } else {
                proxy.scrollTo(section, anchor: .top)
            }
        }
    }
}

// MARK: - Form rows

/// Right-aligned `Label:` column + value, Little Snitch style.
struct SettingsRow<Content: View>: View {
    let label: String
    var labelWidth: CGFloat = 230
    @ViewBuilder var content: () -> Content

    init(_ label: String, labelWidth: CGFloat = 230, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.labelWidth = labelWidth
        self.content = content
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            FormLabel(label, width: labelWidth)
            HStack(spacing: 10) { content() }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 30)
    }
}

/// A popup whose options are `(value, title)` pairs; the selected one gets a checkmark.
struct OptionsPopup<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    var accessibilityName: String

    var body: some View {
        Menu {
            ForEach(options, id: \.0) { option in
                Button {
                    selection = option.0
                } label: {
                    if option.0 == selection { Label(option.1, systemImage: "checkmark") } else { Text(option.1) }
                }
            }
        } label: {
            PopupLabel { Text(options.first { $0.0 == selection }?.1 ?? "") }
        }
        .plainMenu()
        .accessibilityLabel(accessibilityName)
    }
}

// MARK: - Languages & Voices

private struct LanguagesSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.badgeStyle) private var badgeStyle

    static let speeds: [Double] = [0.6, 0.7, 0.75, 0.8, 0.85, 0.9, 1.0, 1.1, 1.25, 1.5]

    var body: some View {
        @Bindable var settings = model.settings
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                tableHeader
                ForEach(settings.listedLanguagesSorted, id: \.self) { language in
                    LanguageRow(language: language)
                }
                HStack {
                    addLanguageMenu
                    Spacer()
                }
                .padding(.top, 10)
                .padding(.bottom, 4)
            }
            .padding(.horizontal, -2)

            VStack(alignment: .leading, spacing: 2) {
                SettingsRow("Detect language:") {
                    OptionsPopup(
                        options: [(.folderThenAuto, "Folder language first, then auto"), (.autoOnly, "Always auto-detect")],
                        selection: $settings.detectionMode, accessibilityName: "Detect language"
                    )
                }
                SettingsRow("When Dutch vs. German is unclear:") {
                    OptionsPopup(
                        options: [(.nl, "Prefer \(LanguageCode.nl.info.nativeName)"), (.de, "Prefer \(LanguageCode.de.info.nativeName)")],
                        selection: $settings.nlDeTiePreference, accessibilityName: "When Dutch versus German is unclear"
                    )
                }
                if settings.isEnglishEnabled {
                    SettingsRow("English variant:") {
                        SegmentedControl(options: LanguageCode.englishVariants, selection: $settings.englishVariant, accessibilityName: "English variant") { variant in
                            HStack(spacing: 6) {
                                LanguageBadge(language: variant, style: badgeStyle, size: .s)
                                Text(variant == .enUS ? "US" : "UK")
                            }
                        }
                        SettingsHint("Used when English is detected.")
                    }
                }
                SettingsRow("Language badge:") {
                    SegmentedControl(options: BadgeStyle.allCases, selection: $settings.badgeStyle, accessibilityName: "Language badge style") { style in
                        HStack(spacing: 6) {
                            LanguageBadge(language: .nl, style: style, size: .s)
                            Text(style == .code ? "Code" : "Flag")
                        }
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    private var tableHeader: some View {
        LanguageGrid {
            Text("Language")
        } voice: {
            Text("Voice")
        } backup: {
            Text("Backup")
        } speed: {
            Text("Speed")
        } test: {
            Text("Test")
        } on: {
            Text("On")
        } remove: {
            EmptyView()
        }
        .font(.spreekRounded(size: 11.5, weight: .heavy))
        .foregroundStyle(Color.fg3)
        .frame(height: 26)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.separator).frame(height: Metrics.hairline) }
    }

    private var addLanguageMenu: some View {
        let addable = model.settings.addableLanguages
        return Menu {
            ForEach(addable, id: \.self) { language in
                Button("\(language.info.flagEmoji)  \(language.info.nativeName) — \(language.info.englishName)") {
                    model.settings.add(language)
                    model.voices.load(language)
                }
            }
        } label: {
            AddLanguageLabel(isEnabled: !addable.isEmpty)
        }
        .plainMenu()
        .disabled(addable.isEmpty)
        .help(addable.isEmpty ? "Every language is listed" : "Add another language")
        .accessibilityLabel("Add language")
    }
}

/// Tinted capsule: plus glyph + "Add Language", brighter on hover.
private struct AddLanguageLabel: View {
    let isEnabled: Bool
    @State private var hovering = false

    var body: some View {
        let tint = isEnabled ? Color.accentColor : Color.fg3
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 10.5, weight: .bold))
            Text("Add Language")
                .font(.system(size: 12.5, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(height: 26)
        .background(Capsule().fill(tint.opacity(hovering && isEnabled ? 0.18 : 0.1)))
        .contentShape(Capsule())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Column layout shared by the header and the rows: 140 | flexible (voice popup 140–290) | flexible 110–150 | 80 | 50 | 46 | 20.
private struct LanguageGrid<A: View, B: View, G: View, C: View, D: View, E: View, F: View>: View {
    @ViewBuilder var language: () -> A
    @ViewBuilder var voice: () -> B
    @ViewBuilder var backup: () -> G
    @ViewBuilder var speed: () -> C
    @ViewBuilder var test: () -> D
    @ViewBuilder var on: () -> E
    @ViewBuilder var remove: () -> F

    var body: some View {
        HStack(spacing: 8) {
            language().frame(width: 140, alignment: .leading)
            voice().frame(maxWidth: .infinity, alignment: .leading)
            backup().frame(minWidth: 110, maxWidth: 150, alignment: .leading)
            speed().frame(width: 80, alignment: .leading)
            test().frame(width: 50, alignment: .leading)
            on().frame(width: 46, alignment: .leading)
            remove().frame(width: 20)
        }
    }
}

private struct LanguageRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.badgeStyle) private var badgeStyle
    let language: LanguageCode
    @State private var hovering = false

    var body: some View {
        let settings = model.settings
        let enabled = settings.enabledLanguages.contains(language)
        VStack(alignment: .leading, spacing: 0) {
            LanguageGrid {
                HStack(spacing: 9) {
                    LanguageBadge(language: language, style: badgeStyle, size: .s)
                    Text(language.info.nativeName)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.fg)
                        .lineLimit(1)
                }
            } voice: {
                voiceMenu
            } backup: {
                backupMenu
            } speed: {
                speedMenu
            } test: {
                testButton
            } on: {
                SettingsSwitch("Enable \(language.info.nativeName)", isOn: Binding(
                    get: { enabled },
                    set: { settings.setEnabled($0, language) }
                ))
                .disabled(enabled && settings.enabledLanguages.count == 1)
                .help(enabled && settings.enabledLanguages.count == 1 ? "At least one language stays on" : "")
            } remove: {
                removeButton
            }
            .frame(height: 40)
            stateNote
        }
        .opacity(enabled ? 1 : 0.55)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Remove \(language.info.nativeName)", role: .destructive) { settings.remove(language) }
                .disabled(!settings.canRemove(language))
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(light: .black.opacity(0.07), dark: .white.opacity(0.06))).frame(height: Metrics.hairline)
        }
        .onAppear { model.voices.load(language) }
    }

    // MARK: Backup voice

    private var autoBackupID: String? {
        model.voiceHealth.autoBackup(for: model.settings.voice(for: language), language: language)
    }

    /// The voice that reads when the chosen one doesn't.
    private var effectiveBackupID: String? {
        model.settings.backupVoices[language] ?? autoBackupID
    }

    private var backupMenu: some View {
        let settings = model.settings
        let chosen = settings.backupVoices[language]
        let current = settings.voice(for: language)
        let isEdge = EdgeCLIProvider.isEdgeVoiceID(current)
        let auto = autoBackupID
        let voices = (model.voices.edgeVoices[language] ?? []).filter { $0.id != current }
        return Menu {
            Button {
                settings.backupVoices[language] = nil
            } label: {
                let title = auto.map { "Auto   \(VoiceName.name($0))" } ?? "Auto"
                if chosen == nil { Label(title, systemImage: "checkmark") } else { Text(title) }
            }
            Divider()
            ForEach(voices) { voice in
                Button {
                    settings.backupVoices[language] = voice.id
                } label: {
                    let title = "\(voice.displayName)   \(voice.detail)"
                    if voice.id == chosen { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
        } label: {
            PopupLabel {
                HStack(spacing: 6) {
                    if let chosen {
                        Text(VoiceName.name(chosen)).foregroundStyle(Color.fg)
                    } else {
                        Text("Auto").foregroundStyle(Color.fg)
                        if let auto {
                            Text(VoiceName.name(auto)).font(.spreekMono(size: 11)).foregroundStyle(Color.fg3)
                        }
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 110, maxWidth: 150)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .disabled(!isEdge)
        .opacity(isEdge ? 1 : 0.5)
        .help(isEdge ? "Reads when \(VoiceName.name(current)) doesn't work" : "Only Edge voices need a backup")
        .accessibilityLabel("\(language.info.nativeName) backup voice")
        .accessibilityValue(chosen.map { VoiceName.name($0) } ?? "Auto")
    }

    /// One short sentence under a voice that is retired or unavailable.
    @ViewBuilder private var stateNote: some View {
        let settings = model.settings
        let current = settings.voice(for: language)
        let name = VoiceName.name(current)
        switch model.voiceHealth.state(of: current) {
        case .ok:
            EmptyView()
        case .retired:
            HStack(spacing: 4) {
                Text("Microsoft no longer offers \(name), but it still works for now.")
                if let auto = autoBackupID {
                    Button("Use \(VoiceName.name(auto))") {
                        settings.voices[language] = auto == language.info.defaultEdgeVoice ? nil : auto
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Color.fg3)
            .padding(.leading, 148)
            .padding(.bottom, 9)
        case .unavailable:
            if let backup = effectiveBackupID {
                Text("\(VoiceName.name(backup)) reads \(language.info.englishName) until \(name) is back.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.fg3)
                    .padding(.leading, 148)
                    .padding(.bottom, 9)
            }
        }
    }

    private var voiceMenu: some View {
        let settings = model.settings
        let current = settings.voice(for: language)
        let groups = model.voices.groups(for: language, selected: current)
        return Menu {
            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.voices) { voice in
                        Button {
                            settings.voices[language] = voice.id == language.info.defaultEdgeVoice ? nil : voice.id
                        } label: {
                            let title = "\(voice.displayName)   \(voice.detail)"
                            if voice.id == current { Label(title, systemImage: "checkmark") } else { Text(title) }
                        }
                    }
                }
            }
        } label: {
            PopupLabel {
                HStack(spacing: 6) {
                    Text(VoiceName.name(current))
                        .foregroundStyle(Color.fg)
                    Text(EdgeCLIProvider.isEdgeVoiceID(current) ? current : "macOS")
                        .font(.spreekMono(size: 11))
                        .foregroundStyle(Color.fg3)
                    Spacer(minLength: 4)
                    switch model.voiceHealth.state(of: current) {
                    case .unavailable:
                        Text("Unavailable").font(.system(size: 11, weight: .heavy)).foregroundStyle(Color.attentionText)
                    case .retired:
                        Text("Retired").font(.system(size: 11, weight: .heavy)).foregroundStyle(Color.fg3)
                    case .ok:
                        EmptyView()
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Up to 290 wide; at the minimum window width it shrinks (the voice id truncates)
            // instead of widening the page, so it can't use plainMenu()'s fixedSize().
            .frame(minWidth: 140, maxWidth: 290)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("\(language.info.nativeName) voice")
        .accessibilityValue(VoiceName.name(current))
    }

    private var speedMenu: some View {
        let settings = model.settings
        let speed = settings.speed(for: language)
        return Menu {
            ForEach(LanguagesSection.speeds, id: \.self) { option in
                Button {
                    settings.speeds[language] = option == 1 ? nil : option
                } label: {
                    let title = PlaybackFormat.speed(option)
                    if abs(option - speed) < 0.001 { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
        } label: {
            PopupLabel {
                Text(PlaybackFormat.speed(speed))
                    .font(.spreekMono(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 76)
        }
        .plainMenu()
        .accessibilityLabel("\(language.info.nativeName) speed")
        .accessibilityValue(PlaybackFormat.speed(speed))
    }

    /// Shown while the row is hovered; the last enabled language can't be removed.
    private var removeButton: some View {
        let settings = model.settings
        let removable = settings.canRemove(language)
        return Button {
            settings.remove(language)
        } label: {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 14))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.fg3)
                .frame(width: 20, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!removable)
        .opacity(hovering && removable ? 1 : 0)
        .allowsHitTesting(hovering && removable)
        .help("Remove \(language.info.nativeName)")
        .accessibilityLabel("Remove \(language.info.nativeName)")
    }

    private var testButton: some View {
        let speech = model.speech
        let previewing = speech.source == .preview && speech.language == language
            && (speech.state.isPlaying || speech.state.name == "synthesizing")
        return Button {
            if previewing { speech.stop() } else { model.testVoice(for: language) }
        } label: {
            Image(systemName: previewing ? "stop.fill" : "play.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.fg)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.control))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(previewing ? "Stop" : "Play a sample with this voice and speed")
        .accessibilityLabel(previewing ? "Stop \(language.info.nativeName) sample" : "Test \(language.info.nativeName) voice")
    }
}

// MARK: - Engines

private struct EnginesSection: View {
    @Environment(AppModel.self) private var model
    @State private var showsInstall = false
    @State private var path = ""

    var body: some View {
        let engines = model.engines
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                edgeCard
                EngineCard(
                    name: "macOS System", role: "Fallback", roleIsPrimary: false,
                    state: engines.systemVoiceCount > 0 ? .ok : .off,
                    status: engines.systemVoiceCount > 0 ? "Offline-ready" : "No voices installed",
                    meta: "AVSpeechSynthesizer · \(engines.systemVoiceCount) voices",
                    detail: "Used when Edge fails or you are offline. Enhanced voices sound better."
                ) {
                    Button("Manage Voices…") { SystemSettingsLinks.openSpokenContent() }
                        .buttonStyle(.small)
                        .help("System Settings › Accessibility › Spoken Content")
                }
                EngineCard(
                    name: "Azure Speech", role: "Optional", roleIsPrimary: false, state: .off,
                    status: "Not configured", meta: "free tier · monthly quota",
                    detail: "Same neural voices as Edge through an official API."
                ) {
                    Button("Coming later") {}
                        .buttonStyle(.small)
                        .disabled(true)
                }
            }
            .padding(.top, 2)
            SettingsRow("Edge engine:") {
                OptionsPopup(
                    options: EdgeEngineMode.allCases.map { ($0, $0.displayName) },
                    selection: Binding(get: { model.settings.edgeEngineMode }, set: { model.settings.edgeEngineMode = $0 }),
                    accessibilityName: "Edge engine"
                )
                SettingsHint(Self.engineHint(model.settings.edgeEngineMode))
            }
            SettingsRow("edge-tts path:") {
                TextField("Automatic", text: $path)
                    .textFieldStyle(.plain)
                    .font(.spreekMono(size: 12))
                    .padding(.horizontal, 8)
                    .frame(width: 290, height: 24)
                    .background(Color.field, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).strokeBorder(Color.separator, lineWidth: Metrics.hairline))
                    .onSubmit(commitPath)
                    .accessibilityLabel("edge-tts path")
                SettingsHint("Optional backup. Empty: ~/.local/bin, /opt/homebrew/bin, then uvx.")
            }
        }
        .onAppear {
            path = model.settings.edgeExecutablePath ?? ""
            engines.checkIfNeeded(edgePath: model.settings.edgeExecutablePath, mode: model.settings.edgeEngineMode)
        }
        .onDisappear(perform: commitPath)
        .onChange(of: model.settings.edgeEngineMode) { _, mode in
            engines.check(edgePath: model.settings.edgeExecutablePath, mode: mode)
        }
        .sheet(isPresented: $showsInstall) {
            InstallEdgeSheet {
                showsInstall = false
                engines.check(edgePath: model.settings.edgeExecutablePath, mode: model.settings.edgeEngineMode)
            }
        }
    }

    private func commitPath() {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? nil : trimmed
        guard value != model.settings.edgeExecutablePath else { return }
        model.settings.edgeExecutablePath = value
        model.engines.check(edgePath: value, mode: model.settings.edgeEngineMode)
    }

    /// Enabled languages whose chosen Edge voice is unavailable or retired.
    private var voicesNeedingAttention: [(voice: String, state: VoiceState)] {
        let settings = model.settings
        var seen = Set<String>()
        var result: [(String, VoiceState)] = []
        for language in settings.listedLanguagesSorted where settings.enabledLanguages.contains(language) {
            let voice = settings.voice(for: language)
            let state = model.voiceHealth.state(of: voice)
            if state != .ok, seen.insert(voice).inserted { result.append((voice, state)) }
        }
        return result
    }

    private static func listLine(_ snapshot: EdgeVoiceCatalog.Snapshot) -> String {
        let calendar = Calendar.current
        let time = snapshot.fetchedAt.formatted(date: .omitted, time: .shortened)
        let day: String
        if calendar.isDateInToday(snapshot.fetchedAt) {
            day = "today"
        } else if calendar.isDateInYesterday(snapshot.fetchedAt) {
            day = "yesterday"
        } else {
            day = snapshot.fetchedAt.formatted(date: .abbreviated, time: .omitted)
        }
        return "\(snapshot.count) voices · list updated \(day) \(time)"
    }

    private var edgeCard: some View {
        let engines = model.engines
        let average = engines.edgeAverage.map { String(format: "%.1f", $0) }
        let attention = voicesNeedingAttention
        var (state, status, meta): (EngineState, String, String) = switch engines.edge {
        case .unknown, .checking:
            (.checking, "Testing…", model.settings.edgeEngineMode == .cliOnly ? "edge-tts · no key" : "native client · no key")
        case .working(.native):
            (.ok, "Working · native · avg \(average ?? "–") s", "speech.platform.bing.com · no key")
        case .working(.cli(let executable)):
            (.ok, "Working · edge-tts · avg \(average ?? "–") s", "\(Self.abbreviate(executable)) · no key")
        case .notFound(let nativeError?): (.error, "Not working", nativeError)
        case .notFound(nil): (.error, "edge-tts not found", "looked in ~/.local/bin, /opt/homebrew/bin")
        case .failed(let message): (.error, "Not working", message)
        }
        if let snapshot = model.voiceHealth.snapshot, state == .ok || state == .attention { meta = Self.listLine(snapshot) }
        if state == .ok, !attention.isEmpty {
            state = .attention
            status = attention.count == 1 ? "1 voice needs attention" : "\(attention.count) voices need attention"
        }
        let health = model.voiceHealth
        let extra = AnyView(VStack(alignment: .leading, spacing: 6) {
            ForEach(attention, id: \.voice) { item in
                HStack(spacing: 8) {
                    Text(VoiceName.name(item.voice))
                        .font(.spreekRounded(size: 12.5, weight: .heavy))
                        .foregroundStyle(Color.fg)
                    Text(item.voice)
                        .font(.spreekMono(size: 11))
                        .foregroundStyle(Color.fg3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(item.state == .retired ? "Retired" : "Unavailable")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(item.state == .retired ? Color.fg3 : Color.attentionText)
                }
            }
            if let note = health.note {
                Text(note).font(.system(size: 12)).foregroundStyle(Color.fg3)
            }
        })
        return EngineCard(
            name: "Edge Neural", role: "Primary", roleIsPrimary: true, state: state, status: status, meta: meta,
            detail: "Free and keyless. Spreek talks to the service directly; the edge-tts CLI is only a backup. Unofficial endpoint, so it can break without notice.",
            extra: extra
        ) {
            AnyView(VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Button { checkVoices() } label: {
                        HStack(spacing: 5) {
                            if health.isChecking { ProgressView().controlSize(.mini) }
                            Text("Check my voices")
                        }
                    }
                    .buttonStyle(.small)
                    .disabled(health.isChecking)
                    Button("Refresh voice list") {
                        Task { await health.refreshList(mode: model.settings.edgeEngineMode, path: model.settings.edgeExecutablePath) }
                    }
                    .buttonStyle(.small)
                    .disabled(health.isRefreshing)
                }
                HStack(spacing: 6) {
                    if engines.isEdgeNotFound {
                        Button("Install Instructions…") { showsInstall = true }
                            .buttonStyle(.small)
                    }
                    Button("Test Connection") { engines.check(edgePath: model.settings.edgeExecutablePath, mode: model.settings.edgeEngineMode) }
                        .buttonStyle(.small)
                        .disabled(engines.edge == .checking)
                }
            })
        }
    }

    private func checkVoices() {
        let settings = model.settings
        let languages = settings.listedLanguagesSorted
            .filter { settings.enabledLanguages.contains($0) }
            .map { ($0, settings.voice(for: $0)) }
        let chain = model.speech.chain
        Task { await model.voiceHealth.checkVoices(languages, chain: chain) }
    }

    private static func engineHint(_ mode: EdgeEngineMode) -> String {
        switch mode {
        case .automatic: "Native, then edge-tts, then System."
        case .nativeOnly: "Native, then System."
        case .cliOnly: "edge-tts, then System."
        }
    }

    private static func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

private enum EngineState { case ok, checking, error, off, attention }

private struct EngineCard<Action: View>: View {
    let name: String
    let role: String
    let roleIsPrimary: Bool
    let state: EngineState
    let status: String
    let meta: String
    let detail: String
    var extra: AnyView?
    @ViewBuilder var action: () -> Action

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name)
                    .font(.spreekRounded(size: 15, weight: .black))
                    .foregroundStyle(Color.fg)
                Spacer()
                Text(role)
                    .font(.spreekRounded(size: 11, weight: .heavy))
                    .foregroundStyle(roleIsPrimary ? Color.blueFG : Color.fg2)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(roleIsPrimary ? Color.blueBG : Color.control))
            }
            HStack(spacing: 6) {
                statusMark
                Text(status)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.fg)
                    .lineLimit(1)
            }
            Text(meta)
                .font(.spreekMono(size: 11))
                .foregroundStyle(Color.fg3)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(meta)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Color.fg3)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if let extra { extra }
            Spacer(minLength: 0)
            action()
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
        .background(Color(light: .white, dark: Color(hex: 0x2E2E31)), in: shape)
        .overlay(shape.strokeBorder(Color.separator, lineWidth: Metrics.hairline))
        .shadow(color: .black.opacity(0.06), radius: 1.5, y: 1)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var statusMark: some View {
        switch state {
        case .checking:
            ProgressView().controlSize(.mini).frame(width: 15, height: 15)
        case .attention:
            Circle().fill(Color.attention).frame(width: 9, height: 9).frame(width: 15, height: 15)
                .accessibilityHidden(true)
        case .ok, .error, .off:
            Image(systemName: state == .ok ? "checkmark.circle.fill" : state == .error ? "xmark.circle.fill" : "minus.circle.fill")
                .font(.system(size: 14))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, state == .ok ? Color(hex: 0x30A46C) : state == .error ? Color(hex: 0xE5484D) : Color(hex: 0x8E8E93))
                .accessibilityHidden(true)
        }
    }
}

private struct InstallEdgeSheet: View {
    var onDone: () -> Void
    @State private var copied = false

    static let command = "uv tool install edge-tts"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Install edge-tts")
                .font(.spreekRounded(size: 20, weight: .black))
                .foregroundStyle(Color.fg)
            Text("Spreek speaks with Edge neural voices through the free edge-tts command-line tool. Run this in Terminal, then test again:")
                .font(.system(size: 13))
                .foregroundStyle(Color.fg2)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(Self.command)
                    .font(.spreekMono(size: 13))
                    .foregroundStyle(Color.fg)
                    .textSelection(.enabled)
                Spacer()
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.command, forType: .string)
                    copied = true
                }
                .buttonStyle(.small)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Color.field, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.separator, lineWidth: Metrics.hairline))
            Text("Needs uv (astral.sh/uv). Until then Spreek uses the macOS voices. If edge-tts lives somewhere else, set its path under Engines.")
                .font(.system(size: 12))
                .foregroundStyle(Color.fg3)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Test Again", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 452)
    }
}

// MARK: - Floating Bar

private struct FloatingBarSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        VStack(alignment: .leading, spacing: 2) {
            SettingsRow("Show bar:") {
                OptionsPopup(
                    options: [(.whileSpeaking, "While speaking"), (.onlyWhenPinned, "Only when pinned")],
                    selection: $settings.barShowMode, accessibilityName: "Show bar"
                )
            }
            SettingsRow("Hide after finishing:") {
                HStack(spacing: 3) {
                    TextField("Seconds", value: $settings.barHideAfterSeconds, format: .number)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(.spreekMono(size: 12.5))
                        .frame(width: 30)
                        .accessibilityLabel("Seconds before hiding")
                    Text("s")
                        .font(.spreekMono(size: 12.5))
                        .foregroundStyle(Color.fg)
                        .padding(.trailing, 6)
                }
                .frame(height: 24)
                .background(Color.field, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).strokeBorder(Color.separator, lineWidth: Metrics.hairline))
                SettingsHint("Hovering the bar pauses the countdown.")
            }
            SettingsRow("Pin by default:") {
                SettingsSwitch("Pin by default", isOn: $settings.barPinByDefault)
            }
            SettingsRow("Position:") {
                SegmentedControl("Position", options: FloatingBarPlacementMode.allCases, selection: $settings.barPlacement) {
                    Self.title(for: $0)
                }
            }
            SettingsRow("") {
                if settings.barPlacement == .nearSelection {
                    SettingsHint(Self.hint(for: .nearSelection, settings: settings))
                        .frame(maxWidth: 420, alignment: .leading)
                } else {
                    BarPositionMap(
                        selection: $settings.barPosition,
                        isStartingPoint: settings.barPlacement == .lastDragged,
                        dragged: settings.barPlacement == .lastDragged ? settings.barDragPosition : nil
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(settings.barPlacement == .lastDragged ? "Starts at \(settings.barPosition.title.lowercased())" : settings.barPosition.title)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.fg)
                        SettingsHint(Self.hint(for: settings.barPlacement, settings: settings))
                    }
                    .frame(maxWidth: 280, alignment: .leading)
                }
            }
            SettingsRow("Material:") {
                PopupLabel { Text("Frosted glass") }
                    .disabled(true)
                    .accessibilityLabel("Material: Frosted glass")
                SettingsHint("Follows system appearance.")
            }
            SettingsRow("Highlight spoken word:") {
                SettingsSwitch("Highlight spoken word", isOn: $settings.highlightSpokenWord)
            }
        }
    }
}

extension FloatingBarSection {
    fileprivate static func title(for mode: FloatingBarPlacementMode) -> String {
        switch mode {
        case .fixed: "Fixed"
        case .nearSelection: "Near selection"
        case .lastDragged: "Where I left it"
        }
    }

    fileprivate static func hint(for mode: FloatingBarPlacementMode, settings: AppSettings) -> String {
        switch mode {
        case .fixed:
            "Drag the bar to move it; a new bar comes back here."
        case .nearSelection:
            "Just below the selected text, or above it when there’s no room. When an app doesn’t say where the selection is, the bar appears near the pointer."
        case .lastDragged where settings.barDragPosition == nil:
            "New bars open where you last dragged one. Until you drag one, they open at the spot picked here."
        case .lastDragged:
            "New bars open where you last dragged one (dashed). Until you drag one, they open at the spot picked here."
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SettingsRow("Speak selection:") {
                KeyboardShortcuts.Recorder(for: .speakSelection)
                SettingsHint("Also right-click › Services › Speak with Spreek")
            }
            SettingsRow("Speak slower:") {
                KeyboardShortcuts.Recorder(for: .speakSlower)
            }
            SettingsRow("Speak clipboard:") {
                KeyboardShortcuts.Recorder(for: .speakClipboard)
                SettingsHint("Speaks the text you last copied.")
            }
            SettingsRow("Replay last:") {
                KeyboardShortcuts.Recorder(for: .replayLast)
            }
            SettingsRow("Save to favorites:") {
                KeyboardShortcuts.Recorder(for: .saveFavorite)
            }
            SettingsRow("Pause / resume:") {
                KeyboardShortcuts.Recorder(for: .pauseResume)
                SettingsHint("Pauses the current sentence where it is.")
            }
        }
    }
}

// MARK: - Appearance

private struct AppearanceSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        VStack(alignment: .leading, spacing: 2) {
            SettingsRow("Appearance:") {
                SegmentedControl("Appearance", options: AppearanceMode.allCases, selection: $settings.appearance) {
                    switch $0 {
                    case .system: "System"
                    case .light: "Light"
                    case .dark: "Dark"
                    }
                }
            }
            HStack(alignment: .top, spacing: 12) {
                FormLabel("App icon:", width: 230)
                    .padding(.top, 8)
                VStack(alignment: .leading, spacing: 8) {
                    AppIconPicker(selection: $settings.appIcon)
                    SettingsHint("The Dock and the menu bar switch together. Finder and Launchpad keep showing Snavel.")
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
        }
    }
}

/// Six icon tiles: the Dock icon above its paired menu-bar glyph and name.
private struct AppIconPicker: View {
    @Binding var selection: AppIconChoice

    var body: some View {
        // One row of six when the page is wide enough, otherwise wrapped rows. Tiles have a fixed
        // width so names line up; the layout never asks for more width than it is offered.
        TileFlow(spacing: 4, rowSpacing: 6) {
            ForEach(AppIconChoice.allCases, id: \.self, content: tile)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("App icon")
    }

    private func tile(_ icon: AppIconChoice) -> some View {
        let selected = icon == selection
        return Button { selection = icon } label: {
            VStack(spacing: 4) {
                Image("AppIcon-\(icon.rawValue)")
                    .resizable()
                    .frame(width: 72, height: 72)
                HStack(spacing: 4) {
                    Image("MenuBar-\(icon.rawValue)")
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 13, height: 13)
                    Text(icon.title)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .lineLimit(1)
                }
                .foregroundStyle(selected ? Color.accentColor : Color.fg)
            }
            .padding(EdgeInsets(top: 2, leading: 6, bottom: 8, trailing: 6))
            .frame(width: 98)
            .background(selected ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("\(icon.title) · \(icon.subtitle)")
        .accessibilityLabel(icon.title)
        .accessibilityHint(icon.subtitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Equal-width tiles laid out left to right, wrapping to the offered width. Its ideal width (no
/// proposal) is three tiles, so it never widens the settings page.
private struct TileFlow: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let tile = tileSize(subviews)
        let columns = columns(for: proposal.width, tile: tile, count: subviews.count)
        let rows = (subviews.count + columns - 1) / max(columns, 1)
        return CGSize(
            width: CGFloat(columns) * tile.width + CGFloat(max(columns - 1, 0)) * spacing,
            height: CGFloat(rows) * tile.height + CGFloat(max(rows - 1, 0)) * rowSpacing
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let tile = tileSize(subviews)
        let columns = columns(for: bounds.width, tile: tile, count: subviews.count)
        for (index, subview) in subviews.enumerated() {
            let x = bounds.minX + CGFloat(index % columns) * (tile.width + spacing)
            let y = bounds.minY + CGFloat(index / columns) * (tile.height + rowSpacing)
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(tile))
        }
    }

    private func tileSize(_ subviews: Subviews) -> CGSize {
        subviews.reduce(.zero) { size, subview in
            let fit = subview.sizeThatFits(.unspecified)
            return CGSize(width: max(size.width, fit.width), height: max(size.height, fit.height))
        }
    }

    private func columns(for width: CGFloat?, tile: CGSize, count: Int) -> Int {
        guard let width, width.isFinite, tile.width > 0 else { return min(3, count) }
        return max(1, min(count, Int((width + spacing) / (tile.width + spacing))))
    }
}

extension AppIconChoice {
    var title: String {
        switch self {
        case .snavel: "Snavel"
        case .ara: "Ara"
        case .beo: "Beo"
        case .nachtegaal: "Nachtegaal"
        case .merel: "Merel"
        case .raaf: "Raaf"
        }
    }

    /// What the bird is, in English.
    var subtitle: String {
        switch self {
        case .snavel: "Beak (default)"
        case .ara: "Scarlet macaw"
        case .beo: "Hill myna"
        case .nachtegaal: "Nightingale"
        case .merel: "Blackbird at dusk"
        case .raaf: "Raven"
        }
    }
}

// MARK: - General

private struct GeneralSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        let login = model.loginItem
        VStack(alignment: .leading, spacing: 2) {
            SettingsRow("Show in Dock:") {
                OptionsPopup(
                    options: [(.whileDashboardOpen, "While Dashboard is open"), (.always, "Always"), (.never, "Never")],
                    selection: $settings.dockIconMode, accessibilityName: "Show in Dock"
                )
            }
            SettingsRow("Open Dashboard:") {
                SettingsSwitch("Open the Dashboard when Spreek is opened", isOn: $settings.openDashboardOnLaunch)
                Text("When opened from Spotlight or Raycast")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.fg)
                SettingsHint("Launch at login never opens it.")
            }
            SettingsRow("Launch at login:") {
                SettingsSwitch("Launch at login", isOn: Binding(get: { login.isEnabled }, set: { login.setEnabled($0) }))
                if login.needsApproval {
                    SettingsHint("Waiting for approval in System Settings.")
                    Button("Open Login Items…") { login.openSystemSettings() }
                        .buttonStyle(.small)
                } else if let error = login.error {
                    SettingsHint(error)
                }
            }
            SettingsRow("Notes:") {
                SettingsSwitch("Keep only bold and italic when pasting", isOn: $settings.notesPasteKeepsBoldItalicOnly)
                Text("Keep only bold & italic when pasting")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.fg)
                SettingsHint("Strips links, colors and headings from pasted AI explanations.")
            }
            SettingsRow("Storage:") {
                Text(model.storage.report.map { StorageModel.size($0.totalBytes) } ?? "…")
                    .font(.spreekMono(size: 12))
                    .foregroundStyle(Color.fg)
                Button("Manage Storage…") { model.dashboard.show(.storage) }
                    .buttonStyle(.link)
                    .font(.system(size: 13))
            }
        }
        .onAppear {
            login.refresh()
            model.storage.refresh()
        }
    }
}
