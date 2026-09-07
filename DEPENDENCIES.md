# Dependencies

## Build Requirements

- macOS 14.0 or later (Apple silicon; Rosetta 2 for Wine)
- Xcode with Swift 6 support (Swift 6.4 tested)
- Swift Package Manager access (resolves on `xcodebuild` or `swift build`)

## Swift Packages (via Xcode / GIACKKit)

| Package | Purpose | License | Repo |
|---------|---------|---------|------|
| **Sparkle** | In-app update feed (`SUFeedURL` → `SparkleView`) | Sparkle license | https://github.com/sparkle-project/Sparkle |
| **SemanticVersion** | `SemanticVersion` parsing / comparison for runtimes & `BottleSettings` | Apache-2.0 | https://github.com/SwiftPackageIndex/SemanticVersion |
| **swift-argument-parser** | `GIACKCmd` (`giack` / `whisky` symlink) CLI parsing | Apache-2.0 | https://github.com/apple/swift-argument-parser |
| **SwiftyTextTable** | `giack list` table output | MIT | https://github.com/scottrhoyt/SwiftyTextTable |
| **Progress.swift** | CLI progress reporting | MIT | https://github.com/jkandzi/Progress.swift |

Exact resolved revisions are in `GIACK.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` and `GIACKKit/Package.resolved`. `GIACKKit/Package.swift` declares the `GIACKKit` library target (macOS 14+, Swift 6).

## Runtime Components (not bundled)

- **Managed GPTK Wine runtime** — downloaded at runtime from `Gcenx/game-porting-toolkit` (redirect fallback) into `~/Library/Application Support/com.einnovoeg.GIACK/Libraries/Wine`; or a locally mounted Apple Game Porting Toolkit image (`/Applications/Game Porting Toolkit.app`, `/Volumes…`) with optional `redist` overlay.
- **Homebrew Wine channels** (optional alternative to managed GPTK): `wine-stable` / `wine@devel` / `wine@staging` — resolved via `HomebrewRuntimeManager` + `ExternalWineRuntime` from `/Applications/Wine *.app`.
- **DOSBox Staging** (0.82+ recommended) — `dosbox-staging` Homebrew package or a custom binary path set in Settings → Runners; shaders use `crt-auto` / `sharp` etc.

> GIaCK does **not** redistribute Apple GPTK installers, Wine archives, or DOSBox Staging binaries. Those remain under their own licenses/distribution terms (see `THIRD_PARTY_NOTICES.md` + `LICENSES/`).

## Optional Tools

```bash
brew install swiftlint              # lint parity with Xcode build phase
brew install cabextract             # required for Winetricks verbs
brew install dosbox-staging         # DOS libraries
brew install --cask wine-stable     # optional: wine-stable / wine@devel / wine@staging
brew install --cask dosbox-staging-app  # cask variant if preferred
```

- `swiftlint` — lint step only (config `.swiftlint.yml`, `.swiftlint.yml` disables noisy rules).
- `cabextract` — required for `winetricks` verbs.
- `dosbox-staging` — DOS libraries.
- Homebrew Wine — optional alternative to managed GPTK.

## System scan expectations

Settings → Runners → “Scan This Mac” checks: Rosetta 2, current Wine runtime (`ActiveWineRuntime`), DOSBox availability, App Nap / auto-update defaults, and Homebrew presence (`GIACKSystemScan`).

## License notes

Each dependency retains its own license. Keep `LICENSE`, `NOTICE.md`, `THIRD_PARTY_NOTICES.md`, and `LICENSES/` with redistributions. Review terms before bundling external executables/archives. Support: [buymeacoffee.com/einnovoeg](https://buymeacoffee.com/einnovoeg)
