//
//  RunnerSupport.swift
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

import Darwin
import Foundation

/// Homebrew casks that GIACK GPTK can manage directly.
///
/// Only native macOS packages are listed here. Lutris is intentionally absent
/// because the upstream project is Linux-first and does not provide a supported
/// native macOS runner we can invoke reliably from this app.
public enum HomebrewCask: String, CaseIterable, Sendable {
    case dosboxStaging = "dosbox-staging-app"
    case wineStable = "wine-stable"
    case wineDevel = "wine@devel"
    case wineStaging = "wine@staging"

    public var displayName: String {
        switch self {
        case .dosboxStaging:
            return "DOSBox Staging"
        case .wineStable:
            return "Wine 11 Stable"
        case .wineDevel:
            return "Wine Devel"
        case .wineStaging:
            return "Wine Staging"
        }
    }

    public var installSummary: String {
        switch self {
        case .dosboxStaging:
            return "Native DOS runner for classic DOS games and installers."
        case .wineStable:
            return "Official WineHQ stable macOS build, currently Wine 11."
        case .wineDevel:
            return "Official WineHQ development macOS build from Gcenx's packaged releases."
        case .wineStaging:
            return "Official WineHQ staging macOS build with staging patches."
        }
    }

    /// Casks install macOS apps into `/Applications`; the runner binaries live
    /// inside those app bundles and are intentionally resolved without PATH.
    public var appBundleURL: URL {
        switch self {
        case .dosboxStaging:
            return URL(fileURLWithPath: "/Applications/DOSBox Staging.app")
        case .wineStable:
            return URL(fileURLWithPath: "/Applications/Wine Stable.app")
        case .wineDevel:
            return URL(fileURLWithPath: "/Applications/Wine Devel.app")
        case .wineStaging:
            return URL(fileURLWithPath: "/Applications/Wine Staging.app")
        }
    }

    public var bundleVersion: String? {
        let infoURL = appBundleURL.appending(path: "Contents").appending(path: "Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL) else {
            return nil
        }

        if let version = info["CFBundleShortVersionString"] as? String,
           !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return version
        }
        if let build = info["CFBundleVersion"] as? String,
           !build.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return build
        }
        return nil
    }

    public var isInstalled: Bool {
        FileManager.default.fileExists(atPath: appBundleURL.path(percentEncoded: false))
    }
}

public struct HomebrewCaskStatus: Sendable {
    public let cask: HomebrewCask
    public let latestVersion: String?
    public let installedVersion: String?
    public let isInstalled: Bool
    public let homebrewAvailable: Bool

    public var summary: String {
        switch (installedVersion, latestVersion) {
        case let (installedVersion?, latestVersion?):
            return installedVersion == latestVersion
                ? "Installed \(installedVersion)"
                : "Installed \(installedVersion) · Latest \(latestVersion)"
        case let (installedVersion?, nil):
            return "Installed \(installedVersion)"
        case let (nil, latestVersion?):
            return "Not installed · Latest \(latestVersion)"
        case (nil, nil):
            return homebrewAvailable ? "Version information unavailable" : "Homebrew not installed"
        }
    }
}

public struct HomebrewCommandResult: Sendable {
    public let success: Bool
    public let output: String
}

/// Minimal Homebrew wrapper used for one-click runner installs and updates.
///
/// Commands are executed with `Process` and explicit argument arrays so the UI
/// never shells out through an interpolated command string.
public enum HomebrewRuntimeManager {
    private static let brewCandidates = [
        URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
        URL(fileURLWithPath: "/usr/local/bin/brew")
    ]

    public static func brewExecutableURL() -> URL? {
        brewCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path(percentEncoded: false)) })
    }

    public static func isAvailable() -> Bool {
        brewExecutableURL() != nil
    }

    public static func status(for cask: HomebrewCask) async -> HomebrewCaskStatus {
        guard let brewExecutableURL = brewExecutableURL() else {
            return HomebrewCaskStatus(
                cask: cask,
                latestVersion: nil,
                installedVersion: cask.bundleVersion,
                isInstalled: cask.isInstalled,
                homebrewAvailable: false
            )
        }

        let result = await run(brewExecutableURL: brewExecutableURL, arguments: ["info", "--cask", cask.rawValue, "--json=v2"])
        let latestVersion = parseLatestVersion(from: result.output)
        let installedVersion = cask.bundleVersion

        return HomebrewCaskStatus(
            cask: cask,
            latestVersion: latestVersion,
            installedVersion: installedVersion,
            isInstalled: cask.isInstalled,
            homebrewAvailable: true
        )
    }

    public static func installOrUpgrade(_ cask: HomebrewCask) async -> HomebrewCommandResult {
        guard let brewExecutableURL = brewExecutableURL() else {
            return HomebrewCommandResult(success: false, output: "Homebrew is not installed.")
        }

        let verb = cask.isInstalled ? "upgrade" : "install"
        return await run(brewExecutableURL: brewExecutableURL, arguments: [verb, "--cask", cask.rawValue])
    }

    private static func run(brewExecutableURL: URL, arguments: [String]) async -> HomebrewCommandResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = brewExecutableURL
            process.arguments = arguments
            process.qualityOfService = .userInitiated

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: HomebrewCommandResult(
                    success: process.terminationStatus == 0,
                    output: output
                ))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: HomebrewCommandResult(success: false, output: error.localizedDescription))
            }
        }
    }

    private static func parseLatestVersion(from output: String) -> String? {
        guard let data = output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let casks = object["casks"] as? [[String: Any]],
              let cask = casks.first else {
            return nil
        }

        return cask["version"] as? String
    }
}

public enum ExternalWineRuntime: String, CaseIterable, Sendable {
    case stable
    case devel
    case staging

    public var cask: HomebrewCask {
        switch self {
        case .stable:
            return .wineStable
        case .devel:
            return .wineDevel
        case .staging:
            return .wineStaging
        }
    }

    public var displayName: String {
        cask.displayName
    }

    public var appBundleURL: URL {
        cask.appBundleURL
    }

    public var wineBinaryURL: URL? {
        [
            appBundleURL.appending(path: "Contents/Resources/wine/bin/wine64"),
            appBundleURL.appending(path: "Contents/Resources/wine/bin/wine")
        ].first(where: isExecutable)
    }

    public var wineserverBinaryURL: URL? {
        let candidate = appBundleURL.appending(path: "Contents/Resources/wine/bin/wineserver")
        return isExecutable(candidate) ? candidate : nil
    }

    public var binDirectoryURL: URL? {
        wineBinaryURL?.deletingLastPathComponent()
    }

    public func toolBinaryURL(named name: String) -> URL? {
        let candidate = appBundleURL.appending(path: "Contents/Resources/wine/bin/\(name)")
        return isExecutable(candidate) ? candidate : nil
    }

    public var installedVersion: String? {
        cask.bundleVersion ?? resolvedVersionFromBinary()
    }

    public var isInstalled: Bool {
        wineBinaryURL != nil && wineserverBinaryURL != nil
    }

    private func resolvedVersionFromBinary() -> String? {
        guard let wineBinaryURL else { return nil }

        let process = Process()
        process.executableURL = wineBinaryURL
        process.arguments = ["--version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let output, !output.isEmpty else {
            return nil
        }

        return output.replacingOccurrences(of: "wine-", with: "")
    }

    private func isExecutable(_ url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path(percentEncoded: false))
    }
}

public enum SystemScanSeverity: String, Sendable {
    case ready
    case actionNeeded
}

public struct SystemScanFinding: Identifiable, Sendable, Hashable {
    public let id = UUID()
    public let severity: SystemScanSeverity
    public let title: String
    public let detail: String
}

public struct SystemScanReport: Sendable {
    public let summary: String
    public let activeWineSummary: String
    public let dosboxSummary: String
    public let findings: [SystemScanFinding]
}

/// Lightweight environment scan used by the Settings runner tab.
///
/// The report only covers things this app can act on directly: Rosetta, the
/// currently selected Wine runtime, DOSBox availability, and a few stability
/// defaults stored in `UserDefaults`.
public enum GIACKSystemScan {
    public static func scan() async -> SystemScanReport {
        let activeWineSummary = GIACKWineInstaller.activeWineRuntimeSummary()
        let dosboxStatus = await HomebrewRuntimeManager.status(for: .dosboxStaging)
        let dosboxSummary = dosboxStatus.summary
        var findings: [SystemScanFinding] = []

        if isAppleSiliconMac(), !Rosetta2.isRosettaInstalled {
            findings.append(SystemScanFinding(
                severity: .actionNeeded,
                title: "Rosetta 2 is missing",
                detail: "Install Rosetta so Wine-based Windows libraries can start correctly on Apple Silicon."
            ))
        }

        if GIACKWineInstaller.currentWineRuntime() == nil {
            findings.append(SystemScanFinding(
                severity: .actionNeeded,
                title: "No Wine runtime is active",
                detail: "Install the managed GPTK runtime or a Homebrew Wine runtime before starting Windows libraries."
            ))
        }

        if !DOSBox.isInstalled() {
            findings.append(SystemScanFinding(
                severity: .actionNeeded,
                title: "DOSBox Staging is not installed",
                detail: "Install DOSBox Staging if you want DOS libraries to run without manual setup."
            ))
        }

        if !(UserDefaults.standard.object(forKey: "disableAppNap") as? Bool ?? true) {
            findings.append(SystemScanFinding(
                severity: .actionNeeded,
                title: "App Nap protection is disabled",
                detail: "Prevent App Nap to reduce background throttling while games or installers are running."
            ))
        }

        if !(UserDefaults.standard.object(forKey: "checkGIACKWineUpdates") as? Bool ?? true) {
            findings.append(SystemScanFinding(
                severity: .actionNeeded,
                title: "Runtime update checks are off",
                detail: "Enable runtime update checks so managed GPTK installs do not fall behind."
            ))
        }

        if !HomebrewRuntimeManager.isAvailable() {
            findings.append(SystemScanFinding(
                severity: .actionNeeded,
                title: "Homebrew is unavailable",
                detail: "Install Homebrew if you want one-click Wine 11 and DOSBox installs from inside GIACK GPTK."
            ))
        }

        let summary: String
        if findings.isEmpty {
            summary = "This Mac is configured correctly for the managed GPTK runtime and DOSBox workflows."
        } else {
            summary = "\(findings.count) item\(findings.count == 1 ? "" : "s") need attention before every runner path is fully ready."
        }

        return SystemScanReport(
            summary: summary,
            activeWineSummary: activeWineSummary,
            dosboxSummary: dosboxSummary,
            findings: findings
        )
    }

    private static func isAppleSiliconMac() -> Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return result == 0 && value == 1
    }
}
