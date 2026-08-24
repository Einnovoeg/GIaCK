//
//  RemoteDatabase.swift
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
import os.log

actor RemoteDatabase {
    static let shared = RemoteDatabase()

    private let logger = Logger(subsystem: Bundle.giackBundleIdentifier, category: "RemoteDatabase")
    private let session: URLSession
    private let cacheDir: URL
    private let cacheFile: URL

    private var entries: [String: DatabaseEntry] = [:]
    private var isLoaded = false

    struct DatabaseEntry: Codable, Identifiable, Sendable {
        var id: String { executableName.lowercased() }
        let executableName: String
        let description: String
        let category: Category
        let requiredDlls: [String]
        let requiredVerbs: [String]
        let windowsVersion: String?
        let dxvkRequired: Bool
        let notes: String?
        let difficulty: Difficulty
        let knownIssues: [String]?
        let launchArguments: [String]?
        let environmentVariables: [String: String]?
        let customConfig: String?

        enum Category: String, Codable, Sendable, CaseIterable {
            case game
            case productivity
            case utility
            case media
            case development
            case other
        }

        enum Difficulty: String, Codable, Sendable {
            case easy
            case moderate
            case difficult
            case experimental
        }
    }

    struct DatabaseManifest: Codable {
        let version: String
        let lastUpdated: Date
        let entryCount: Int
        let checksum: String?
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.cacheDir = appSupport
            .appending(path: Bundle.giackBundleIdentifier)
            .appending(path: "Database")
        self.cacheFile = cacheDir.appending(path: "entries.json")

        Task { await loadLocalCache() }
    }

    // MARK: - Public API

    func lookup(byName name: String) -> DatabaseEntry? {
        let lowercased = name.lowercased()
        return entries[lowercased] ??
               entries[lowercased.replacingOccurrences(of: ".exe", with: "")] ??
               entries.first(where: { key, _ in lowercased.hasSuffix(key) })?.value
    }

    func search(query: String) -> [DatabaseEntry] {
        let lowercased = query.lowercased()
        return entries.values.filter { entry in
            entry.executableName.lowercased().contains(lowercased) ||
            entry.description.lowercased().contains(lowercased) ||
            entry.category.rawValue.contains(lowercased) ||
            (entry.notes?.lowercased().contains(lowercased) ?? false)
        }.sorted { $0.executableName < $1.executableName }
    }

    func allEntries() -> [DatabaseEntry] {
        Array(entries.values).sorted { $0.executableName < $1.executableName }
    }

    func entries(for category: DatabaseEntry.Category) -> [DatabaseEntry] {
        entries.values.filter { $0.category == category }.sorted { $0.executableName < $1.executableName }
    }

    func dependencies(for entry: DatabaseEntry) -> [DependencyInfo] {
        var deps: [DependencyInfo] = []

        for dll in entry.requiredDlls {
            deps.append(DependencyInfo(
                name: dll,
                type: .dll,
                required: true,
                autoInstallable: isVerbAvailable(dll)
            ))
        }

        for verb in entry.requiredVerbs {
            deps.append(DependencyInfo(
                name: verb,
                type: .verb,
                required: true,
                autoInstallable: true
            ))
        }

        if entry.dxvkRequired {
            deps.append(DependencyInfo(
                name: "DXVK",
                type: .framework,
                required: true,
                autoInstallable: true
            ))
        }

        return deps
    }

    // MARK: - Sync

    func syncFromRemote() async throws {
        guard let url = ProjectInfo.applicationDatabaseURL else {
            throw DatabaseError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw DatabaseError.fetchFailed
        }

        let decoded = try JSONDecoder().decode([DatabaseEntry].self, from: data)

        var newEntries: [String: DatabaseEntry] = [:]
        for entry in decoded {
            newEntries[entry.executableName.lowercased()] = entry
        }

        entries = newEntries
        try saveToCache()
        isLoaded = true

        logger.info("Synced \(decoded.count) entries from remote database")
    }

    func mergeWithLocal(_ localEntries: [DatabaseEntry]) {
        for entry in localEntries {
            let key = entry.executableName.lowercased()
            if entries[key] == nil {
                entries[key] = entry
            }
        }
    }

    // MARK: - Cache

    private func loadLocalCache() async {
        guard FileManager.default.fileExists(atPath: cacheFile.path) else {
            loadBuiltinEntries()
            return
        }

        do {
            let data = try Data(contentsOf: cacheFile)
            let decoded = try JSONDecoder().decode([DatabaseEntry].self, from: data)
            for entry in decoded {
                entries[entry.id] = entry
            }
            isLoaded = true
            logger.info("Loaded \(decoded.count) entries from local cache")
        } catch {
            logger.error("Failed to load cache: \(error.localizedDescription)")
            loadBuiltinEntries()
        }
    }

    private func saveToCache() throws {
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Array(entries.values))
        try data.write(to: cacheFile)
    }

    private func loadBuiltinEntries() {
        let builtin: [DatabaseEntry] = [
            DatabaseEntry(
                executableName: "steam.exe",
                description: "Steam client for Windows",
                category: .game,
                requiredDlls: ["d3d11.dll", "dxgi.dll"],
                requiredVerbs: ["d3dx11", "d3dcompiler_47"],
                windowsVersion: "win10",
                dxvkRequired: false,
                notes: "Steam client with built-in Proton-like features",
                difficulty: .easy,
                knownIssues: nil,
                launchArguments: ["-silent"],
                environmentVariables: nil,
                customConfig: nil
            ),
            DatabaseEntry(
                executableName: "epicgameslauncher.exe",
                description: "Epic Games Store launcher",
                category: .game,
                requiredDlls: ["d3d11.dll", "dxgi.dll"],
                requiredVerbs: ["d3dx11", "d3dcompiler_47"],
                windowsVersion: "win10",
                dxvkRequired: false,
                notes: nil,
                difficulty: .moderate,
                knownIssues: ["May require .NET Framework workaround"],
                launchArguments: nil,
                environmentVariables: nil,
                customConfig: nil
            ),
            DatabaseEntry(
                executableName: "gog galaxy.exe",
                description: "GOG Galaxy game client",
                category: .game,
                requiredDlls: ["d3d11.dll", "dxgi.dll"],
                requiredVerbs: ["d3dx11"],
                windowsVersion: "win10",
                dxvkRequired: false,
                notes: nil,
                difficulty: .moderate,
                knownIssues: nil,
                launchArguments: nil,
                environmentVariables: nil,
                customConfig: nil
            ),
            DatabaseEntry(
                executableName: "battle.net.exe",
                description: "Blizzard Battle.net launcher",
                category: .game,
                requiredDlls: ["d3d11.dll", "dxgi.dll"],
                requiredVerbs: ["d3dx11", "d3dcompiler_47"],
                windowsVersion: "win10",
                dxvkRequired: false,
                notes: nil,
                difficulty: .moderate,
                knownIssues: ["Overwatch 2 requires additional configuration"],
                launchArguments: nil,
                environmentVariables: nil,
                customConfig: nil
            ),
            DatabaseEntry(
                executableName: "origin.exe",
                description: "EA Origin game launcher",
                category: .game,
                requiredDlls: ["d3d11.dll", "dxgi.dll", "mf.dll"],
                requiredVerbs: ["d3dx11", "mf", "mscoree"],
                windowsVersion: "win10",
                dxvkRequired: false,
                notes: "May require additional DLL overrides",
                difficulty: .difficult,
                knownIssues: ["EA App is replacing Origin"],
                launchArguments: nil,
                environmentVariables: nil,
                customConfig: nil
            ),
            DatabaseEntry(
                executableName: "ubisoft connect.exe",
                description: "Ubisoft Connect game client",
                category: .game,
                requiredDlls: ["d3d11.dll", "dxgi.dll"],
                requiredVerbs: ["d3dx11"],
                windowsVersion: "win10",
                dxvkRequired: false,
                notes: nil,
                difficulty: .moderate,
                knownIssues: nil,
                launchArguments: nil,
                environmentVariables: nil,
                customConfig: nil
            ),
            DatabaseEntry(
                executableName: "notepad++.exe",
                description: "Notepad++ text editor",
                category: .productivity,
                requiredDlls: [],
                requiredVerbs: [],
                windowsVersion: nil,
                dxvkRequired: false,
                notes: nil,
                difficulty: .easy,
                knownIssues: nil,
                launchArguments: nil,
                environmentVariables: nil,
                customConfig: nil
            ),
            DatabaseEntry(
                executableName: "7z.exe",
                description: "7-Zip file archiver",
                category: .utility,
                requiredDlls: [],
                requiredVerbs: [],
                windowsVersion: nil,
                dxvkRequired: false,
                notes: nil,
                difficulty: .easy,
                knownIssues: nil,
                launchArguments: nil,
                environmentVariables: nil,
                customConfig: nil
            ),
            DatabaseEntry(
                executableName: "firefox.exe",
                description: "Mozilla Firefox web browser",
                category: .productivity,
                requiredDlls: ["d3d11.dll", "dxgi.dll", "vulkan-1.dll"],
                requiredVerbs: ["d3dx11"],
                windowsVersion: "win10",
                dxvkRequired: false,
                notes: "WebGL acceleration may require DXVK",
                difficulty: .moderate,
                knownIssues: nil,
                launchArguments: nil,
                environmentVariables: nil,
                customConfig: nil
            ),
            DatabaseEntry(
                executableName: "chrome.exe",
                description: "Google Chrome web browser",
                category: .productivity,
                requiredDlls: ["d3d11.dll", "dxgi.dll"],
                requiredVerbs: [],
                windowsVersion: "win10",
                dxvkRequired: false,
                notes: nil,
                difficulty: .moderate,
                knownIssues: nil,
                launchArguments: nil,
                environmentVariables: nil,
                customConfig: nil
            ),
            DatabaseEntry(
                executableName: "vlc.exe",
                description: "VLC Media Player",
                category: .media,
                requiredDlls: ["d3d9.dll"],
                requiredVerbs: [],
                windowsVersion: nil,
                dxvkRequired: false,
                notes: "Lightweight media player",
                difficulty: .easy,
                knownIssues: nil,
                launchArguments: nil,
                environmentVariables: nil,
                customConfig: nil
            ),
        ]

        for entry in builtin {
            entries[entry.id] = entry
        }
        isLoaded = true
    }

    private func isVerbAvailable(_ dll: String) -> Bool {
        dll.hasPrefix("d3d") || dll.hasPrefix("dxgi") || dll.hasPrefix("vulkan")
    }
}

enum DatabaseError: LocalizedError {
    case invalidURL
    case fetchFailed
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid database URL"
        case .fetchFailed: "Failed to fetch database"
        case .decodeFailed: "Failed to decode database"
        }
    }
}

struct DependencyInfo: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let type: DependencyType
    let required: Bool
    let autoInstallable: Bool

    enum DependencyType: String, Sendable {
        case dll
        case verb
        case framework
        case registry
    }
}
