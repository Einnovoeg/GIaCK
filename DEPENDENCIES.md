# Dependencies

## Build Dependencies

- macOS 14.0 or later.
- Xcode with Swift 6 support.
- Swift Package Manager access for resolving the project packages.
- SwiftLint for local parity with the Xcode build script and continuous integration.

The project resolves these Swift packages:

- Sparkle: application update framework.
- SemanticVersion: semantic-version parsing and comparison.
- swift-argument-parser: `GIACKCmd` command parsing.
- SwiftyTextTable: `GIACKCmd` table output.
- Progress.swift: command-line progress reporting.

Exact package revisions are recorded in `GIACK.xcodeproj` and `GIACKKit/Package.resolved`.

## Runtime Dependencies

- A managed GPTK-compatible Wine runtime, a locally mounted Apple Game Porting Toolkit installation, or an optional Homebrew Wine channel.
- DOSBox Staging for DOS libraries.

GIACK GPTK does not redistribute Apple Game Porting Toolkit installers, Wine runtime archives, or DOSBox Staging binaries.

## Optional Tools

```bash
brew install swiftlint
brew install cabextract
brew install dosbox-staging
brew install --cask wine-stable
```

- `swiftlint` is required only for the project lint step.
- `cabextract` is required for Winetricks verbs.
- `dosbox-staging` enables DOS libraries.
- Homebrew Wine channels are optional alternatives to the managed GPTK runtime.

## License Notes

Each dependency retains its own license. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and the accompanying `LICENSES/` directory before redistributing binaries or modified third-party code.
