# Architecture

Spreek is a menu-bar app (no Dock icon while only the popover is in use) written in Swift 6 with SwiftUI, and AppKit where SwiftUI can't do the job (`NSPanel`, `NSTextView`, the Accessibility API, Services). It targets macOS 15 and is not sandboxed: it needs the Accessibility API, and it may launch the optional `edge-tts` command-line tool.

## Layout

```
Spreek/
├── project.yml                 XcodeGen spec (Spreek.xcodeproj is generated and git-ignored)
├── scripts/                    verify.sh (tests + build), release scripts, icon rendering
├── art/icons/                  SVG sources of the app and menu-bar icons
├── packaging/                  DMG layout and the Homebrew cask template
├── Packages/SpreekCore/        SwiftPM package: all testable logic, no UI
│   ├── Sources/SpreekCore/
│   │   ├── Language/           LanguageCode, LanguageRegistry, LanguageDetector
│   │   ├── TTS/                providers (native Edge client, edge-tts CLI, macOS system voice),
│   │   │                       ProviderChain (fallback order), VoiceHealth, VoiceCatalog
│   │   ├── Audio/              AudioCache, SpeechController (playback state machine), AudioPlayer
│   │   ├── Text/               TextNormalizer, NoteFormat (bold/italic Markdown subset)
│   │   ├── Capture/            SpeakPipeline, PasteboardCopy
│   │   ├── Store/              SwiftData models and LibraryStore
│   │   ├── Storage/            cache scanner, classification and clean-up
│   │   ├── FloatingBar/        floating bar model and placement
│   │   └── Settings/           AppSettings (UserDefaults-backed)
│   └── Tests/SpreekCoreTests/
└── App/                        the app target
    ├── SpreekApp.swift         MenuBarExtra and the Dashboard window scene
    ├── AppModel.swift          wires capture, speech, library and settings together
    ├── DesignSystem/           tokens and shared components
    ├── Capture/                SelectionReader (Accessibility, with ⌘C fallback), Hotkeys, Services
    ├── MenuBar/                popover
    ├── FloatingBar/            NSPanel controller and SwiftUI views
    ├── Dashboard/              library, detail column, folder sheet
    ├── Settings/               settings and storage pages
    └── Voices/                 voice health and fallback hints
```

## Data flow

1. **Capture.** A global shortcut (via KeyboardShortcuts) or the Services menu triggers `AppModel`. `SelectionReader` reads the selection through the Accessibility API, or sends ⌘C and restores the clipboard. The Services path receives the text directly.
2. **Prepare.** `SpeakPipeline` normalizes the text, `LanguageDetector` picks a language from the enabled ones (script shortcuts first, then `NLLanguageRecognizer`; a folder's language wins when replaying from it) and the voice and speed for that language are looked up in settings.
3. **Synthesize.** `AudioCache` is keyed by `sha256(text | voice | rate)`; a hit never touches the network. A miss goes through `ProviderChain`: for the chosen voice, the native Edge client with word marks, the native client with sentence marks, then the `edge-tts` CLI; then the backup voice through the same steps; then the macOS system voice. `VoiceHealth` remembers what failed so later requests skip it.
4. **Play.** `SpeechController` runs the playback state machine (`AudioPlayer` for cached audio, `AVSpeechSynthesizer` for the system voice) and publishes progress, which the floating bar and the popover show.
5. **Record.** `LibraryStore` saves the sentence in SwiftData. Speaking the same normalized text and language again increments `playCount` instead of adding a duplicate.

## Decisions

- **XcodeGen** owns the project file; never edit the `.pbxproj`.
- The only dependency is **KeyboardShortcuts**. Don't add others without discussion.
- **Edge voices**: the native client speaks the read-aloud WebSocket protocol directly (`EdgeProtocol.swift`; the values match edge-tts and are the place to update when Microsoft changes them). The `edge-tts` CLI is an optional fallback, found at the path in Settings, `~/.local/bin`, `/opt/homebrew/bin` or through `uvx`. GUI apps don't inherit the shell `PATH`, so these are absolute paths.
- **Audio cache**: `~/Library/Application Support/Spreek/Audio/<key>.mp3` with `.json` metadata and `.srt` subtitles when the provider produced them.
- **Languages** are registry entries (`LanguageRegistry`); adding one means adding an entry with its codes, default Edge voice and system voice language.
- **Notes** are stored as a restricted Markdown string (bold, italic, paragraphs); `NoteFormat` converts to and from attributed strings and drops everything else.
- **Persistence** is SwiftData: `Sentence`, `Folder`, `Tag` and `PlayEvent` (for the activity chart).
- **Design tokens** (`App/DesignSystem/Tokens.swift`) are the contract for colors and spacing: use them, never hard-coded light-only colors.
- **Tests** cover everything in `SpreekCore`; `scripts/verify.sh` runs them and builds the app. The live speech test is opt-in because it needs the network.
