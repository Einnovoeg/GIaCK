//
//  AICompatibilityService.swift
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
import os.log

/// Central compatibility service that aggregates local curated data with
/// remote sources like Steam Deck verified lists, ProtonDB, and Wine AppDB.
///
/// The service is intentionally cache-first and offline-capable. Remote
/// sync is best-effort and never blocks a local recommendation.
public actor AICompatibilityService {
    public static let shared = AICompatibilityService()

    private let logger = Logger(subsystem: Bundle.giackBundleIdentifier, category: "AICompatibilityService")
    private let session: URLSession
    private let cacheDirectory: URL
    private let cacheFile: URL

    public struct CompatibilityEntry: Codable, Sendable, Identifiable {
        public var id: String { executableName.lowercased() }
        public let executableName: String
        public let displayName: String?
        public let publisher: String?
        public let version: String?
        public let category: String
        public let requiredDLLs: [String]
        public let requiredVerbs: [String]
        public let optionalVerbs: [String]?
        public let frameworks: [String]?
        public let windowsVersion: String?
        public let dxvkRecommended: Bool?
        public let preferESync: Bool
        public let environmentVariables: [String: String]?
        public let launchArguments: [String]?
        public let notes: String?
        public let source: String
        public let steamDeckStatus: SteamDeckStatus?
        public let protonDBRating: String?
        public let lastUpdated: Date?

        public enum SteamDeckStatus: String, Codable, Sendable {
            case verified
            case playable
            case unsupported
            case unknown
        }
    }

    private var entries: [String: CompatibilityEntry] = [:]
    private var isLoaded = false

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.cacheDirectory = appSupport.appending(path: Bundle.giackBundleIdentifier).appending(path: "AICompatibility")
        self.cacheFile = cacheDirectory.appending(path: "compatibility.json")

        Task { await load() }
    }

    // MARK: - Public API

    public func lookup(executableName: String) -> CompatibilityEntry? {
        let key = executableName.lowercased()
        if let direct = entries[key] { return direct }
        let withoutExe = key.replacingOccurrences(of: ".exe", with: "")
        if let direct = entries[withoutExe] { return direct }
        // Suffix match for sub-path exes like "game/bin/launcher.exe"
        return entries.first(where: { key.hasSuffix($0.key) })?.value
    }

    public func search(query: String) -> [CompatibilityEntry] {
        let lower = query.lowercased()
        return entries.values.filter {
            $0.executableName.lowercased().contains(lower) ||
            ($0.displayName?.lowercased().contains(lower) ?? false) ||
            ($0.publisher?.lowercased().contains(lower) ?? false)
        }.sorted { $0.executableName < $1.executableName }
    }

    public func allEntries() -> [CompatibilityEntry] {
        Array(entries.values).sorted { $0.executableName < $1.executableName }
    }

    public func entriesBySteamDeckStatus(_ status: CompatibilityEntry.SteamDeckStatus) -> [CompatibilityEntry] {
        entries.values.filter { $0.steamDeckStatus == status }.sorted { $0.executableName < $1.executableName }
    }

    /// Sync remote databases. Tries curated GIACK remote if available, otherwise
    /// uses built-in curated list. Never throws fatally; logs errors.
    ///
    /// Remote location is unified to `Einnovoeg/GIaCK` (see `ProjectInfo.applicationDatabaseURL`
    /// in the app target and `Constants.swift`). The previous hard-coded
    /// `GIACK-App/GIACK` 404'd and caused this sync to silently merge nothing.
    public func sync() async {
        // Try GIACK curated remote first - unified to Einnovoeg/GIaCK main
        let remoteURLString = "https://raw.githubusercontent.com/Einnovoeg/GIaCK/main/GIACK/Resources/ApplicationDatabase.json"
        if let url = URL(string: remoteURLString) {
            do {
                let (data, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    if let remoteEntries = try? JSONDecoder().decode([CompatibilityEntry].self, from: data) {
                        var newEntries: [String: CompatibilityEntry] = [:]
                        for entry in remoteEntries {
                            newEntries[entry.executableName.lowercased()] = entry
                        }
                        if !newEntries.isEmpty {
                            entries.merge(newEntries) { _, new in new }
                            try save()
                            logger.info("Merged \(newEntries.count) entries from GIACK remote")
                        }
                    }
                }
            } catch {
                logger.warning("GIACK remote sync failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        // ProtonDB + Steam Deck enrichment is future work; for now we enrich
        // local entries with Steam Deck hints via placeholder fetch
        await enrichFromSteamDeckIfAvailable()
    }

    public func addOrUpdate(_ entry: CompatibilityEntry) async {
        entries[entry.id] = entry
        try? save()
    }

    // MARK: - Private: Load / Save

    private func load() async {
        // Try cache file first
        if FileManager.default.fileExists(atPath: cacheFile.path(percentEncoded: false)) {
            do {
                let data = try Data(contentsOf: cacheFile)
                let decoded = try JSONDecoder().decode([CompatibilityEntry].self, from: data)
                for entry in decoded {
                    entries[entry.id] = entry
                }
                if !decoded.isEmpty {
                    isLoaded = true
                    logger.info("Loaded \(decoded.count) AI compatibility entries from cache")
                    return
                }
            } catch {
                logger.warning("Failed to load AI cache: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Fallback to builtin curated entries
        loadBuiltin()
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Array(entries.values))
        try data.write(to: cacheFile, options: .atomic)
    }

    private func loadBuiltin() {
        let builtin: [CompatibilityEntry] = [
            CompatibilityEntry(
                executableName: "steam.exe",
                displayName: "Steam",
                publisher: "Valve",
                version: nil,
                category: "launcher",
                requiredDLLs: ["d3d11.dll", "dxgi.dll"],
                requiredVerbs: ["d3dcompiler_47", "vcrun2022"],
                optionalVerbs: [],
                frameworks: ["steam"],
                windowsVersion: "win10",
                dxvkRecommended: false,
                preferESync: false,
                environmentVariables: nil,
                launchArguments: [],
                notes: "Steam client - use launcher preset, keep MSync off for initial install",
                source: "GIACK Curated",
                steamDeckStatus: .verified,
                protonDBRating: "platinum",
                lastUpdated: Date()
            ),
            CompatibilityEntry(
                executableName: "epicgameslauncher.exe",
                displayName: "Epic Games Launcher",
                publisher: "Epic Games",
                version: nil,
                category: "launcher",
                requiredDLLs: ["d3d11.dll"],
                requiredVerbs: ["d3dcompiler_47", "vcrun2022", "dotnet48"],
                optionalVerbs: [],
                frameworks: [],
                windowsVersion: "win10",
                dxvkRecommended: false,
                preferESync: false,
                environmentVariables: nil,
                launchArguments: [],
                notes: "Requires .NET 4.8 and VCRun 2022; known issues with overlay",
                source: "GIACK Curated + ProtonDB",
                steamDeckStatus: .playable,
                protonDBRating: "gold",
                lastUpdated: Date()
            ),
            CompatibilityEntry(
                executableName: "gog galaxy.exe",
                displayName: "GOG Galaxy",
                publisher: "GOG",
                version: nil,
                category: "launcher",
                requiredDLLs: ["d3d11.dll"],
                requiredVerbs: ["d3dcompiler_47"],
                optionalVerbs: ["vcrun2022"],
                frameworks: [],
                windowsVersion: "win10",
                dxvkRecommended: false,
                preferESync: false,
                environmentVariables: nil,
                launchArguments: [],
                notes: "Minimal dependencies; MSync recommended",
                source: "GIACK Curated",
                steamDeckStatus: .playable,
                protonDBRating: "gold",
                lastUpdated: Date()
            ),
            CompatibilityEntry(
                executableName: "battle.net.exe",
                displayName: "Battle.net",
                publisher: "Blizzard",
                version: nil,
                category: "launcher",
                requiredDLLs: ["d3d11.dll", "dxgi.dll"],
                requiredVerbs: ["d3dcompiler_47", "vcrun2022"],
                optionalVerbs: [],
                frameworks: [],
                windowsVersion: "win10",
                dxvkRecommended: false,
                preferESync: false,
                environmentVariables: nil,
                launchArguments: [],
                notes: "Overwatch 2 requires additional config",
                source: "GIACK Curated",
                steamDeckStatus: .playable,
                protonDBRating: "gold",
                lastUpdated: Date()
            ),
            CompatibilityEntry(
                executableName: "witcher3.exe",
                displayName: "The Witcher 3: Wild Hunt",
                publisher: "CD Projekt Red",
                version: nil,
                category: "game",
                requiredDLLs: ["d3d11.dll", "xinput1_3.dll"],
                requiredVerbs: ["d3dcompiler_47", "vcrun2019", "xinput"],
                optionalVerbs: [],
                frameworks: [],
                windowsVersion: "win10",
                dxvkRecommended: true,
                preferESync: false,
                environmentVariables: ["DXVK_HUD": "0"],
                launchArguments: [],
                notes: "Steam Deck Verified; DXVK recommended for performance",
                source: "Steam Deck Verified + ProtonDB Platinum",
                steamDeckStatus: .verified,
                protonDBRating: "platinum",
                lastUpdated: Date()
            ),
            CompatibilityEntry(
                executableName: "eldenring.exe",
                displayName: "Elden Ring",
                publisher: "FromSoftware",
                version: nil,
                category: "game",
                requiredDLLs: ["d3d12.dll", "d3dcompiler_47.dll"],
                requiredVerbs: ["d3dcompiler_47", "vcrun2022"],
                optionalVerbs: [],
                frameworks: [],
                windowsVersion: "win10",
                dxvkRecommended: true,
                preferESync: false,
                environmentVariables: nil,
                launchArguments: [],
                notes: "Steam Deck Verified; use MSync, avoid ESync",
                source: "Steam Deck Verified + ProtonDB Gold",
                steamDeckStatus: .verified,
                protonDBRating: "gold",
                lastUpdated: Date()
            ),
            CompatibilityEntry(
                executableName: "cyberpunk2077.exe",
                displayName: "Cyberpunk 2077",
                publisher: "CD Projekt Red",
                version: nil,
                category: "game",
                requiredDLLs: ["d3d12.dll", "vulkan-1.dll"],
                requiredVerbs: ["d3dcompiler_47", "vcrun2022"],
                optionalVerbs: ["dotnet48"],
                frameworks: [],
                windowsVersion: "win10",
                dxvkRecommended: true,
                preferESync: false,
                environmentVariables: nil,
                launchArguments: [],
                notes: "Requires VCRun 2022; DXR optional via metal trace",
                source: "Steam Deck Playable + ProtonDB Gold",
                steamDeckStatus: .playable,
                protonDBRating: "gold",
                lastUpdated: Date()
            ),
            CompatibilityEntry(
                executableName: "skyrimse.exe",
                displayName: "Skyrim Special Edition",
                publisher: "Bethesda",
                version: nil,
                category: "game",
                requiredDLLs: ["d3d11.dll", "xaudio2_7.dll"],
                requiredVerbs: ["d3dcompiler_47", "xact", "vcrun2019"],
                optionalVerbs: [],
                frameworks: [],
                windowsVersion: "win10",
                dxvkRecommended: true,
                preferESync: false,
                environmentVariables: nil,
                launchArguments: [],
                notes: "XAudio2 required for sound; Steam Deck Verified",
                source: "Steam Deck Verified + ProtonDB Platinum",
                steamDeckStatus: .verified,
                protonDBRating: "platinum",
                lastUpdated: Date()
            ),
            CompatibilityEntry(
                executableName: "notepad++.exe",
                displayName: "Notepad++",
                publisher: "Notepad++ Team",
                version: nil,
                category: "utility",
                requiredDLLs: [],
                requiredVerbs: [],
                optionalVerbs: [],
                frameworks: [],
                windowsVersion: "win10",
                dxvkRecommended: false,
                preferESync: false,
                environmentVariables: nil,
                launchArguments: [],
                notes: "No extra dependencies",
                source: "GIACK Curated",
                steamDeckStatus: .unknown,
                protonDBRating: nil,
                lastUpdated: Date()
            ),
        ]

        for entry in builtin {
            entries[entry.id] = entry
        }
        isLoaded = true
        logger.info("Loaded \(builtin.count) builtin AI compatibility entries")
        try? save()
    }

    // MARK: - Steam Deck enrichment placeholder

    private func enrichFromSteamDeckIfAvailable() async {
        // Future: fetch https://steamdeckverified API or ProtonDB API
        // For now, no-op but structure is ready for Heroic-like online integration
        // Placeholder logs that the enrichment path is wired.
        logger.debug("Steam Deck enrichment check - using curated data until remote API is configured")
    }
}

// MARK: - AI Compatibility Helpers

/// Centralized URL for AI compatibility database.
/// Unified to the maintained fork; previously `GIACK-App/GIACK` returned 404.
enum AICompatibilityConfig {
    static var remoteURL: URL? {
        URL(string: "https://raw.githubusercontent.com/Einnovoeg/GIaCK/main/GIACK/Resources/ApplicationDatabase.json")
    }
}
