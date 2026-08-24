# GIACK Agent Handoff

## 1. Point of this project
GIACK is a maintained macOS fork of the archived GIACK app. It provides a native SwiftUI launcher for running Windows software via Game Porting Toolkit/Wine and for running DOS-era software via DOSBox Staging. It is designed to keep GPTK runtimes current, expose a stable runner model, and keep the UI cohesive while remaining GPL-3.0-or-later compliant.

## 2. What has been done
- Runtime sourcing and updates:
  - Managed GPTK runtime resolution from `Gcenx/game-porting-toolkit`.
  - Local mounted GPTK detection and optional redist overlays.
  - Settings-driven runtime updates, auto-install, and local preference handling.
- Runner model:
  - `GPTK Wine` and `DOSBox` as first-class runners.
  - Homebrew-backed install/update support for Wine 11 Stable/Devel/Staging and DOSBox Staging.
- UI cleanup:
  - Main window simplified with primary actions above the fold.
  - Settings converted to tabbed layout with a dedicated `Runners` tab.
  - Optional glass styling preserved as a toggle.
  - Tooltips added throughout interactive UI.
- Compatibility presets:
  - Added curated presets for Wine and DOS libraries.
  - Preset-first creation flow.
  - Preset reapply flow in the bottle `Config` tab.
  - Preset visibility in bottle details and CLI.
- CLI parity:
  - `whisky create --preset ...` supported.
  - `whisky list` includes preset column.
- Docs and compliance:
  - Updated `README.md`, `CHANGELOG.md`, and `RELEASE_NOTES.md`.
  - License and third‑party notices maintained (GPL‑3.0‑or‑later).
  - Funding link included (Buy Me a Coffee).
- Releases:
  - Latest published release: `v3.4.0`.
  - Asset: `GIACKGPTK-v3.4.0-unsigned.zip` (SHA‑256 `741746716dc46834d5946644c14a091d253bdac4bc6cb6cd9e264e476d9ded6e`).

## 3. Steps that need to be taken next
1. Decide whether Wine runtime selection should also be exposed per‑bottle (currently global in Settings → Runners).
2. Add an installer/preset manifest system (Lutris‑style) if game‑specific scripts are desired.
3. Add a small in‑app “Runtime Status” panel that explicitly highlights the currently selected Wine channel to reduce confusion.
4. Optional: implement signing/notarization workflow for official releases.
5. Optional: add a lightweight test target or scripted smoke test to reduce reliance on manual UI verification.
