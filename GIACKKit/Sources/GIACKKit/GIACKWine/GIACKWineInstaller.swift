//
//  GIACKWineInstaller.swift
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

public class GIACKWineInstaller {
    private static func requiredURL(_ value: String) -> URL {
        guard let url = URL(string: value) else {
            preconditionFailure("Invalid static URL constant: \(value)")
        }
        return url
    }

    /// Application Support root scoped by the active bundle identifier.
    public static let applicationFolder = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
    )[0].appending(path: Bundle.giackBundleIdentifier)

    /// Root folder that stores the installed runtime payload and helper files.
    public static let libraryFolder = applicationFolder.appending(path: "Libraries")

    /// URL to the installed `wine` `bin` directory.
    public static let binFolder: URL = libraryFolder.appending(path: "Wine").appending(path: "bin")

    private static let latestGPTKReleaseURL = requiredURL(
        "https://api.github.com/repos/Gcenx/game-porting-toolkit/releases/latest"
    )
    private static let latestGPTKReleasePageURL = requiredURL(
        "https://github.com/Gcenx/game-porting-toolkit/releases/latest"
    )
    private static let latestGPTKReleaseDownloadBaseURL = requiredURL(
        "https://github.com/Gcenx/game-porting-toolkit/releases/download/"
    )
    private static let legacyVersionPlistURL = requiredURL("https://data.getwhisky.app/Wine/GIACKWineVersion.plist")
    private static let legacyRuntimeArchiveURL = requiredURL("https://data.getwhisky.app/Wine/Libraries.tar.gz")
    private static let session = URLSession(configuration: .ephemeral)
    private static let localVersionPlistURL = libraryFolder
        .appending(path: "GIACKWineVersion")
        .appendingPathExtension("plist")
    private static let localRuntimeCandidates = [
        URL(fileURLWithPath: "/Applications/Game Porting Toolkit.app")
            .appending(path: "Contents")
            .appending(path: "Resources")
            .appending(path: "wine"),
        URL(fileURLWithPath: "/Volumes/Game Porting Toolkit")
            .appending(path: "Game Porting Toolkit.app")
            .appending(path: "Contents")
            .appending(path: "Resources")
            .appending(path: "wine"),
        URL(fileURLWithPath: "/Volumes/Evaluation environment for Windows games 3.0")
            .appending(path: "Game Porting Toolkit.app")
            .appending(path: "Contents")
            .appending(path: "Resources")
            .appending(path: "wine")
    ]
    private static let localRedistCandidates = [
        URL(fileURLWithPath: "/Volumes/Evaluation environment for Windows games 3.0/redist"),
        URL(fileURLWithPath: "/Volumes/Game Porting Toolkit/redist")
    ]

    /// Resolved runtime metadata used by setup, settings, and update checks.
    public struct RuntimePackage {
        public let downloadURL: URL
        public let version: SemanticVersion
        public let source: String
        public let releaseName: String

        public init(downloadURL: URL, version: SemanticVersion, source: String, releaseName: String) {
            self.downloadURL = downloadURL
            self.version = version
            self.source = source
            self.releaseName = releaseName
        }
    }

    /// User-selectable Wine runtime families exposed in Settings.
    ///
    /// The managed GPTK runtime remains the default because it is the path that
    /// carries app-managed extras such as DXVK and Winetricks. Homebrew-backed
    /// Wine selections are offered for users who want upstream Wine 11 builds.
    public enum RuntimeSelection: String, CaseIterable, Sendable, Codable {
        case gptkManaged
        case wineStable
        case wineDevel
        case wineStaging

        public var displayName: String {
            switch self {
            case .gptkManaged:
                return "Managed GPTK Runtime"
            case .wineStable:
                return "Wine 11 Stable"
            case .wineDevel:
                return "Wine Devel"
            case .wineStaging:
                return "Wine Staging"
            }
        }

        public var summary: String {
            switch self {
            case .gptkManaged:
                return "App-managed Game Porting Toolkit runtime with integrated extras."
            case .wineStable:
                return "Homebrew-installed stable Wine build from the official WineHQ macOS packages."
            case .wineDevel:
                return "Homebrew-installed development Wine build for newer upstream fixes."
            case .wineStaging:
                return "Homebrew-installed staging Wine build with staging patches."
            }
        }

        fileprivate var externalRuntime: ExternalWineRuntime? {
            switch self {
            case .gptkManaged:
                return nil
            case .wineStable:
                return .stable
            case .wineDevel:
                return .devel
            case .wineStaging:
                return .staging
            }
        }
    }

    public struct ActiveWineRuntime: Sendable {
        public let selection: RuntimeSelection
        public let displayName: String
        public let versionSummary: String
        public let sourceSummary: String
        public let wineBinaryURL: URL
        public let wineserverBinaryURL: URL
        public let binDirectoryURL: URL
        public let supportsManagedExtras: Bool
    }

    private static let selectedRuntimeKey = "selectedWineRuntimeSelection"

    public static func selectedRuntimeSelection() -> RuntimeSelection {
        if let rawValue = UserDefaults.standard.string(forKey: selectedRuntimeKey),
           let selection = RuntimeSelection(rawValue: rawValue) {
            return selection
        }
        return .gptkManaged
    }

    public static func setSelectedRuntimeSelection(_ selection: RuntimeSelection) {
        UserDefaults.standard.set(selection.rawValue, forKey: selectedRuntimeKey)
    }

    public static func currentWineRuntime() -> ActiveWineRuntime? {
        if let selectedRuntime = runtimeForSelection(selectedRuntimeSelection()) {
            return selectedRuntime
        }
        return runtimeForSelection(.gptkManaged)
    }

    public static func activeWineRuntimeSummary() -> String {
        guard let runtime = currentWineRuntime() else {
            return "No Wine runtime installed"
        }
        return "\(runtime.displayName) · \(runtime.versionSummary) · \(runtime.sourceSummary)"
    }

    public static func wineBinaryURL() -> URL? {
        currentWineRuntime()?.wineBinaryURL
    }

    public static func wineBinaryURL(for selection: RuntimeSelection) -> URL? {
        runtimeForSelection(selection)?.wineBinaryURL
    }

    public static func wineserverBinaryURL() -> URL? {
        currentWineRuntime()?.wineserverBinaryURL
    }

    public static func wineserverBinaryURL(for selection: RuntimeSelection) -> URL? {
        runtimeForSelection(selection)?.wineserverBinaryURL
    }

    public static func wineBinDirectoryURL() -> URL? {
        currentWineRuntime()?.binDirectoryURL
    }

    public static func wineBinDirectoryURL(for selection: RuntimeSelection) -> URL? {
        runtimeForSelection(selection)?.binDirectoryURL
    }

    /// Resolve an installed runtime for the given selection, or nil if not installed.
    ///
    /// This is the per-bottle-safe variant of `currentWineRuntime()`. The Config tab
    /// and the per-bottle status cards use this to surface install state without
    /// mutating global `UserDefaults` selection.
    public static func runtime(for selection: RuntimeSelection) -> ActiveWineRuntime? {
        runtimeForSelection(selection)
    }

    /// Whether the requested runtime is currently installed and executable on this Mac.
    ///
    /// For `.gptkManaged`, this checks the managed `Wine/bin/wine64` path. For Homebrew
    /// selections, it checks the corresponding `*.app` bundle under `/Applications`.
    public static func isRuntimeInstalled(for selection: RuntimeSelection) -> Bool {
        runtimeForSelection(selection) != nil
    }

    /// Human-readable summary for settings and library detail views.
    ///
    /// Returns `DisplayName · Version · Source` when installed, otherwise
    /// `DisplayName · Not installed` so the UI can guide the user to
    /// Settings → Runners without leaving the detail blank.
    public static func runtimeSummary(for selection: RuntimeSelection) -> String {
        if let runtime = runtimeForSelection(selection) {
            return "\(runtime.displayName) · \(runtime.versionSummary) · \(runtime.sourceSummary)"
        }
        return "\(selection.displayName) · Not installed"
    }

    public static func wineToolBinaryURL(named name: String) -> URL? {
        if currentWineRuntime()?.supportsManagedExtras == true {
            let candidate = binFolder.appending(path: name)
            if FileManager.default.isExecutableFile(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }
        }

        guard let externalRuntime = currentWineRuntime()?.selection.externalRuntime else {
            return nil
        }
        return externalRuntime.toolBinaryURL(named: name)
    }

    public static func wineToolBinaryURL(named name: String, for selection: RuntimeSelection) -> URL? {
        let runtime = runtimeForSelection(selection)
        if runtime?.supportsManagedExtras == true {
            let candidate = binFolder.appending(path: name)
            if FileManager.default.isExecutableFile(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }
        }
        guard let externalRuntime = runtime?.selection.externalRuntime else {
            return nil
        }
        return externalRuntime.toolBinaryURL(named: name)
    }

    public static func supportsManagedRuntimeExtras() -> Bool {
        currentWineRuntime()?.supportsManagedExtras ?? false
    }

    public static func isGIACKWineInstalled() -> Bool {
        currentWineRuntime() != nil
    }

    /// Installs a runtime from either an archive or a local extracted directory.
    ///
    /// The installation process follows these steps:
    /// 1. Backs up existing "extras" (like DXVK and Winetricks) to a temporary folder.
    /// 2. Removes the existing runtime library folder to ensure a clean slate.
    /// 3. Extracts the new runtime payload (via Tar if it's an archive).
    /// 4. Applies any available local redist overlays (custom library overrides).
    /// 5. Restores the backed-up extras into the new runtime.
    /// 6. Saves the installation version and source metadata.
    ///
    /// If any step fails, the installer attempts to restore the backed-up extras
    /// to avoid leaving the user with a broken installation.
    @discardableResult
    public static func install(
        from archiveURL: URL,
        versionOverride: SemanticVersion? = nil,
        source: String = "Unknown",
        releaseName: String? = nil
    ) -> Bool {
        let fileManager = FileManager.default
        let extractionFolder = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
        let preservedExtrasFolder = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
        let shouldCleanupArchive = shouldDeleteInstallerArtifact(at: archiveURL, fileManager: fileManager)
        var isDirectory = ObjCBool(false)
        let archiveExists = fileManager.fileExists(atPath: archiveURL.path, isDirectory: &isDirectory)
        var installSucceeded = false

        do {
            try preserveRuntimeExtrasIfNeeded(from: libraryFolder, to: preservedExtrasFolder)
            if fileManager.fileExists(atPath: libraryFolder.path) {
                try fileManager.removeItem(at: libraryFolder)
            }
            try fileManager.createDirectory(at: applicationFolder, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: libraryFolder, withIntermediateDirectories: true)

            if archiveExists && isDirectory.boolValue {
                try installRuntimePayload(from: archiveURL)
            } else {
                try fileManager.createDirectory(at: extractionFolder, withIntermediateDirectories: true)
                try Tar.untar(tarBall: archiveURL, toURL: extractionFolder)
                try installRuntimePayload(from: extractionFolder)
            }
            try applyLocalRedistOverlayIfPresent()
            try restoreRuntimeExtrasIfNeeded(from: preservedExtrasFolder)

            if let version = versionOverride {
                try saveVersion(version: version, source: source, releaseName: releaseName)
            } else if !fileManager.fileExists(atPath: localVersionPlistURL.path) {
                // Some archives only provide wine binaries and no version metadata.
                try saveVersion(version: SemanticVersion(0, 0, 0), source: source, releaseName: releaseName)
            }
            installSucceeded = true
        } catch {
            print("Failed to install runtime: \(error)")
            do {
                if !fileManager.fileExists(atPath: libraryFolder.path) {
                    try fileManager.createDirectory(at: libraryFolder, withIntermediateDirectories: true)
                }
                try restoreRuntimeExtrasIfNeeded(from: preservedExtrasFolder)
            } catch {
                print("Failed to restore preserved runtime extras: \(error)")
            }
        }

        do {
            if fileManager.fileExists(atPath: extractionFolder.path) {
                try fileManager.removeItem(at: extractionFolder)
            }
            if fileManager.fileExists(atPath: preservedExtrasFolder.path) {
                try fileManager.removeItem(at: preservedExtrasFolder)
            }
            if shouldCleanupArchive, fileManager.fileExists(atPath: archiveURL.path) {
                try fileManager.removeItem(at: archiveURL)
            }
        } catch {
            print("Failed to clean installer files: \(error)")
        }
        return installSucceeded
    }

    public static func uninstall() {
        do {
            try FileManager.default.removeItem(at: libraryFolder)
        } catch {
            print("Failed to uninstall runtime: \(error)")
        }
    }

    /// Resolves the best available runtime by comparing remote maintained GPTK
    /// releases with any mounted local toolkit installations.
    public static func latestRuntimePackage() async -> RuntimePackage? {
        let localPackage = prefersLocalRuntime() ? localRuntimePackage() : nil

        if let remotePackage = await fetchLatestGPTKPackage() {
            if let localPackage {
                return localPackage.version >= remotePackage.version ? localPackage : remotePackage
            }
            return remotePackage
        }

        if let localPackage {
            return localPackage
        }

        return await fetchLegacyPackage()
    }

    public static func shouldUpdateGIACKWine() async -> (Bool, SemanticVersion) {
        guard selectedRuntimeSelection() == .gptkManaged else {
            return (false, SemanticVersion(0, 0, 0))
        }

        let localVersion = giackWineVersion()
        let remoteVersion = await latestRuntimePackage()?.version

        if let localVersion = localVersion, let remoteVersion = remoteVersion, localVersion < remoteVersion {
            return (true, remoteVersion)
        }

        return (false, SemanticVersion(0, 0, 0))
    }

    /// Current managed runtime version. Prefer `giackWineVersion()`; `whiskyWineVersion()` remains for compatibility.
    public static func giackWineVersion() -> SemanticVersion? {
        runtimeVersionInfo()?.version
    }

    @available(*, deprecated, renamed: "giackWineVersion")
    public static func whiskyWineVersion() -> SemanticVersion? {
        giackWineVersion()
    }

    public static func runtimeReleaseName() -> String? {
        runtimeVersionInfo()?.releaseName
    }

    public static func runtimeSource() -> String? {
        runtimeVersionInfo()?.source
    }

    public static func legacyRuntimeDownloadURL() -> URL {
        legacyRuntimeArchiveURL
    }

    public static func hasDXVKRuntime() -> Bool {
        guard supportsManagedRuntimeExtras() else {
            return false
        }
        return FileManager.default.fileExists(
            atPath: libraryFolder.appending(path: "DXVK").appending(path: "x64").path
        )
    }

    public static func hasWinetricksRuntime() -> Bool {
        guard supportsManagedRuntimeExtras() else {
            return false
        }
        return FileManager.default.fileExists(atPath: libraryFolder.appending(path: "winetricks").path)
    }

    /// Detects a directly usable local GPTK runtime on disk, including mounted
    /// volumes that expose `Game Porting Toolkit.app` outside `/Applications`.
    ///
    /// The search order is:
    /// 1. Environment variable `WHISKY_GPTK_LOCAL_RUNTIME_PATH`.
    /// 2. Known local candidate paths (e.g., `/Applications/Game Porting Toolkit.app`).
    /// 3. Root-level search of all mounted volumes in `/Volumes`.
    /// 4. Deep nested search in `/Volumes` for any directory named `Game Porting Toolkit.app`.
    public static func localRuntimePackage() -> RuntimePackage? {
        if let environmentPath = ProcessInfo.processInfo.environment["WHISKY_GPTK_LOCAL_RUNTIME_PATH"] {
            let candidate = URL(fileURLWithPath: environmentPath)
            if hasWineBinary(in: candidate) {
                return packageForLocalRuntime(at: candidate)
            }
        }

        for candidate in localRuntimeCandidates where hasWineBinary(in: candidate) {
            return packageForLocalRuntime(at: candidate)
        }

        let volumesRoot = URL(fileURLWithPath: "/Volumes")
        if let volumeURLs = try? FileManager.default.contentsOfDirectory(
            at: volumesRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for volumeURL in volumeURLs {
                for candidate in runtimeCandidates(for: volumeURL) where hasWineBinary(in: candidate) {
                    return packageForLocalRuntime(at: candidate)
                }
            }
        }

        if let discoveredRuntime = discoverNestedRuntime(in: URL(fileURLWithPath: "/Volumes")) {
            return packageForLocalRuntime(at: discoveredRuntime)
        }

        return nil
    }

    private static func runtimeForSelection(_ selection: RuntimeSelection) -> ActiveWineRuntime? {
        switch selection {
        case .gptkManaged:
            return managedRuntime()
        case .wineStable, .wineDevel, .wineStaging:
            guard let externalRuntime = selection.externalRuntime else {
                return nil
            }
            return externalRuntimeInfo(for: externalRuntime, selection: selection)
        }
    }

    private static func managedRuntime() -> ActiveWineRuntime? {
        let wineBinaryCandidates = [
            binFolder.appending(path: "wine64"),
            binFolder.appending(path: "wine")
        ]
        let wineserverBinaryURL = binFolder.appending(path: "wineserver")

        guard let wineBinaryURL = wineBinaryCandidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path(percentEncoded: false))
        }),
              FileManager.default.isExecutableFile(atPath: wineserverBinaryURL.path(percentEncoded: false)) else {
            return nil
        }

        let versionSummary = runtimeVersionInfo()?.version.description ?? "Unknown version"
        let sourceSummary = runtimeSource() ?? "Managed GPTK Runtime"
        return ActiveWineRuntime(
            selection: .gptkManaged,
            displayName: "GPTK Wine",
            versionSummary: versionSummary,
            sourceSummary: sourceSummary,
            wineBinaryURL: wineBinaryURL,
            wineserverBinaryURL: wineserverBinaryURL,
            binDirectoryURL: binFolder,
            supportsManagedExtras: true
        )
    }

    private static func externalRuntimeInfo(
        for runtime: ExternalWineRuntime,
        selection: RuntimeSelection
    ) -> ActiveWineRuntime? {
        guard let wineBinaryURL = runtime.wineBinaryURL,
              let wineserverBinaryURL = runtime.wineserverBinaryURL,
              let binDirectoryURL = runtime.binDirectoryURL else {
            return nil
        }

        return ActiveWineRuntime(
            selection: selection,
            displayName: runtime.displayName,
            versionSummary: runtime.installedVersion ?? "Installed",
            sourceSummary: "Homebrew Cask",
            wineBinaryURL: wineBinaryURL,
            wineserverBinaryURL: wineserverBinaryURL,
            binDirectoryURL: binDirectoryURL,
            supportsManagedExtras: false
        )
    }

    private static func runtimeVersionInfo() -> GIACKWineVersion? {
        do {
            let decoder = PropertyListDecoder()
            let data = try Data(contentsOf: localVersionPlistURL)
            return try decoder.decode(GIACKWineVersion.self, from: data)
        } catch {
            return nil
        }
    }

    private static func fetchLatestGPTKPackage() async -> RuntimePackage? {
        if let release = await fetchLatestGPTKRelease(),
           let package = packageForGitHubRelease(release) {
            return package
        }
        return await fetchLatestGPTKPackageFromRedirect()
    }

    private static func fetchLatestGPTKRelease() async -> GitHubRelease? {
        guard let data = await fetchData(from: latestGPTKReleaseURL) else { return nil }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(GitHubRelease.self, from: data)
        } catch {
            print(error)
            return nil
        }
    }

    private static func packageForGitHubRelease(_ release: GitHubRelease) -> RuntimePackage? {
        guard let asset = release.assets.first(where: { asset in
            asset.name.hasPrefix("game-porting-toolkit-")
                && (asset.name.hasSuffix(".tar.xz") || asset.name.hasSuffix(".tar.gz"))
        }), let downloadURL = URL(string: asset.browserDownloadURL) else {
            return nil
        }

        let version = parseVersion(from: [asset.name, release.tagName, release.name]) ?? SemanticVersion(0, 0, 0)
        return RuntimePackage(
            downloadURL: downloadURL,
            version: version,
            source: "Gcenx/game-porting-toolkit",
            releaseName: release.name
        )
    }

    private static func fetchLatestGPTKPackageFromRedirect() async -> RuntimePackage? {
        guard let releaseURL = await resolveFinalURL(for: latestGPTKReleasePageURL) else {
            return nil
        }

        let tagName = releaseURL.lastPathComponent
        let versionSuffix = tagName.replacingOccurrences(of: "Game-Porting-Toolkit-", with: "")
        guard !versionSuffix.isEmpty, versionSuffix != tagName else {
            return nil
        }

        let assetNames = [
            "game-porting-toolkit-\(versionSuffix).tar.xz",
            "game-porting-toolkit-\(versionSuffix).tar.gz"
        ]

        for assetName in assetNames {
            let assetURL = latestGPTKReleaseDownloadBaseURL
                .appending(path: tagName)
                .appending(path: assetName)
            if await resolveFinalURL(for: assetURL) != nil {
                let version = parseVersion(from: [assetName, tagName, versionSuffix]) ?? SemanticVersion(0, 0, 0)
                return RuntimePackage(
                    downloadURL: assetURL,
                    version: version,
                    source: "Gcenx/game-porting-toolkit",
                    releaseName: tagName.replacingOccurrences(of: "Game-Porting-Toolkit-", with: "Game Porting Toolkit ")
                )
            }
        }

        return nil
    }

    private static func fetchLegacyPackage() async -> RuntimePackage? {
        guard let data = await fetchData(from: legacyVersionPlistURL) else { return nil }

        do {
            let decoder = PropertyListDecoder()
            let info = try decoder.decode(GIACKWineVersion.self, from: data)
            return RuntimePackage(
                downloadURL: legacyRuntimeArchiveURL,
                version: info.version,
                source: "Legacy Runtime Feed",
                releaseName: "Legacy Runtime \(info.version)"
            )
        } catch {
            print(error)
            return nil
        }
    }

    private static func fetchData(from url: URL) async -> Data? {
        guard let (data, _) = await fetchResponse(from: url) else { return nil }
        return data
    }

    private static func resolveFinalURL(for url: URL) async -> URL? {
        if let (_, response) = await fetchResponse(from: url, method: "HEAD") {
            return response.url
        }
        if let (_, response) = await fetchResponse(from: url, method: "GET") {
            return response.url
        }
        return nil
    }

    private static func fetchResponse(
        from url: URL,
        method: String = "GET",
        attempts: Int = 3
    ) async -> (Data, URLResponse)? {
        for attempt in 0..<attempts {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 30
            if url.host == "api.github.com" {
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("GIACKGPTK", forHTTPHeaderField: "User-Agent")
                request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            }

            do {
                let (data, response) = try await session.data(for: request)
                if let response = response as? HTTPURLResponse,
                   !(200...299).contains(response.statusCode) {
                    throw RuntimeInstallError.requestFailed(url: url, statusCode: response.statusCode)
                }
                return (data, response)
            } catch {
                if attempt == attempts - 1 {
                    print(error)
                    return nil
                }
                try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 1_000_000_000)
            }
        }

        return nil
    }

    private static func saveVersion(version: SemanticVersion, source: String, releaseName: String?) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(GIACKWineVersion(version: version, source: source, releaseName: releaseName))
        try data.write(to: localVersionPlistURL)
    }

    private static func installRuntimePayload(from extractedArchiveURL: URL) throws {
        let fileManager = FileManager.default

        if hasWineBinary(in: extractedArchiveURL) {
            try copyWinePayload(from: extractedArchiveURL)
            return
        }

        let legacyLibrariesURL = extractedArchiveURL.appending(path: "Libraries")
        if fileManager.fileExists(atPath: legacyLibrariesURL.path) {
            try fileManager.moveItem(at: legacyLibrariesURL, to: libraryFolder)
            return
        }

        guard let winePayloadURL = locateWinePayload(in: extractedArchiveURL) else {
            throw RuntimeInstallError.unsupportedArchiveLayout
        }

        try copyWinePayload(from: winePayloadURL)
    }

    private static func locateWinePayload(in extractedArchiveURL: URL) -> URL? {
        let gptkPath = extractedArchiveURL
            .appending(path: "Game Porting Toolkit.app")
            .appending(path: "Contents")
            .appending(path: "Resources")
            .appending(path: "wine")
        if FileManager.default.fileExists(atPath: gptkPath.appending(path: "bin").appending(path: "wine64").path) {
            return gptkPath
        }

        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        guard let enumerator = FileManager.default.enumerator(
            at: extractedArchiveURL,
            includingPropertiesForKeys: nil,
            options: options
        ) else {
            return nil
        }

        for case let url as URL in enumerator {
            guard url.lastPathComponent == "wine" else { continue }
            if FileManager.default.fileExists(atPath: url.appending(path: "bin").appending(path: "wine64").path) {
                return url
            }
        }
        return nil
    }

    private static func copyWinePayload(from source: URL) throws {
        let fileManager = FileManager.default
        let destination = libraryFolder.appending(path: "Wine")
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private static func applyLocalRedistOverlayIfPresent() throws {
        guard let redistURL = localRedistPath() else {
            return
        }
        let sourceLibURL = redistURL.appending(path: "lib")
        guard FileManager.default.fileExists(atPath: sourceLibURL.path) else {
            return
        }
        let destinationLibURL = libraryFolder.appending(path: "Wine").appending(path: "lib")
        try mergeDirectoryContents(from: sourceLibURL, to: destinationLibURL)
    }

    private static func localRedistPath() -> URL? {
        if let environmentPath = ProcessInfo.processInfo.environment["WHISKY_GPTK_LOCAL_REDIST_PATH"] {
            let candidate = URL(fileURLWithPath: environmentPath)
            let winePath = candidate.appending(path: "lib").appending(path: "wine")
            if FileManager.default.fileExists(atPath: winePath.path) {
                return candidate
            }
        }

        for candidate in localRedistCandidates {
            let winePath = candidate.appending(path: "lib").appending(path: "wine")
            if FileManager.default.fileExists(atPath: winePath.path) {
                return candidate
            }
        }

        let volumesRoot = URL(fileURLWithPath: "/Volumes")
        if let volumeURLs = try? FileManager.default.contentsOfDirectory(
            at: volumesRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for volumeURL in volumeURLs {
                for candidate in redistCandidates(for: volumeURL) {
                    let winePath = candidate.appending(path: "lib").appending(path: "wine")
                    if FileManager.default.fileExists(atPath: winePath.path) {
                        return candidate
                    }
                }
            }
        }

        return discoverNestedRedist(in: URL(fileURLWithPath: "/Volumes"))
    }

    private static func discoverNestedRuntime(in root: URL) -> URL? {
        for appURL in discoverNestedDirectories(named: "Game Porting Toolkit.app", in: root, maxDepth: 4) {
            let candidate = appURL
                .appending(path: "Contents")
                .appending(path: "Resources")
                .appending(path: "wine")
            if hasWineBinary(in: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func discoverNestedRedist(in root: URL) -> URL? {
        for candidate in discoverNestedDirectories(named: "redist", in: root, maxDepth: 4) {
            let winePath = candidate.appending(path: "lib").appending(path: "wine")
            if FileManager.default.fileExists(atPath: winePath.path) {
                return candidate
            }
        }
        return nil
    }

    /// Recursively searches for directories with a specific name within a root directory,
    /// limiting the search depth to prevent excessive filesystem traversal.
    ///
    /// This is used to find GPTK runtimes or redist folders that may be buried within
    /// complex disk image structures.
    private static func discoverNestedDirectories(named name: String, in root: URL, maxDepth: Int) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let rootDepth = root.pathComponents.count
        var matches: [URL] = []

        for case let url as URL in enumerator {
            let depth = url.pathComponents.count - rootDepth
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            guard url.lastPathComponent == name else { continue }
            matches.append(url)
            enumerator.skipDescendants()
        }

        return matches
    }

    private static func mergeDirectoryContents(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [source.path(percentEncoded: false), destination.path(percentEncoded: false)]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let message = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw RuntimeInstallError.copyOverlayFailed(message: message)
        }
    }

    private static func hasWineBinary(in folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: "bin").appending(path: "wine64").path)
    }

    private static func runtimeCandidates(for volumeURL: URL) -> [URL] {
        [
            volumeURL,
            volumeURL.appending(path: "Applications"),
            volumeURL.appending(path: "Games.localized")
        ].map { candidateRoot in
            candidateRoot
                .appending(path: "Game Porting Toolkit.app")
                .appending(path: "Contents")
                .appending(path: "Resources")
                .appending(path: "wine")
        }
    }

    private static func redistCandidates(for volumeURL: URL) -> [URL] {
        [
            volumeURL.appending(path: "redist"),
            volumeURL.appending(path: "Applications").appending(path: "redist"),
            volumeURL.appending(path: "Games.localized").appending(path: "redist")
        ]
    }

    private static func packageForLocalRuntime(at localWineFolder: URL) -> RuntimePackage {
        let runtimeBundleInfo = localRuntimeBundleInfo(for: localWineFolder)
        let nameComponents = [
            localWineFolder.path(percentEncoded: false),
            localWineFolder.deletingLastPathComponent().lastPathComponent,
            localWineFolder.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent,
            runtimeBundleInfo?.versionString ?? ""
        ]
        let version = parseVersion(from: nameComponents) ?? SemanticVersion(0, 0, 0)
        return RuntimePackage(
            downloadURL: localWineFolder,
            version: version,
            source: "Local Game Porting Toolkit",
            releaseName: runtimeBundleInfo?.releaseName ?? "Local GPTK \(version)"
        )
    }

    private static func localRuntimeBundleInfo(for localWineFolder: URL) -> (versionString: String, releaseName: String)? {
        let appURL = localWineFolder
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoPlistURL = appURL.appending(path: "Contents").appending(path: "Info").appendingPathExtension("plist")

        guard let data = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let versionString = (plist["CFBundleShortVersionString"] as? String) ?? (plist["CFBundleVersion"] as? String)
        else {
            return nil
        }

        let bundleName = (plist["CFBundleName"] as? String) ?? "Game Porting Toolkit"
        return (versionString, "\(bundleName) \(versionString)")
    }

    private static func shouldDeleteInstallerArtifact(at url: URL, fileManager: FileManager) -> Bool {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }
        return url.path.hasPrefix(fileManager.temporaryDirectory.path)
    }

    private static func prefersLocalRuntime() -> Bool {
        if let preference = UserDefaults.standard.object(forKey: "preferLocalGPTKRuntime") as? Bool {
            return preference
        }
        return true
    }

    private static func preserveRuntimeExtrasIfNeeded(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        let runtimeExtras = ["winetricks", "verbs.txt", "DXVK"]
        var hasAnyExtras = false

        for runtimeExtra in runtimeExtras {
            let sourceURL = source.appending(path: runtimeExtra)
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
            if !hasAnyExtras {
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                hasAnyExtras = true
            }
            try fileManager.copyItem(at: sourceURL, to: destination.appending(path: runtimeExtra))
        }
    }

    private static func restoreRuntimeExtrasIfNeeded(from source: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path) else {
            return
        }
        let runtimeExtras = ["winetricks", "verbs.txt", "DXVK"]
        for runtimeExtra in runtimeExtras {
            let sourceURL = source.appending(path: runtimeExtra)
            let destinationURL = libraryFolder.appending(path: runtimeExtra)
            guard fileManager.fileExists(atPath: sourceURL.path),
                  !fileManager.fileExists(atPath: destinationURL.path) else {
                continue
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    private static func parseVersion(from strings: [String]) -> SemanticVersion? {
        for string in strings {
            if let version = parseVersion(from: string) {
                return version
            }
        }
        return nil
    }

    private static func parseVersion(from string: String) -> SemanticVersion? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+)\.(\d+)(?:[.-](\d+))?"#) else {
            return nil
        }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let match = regex.firstMatch(in: string, options: [], range: range) else {
            return nil
        }

        func value(_ index: Int) -> Int? {
            guard index < match.numberOfRanges else { return nil }
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: string) else { return nil }
            return Int(string[swiftRange])
        }

        guard let major = value(1), let minor = value(2) else { return nil }
        let patch = value(3) ?? 0
        return SemanticVersion(major, minor, patch)
    }

    private struct GitHubRelease: Codable {
        let tagName: String
        let name: String
        let assets: [GitHubAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case assets
        }
    }

    private struct GitHubAsset: Codable {
        let name: String
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    private enum RuntimeInstallError: Error {
        case unsupportedArchiveLayout
        case copyOverlayFailed(message: String)
        case requestFailed(url: URL, statusCode: Int)
    }
}

struct GIACKWineVersion: Codable {
    var version: SemanticVersion = SemanticVersion(1, 0, 0)
    var source: String = "GIACK GPTK"
    var releaseName: String?

    enum CodingKeys: String, CodingKey {
        case version
        case source
        case releaseName
    }

    init(version: SemanticVersion = SemanticVersion(1, 0, 0), source: String = "GIACK GPTK", releaseName: String? = nil) {
        self.version = version
        self.source = source
        self.releaseName = releaseName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(SemanticVersion.self, forKey: .version) ?? SemanticVersion(1, 0, 0)
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "GIACK GPTK"
        releaseName = try container.decodeIfPresent(String.self, forKey: .releaseName)
    }
}
