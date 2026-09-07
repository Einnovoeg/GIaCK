# Changelog

All notable public changes are documented here. GIaCK follows Semantic Versioning for public releases.

## [2.0.0] - 2026-09-07

### Added
- **Per-bottle Wine runtime UI** — `ConfigView.wineRuntimeSection` with `Use Global (<channel>)` + per-channel tags (`— Not installed` suffix), effective summary, missing-runtime warning, `Open Runners Settings` and `Use Global Runtime` actions. Bottle-aware throughout via `Wine.wineBinary(for:)` / `GIACKWineInstaller.wineBinaryURL(for:)`.
- **Per-bottle runtime status panel** — new `BottleView.BottleRuntimeStatusSection` in Overview (effective/global/binary path, scope pill `Global`/`Per-Bottle`, not-installed warning, deeplink to Config tab). Header `statusBadges`, `OverviewMetricsSection`, `BottleDetailsSection`, and `BottleListEntry.subtitle` now surface the effective runtime channel (short labels GPTK/Stable/Devel/Staging + `Per-Bottle` flag).
- Public helpers `GIACKWineInstaller.runtime(for:)`, `isRuntimeInstalled(for:)`, `runtimeSummary(for:)` and `ActiveWineRuntime` resolution for UI without mutating global selection.
- Documentation refresh for 2.0 and `.gitignore` hardening (excludes `AGENTS.md`, `AGENT_HANDOFF.md`, `SESSION_LOG*.md`, `.DS_Store`, `.build`).

### Changed
- Unified repo URLs to `https://github.com/Einnovoeg/GIaCK` in `Constants.swift` (`repositoryURL`, `latestReleaseAPIURL`, `applicationDatabaseURL`) and `README`.
- Runners tab now notes global → per-bottle override model.
- Updated `README.md` (2.0 features, runtime model, known limitations, help-wanted imploration), `RELEASE_NOTES.md`, and `DEPENDENCIES.md`.
- Security & hygiene: recursive `.DS_Store` / `.build` cleanup, audit for secrets/PII (only intentional `buymeacoffee.com/einnovoeg` + `com.einnovoeg.GIACK`), argument-array `Process` usage, `shellSplit`/`esc`/`appleScriptEscaped` guards.

### Fixed
- Fixed per-bottle runtime fallback: `Wine.wineBinary(for: bottle)` returns global binary when selected per-bottle channel is not installed, while UI still warns about the missing install.

## [1.1.0] - 2026-09-05 (development)

### Added
- AI auto-configuration: `AIGameDetector`, `AIDependencyAnalyzer`, `AIBottleAdvisor`, `AICompatibilityService` with Steam Deck/ProtonDB-aware curated profiles and GIACK remote sync.
- Per-bottle Wine runtime override model (`BottleSettings.perBottleWineRuntimeSelection`, `effectiveWineRuntime`) so Wine 11 channels can be pinned per library; bottle-aware `wineBinary(for:)`.
- Bottle modes `singleApp` vs `multiApp` for isolated vs shared bottle workflows.
- CLI `giack` alias with `whisky` symlink retained for migration.

### Changed
- Renamed `WhiskyKit` → `GIACKKit` (sources `GIACKKit/Sources/GIACKKit/`, subfolders `Bottle`/`GIACKWine`, file `GIACKWineInstaller.swift`).
- Migrated `Bundle.whiskyBundleIdentifier` → `giackBundleIdentifier`, `whiskyWineVersion()` → `giackWineVersion()`, `whiskyDefault`/`whiskyPanelCard` etc. → `giack*` with deprecated aliases.
- Bumped default Wine version 7.7.0 → 11.0.0 and updated `GIACKWineInstaller`/`Wine` to be bottle-aware.
- Updated `GIACKGlass`/`ThumbnailProvider` whisky icon naming to giack with aliases.

### Fixed
- Fixed broken dirty edits that introduced duplicate `InstallerManifest` typealiases and an invalid `Wine` instance property.

## [1.0.0] - 2026-08-18

### Added
- Published the first public GIACK release.
- Added GPTK Wine and DOSBox Staging as first-class library runners.
- Added compatibility presets for Windows games, launchers, utilities, blank Wine, blank DOS, classic DOS games.
- Added runner health scanning and Homebrew-backed management for Wine and DOSBox Staging.
- Added active runtime status in sidebar and Settings → Runners.
- Added `GIACKCmd` preset support and runner-aware library listing.
- Added tooltips across GUI actions.

### Changed
- Renamed application targets, product, shared schemes, and bundle identifiers for GIACK.
- Set public version to `1.0.0` build `1`.
- Consolidated docs, dependency guidance, license notices, and release notes.

### Fixed
- Fixed shared Xcode scheme migration so `xcodebuild -scheme GIACK` resolves.
- Fixed Wine bottle termination to log async shutdown errors.
- Preserved legacy Whisky application-data discovery while moving new installs to GIACK bundle id.
