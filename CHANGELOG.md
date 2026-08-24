# Changelog

All notable public changes are documented here. GIACK GPTK follows Semantic Versioning for public releases.

## [1.0.0] - 2026-08-18

### Added

- Published the first public GIACK GPTK release.
- Added GPTK Wine and DOSBox Staging as first-class library runners.
- Added compatibility presets for Windows games, game launchers, Windows utilities, blank Wine bottles, blank DOS libraries, and classic DOS games.
- Added runner health scanning and Homebrew-backed management for Wine and DOSBox Staging.
- Added active runtime status in the main library sidebar and Settings > Runners.
- Added `GIACKCmd` preset support and runner-aware library listing.
- Added tooltips across GUI actions and controls.

### Changed

- Renamed the application targets, product, shared schemes, and bundle identifiers for GIACK GPTK.
- Set the public application version to `1.0.0` with build number `1`.
- Consolidated public documentation, dependency guidance, license notices, and release notes for the 1.0 release.

### Fixed

- Fixed the shared Xcode scheme migration so `xcodebuild -scheme GIACK` resolves the application scheme.
- Fixed Wine bottle termination so asynchronous shutdown errors are logged instead of being silently discarded.
- Preserved legacy Whisky application-data discovery while moving new installations to the GIACK bundle identifier.
