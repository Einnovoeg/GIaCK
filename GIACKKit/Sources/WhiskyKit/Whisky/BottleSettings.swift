//
//  BottleSettings.swift
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
import SemanticVersion
import os.log

/// Runtime families supported by a bottle.
///
/// This is intentionally narrow today: GPTK Wine for Windows software and
/// DOSBox Staging for DOS software. Both the UI and CLI branch on this.
public enum BottleRunner: String, CaseIterable, Codable, Sendable {
    case wine
    case dosbox

    public var displayName: String {
        switch self {
        case .wine:
            return "GPTK Wine"
        case .dosbox:
            return "DOSBox"
        }
    }

    public var shortDisplayName: String {
        switch self {
        case .wine:
            return "Wine"
        case .dosbox:
            return "DOS"
        }
    }

    public var systemImage: String {
        switch self {
        case .wine:
            return "wineglass.fill"
        case .dosbox:
            return "opticaldiscdrive.fill"
        }
    }

    public var creationSummary: String {
        switch self {
        case .wine:
            return "Use Game Porting Toolkit and Wine for modern Windows games."
        case .dosbox:
            return "Use DOSBox Staging for DOS games, installers, and classic launchers."
        }
    }
}

public struct PinnedProgram: Codable, Hashable, Equatable {
    public var name: String
    public var url: URL?
    public var removable: Bool

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
        do {
            let volume = try url.resourceValues(forKeys: [.volumeURLKey]).volume
            self.removable = try !(volume?.resourceValues(forKeys: [.volumeIsInternalKey]).volumeIsInternal ?? false)
        } catch {
            self.removable = false
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.url = try container.decodeIfPresent(URL.self, forKey: .url)
        self.removable = try container.decodeIfPresent(Bool.self, forKey: .removable) ?? false
    }
}

public struct BottleInfo: Codable, Equatable {
    var name: String = "Bottle"
    var pins: [PinnedProgram] = []
    var blocklist: [URL] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Bottle"
        self.pins = try container.decodeIfPresent([PinnedProgram].self, forKey: .pins) ?? []
        self.blocklist = try container.decodeIfPresent([URL].self, forKey: .blocklist) ?? []
    }
}

public enum WinVersion: String, CaseIterable, Codable, Sendable {
    case winXP = "winxp64"
    case win7 = "win7"
    case win8 = "win8"
    case win81 = "win81"
    case win10 = "win10"
    case win11 = "win11"

    public func pretty() -> String {
        switch self {
        case .winXP:
            return "Windows XP"
        case .win7:
            return "Windows 7"
        case .win8:
            return "Windows 8"
        case .win81:
            return "Windows 8.1"
        case .win10:
            return "Windows 10"
        case .win11:
            return "Windows 11"
        }
    }
}

public enum EnhancedSync: Codable, Equatable {
    case none, esync, msync
}

public enum DOSBoxCycles: String, CaseIterable, Codable, Sendable {
    case auto
    case max
    case fixed8000
    case fixed12000
    case fixed20000

    public var displayName: String {
        switch self {
        case .auto:
            return "Auto"
        case .max:
            return "Max"
        case .fixed8000:
            return "Fixed 8000"
        case .fixed12000:
            return "Fixed 12000"
        case .fixed20000:
            return "Fixed 20000"
        }
    }

    var cpuCyclesValue: String {
        switch self {
        case .auto:
            return "3000"
        case .max:
            return "max"
        case .fixed8000:
            return "8000"
        case .fixed12000:
            return "12000"
        case .fixed20000:
            return "20000"
        }
    }
}

public enum DOSBoxCore: String, CaseIterable, Codable, Sendable {
    case auto
    case dynamic
    case normal
    case simple

    public var displayName: String {
        rawValue.capitalized
    }
}

public enum DOSBoxScaler: String, CaseIterable, Codable, Sendable {
    case none
    case normal2x
    case hq2x
    case rgb3x

    public var displayName: String {
        switch self {
        case .none:
            return "None"
        case .normal2x:
            return "Sharp"
        case .hq2x:
            return "CRT Auto"
        case .rgb3x:
            return "Arcade Sharp"
        }
    }

    var configValue: String {
        switch self {
        case .none:
            return "none"
        case .normal2x:
            return "sharp"
        case .hq2x:
            return "crt-auto"
        case .rgb3x:
            return "crt-auto-arcade-sharp"
        }
    }
}

public struct BottleWineConfig: Codable, Equatable {
    static let defaultWineVersion = SemanticVersion(7, 7, 0)
    var wineVersion: SemanticVersion = Self.defaultWineVersion
    var windowsVersion: WinVersion = .win10
    var enhancedSync: EnhancedSync = .msync
    var avxEnabled: Bool = false

    public init() {}

    // swiftlint:disable line_length
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.wineVersion = try container.decodeIfPresent(SemanticVersion.self, forKey: .wineVersion) ?? Self.defaultWineVersion
        self.windowsVersion = try container.decodeIfPresent(WinVersion.self, forKey: .windowsVersion) ?? .win10
        self.enhancedSync = try container.decodeIfPresent(EnhancedSync.self, forKey: .enhancedSync) ?? .msync
        self.avxEnabled = try container.decodeIfPresent(Bool.self, forKey: .avxEnabled) ?? false
    }
    // swiftlint:enable line_length
}

public struct BottleMetalConfig: Codable, Equatable {
    var metalHud: Bool = false
    var metalTrace: Bool = false
    var dxrEnabled: Bool = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.metalHud = try container.decodeIfPresent(Bool.self, forKey: .metalHud) ?? false
        self.metalTrace = try container.decodeIfPresent(Bool.self, forKey: .metalTrace) ?? false
        self.dxrEnabled = try container.decodeIfPresent(Bool.self, forKey: .dxrEnabled) ?? false
    }
}

public enum DXVKHUD: Codable, Equatable {
    case full, partial, fps, off
}

public struct BottleDXVKConfig: Codable, Equatable {
    var dxvk: Bool = false
    var dxvkAsync: Bool = true
    var dxvkHud: DXVKHUD = .off

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.dxvk = try container.decodeIfPresent(Bool.self, forKey: .dxvk) ?? false
        self.dxvkAsync = try container.decodeIfPresent(Bool.self, forKey: .dxvkAsync) ?? true
        self.dxvkHud = try container.decodeIfPresent(DXVKHUD.self, forKey: .dxvkHud) ?? .off
    }
}

/// Per-bottle DOSBox settings that are safe to persist in metadata.
///
/// Advanced users can still edit the generated config file directly, but the
/// common controls live here so the UI can expose them consistently.
public struct BottleDOSBoxConfig: Codable, Equatable {
    var fullscreen: Bool = false
    var captureMouse: Bool = true
    var cycles: DOSBoxCycles = .auto
    var core: DOSBoxCore = .auto
    var scaler: DOSBoxScaler = .none
    var startupProgram: String?

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.fullscreen = try container.decodeIfPresent(Bool.self, forKey: .fullscreen) ?? false
        self.captureMouse = try container.decodeIfPresent(Bool.self, forKey: .captureMouse) ?? true
        self.cycles = try container.decodeIfPresent(DOSBoxCycles.self, forKey: .cycles) ?? .auto
        self.core = try container.decodeIfPresent(DOSBoxCore.self, forKey: .core) ?? .auto
        self.scaler = try container.decodeIfPresent(DOSBoxScaler.self, forKey: .scaler) ?? .none
        self.startupProgram = try container.decodeIfPresent(String.self, forKey: .startupProgram)
    }
}

public struct BottleSettings: Codable, Equatable {
    static let defaultFileVersion = SemanticVersion(1, 0, 0)

    var fileVersion: SemanticVersion = Self.defaultFileVersion
    private var preset: BottlePreset?
    private var runner: BottleRunner
    private var info: BottleInfo
    private var wineConfig: BottleWineConfig
    private var metalConfig: BottleMetalConfig
    private var dxvkConfig: BottleDXVKConfig
    private var dosboxConfig: BottleDOSBoxConfig

    public init() {
        self.preset = .windowsGame
        self.runner = .wine
        self.info = BottleInfo()
        self.wineConfig = BottleWineConfig()
        self.metalConfig = BottleMetalConfig()
        self.dxvkConfig = BottleDXVKConfig()
        self.dosboxConfig = BottleDOSBoxConfig()
    }

    // swiftlint:disable line_length
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.fileVersion = try container.decodeIfPresent(SemanticVersion.self, forKey: .fileVersion) ?? Self.defaultFileVersion
        self.preset = try container.decodeIfPresent(BottlePreset.self, forKey: .preset)
        self.runner = try container.decodeIfPresent(BottleRunner.self, forKey: .runner) ?? .wine
        self.info = try container.decodeIfPresent(BottleInfo.self, forKey: .info) ?? BottleInfo()
        self.wineConfig = try container.decodeIfPresent(BottleWineConfig.self, forKey: .wineConfig) ?? BottleWineConfig()
        self.metalConfig = try container.decodeIfPresent(BottleMetalConfig.self, forKey: .metalConfig) ?? BottleMetalConfig()
        self.dxvkConfig = try container.decodeIfPresent(BottleDXVKConfig.self, forKey: .dxvkConfig) ?? BottleDXVKConfig()
        self.dosboxConfig = try container.decodeIfPresent(BottleDOSBoxConfig.self, forKey: .dosboxConfig) ?? BottleDOSBoxConfig()
    }
    // swiftlint:enable line_length

    /// The runtime family that owns this bottle.
    public var bottleRunner: BottleRunner {
        get { runner }
        set { runner = newValue }
    }

    /// The curated preset last applied to this bottle, if any.
    public var appliedPreset: BottlePreset? {
        get { preset }
        set { preset = newValue }
    }

    /// The name of this bottle.
    public var name: String {
        get { return info.name }
        set { info.name = newValue }
    }

    /// The version of wine used by this bottle.
    public var wineVersion: SemanticVersion {
        get { return wineConfig.wineVersion }
        set { wineConfig.wineVersion = newValue }
    }

    /// The Windows version used by this bottle.
    public var windowsVersion: WinVersion {
        get { return wineConfig.windowsVersion }
        set { wineConfig.windowsVersion = newValue }
    }

    public var avxEnabled: Bool {
        get { return wineConfig.avxEnabled }
        set { wineConfig.avxEnabled = newValue }
    }

    /// The pinned programs on this bottle.
    public var pins: [PinnedProgram] {
        get { return info.pins }
        set { info.pins = newValue }
    }

    /// Blocked applications on this bottle.
    public var blocklist: [URL] {
        get { return info.blocklist }
        set { info.blocklist = newValue }
    }

    public var enhancedSync: EnhancedSync {
        get { return wineConfig.enhancedSync }
        set { wineConfig.enhancedSync = newValue }
    }

    public var metalHud: Bool {
        get { return metalConfig.metalHud }
        set { metalConfig.metalHud = newValue }
    }

    public var metalTrace: Bool {
        get { return metalConfig.metalTrace }
        set { metalConfig.metalTrace = newValue }
    }

    public var dxrEnabled: Bool {
        get { return metalConfig.dxrEnabled }
        set { metalConfig.dxrEnabled = newValue }
    }

    public var dxvk: Bool {
        get { return dxvkConfig.dxvk }
        set { dxvkConfig.dxvk = newValue }
    }

    public var dxvkAsync: Bool {
        get { return dxvkConfig.dxvkAsync }
        set { dxvkConfig.dxvkAsync = newValue }
    }

    public var dxvkHud: DXVKHUD {
        get { return dxvkConfig.dxvkHud }
        set { dxvkConfig.dxvkHud = newValue }
    }

    public var dosboxFullscreen: Bool {
        get { return dosboxConfig.fullscreen }
        set { dosboxConfig.fullscreen = newValue }
    }

    public var dosboxCaptureMouse: Bool {
        get { return dosboxConfig.captureMouse }
        set { dosboxConfig.captureMouse = newValue }
    }

    public var dosboxCycles: DOSBoxCycles {
        get { return dosboxConfig.cycles }
        set { dosboxConfig.cycles = newValue }
    }

    public var dosboxCore: DOSBoxCore {
        get { return dosboxConfig.core }
        set { dosboxConfig.core = newValue }
    }

    public var dosboxScaler: DOSBoxScaler {
        get { return dosboxConfig.scaler }
        set { dosboxConfig.scaler = newValue }
    }

    /// Relative path inside the DOS games folder for the default startup program.
    public var dosboxStartupProgram: String? {
        get { dosboxConfig.startupProgram }
        set {
            let trimmedValue = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            dosboxConfig.startupProgram = trimmedValue?.isEmpty == true ? nil : trimmedValue
        }
    }

    @discardableResult
    public static func decode(from metadataURL: URL) throws -> BottleSettings {
        guard FileManager.default.fileExists(atPath: metadataURL.path(percentEncoded: false)) else {
            let settings = BottleSettings()
            try settings.encode(to: metadataURL)
            return settings
        }

        let decoder = PropertyListDecoder()
        let data = try Data(contentsOf: metadataURL)
        var settings = try decoder.decode(BottleSettings.self, from: data)

        guard settings.fileVersion == BottleSettings.defaultFileVersion else {
            Logger.wineKit.warning("Invalid file version `\(settings.fileVersion)`")
            settings = BottleSettings()
            try settings.encode(to: metadataURL)
            return settings
        }

        return settings
    }

    func encode(to metadataUrl: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(self)
        try data.write(to: metadataUrl)
    }

    // swiftlint:disable:next cyclomatic_complexity
    public func environmentVariables(wineEnv: inout [String: String]) {
        guard bottleRunner == .wine else {
            return
        }

        if dxvk {
            wineEnv.updateValue("dxgi,d3d9,d3d10core,d3d11=n,b", forKey: "WINEDLLOVERRIDES")
            switch dxvkHud {
            case .full:
                wineEnv.updateValue("full", forKey: "DXVK_HUD")
            case .partial:
                wineEnv.updateValue("devinfo,fps,frametimes", forKey: "DXVK_HUD")
            case .fps:
                wineEnv.updateValue("fps", forKey: "DXVK_HUD")
            case .off:
                break
            }
        }

        if dxvkAsync {
            wineEnv.updateValue("1", forKey: "DXVK_ASYNC")
        }

        switch enhancedSync {
        case .none:
            break
        case .esync:
            wineEnv.updateValue("1", forKey: "WINEESYNC")
        case .msync:
            wineEnv.updateValue("1", forKey: "WINEMSYNC")
        }

        if metalHud {
            wineEnv.updateValue("1", forKey: "MTL_HUD_ENABLED")
        }

        if metalTrace {
            wineEnv.updateValue("1", forKey: "METAL_CAPTURE_ENABLED")
        }

        if avxEnabled {
            wineEnv.updateValue("1", forKey: "ROSETTA_ADVERTISE_AVX")
        }

        if dxrEnabled {
            wineEnv.updateValue("1", forKey: "D3DM_SUPPORT_DXR")
        }
    }
}
