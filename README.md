# Spreek

Select-to-speak for language learners, in your Mac's menu bar. Select text in any app, press **⌥S**, and Spreek detects the language, reads it aloud with a natural neural voice and keeps the sentence in a history you can sort into favorites, folders, tags and notes.

<!-- screenshot: put a picture of the popover, floating bar and dashboard here -->

- Detects the language of the selection (Dutch, German, Japanese, Korean, English, Chinese, Spanish, French, Italian, Russian and Portuguese are built in; enable the ones you use in Settings).
- Reads with Microsoft Edge's neural voices, and falls back to a backup voice and then to the macOS system voice when a voice isn't available.
- A floating bar shows what is playing: pause, replay, change speed.
- A dashboard holds the history, favorites, folders (each with its own language and voice), tags and per-sentence notes.
- Replays come from a local audio cache and never touch the network.

## Install

```bash
brew install --cask gitkeniwo/spreek/spreek
```

Or download the latest DMG from [Releases](https://github.com/gitkeniwo/Spreek/releases), open it and drag Spreek into Applications. Requires macOS 15 (Sequoia) or later, on Apple silicon or Intel.

### First launch

Spreek isn't notarized (there is no paid Apple developer account behind it), so macOS blocks it the first time. Open **System Settings › Privacy & Security**, find *"Spreek" was blocked…* and click **Open Anyway**.

### Accessibility permission

To read the text you selected, Spreek needs **System Settings › Privacy & Security › Accessibility**. The popover shows a button that opens that page until access is granted. Where an app doesn't expose its selection, Spreek sends ⌘C and puts your clipboard back afterwards.

## Using it

Select text in any app and press a shortcut. All shortcuts can be changed in Settings › Shortcuts.

| Shortcut | Action |
|---|---|
| ⌥S | Speak selection |
| ⌥⇧S | Speak selection slower (0.8×) |
| ⌥R | Replay last |
| ⌥P | Pause / resume |
| ⌥F | Save to favorites |

Speak the clipboard is available as a shortcut you record yourself.

### Services menu

Right-click selected text › **Services › Speak with Spreek** works without Accessibility access. If the item is missing, enable it in **System Settings › Keyboard › Keyboard Shortcuts… › Services › Text › Speak with Spreek**; you can also bind a key to it there. macOS only picks up a new service after the app has run once; if it still doesn't appear, run `/System/Library/CoreServices/pbs -update` and relaunch the source app.

## Privacy

- **The selected text is sent to Microsoft's Edge read-aloud service** to synthesize speech. That is the only network traffic Spreek makes. If you don't want that, choose a macOS system voice for a language: it speaks fully offline.
- Nothing else leaves your Mac. The history, favorites, notes and audio cache stay on your disk (`~/Library/Application Support/Spreek`). There is no account, analytics or telemetry.

## Credits and disclaimer

Spreek talks to the same read-aloud service that Microsoft Edge uses, following the protocol documented by the [edge-tts](https://github.com/rany2/edge-tts) project. Spreek can also use the `edge-tts` command-line tool as a fallback (`uv tool install edge-tts`). Global shortcuts come from [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus.

Spreek is an independent project and is **not affiliated with, endorsed by or sponsored by Microsoft**. The service is unofficial and may change or stop working without notice.

## Build from source

Needs macOS 15+, Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
scripts/verify.sh
```

Runs the `SpreekCore` unit tests, generates `Spreek.xcodeproj` from `project.yml`, and builds the app unsigned. Prints a one-line `PASS`/`FAIL` summary.

To run it in Xcode:

```bash
xcodegen generate && open Spreek.xcodeproj
```

Run the `Spreek` scheme. The app has no Dock icon; look for the bird icon in the menu bar (Settings › Appearance picks which bird). In Debug builds the popover has a **Design Preview…** button showing every design-system component in light and dark. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the code is laid out and [CONTRIBUTING.md](CONTRIBUTING.md) before sending a pull request.

### Stable signing (keeps the Accessibility grant)

By default the app is signed ad hoc, which gives every build a new signature. macOS ties the Accessibility grant to that signature, so after each rebuild Spreek silently loses access (the switch still looks on). To avoid this, sign with your free Personal Team:

1. Xcode › Settings › Accounts: add your Apple ID. This creates a "Personal Team" and an Apple Development certificate.
2. Copy the example config and fill in your team ID:

   ```bash
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   ```

   Replace `YOURTEAMID` with the 10-character team ID (shown in Xcode's Signing & Capabilities team popup, or as the `OU=` value of `security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject`).
3. `xcodegen generate`, build and run once, then grant Accessibility again. From now on rebuilds keep it.

`Config/Local.xcconfig` is git-ignored and included by `Config/Base.xcconfig`; without it the committed ad-hoc defaults apply. `scripts/verify.sh` builds unsigned either way.

If access seems granted but ⌥S does nothing (status: "Spreek needs Accessibility access…"), the grant belongs to an older signature: select Spreek in the Accessibility list, remove it with **–**, then add the current build again (or toggle it off and on).

## Releasing

Maintainers only. Releases are built and published by GitHub Actions from a version tag:

```bash
scripts/release.sh 0.3.0 [--notes FILE]
```

From a clean `main`, the script writes `MARKETING_VERSION` in `project.yml`, commits "Spreek 0.3.0", creates the annotated tag `v0.3.0` (its message becomes the release's "Changes") and, after you confirm, pushes `main` and the tag. The tag starts the `Release` workflow: it runs the tests, builds a universal app signed with the project's fixed self-signed certificate, makes the DMG, creates the GitHub release and updates the cask in [gitkeniwo/homebrew-spreek](https://github.com/gitkeniwo/homebrew-spreek). `scripts/release.sh 0.3.0 --dry-run` only builds the DMG locally, and the workflow can also be started by hand as a dry run. The certificate must never change, or every user would have to grant Accessibility again.

## License

[MIT](LICENSE)
