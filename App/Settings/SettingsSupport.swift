import AppKit
import AVFoundation
import Observation
import ServiceManagement
import SpreekCore

/// Settings › Engines status, from a real quick synthesis rather than just "the file exists".
/// Tries the Edge paths the engine mode allows, in the order speech uses them.
@MainActor
@Observable
final class EngineStatus {
    /// Which way Edge voices are reached.
    enum EdgePath: Equatable {
        /// Spreek's own WebSocket client.
        case native
        /// The edge-tts CLI at this executable (or uvx) path.
        case cli(executable: String)
    }

    enum Edge: Equatable {
        case unknown
        case checking
        case working(EdgePath)
        /// edge-tts isn't installed; `nativeError` says why native also failed (Automatic mode).
        case notFound(nativeError: String?)
        case failed(String)
    }

    private(set) var edge: Edge = .unknown
    /// Seconds per test synthesis this session.
    private(set) var edgeTimings: [Double] = []
    /// Installed macOS voices (all languages).
    private(set) var systemVoiceCount = 0

    var edgeAverage: Double? {
        edgeTimings.isEmpty ? nil : edgeTimings.reduce(0, +) / Double(edgeTimings.count)
    }

    var isEdgeNotFound: Bool {
        if case .notFound = edge { true } else { false }
    }

    /// Once per session (the page can be opened many times).
    func checkIfNeeded(edgePath: String?, mode: EdgeEngineMode) {
        if edge == .unknown { check(edgePath: edgePath, mode: mode) }
    }

    /// Synthesizes a short phrase with the Edge paths `mode` allows (native, then CLI, as speech
    /// tries them) and times it; counts macOS voices.
    func check(edgePath: String?, mode: EdgeEngineMode) {
        guard edge != .checking else { return }
        systemVoiceCount = AVSpeechSynthesisVoice.speechVoices().count
        edge = .checking
        let resolver = EdgeExecutableResolver(configuredPath: edgePath)
        Task {
            let request = SpeechRequest(text: "Spreek test.", language: .enUS)
            var nativeError: String?
            if mode != .cliOnly {
                do {
                    try await timedTest { try await EdgeNativeProvider(timeout: 15).synthesize(request) }
                    edge = .working(.native)
                    return
                } catch {
                    nativeError = error.localizedDescription
                }
            }
            if mode == .nativeOnly {
                edge = .failed(nativeError ?? "")
                return
            }
            guard let command = resolver.resolve() else {
                edge = .notFound(nativeError: nativeError)
                return
            }
            do {
                try await timedTest { try await EdgeCLIProvider(resolver: resolver, timeout: 15).synthesize(request) }
                edge = .working(.cli(executable: command.executable.path))
            } catch {
                edge = .failed(error.localizedDescription)
            }
        }
    }

    private func timedTest(_ synthesize: () async throws -> SynthesisResult) async throws {
        let clock = ContinuousClock()
        let start = clock.now
        let result = try await synthesize()
        let elapsed = clock.now - start
        try? FileManager.default.removeItem(at: result.audioURL)
        if let subtitles = result.subtitlesURL { try? FileManager.default.removeItem(at: subtitles) }
        edgeTimings.append(Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
    }
}

/// Settings › General › Launch at login, through `SMAppService.mainApp`.
@MainActor
@Observable
final class LoginItem {
    private(set) var isEnabled = false
    /// Registered but waiting for the user in System Settings › General › Login Items.
    private(set) var needsApproval = false
    private(set) var error: String?

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        error = nil
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

enum SystemSettingsLinks {
    /// System Settings › Accessibility › Spoken Content (System voice downloads).
    static func openSpokenContent() {
        let urls = [
            "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?SpokenContent",
            "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }
}

/// Short phrases for Settings › Test ▶, one per language.
enum LanguageSamples {
    static func sentence(for language: LanguageCode) -> String {
        switch language {
        case .nl: "Goedemorgen! Zullen we straks samen koffie drinken?"
        case .de: "Guten Morgen! Wollen wir nachher zusammen Kaffee trinken?"
        case .ja: "おはようございます。後で一緒にコーヒーを飲みませんか？"
        case .ko: "좋은 아침이에요! 이따가 같이 커피 마실래요?"
        case .enUS, .enGB: "Good morning! Shall we grab a coffee together later?"
        case .zhCN: "早上好！我们待会儿一起喝杯咖啡吧？"
        case .zhTW: "早安！我們等一下一起喝杯咖啡吧？"
        case .es: "¡Buenos días! ¿Tomamos un café juntos más tarde?"
        case .fr: "Bonjour ! On prend un café ensemble tout à l’heure ?"
        case .it: "Buongiorno! Prendiamo un caffè insieme più tardi?"
        case .ru: "Доброе утро! Выпьем потом вместе кофе?"
        case .ptBR: "Bom dia! Vamos tomar um café juntos mais tarde?"
        case .zhHK: "早晨！我哋陣間一齊飲杯咖啡好唔好？"
        case .ar: "صباح الخير! هل نشرب القهوة معًا لاحقًا؟"
        case .pl: "Dzień dobry! Napijemy się później razem kawy?"
        case .sv: "God morgon! Ska vi ta en kaffe tillsammans sen?"
        case .da: "Godmorgen! Skal vi drikke en kop kaffe sammen senere?"
        case .fi: "Hyvää huomenta! Juodaanko myöhemmin kahvit yhdessä?"
        case .vi: "Chào buổi sáng! Lát nữa mình cùng đi uống cà phê nhé?"
        case .tr: "Günaydın! Sonra birlikte kahve içelim mi?"
        case .th: "สวัสดีตอนเช้า! เดี๋ยวเราไปดื่มกาแฟด้วยกันไหม?"
        case .fa: "صبح بخیر! بعداً با هم یک قهوه بنوشیم؟"
        }
    }
}
