# Contributing to GIACK GPTK

## Scope

GIACK GPTK is a maintained fork of the archived GIACK project. Contributions should focus on runtime compatibility, bottle reliability, macOS UX quality, documentation, and licensing/compliance hygiene.

## Build Environment

- Apple Silicon Mac
- macOS 14.0 or later
- Xcode 26.3 or later
- SwiftLint for local lint parity: `brew install swiftlint`

All package dependencies are resolved through Swift Package Manager.

## Code Style

- Prefer clear, minimal changes over broad refactors.
- Keep comments factual and useful; explain intent where code is not obvious.
- Preserve existing localization behavior when practical.
- Avoid bundling third-party executables unless their redistribution terms are explicitly reviewed.

## Validation

Before opening a pull request:

1. Build the `GIACK` scheme in Debug.
2. Build the `GIACK` scheme in Release if you changed packaging or release metadata.
3. Run `GIACKCmd --help` from the built app bundle or build products.
4. Confirm that bottle creation/import still works if your change touches bottle or runtime code.

## Pull Requests

- Use a focused branch.
- Describe the problem, the change, and the validation steps.
- Include screenshots for UI changes.
- Call out license or dependency changes explicitly.
