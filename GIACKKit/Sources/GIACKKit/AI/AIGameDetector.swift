//
//  AIGameDetector.swift
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

/// Identifies a Windows application or game from its executable.
///
/// The detector combines PE metadata, import analysis, filesystem heuristics,
/// and remote compatibility databases to determine the most likely identity.
/// This is the entry point for the AI-driven auto-configuration flow.
public actor AIGameDetector {
    public static let shared = AIGameDetector()

    private let logger = Logger(subsystem: Bundle.giackBundleIdentifier, category: "AIGameDetector")

    public struct GameIdentity: Sendable, Hashable {
        public let executableName: String
        public let displayName: String
        public let publisher: String?
        public let engine: Engine?
        public let confidence: Confidence
        public let detectedVersion: String?
        public let architecture: Architecture
        public let importedDLLs: [String]
        public let fileSize: UInt64
        public let sha256Prefix: String?

        public enum Confidence: String, Sendable {
            case high
            case medium
            case low
            case unknown
        }

        public enum Engine: String, Sendable {
            case unity
            case unreal
            case cryEngine
            case godot
            case rpgMaker
            case source
            case idTech
            case custom
            case unknown
        }
    }

    public struct DetectionContext: Sendable {
        public let url: URL
        public let peFile: PEFile?
        public let fileSize: UInt64
        public let parentFolderName: String
        public let siblingFiles: [String]
    }

    private init() {}

    // MARK: - Public

    /// Detect the identity of a game or application from its executable URL.
    public func detect(at url: URL) async -> GameIdentity {
        let context = await buildContext(for: url)
        let dlls = await extractImportedDLLs(from: context)
        let engine = detectEngine(from: dlls, siblings: context.siblingFiles)
        let (displayName, publisher, version, confidence) = await resolveDisplayName(for: context, dlls: dlls)

        let shaPrefix = await sha256Prefix(for: url)
        let arch: Architecture
        if let peFile = context.peFile {
            arch = peFile.architecture
        } else {
            arch = .unknown
        }

        let identity = GameIdentity(
            executableName: url.lastPathComponent,
            displayName: displayName,
            publisher: publisher,
            engine: engine,
            confidence: confidence,
            detectedVersion: version,
            architecture: arch,
            importedDLLs: dlls,
            fileSize: context.fileSize,
            sha256Prefix: shaPrefix
        )

        logger.info("Detected \(identity.displayName, privacy: .public) [\(identity.confidence.rawValue)] engine=\(identity.engine?.rawValue ?? "unknown") dlls=\(dlls.count)")
        return identity
    }

    /// Batch detect all executables in a folder.
    public func detectAll(in folder: URL) async -> [GameIdentity] {
        let exes = findExecutables(in: folder)
        var results: [GameIdentity] = []
        for exe in exes {
            let identity = await detect(at: exe)
            results.append(identity)
        }
        return results.sorted { $0.displayName < $1.displayName }
    }

    // MARK: - Context

    private func buildContext(for url: URL) async -> DetectionContext {
        let peFile: PEFile?
        do {
            peFile = try PEFile(url: url)
        } catch {
            peFile = nil
        }

        let fileSize: UInt64
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)),
           let size = attrs[.size] as? UInt64 {
            fileSize = size
        } else if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)),
                  let size = attrs[.size] as? Int {
            fileSize = UInt64(size)
        } else {
            fileSize = 0
        }

        let parent = url.deletingLastPathComponent().lastPathComponent
        let siblings: [String]
        if let contents = try? FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil) {
            siblings = contents.map { $0.lastPathComponent.lowercased() }
        } else {
            siblings = []
        }

        return DetectionContext(
            url: url,
            peFile: peFile,
            fileSize: fileSize,
            parentFolderName: parent,
            siblingFiles: siblings
        )
    }

    // MARK: - Import extraction

    private func extractImportedDLLs(from context: DetectionContext) async -> [String] {
        // Best effort: try to read import table via PE sections, fallback to heuristic
        // For now, heuristic + known import signatures from sibling files
        var dlls: Set<String> = []

        // Sibling DLLs are strong signals
        for sibling in context.siblingFiles where sibling.hasSuffix(".dll") {
            dlls.insert(sibling.lowercased())
        }

        // PE-derived: if we have a PE file, we can at least infer common imports
        // The current PE parser does not yet expose import directory, so we use
        // file-size + name heuristics as fallback until import parsing is added
        let exeName = context.url.lastPathComponent.lowercased()

        // Heuristic mapping for common engines
        if exeName.contains("unity") || context.siblingFiles.contains(where: { $0.contains("unityplayer.dll") }) {
            dlls.insert("unityplayer.dll")
        }
        if context.siblingFiles.contains("d3d11.dll") { dlls.insert("d3d11.dll") }
        if context.siblingFiles.contains("d3d12.dll") { dlls.insert("d3d12.dll") }
        if context.siblingFiles.contains("vulkan-1.dll") { dlls.insert("vulkan-1.dll") }
        if context.siblingFiles.contains("xinput1_3.dll") { dlls.insert("xinput1_3.dll") }
        if context.siblingFiles.contains("msvcr") || context.siblingFiles.contains(where: { $0.hasPrefix("msvcr") }) {
            dlls.insert("msvcr120.dll")
        }

        // Steam / launcher hints
        if exeName == "steam.exe" { dlls.formUnion(["d3d11.dll", "dxgi.dll"]) }
        if exeName.contains("epic") { dlls.formUnion(["d3d11.dll", "dxgi.dll"]) }

        return dlls.sorted()
    }

    // MARK: - Engine detection

    private func detectEngine(from dlls: [String], siblings: [String]) -> GameIdentity.Engine {
        let lowerDLLs = Set(dlls.map { $0.lowercased() })
        let lowerSiblings = Set(siblings.map { $0.lowercased() })

        if lowerSiblings.contains("unityplayer.dll") || lowerDLLs.contains("unityplayer.dll") {
            return .unity
        }
        if lowerSiblings.contains(where: { $0.hasPrefix("ue4") || $0.contains("unreal") }) || lowerDLLs.contains("ue4.dll") {
            return .unreal
        }
        if lowerSiblings.contains("cryengine.dll") { return .cryEngine }
        if lowerSiblings.contains("godot") { return .godot }
        if lowerSiblings.contains("rgss301.dll") || lowerSiblings.contains("rpg_rt.exe") { return .rpgMaker }
        if lowerSiblings.contains("tier0.dll") || lowerSiblings.contains("vstdlib.dll") { return .source }
        if lowerDLLs.contains("id5.dll") || lowerSiblings.contains("id5.dll") { return .idTech }

        return .unknown
    }

    // MARK: - Display name resolution

    private func resolveDisplayName(for context: DetectionContext, dlls: [String]) async -> (String, String?, String?, GameIdentity.Confidence) {
        let exeName = context.url.lastPathComponent
        let baseName = exeName.replacingOccurrences(of: ".exe", with: "").replacingOccurrences(of: "_", with: " ")

        // Try PE version info if available (icon + version resource not yet fully parsed, so use exe name)
        // Check sibling folder name as game folder often contains proper title
        let folderName = context.parentFolderName
        let isGenericExeName = ["game", "launch", "start", "play", "client", "launcher", "unity", "app"].contains(baseName.lowercased())

        var displayName = baseName
        var confidence: GameIdentity.Confidence = .low

        if isGenericExeName && !folderName.isEmpty && folderName.lowercased() != "drive_c" {
            displayName = folderName
            confidence = .medium
        } else if !isGenericExeName {
            displayName = baseName.capitalized
            confidence = .medium
        }

        // Check remote database for exact match to upgrade confidence
        if let entry = await AICompatibilityService.shared.lookup(executableName: exeName) {
            displayName = entry.displayName ?? displayName
            confidence = .high
            return (displayName, entry.publisher, entry.version, confidence)
        }

        // Check known publisher hints from folder/exe patterns
        let publisher = detectPublisher(from: exeName, siblings: context.siblingFiles)

        // Try to extract version from PE optional header or sibling files
        let version = extractVersionHint(from: context)

        return (displayName, publisher, version, confidence)
    }

    private func detectPublisher(from exeName: String, siblings: [String]) -> String? {
        let lower = exeName.lowercased()
        if lower.contains("steam") { return "Valve" }
        if lower.contains("epic") { return "Epic Games" }
        if lower.contains("gog") { return "GOG" }
        if lower.contains("ubisoft") { return "Ubisoft" }
        if lower.contains("battle") { return "Blizzard" }
        if lower.contains("origin") || lower.contains("ea") { return "Electronic Arts" }
        return nil
    }

    private func extractVersionHint(from context: DetectionContext) -> String? {
        // Attempt to read version from sibling files like "version.txt" or exe properties
        // Placeholder until full VS_VERSIONINFO parsing is implemented
        for sibling in context.siblingFiles where sibling == "version.txt" || sibling == "version.ini" {
            let url = context.url.deletingLastPathComponent().appending(path: sibling)
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && trimmed.count < 20 {
                    return trimmed
                }
            }
        }
        return nil
    }

    // MARK: - Helpers

    private func findExecutables(in folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var results: [URL] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "exe" {
            results.append(url)
        }
        return results
    }

    private func sha256Prefix(for url: URL) async -> String? {
        // Lightweight prefix: hash first 64KB to avoid reading massive exes fully on main thread
        // Used for cache keys, not cryptographic identity
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 65536), !data.isEmpty else { return nil }
        var hash: UInt64 = 5381
        for byte in data {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(format: "%016llx", hash)
    }
}
