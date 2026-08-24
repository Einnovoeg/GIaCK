//
//  UpdateManager.swift
//  GIACK
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
import Observation
import os.log
import AppKit
import GIACKKit

@MainActor
@Observable
final class UpdateManager {
    static let shared = UpdateManager()

    private let logger = Logger(subsystem: Bundle.giackBundleIdentifier, category: "UpdateManager")
    private let session: URLSession
    private var updateCheckTask: Task<Void, Never>?

    enum UpdateComponent: String, CaseIterable, Identifiable {
        case giackApp
        case wineRuntime
        case dosbox
        case applicationDatabase

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .giackApp: "GIACK App"
            case .wineRuntime: "Wine Runtime"
            case .dosbox: "DOSBox"
            case .applicationDatabase: "Application Database"
            }
        }
    }

    struct UpdateStatus: Identifiable {
        let id = UUID()
        let component: UpdateComponent
        var isChecking: Bool = false
        var isUpdating: Bool = false
        var hasUpdate: Bool = false
        var currentVersion: String?
        var latestVersion: String?
        var lastChecked: Date?
        var errorMessage: String?
        var progress: Double?
    }

    var statuses: [UpdateComponent: UpdateStatus] = [:]
    var lastFullCheck: Date?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)

        for component in UpdateComponent.allCases {
            statuses[component] = UpdateStatus(component: component)
        }
    }

    var overallStatus: String {
        let checking = statuses.values.filter { $0.isChecking }.count
        let updating = statuses.values.filter { $0.isUpdating }.count
        let available = statuses.values.filter { $0.hasUpdate }.count

        if checking > 0 { return "Checking for updates..." }
        if updating > 0 { return "Updating \(updating) component(s)..." }
        if available > 0 { return "\(available) update(s) available" }
        return "All components up to date"
    }

    var hasAnyUpdate: Bool {
        statuses.values.contains { $0.hasUpdate }
    }

    func checkAllUpdates() async {
        await withTaskGroup(of: Void.self) { group in
            for component in UpdateComponent.allCases {
                group.addTask { [weak self] in
                    await self?.checkUpdate(for: component)
                }
            }
        }
        lastFullCheck = Date()
    }

    func checkUpdate(for component: UpdateComponent) async {
        var status = statuses[component] ?? UpdateStatus(component: component)
        status.isChecking = true
        status.errorMessage = nil
        statuses[component] = status

        do {
            let result: (current: String?, latest: String?)

            switch component {
            case .giackApp:
                result = await checkGIACKAppUpdate()
            case .wineRuntime:
                result = await checkWineRuntimeUpdate()
            case .dosbox:
                result = await checkDOSBoxUpdate()
            case .applicationDatabase:
                result = await checkDatabaseUpdate()
            }

            status.currentVersion = result.current
            status.latestVersion = result.latest
            status.hasUpdate = result.current != nil && result.latest != nil
                && compareVersions(result.current!, result.latest!) == .orderedAscending
            status.lastChecked = Date()
        } catch {
            status.errorMessage = error.localizedDescription
            status.hasUpdate = false
        }

        status.isChecking = false
        statuses[component] = status
    }

    func updateComponent(_ component: UpdateComponent) async throws {
        var status = statuses[component] ?? UpdateStatus(component: component)
        guard !status.isUpdating else { return }

        status.isUpdating = true
        status.progress = 0
        statuses[component] = status

        do {
            switch component {
            case .giackApp:
                try await updateGIACKApp()
            case .wineRuntime:
                try await updateWineRuntime()
            case .dosbox:
                try await updateDOSBox()
            case .applicationDatabase:
                try await updateDatabase()
            }

            status.isUpdating = false
            status.hasUpdate = false
            status.progress = nil
            status.currentVersion = status.latestVersion
        } catch {
            status.isUpdating = false
            status.errorMessage = error.localizedDescription
            status.progress = nil
        }

        statuses[component] = status
    }

    // MARK: - GIACK App

    private func checkGIACKAppUpdate() async -> (current: String?, latest: String?) {
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

        guard let url = ProjectInfo.latestReleaseAPIURL else {
            return (current, nil)
        }

        do {
            let (data, _) = try await session.data(from: url)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latest = release.tagName.replacingOccurrences(of: "v", with: "")
            return (current, latest)
        } catch {
            logger.error("Failed to check GIACK app update: \(error.localizedDescription)")
            return (current, nil)
        }
    }

    private func updateGIACKApp() async throws {
        guard let url = ProjectInfo.latestReleaseAPIURL else {
            throw UpdateError.invalidURL
        }

        let (data, _) = try await session.data(from: url)
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

        guard let downloadAsset = release.assets.first(where: { $0.name.hasSuffix(".zip") }),
              let downloadURL = URL(string: downloadAsset.browserDownloadURL) else {
            throw UpdateError.noDownloadAvailable
        }

        await MainActor.run {
            NSWorkspace.shared.open(downloadURL)
        }
    }

    // MARK: - Wine Runtime

    private func checkWineRuntimeUpdate() async -> (current: String?, latest: String?) {
        let current = await MainActor.run {
            GIACKWineInstaller.giackWineVersion()?.description
        }

        let latestPackage = await GIACKWineInstaller.latestRuntimePackage()
        let latest = latestPackage?.version.description

        return (current, latest)
    }

    private func updateWineRuntime() async throws {
        guard let package = try await GIACKWineInstaller.latestRuntimePackage() else {
            throw UpdateError.noDownloadAvailable
        }
        try await GIACKWineInstaller.install(
            from: package.downloadURL,
            versionOverride: package.version,
            source: package.source,
            releaseName: package.releaseName
        )
    }

    // MARK: - DOSBox

    private func checkDOSBoxUpdate() async -> (current: String?, latest: String?) {
        let current = try? await DOSBox.version()

        guard let brewPath = findBrew() else {
            return (current, nil)
        }

        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: brewPath)
            process.arguments = ["info", "--cask", "dosbox-staging", "--json=v2"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return (current, nil) }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let casks = json?["casks"] as? [[String: Any]]
            let dosboxCask = casks?.first

            let latest = dosboxCask?["version"] as? String
            return (current, latest)
        } catch {
            logger.error("Failed to check DOSBox update: \(error.localizedDescription)")
            return (current, nil)
        }
    }

    private func updateDOSBox() async throws {
        guard let brewPath = findBrew() else {
            throw UpdateError.homebrewNotAvailable
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: brewPath)
        process.arguments = ["upgrade", "--cask", "dosbox-staging"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw UpdateError.installFailed("DOSBox upgrade failed")
        }
    }

    // MARK: - Application Database

    private func checkDatabaseUpdate() async -> (current: String?, latest: String?) {
        let localVersion = UserDefaults.standard.string(forKey: "applicationDatabaseVersion")
        let localDate = UserDefaults.standard.object(forKey: "applicationDatabaseLastUpdated") as? Date

        guard let url = ProjectInfo.applicationDatabaseURL else {
            return (localVersion, nil)
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"

            let ( _, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               let lastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified") {
                return (localVersion ?? localDate?.description, lastModified)
            }
            return (localVersion, "latest")
        } catch {
            logger.error("Failed to check database update: \(error.localizedDescription)")
            return (localVersion, nil)
        }
    }

    private func updateDatabase() async throws {
        guard let url = ProjectInfo.applicationDatabaseURL else {
            throw UpdateError.invalidURL
        }

        let (data, _) = try await session.data(from: url)

        let cacheDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: Bundle.giackBundleIdentifier)
            .appending(path: "Cache")

        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let dbFile = cacheDir.appending(path: "ApplicationDatabase.json")
        try data.write(to: dbFile)

        UserDefaults.standard.set(Date().description, forKey: "applicationDatabaseVersion")
        UserDefaults.standard.set(Date(), forKey: "applicationDatabaseLastUpdated")
    }

    // MARK: - Helpers

    private func findBrew() -> String? {
        let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Semantic version comparison: splits on "." and compares numerically,
    /// falling back to lexicographic for non-numeric suffixes.
    private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsParts = lhs.split(separator: ".").compactMap { Int($0) }
        let rhsParts = rhs.split(separator: ".").compactMap { Int($0) }
        let count = max(lhsParts.count, rhsParts.count)

        for i in 0..<count {
            let l = i < lhsParts.count ? lhsParts[i] : 0
            let r = i < rhsParts.count ? rhsParts[i] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }

        // If numeric parts are equal, compare remaining string suffixes lexicographically
        let lhsSuffix = lhs.split(separator: ".", maxSplits: lhsParts.count, omittingEmptySubsequences: false).last.map(String.init) ?? ""
        let rhsSuffix = rhs.split(separator: ".", maxSplits: rhsParts.count, omittingEmptySubsequences: false).last.map(String.init) ?? ""
        return lhsSuffix.compare(rhsSuffix)
    }

    func startPeriodicChecks(interval: TimeInterval = 3600) {
        updateCheckTask?.cancel()
        updateCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await self?.checkAllUpdates()
            }
        }
    }

    func stopPeriodicChecks() {
        updateCheckTask?.cancel()
        updateCheckTask = nil
    }
}

// MARK: - Supporting Types

enum UpdateError: LocalizedError {
    case invalidURL
    case noDownloadAvailable
    case homebrewNotAvailable
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid URL"
        case .noDownloadAvailable: "No download available"
        case .homebrewNotAvailable: "Homebrew is not installed"
        case .installFailed(let msg): msg
        }
    }
}

struct GitHubRelease: Codable {
    let tagName: String
    let name: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case assets
    }
}

struct GitHubAsset: Codable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
