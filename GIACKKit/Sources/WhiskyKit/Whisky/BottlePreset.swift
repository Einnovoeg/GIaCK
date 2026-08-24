//
//  BottlePreset.swift
//  GIACKKit
//
//  This file is part of GIACK.
//
//  GIACK is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  GIACK is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with GIACK.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation

/// Curated compatibility profiles inspired by the workflow Lutris popularised:
/// start from a known-good recipe, expose advanced overrides only when the
/// user actually needs to deviate. Presets are intentionally conservative so they
/// stay safe across managed GPTK runtimes and external Wine installs.
public enum BottlePreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case blankWine
    case windowsGame
    case gameLauncher
    case windowsUtility
    case blankDOS
    case classicDOSGame

    public var id: Self { self }

    public var runner: BottleRunner {
        switch self {
        case .blankWine, .windowsGame, .gameLauncher, .windowsUtility:
            return .wine
        case .blankDOS, .classicDOSGame:
            return .dosbox
        }
    }

    public var displayName: String {
        switch self {
        case .blankWine:
            return "Blank Wine Bottle"
        case .windowsGame:
            return "Windows Game"
        case .gameLauncher:
            return "Game Launcher"
        case .windowsUtility:
            return "Windows Utility"
        case .blankDOS:
            return "Blank DOS Library"
        case .classicDOSGame:
            return "Classic DOS Game"
        }
    }

    public var systemImage: String {
        switch self {
        case .blankWine:
            return "square.stack.3d.up"
        case .windowsGame:
            return "gamecontroller.fill"
        case .gameLauncher:
            return "arrow.down.app.fill"
        case .windowsUtility:
            return "wrench.and.screwdriver.fill"
        case .blankDOS:
            return "opticaldiscdrive.fill"
        case .classicDOSGame:
            return "display.2"
        }
    }

    public var summary: String {
        switch self {
        case .blankWine:
            return "Manual GPTK Wine setup for advanced users who want a clean starting point."
        case .windowsGame:
            return "Balanced defaults most Windows games should run through the managed GPTK path first."
        case .gameLauncher:
            return "Safer launcher-focused defaults for Steam, Epic, Battle.net, GOG Galaxy, and patchers."
        case .windowsUtility:
            return "Conservative defaults for installers, mod managers, configuration tools, and productivity apps."
        case .blankDOS:
            return "Minimal DOSBox library for manual setup, installers, and shell-driven workflows."
        case .classicDOSGame:
            return "DOSBox profile tuned for classic games with stable mouse capture and CRT-style scaler."
        }
    }

    public var detail: String {
        switch self {
        case .blankWine:
            return "Keeps the bottle close to stock Wine behaviour so you can layer custom tweaks later."
        case .windowsGame:
            return "Uses Windows 10 plus MSync, the most stable default for current macOS GPTK builds."
        case .gameLauncher:
            return "Stays on Windows 10 and avoids extra graphics overrides so launchers can patch and update cleanly."
        case .windowsUtility:
            return "Disables aggressive game-oriented sync tuning to keep utility apps predictable."
        case .blankDOS:
            return "Starts with auto core, auto cycles, and no preset display filter so you can tune each title manually."
        case .classicDOSGame:
            return "Turns on CRT console-like filtering and stable mouse capture for a period-correct experience."
        }
    }

    public var checklist: [String] {
        switch self {
        case .blankWine, .windowsGame, .gameLauncher, .windowsUtility:
            return [
                "Install a managed GPTK runtime or select a Homebrew Wine channel from Settings > Runners.",
                "Run an installer or executable from the bottle overview when ready."
            ]
        case .blankDOS:
            return [
                "Copy DOS files into the library's DOS Games folder.",
                "Set a default startup program in the Config tab if you want one-click launch."
            ]
        case .classicDOSGame:
            return [
                "Copy the game into the DOS Games folder.",
                "Choose a default startup program in the Config tab to launch directly into the game."
            ]
        }
    }

    public static func presets(for runner: BottleRunner) -> [BottlePreset] {
        allCases.filter { $0.runner == runner }
    }

    public static func defaultPreset(for runner: BottleRunner) -> BottlePreset {
        switch runner {
        case .wine:
            return .windowsGame
        case .dosbox:
            return .classicDOSGame
        }
    }
}

public extension BottleSettings {
    /// Applies a curated preset while preserving bottle-local data that should
    /// survive retuning (pins, blocklists, existing DOS startup
    /// path). This method only touches the runtime options the preset is meant to own.
    mutating func apply(preset: BottlePreset) {
        self.appliedPreset = preset
        self.bottleRunner = preset.runner

        switch preset {
        case .blankWine:
            windowsVersion = .win10
            enhancedSync = .none
            avxEnabled = false
            dxvk = false
            dxvkAsync = true
            dxvkHud = .off
            metalHud = false
            metalTrace = false
            dxrEnabled = false
        case .windowsGame:
            windowsVersion = .win10
            enhancedSync = .msync
            avxEnabled = false
            dxvk = false
            dxvkAsync = true
            dxvkHud = .off
            metalHud = false
            metalTrace = false
            dxrEnabled = false
        case .gameLauncher:
            windowsVersion = .win10
            enhancedSync = .msync
            avxEnabled = false
            dxvk = false
            dxvkAsync = true
            dxvkHud = .off
            metalHud = false
            metalTrace = false
            dxrEnabled = false
        case .windowsUtility:
            windowsVersion = .win10
            enhancedSync = .none
            avxEnabled = false
            dxvk = false
            dxvkAsync = true
            dxvkHud = .off
            metalHud = false
            metalTrace = false
            dxrEnabled = false
        case .blankDOS:
            dosboxFullscreen = false
            dosboxCaptureMouse = true
            dosboxCycles = .auto
            dosboxCore = .auto
            dosboxScaler = .none
        case .classicDOSGame:
            dosboxFullscreen = false
            dosboxCaptureMouse = true
            dosboxCycles = .auto
            dosboxCore = .auto
            dosboxScaler = .hq2x
        }
    }
}
