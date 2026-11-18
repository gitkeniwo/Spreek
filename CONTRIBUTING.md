# Contributing

Thanks for helping. Spreek is a small project, so a few ground rules keep it that way.

- **Build:** macOS 15+, Xcode 26, `brew install xcodegen`. The Xcode project is generated from `project.yml`; edit that, never the `.pbxproj`. See the README for running and signing.
- **Tests:** `scripts/verify.sh` must pass (core tests and an app build). Add tests for logic in `Packages/SpreekCore`. The live speech test needs the network and is opt-in.
- **Focused pull requests:** one change per PR, with a short description of what and why. Match the surrounding code style.
- **No new network services** without discussion in an issue first. Today the only traffic is the selected text going to the Edge read-aloud service; that is a promise made in the README.
- **No new dependencies** without asking first.
- **No personal data** in code, fixtures or screenshots.

Open an issue before starting anything large. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the code fits together.
