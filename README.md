# GIACK GPTK

GIACK GPTK is a native macOS SwiftUI application for managing Windows software through Game Porting Toolkit (GPTK)-compatible Wine runtimes and DOS software through DOSBox Staging. It provides a library-oriented workflow: create a bottle or DOS library, apply a compatibility preset, install software, and launch it from one place.

GIACK GPTK is a GPL-3.0-or-later derivative of Whisky. It keeps the Wine/GPTK bottle model while adding runner selection, DOSBox libraries, runtime health checks, compatibility presets, and a companion command-line tool.

Current public release: `1.0` (`1.0.0`, build `1`), August 18, 2026.

## Features

- GPTK Wine bottles for Windows applications and games.
- DOSBox Staging libraries for classic DOS software.
- Curated presets for Windows games, launchers, utilities, and DOS games.
- Managed GPTK runtime detection and updates, with optional Homebrew Wine channels.
- Runner status and stability scan in Settings.
- Per-library tools for program discovery, Winetricks, logs, terminal access, and shader-cache cleanup.
- `GIACKCmd` for listing and creating libraries from the command line.
- Tooltips for interactive GUI controls.

## Requirements

- Apple silicon Mac.
- macOS 14.0 or later.
- Xcode with Swift 6 support when building from source.
- Network access for Swift Package Manager dependencies and optional runtime downloads.

Optional tools:

```bash
brew install cabextract
brew install dosbox-staging
brew install --cask wine-stable
```

`cabextract` is required by Winetricks. DOSBox Staging is required for DOS libraries. Homebrew Wine is optional; GIACK GPTK can instead use its managed GPTK runtime.

## Install

### Build from source

1. Clone the repository.
2. Open `GIACK.xcodeproj` in Xcode.
3. Select the `GIACK` scheme and build the app.
4. Move `GIACKGPTK.app` to `/Applications` if you want it available outside Xcode.
5. On first launch, complete the setup flow and select or install a runtime in Settings > Runners.

To build from Terminal:

```bash
xcodebuild -project GIACK.xcodeproj -scheme GIACK -configuration Release build
```

Public release archives are unsigned unless their release page explicitly says otherwise. macOS may require an explicit Gatekeeper approval before the app can open.

## Runtime Model

GIACK GPTK does not include large runtime archives in the repository. It resolves Windows support from a managed GPTK runtime, a locally mounted Apple Game Porting Toolkit installation, or a selected Homebrew Wine channel. DOS libraries use a locally installed DOSBox Staging executable.

The Runners tab shows the selected Wine channel, installed runtime version, DOSBox status, Homebrew availability, and recommended stability settings. The sidebar also displays the active runtime so the current configuration is visible while working with libraries.

## CLI

The bundled command-line tool supports the same library model:

```bash
GIACKCmd list
GIACKCmd create "Example Game" --preset windowsGame
GIACKCmd create "Commander Keen" --preset classicDOSGame
```

Run `GIACKCmd --help` for the full command reference.

## Known Limitations and Work Needed

- Compatibility varies by Windows application, runtime version, macOS version, and graphics workload. A successful install does not guarantee a working application.
- GPTK and Wine runtimes are external components. Runtime availability and compatibility can change independently of GIACK GPTK.
- Wine 11 and GPTK support are global selections, not per-bottle selections.
- Game-specific installer automation and preset manifests are not implemented.
- The app is not signed or notarized for this release.
- Automated GUI testing is limited; the project currently relies on package builds and manual smoke testing.
- AI implementation for games is not yet implemented (potential for game optimization, compatibility suggestions, and automated configuration).

## To-Do List for Future Releases

### Immediate Priorities
- [ ] Add per-bottle Wine runtime selection (currently global in Settings → Runners)
- [ ] Implement installer/preset manifest system (Lutris-style) for game-specific scripts
- [ ] Add in-app "Runtime Status" panel highlighting currently selected Wine channel
- [ ] Implement signing/notarization workflow for official releases
- [ ] Add lightweight test target or scripted smoke test

### AI Implementation for Games (Future Feature)
- [ ] Research and implement AI-powered game compatibility detection
- [ ] Add AI-driven performance optimization suggestions for Windows games
- [ ] Implement automated configuration recommendations based on game requirements
- [ ] Add machine learning model for predicting optimal Wine/DOSBox settings per game
- [ ] Create AI assistant for troubleshooting game compatibility issues
- [ ] Implement AI-based game library organization and tagging system

Please help improve GIACK GPTK. Report reproducible failures with the macOS version, selected runner, runtime version, application version, and relevant log output. Contributions that improve compatibility, runtime detection, accessibility, documentation, test coverage, or AI implementation for game optimization are especially useful.

## Development

- Main app target: `GIACK`
- App product: `GIACKGPTK.app`
- CLI target: `GIACKCmd`
- Shared package: `GIACKKit/Package.swift`
- Dependencies: [DEPENDENCIES.md](DEPENDENCIES.md)
- Change history: [CHANGELOG.md](CHANGELOG.md)

## License and Credits

GIACK GPTK is licensed under the GNU General Public License, version 3 or later. See [LICENSE](LICENSE), [NOTICE.md](NOTICE.md), and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

This project preserves attribution for Whisky, Wine, DOSBox Staging, Sparkle, swift-argument-parser, SemanticVersion, SwiftyTextTable, Progress.swift, and other third-party components. External runtimes are not bundled and remain subject to their own licenses and distribution terms.

Support development: [buymeacoffee.com/einnovoeg](https://buymeacoffee.com/einnovoeg)
