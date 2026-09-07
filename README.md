# GIaCK

GIaCK is a native macOS SwiftUI application for managing Windows software through Game Porting Toolkit (GPTK)-compatible Wine runtimes and DOS software through DOSBox Staging. Create a bottle or DOS library, apply a compatibility preset, install software, and launch it from one place — without bundling large runtime archives in the repository.

GIaCK is a GPL-3.0-or-later derivative of the archived Whisky app. It keeps the Wine/GPTK bottle model while adding runner selection, DOSBox libraries, runtime health checks, compatibility presets, AI-driven auto-configuration, and a companion command-line tool. Internal naming has been migrated from `WhiskyKit`/`Whisky` to `GIACKKit`/`GIaCK` with deprecated aliases retained for migration.

Current release: **2.0** (`2.0.0`, build `3`) — September 2026. See [CHANGELOG.md](CHANGELOG.md) and [RELEASE_NOTES.md](RELEASE_NOTES.md).

---

## Features

- **GPTK Wine bottles** for Windows applications and games — Wine 11 Stable/Devel/Staging + managed GPTK.
- **DOSBox Staging libraries** for classic DOS software (native Homebrew + custom binary support).
- **Curated presets** for Windows games, launchers, utilities, and DOS games; preset-first creation and reapply in Config.
- **AI Auto-Configuration** — `AIGameDetector` (PE import / folder heuristics + Steam Deck/ProtonDB-aware), `AIDependencyAnalyzer` (DLL→Winetricks verb mapping), `AIBottleAdvisor` (preset/WinVer/DXVK/MSync/env), `AICompatibilityService` (curated + remote GIaCK DB cache at `~/Library/Application Support/com.einnovoeg.GIACK/AICompatibility/compatibility.json`).
- **Managed GPTK runtime** detection and updates, with optional Homebrew Wine channels — now **per-bottle override** (global default in Settings → Runners, per-bottle pin in Bottle Config).
- **Runtime status & stability scan** in Settings with per-bottle runtime card in Overview, header status badges, metrics, details, and sidebar subtitle (GPTK/Stable/Devel/Staging + Per-Bottle flag).
- **Bottle modes** — `singleApp` (isolated) vs `multiApp` (shared) with pinned programs grid, Winetricks, logs, terminal, and shader-cache cleanup.
- **CLI** `GIACKCmd` (`giack` alias, `whisky` symlink retained) for `list` / `create --preset` workflows.
- Tooltips for interactive controls; optional glass styling toggle (`giackGlassCard` family).

## Requirements

- Apple silicon Mac (Rosetta 2 required for Wine).
- macOS 14.0 or later.
- Xcode with Swift 6 support when building from source.
- Network access for Swift Package Manager and optional runtime downloads.

Optional tools:

```bash
brew install cabextract          # required for Winetricks verbs
brew install dosbox-staging      # required for DOS libraries
brew install --cask wine-stable  # optional Homebrew Wine channels (stable/devel/staging)
brew install swiftlint           # optional parity with Xcode build script
```

`cabextract` is required by Winetricks. DOSBox Staging is required for DOS libraries. Homebrew Wine is optional — GIaCK can use its managed GPTK runtime instead.

## Install

### Build from source

1. Clone the repository:
   ```bash
   git clone https://github.com/Einnovoeg/GIaCK.git
   cd GIaCK
   ```
2. Open `GIACK.xcodeproj` in Xcode.
3. Select the `GIACK` scheme and build the app.
4. Move `GIaCK.app` (product `GIACKGPTK.app`) to `/Applications` if you want it outside Xcode.
5. On first launch, complete the setup flow and select or install a runtime in Settings → Runners.

Terminal build:

```bash
xcodebuild -project GIACK.xcodeproj -scheme GIACK -configuration Release build
```

Public release archives are **unsigned** unless the release page explicitly says otherwise. macOS may require an explicit Gatekeeper approval (`System Settings → Privacy & Security → Open Anyway`).

### CLI

The bundled command-line target `GIACKCmd` installs as `giack` with a legacy `whisky` symlink:

```bash
giack list
giack create "Example Game" --preset windowsGame
giack create "Commander Keen" --preset classicDOSGame
giack --help
```

### Project layout

- Main app: `GIACK` (product `GIACKGPTK.app`)
- Shared package: `GIACKKit/Package.swift` (sources under `GIACKKit/Sources/GIACKKit/`, legacy `WhiskyKit` path removed)
- AI: `GIACKKit/Sources/GIACKKit/AI/` (`AIGameDetector`, `AIDependencyAnalyzer`, `AIBottleAdvisor`, `AICompatibilityService`)
- CLI: `GIACKCmd/Main.swift`
- Docs: `README.md`, `CHANGELOG.md`, `RELEASE_NOTES.md`, `DEPENDENCIES.md`, `NOTICE.md`, `THIRD_PARTY_NOTICES.md`, `LICENSES/`
- Bundled docs are symlinked under `Project Resources/` for Xcode’s Copy Files phase.

## Runtime Model

GIaCK does **not** bundle runtime archives. It resolves Windows support from:

1. **Managed GPTK runtime** — downloaded from `Gcenx/game-porting-toolkit` (redirect fallback), versioned at `~/Library/Application Support/com.einnovoeg.GIACK/Libraries/Wine`.
2. **Locally mounted Apple GPTK** — known candidates + `/Volumes` scan (nested discovery) + optional `redist` overlays.
3. **Homebrew Wine channels** — `wine-stable` / `wine@devel` / `wine@staging` via `HomebrewRuntimeManager` + `ExternalWineRuntime` (apps at `/Applications/Wine *.app`).

The **Runners** tab shows selected Wine channel, installed version, DOSBox status, Homebrew availability, and stability recommendations. **Per-bottle overrides** are in each bottle’s Config → Wine Runtime: `Use Global (<channel>)` or a pinned channel. The Overview now has a dedicated runtime card (effective/global/binary path, scope pill, not-installed warning, deeplink to Config), and header/metrics/details/sidebar all reflect the effective channel.

DOS libraries use a locally installed `dosbox-staging` executable (0.82+ recommended, `crt-auto`/`sharp` shader mappings). You can also point Settings → Runners at a custom binary.

### Wine 11 & DOSBox updates (2.0)

- Default Wine config bumped 7.7.0 → **11.0.0** to match Homebrew stable.
- Per-bottle runtime plumbing: `BottleSettings.perBottleWineRuntimeSelection` / `effectiveWineRuntime` / `Wine.wineBinary(for:)`.
- `GIACKWineInstaller` now exposes `runtime(for:)`, `isRuntimeInstalled(for:)`, `runtimeSummary(for:)`, `wineBinaryURL(for:)` family for bottle-aware UI.
- DOSBox config preserved with updated shader mappings for Staging 0.82+.

## How to Use

1. Create a library from a preset (Windows Game, Launcher, Utility, Blank Wine, Blank DOS, Classic DOS Game).
2. Optionally pin a Wine runtime per bottle in Config → Wine Runtime.
3. Run an installer/exe or DOS program, pin frequent launchers, manage via Overview/Programs/Config/Processes.
4. Use Settings → Runners to install or switch the global Wine channel and DOSBox Staging; use Settings → Updates for managed GPTK updates.

## Known Limitations — what doesn’t work yet

- Compatibility is **application-specific**. A successful install does not guarantee a working app — it depends on the Windows application, runtime version, macOS version, and graphics workload.
- GPTK/Wine/DOSBox Staging are external components. Availability and compatibility can change independently of GIaCK.
- Game-specific installer automation and preset manifests are scaffolded via AI but **not yet fully curated** for all titles.
- The app is **not signed or notarized** for this release (Gatekeeper approval required).
- Automated GUI testing is limited; the project relies on `swift build --package-path GIACKKit` and manual smoke testing.
- Online store integration (GOG/Epic via `legendary`/`gogdl`) is **researched but not implemented**; Heroic-inspired “Install from Online” is roadmap only.
- Signing/notarization, lightweight test target, ML settings model, troubleshooting chat assistant, and library tagging are still to-do.

> **Please help fix these gaps.** Report reproducible failures with macOS version, selected runner, runtime version, application version, and relevant log output (`Help → Open Logs` / `Wine/logs/*.log`). Contributions that improve compatibility, runtime detection, accessibility, documentation, test coverage, or AI game optimization are especially useful.

## To-Do (roadmap)

**Next:**
- [x] Per-bottle Wine runtime picker in Bottle Config (global in Settings → Runners, per-bottle override in Config) — done in 2.0
- [x] Runtime Status panel per-bottle in Overview/detail — done in 2.0
- [ ] **Installer / preset manifest system** (Lutris-style) — game-specific scripts and AI-discovered profiles; needs schema + curated manifest repo
- [ ] **Heroic-inspired online stores** — evaluate `legendary` (Epic) + `gogdl` (GOG) via Homebrew, prototype OAuth, add “Install from Online” flow; defer Amazon/Nile if scope large
- [ ] Signing / notarization workflow for official releases
- [ ] Test target / smoke test to reduce manual verification
- [ ] AI follow-ups: ML model for settings, troubleshooting chat assistant, library tagging
- [ ] Multi-app bottle UI polish: visual badge for single vs multi mode, per-app Winetricks queue, bottle import robustness
- [ ] Per-bottle runtime UX follow-ups: optional runtime picker in BottleCreationView, global-runtime-change confirmation when bottles have overrides

**AI (1.1→2.0 done, expanding):**
- [x] `AIGameDetector` / `AIDependencyAnalyzer` / `AIBottleAdvisor` / `AICompatibilityService`
- [ ] ML model for predicting optimal Wine/DOSBox settings per game
- [ ] AI assistant for troubleshooting game compatibility issues
- [ ] AI-based library organization and tagging

See [CHANGELOG.md](CHANGELOG.md) for version history and [DEPENDENCIES.md](DEPENDENCIES.md) for build/runtime dependencies.

## License and Credits

GIaCK is licensed under the **GNU General Public License v3 or later**. See [LICENSE](LICENSE), [NOTICE.md](NOTICE.md), and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

This project gives full credit to its upstream and linked components:

- **Whisky** (archived upstream) — GPL-3.0-or-later — https://github.com/Whisky-App/Whisky — copyright retained in source headers.
- **Wine** — LGPL-2.1-or-later — https://gitlab.winehq.org/wine/wine
- **DOSBox Staging** — GPL-2.0-or-later — https://github.com/dosbox-staging/dosbox-staging
- **Sparkle** (update framework), **SemanticVersion**, **swift-argument-parser**, **SwiftyTextTable**, **Progress.swift** — see `LICENSES/` for per-package texts.
- **Gcenx/game-porting-toolkit** — external GPTK runtime feed (not bundled).

External runtimes are not bundled and remain under their own licenses. Do not redistribute third-party binaries without confirming obligations. Keep `LICENSE`, `NOTICE.md`, `THIRD_PARTY_NOTICES.md`, and `LICENSES/` with redistributions and preserve copyright headers.

Support development: **[buymeacoffee.com/einnovoeg](https://buymeacoffee.com/einnovoeg)**

---

*This project is not affiliated with Apple Inc., Valve, WineHQ, DOSBox Staging, or WhiskyApp. “Game Porting Toolkit” and macOS are trademarks of their respective owners.*
