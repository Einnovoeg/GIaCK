# GIaCK 2.0 — plus 1.1 & 1.0 notes

## 2.0.1 — September 8, 2026 — deep scan & per-game AI (follow-up to 2.0)

**Focus:** fix “pre-installed apps invisible” and wire the AI per-game dependency scan the user flagged.

- **Deep program discovery** — `Bottle.updateInstalledPrograms()` was limited to `Program Files` + `Program Files (x86)`. Now it deep-scans the entire `drive_c` (pruning `windows` system dirs), plus `ProgramData`, `Games`/`GOG Games`, and every `users/*` profile (AppData, Desktop, etc.), de-duplicates case-insensitively, and respects blocklist. Windows system exes are skipped. `BottleView.updateStartMenu()` now **adds** missing Start Menu `.lnk` targets to `bottle.programs` instead of only pinning already-found ones, and `getStartMenuPrograms()` scans all user profiles’ Start Menus (not just `crossover`). `ContentView` now proactively re-scans all bottles on launch so existing installs appear without manual action; `ProgramsView` has an explicit **Rescan Now** header.
- **Per-game AI wired** — `ProgramView` now has an **AI Analysis** section (auto-runs on appear): `AIGameDetector` → `AIDependencyAnalyzer` → `AIBottleAdvisor` shows identity (publisher/engine/confidence/arch), recommended preset/Win version/sync/DXVK, DLLs/verbs, rationale, install plan, **Apply Recommended Settings** (mutates `BottleSettings`), and **Install Missing Dependencies** (queues `Winetricks.runCommand` per verb). `ProgramsView` batch header adds **AI Scan All** and collapsible results. The previous kit was orphaned (no UI call site).
- **AI remote fix** — `AICompatibilityService.remoteURL` / `AICompatibilityConfig.remoteURL` corrected from `GIACK-App/GIACK` (404) to `Einnovoeg/GIaCK`; `ContentView.task` now warms `AICompatibilityService.sync()` + `RemoteDatabase.syncFromRemote()` in background so per-game scans have remote entries. Healing the 404 and the never-called `sync()` makes the “AI/database for installing new files” path intact.
- **Verify:** `swift build --package-path GIACKKit` passes; manual temp-bottle test (8 exes across `Program Files`, `GOG Games`, `users/*/Desktop`, `ProgramData` plus 2 `windows` ignored) → 8 found. Immediate workaround for affected users: open bottle → Programs → **Rescan Now** (or relaunch).

## 2.0 — September 7, 2026

**Focus:** per-bottle Wine runtime UI, runtime status visibility, docs/security polish.

### Highlights

- **Per-bottle Wine runtime picker** — Bottle Config now has a dedicated `Wine Runtime` section. Pick `Use Global (<current channel>)` or pin `Managed GPTK Runtime` / `Wine 11 Stable` / `Wine Devel` / `Wine Staging` per library. Options show `— Not installed` when the channel isn’t present, the effective runtime `DisplayName · Version · Source` is shown selectable, and a missing-runtime warning links to Settings → Runners. `Use Global Runtime` clears the override. All Wine launches are bottle-aware via `Wine.wineBinary(for:)`.
- **Runtime Status panel** — Overview now shows a per-bottle runtime card (effective/global/binary path, scope pill `Global`/`Per-Bottle`, not-installed warning, `Change in Config` + `Open Runners Settings`). The bottle header badges, overview metrics, details grid, and sidebar list subtitle all highlight the effective channel (short labels GPTK/Stable/Devel/Staging + `Per-Bottle` flag).
- **Helpers** — `GIACKWineInstaller.runtime(for:)`, `isRuntimeInstalled(for:)`, `runtimeSummary(for:)` so UI can reflect install state without side effects.
- **Polish** — repo URLs unified to `https://github.com/Einnovoeg/GIaCK`; `.gitignore` hardened; `.DS_Store`/`GIACKKit/.build` cleaned; security audit (no secrets/PII beyond intentional Buy Me a Coffee + `com.einnovoeg.GIACK`; argument-array `Process`; shell-escaping guards); doc comments added to runtime APIs and shell helpers.
- **Docs** — `README.md` (2.0 features, runtime model, known limitations, help-wanted imploration), `CHANGELOG.md`, `DEPENDENCIES.md` refreshed. Build verified via `swift build --package-path GIACKKit`.

### Upgrade notes

- Existing bottles default to `Use Global` — no migration needed. Pin a channel in Config only if you need a specific Wine family for that library.
- Install Homebrew Wine channels or the managed GPTK runtime from Settings → Runners if the status card shows `Not installed`.
- Per-bottle overrides survive global channel switches (global is the fallback; per-bottle wins).

### Important notes

- Still **unsigned / not notarized** — Gatekeeper approval required.
- External runtimes remain **not bundled**.
- Compatibility is app-specific — report with macOS version, runner, runtime version, app version, logs.

---

## 1.1 — September 5, 2026 (development branch)

AI and per-bottle runtime model update. See `CHANGELOG.md` 1.1.

- **AI Auto-Config**: `AIGameDetector` (PE parsing + heuristics + Steam Deck/ProtonDB), `AIDependencyAnalyzer` (DLL→verb mapping), `AIBottleAdvisor` (`apply(to:)`/`plan(for:)`), `AICompatibilityService` (curated + GIaCK remote + Steam Deck enrichment).
- **Per-bottle runtime plumbing** (`effectiveWineRuntime`), **Bottle modes** (`singleApp`/`multiApp`), **Wine 11** defaults, **naming migration** (`WhiskyKit`→`GIACKKit`), **Heroic roadmap** researched.

## 1.0 — August 18, 2026 (build 1)

First public release — GPTK Wine + DOSBox Staging first-class runners, curated presets, runner health scan, Homebrew-backed management, active runtime in sidebar, `GIACKCmd` preset support, tooltips.

---

*Reporting:* open an issue at `https://github.com/Einnovoeg/GIaCK/issues` with macOS version, runner, runtime version, application version, and logs (`Help → Open Logs`). Contributions welcome — see `CONTRIBUTING.md` and the README “Please help fix these gaps” section.

Support: [buymeacoffee.com/einnovoeg](https://buymeacoffee.com/einnovoeg)
