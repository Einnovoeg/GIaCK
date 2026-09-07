//
//  BottleData.swift
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

/// Persistent index of known bottle locations.
///
/// The app keeps bottle paths separate from the bottle contents so that bottles
/// on external drives or custom directories can be re-discovered after relaunch.
public struct BottleData: Codable {
    public static let containerDir = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library")
        .appending(path: "Containers")
        .appending(path: Bundle.giackBundleIdentifier)

    public static let bottleEntriesDir = containerDir
        .appending(path: "BottleVM")
        .appendingPathExtension("plist")

    public static let defaultBottleDir = containerDir
        .appending(path: "Bottles")

    static let currentVersion = SemanticVersion(1, 0, 0)

    private var fileVersion: SemanticVersion
    public var paths: [URL] = [] {
        didSet {
            encode()
        }
    }

    public init() {
        fileVersion = Self.currentVersion

        if !decode() {
            encode()
        }
    }

    /// Loads registered paths, normalizes them, drops stale entries, and
    /// creates lightweight bottle models for the UI.
    public mutating func loadBottles() -> [Bottle] {
        paths = normalizedStoredPaths(from: paths)

        var bottles: [Bottle] = []

        for path in paths {
            let bottleMetadata = path
                .appending(path: "Metadata")
                .appendingPathExtension("plist")
                .path(percentEncoded: false)

            if FileManager.default.fileExists(atPath: bottleMetadata) {
                bottles.append(Bottle(bottleUrl: path, isAvailable: true))
            } else {
                bottles.append(Bottle(bottleUrl: path))
            }
        }

        return bottles
    }

    @discardableResult
    public mutating func registerBottlePath(_ url: URL) -> Bool {
        let normalizedPath = Self.normalizeBottlePath(url)
        let pathKey = normalizedPath.path(percentEncoded: false)

        guard !paths.contains(where: { Self.normalizeBottlePath($0).path(percentEncoded: false) == pathKey }) else {
            return false
        }

        paths.append(normalizedPath)
        return true
    }

    public mutating func removeBottlePath(_ url: URL) {
        let pathKey = Self.normalizeBottlePath(url).path(percentEncoded: false)
        paths.removeAll { Self.normalizeBottlePath($0).path(percentEncoded: false) == pathKey }
    }

    @discardableResult
    public mutating func registerBottlePaths(in selectedURL: URL) -> Int {
        let candidates = Self.importableBottlePaths(from: selectedURL)
        var importedCount = 0

        for candidate in candidates where registerBottlePath(candidate) {
            importedCount += 1
        }

        return importedCount
    }

    public static func importableBottlePaths(from selectedURL: URL) -> [URL] {
        let normalizedSelection = normalizeBottlePath(selectedURL)

        if looksLikeBottleDirectory(normalizedSelection) {
            return [normalizedSelection]
        }

        guard let children = try? FileManager.default.contentsOfDirectory(
            at: normalizedSelection,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return children
            .filter { child in
                (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            }
            .map(normalizeBottlePath)
            .filter(looksLikeBottleDirectory)
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    public static func looksLikeBottleDirectory(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        let metadataURL = url.appending(path: "Metadata").appendingPathExtension("plist")
        let driveCURL = url.appending(path: "drive_c")
        let dosDevicesURL = url.appending(path: "dosdevices")

        return fileManager.fileExists(atPath: metadataURL.path(percentEncoded: false))
            || fileManager.fileExists(atPath: driveCURL.path(percentEncoded: false))
            || fileManager.fileExists(atPath: dosDevicesURL.path(percentEncoded: false))
    }

    @discardableResult
    private mutating func decode() -> Bool {
        let decoder = PropertyListDecoder()
        do {
            let data = try Data(contentsOf: Self.bottleEntriesDir)
            self = try decoder.decode(BottleData.self, from: data)
            if self.fileVersion != Self.currentVersion {
                print("Invalid file version \(self.fileVersion)")
                return false
            }
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    private func encode() -> Bool {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml

        do {
            try FileManager.default.createDirectory(at: Self.containerDir, withIntermediateDirectories: true)
            let data = try encoder.encode(self)
            try data.write(to: Self.bottleEntriesDir)
            return true
        } catch {
            return false
        }
    }

    private func normalizedStoredPaths(from paths: [URL]) -> [URL] {
        var normalizedPaths: [URL] = []
        var seenPaths: Set<String> = []

        for path in paths {
            let normalizedPath = Self.normalizeBottlePath(path)
            var isDirectory = ObjCBool(false)
            // Ignore paths that no longer exist or no longer point at a bottle
            // root so the stored list self-heals over time.
            guard FileManager.default.fileExists(
                atPath: normalizedPath.path(percentEncoded: false),
                isDirectory: &isDirectory
            ), isDirectory.boolValue else {
                continue
            }

            let pathKey = normalizedPath.path(percentEncoded: false)
            guard seenPaths.insert(pathKey).inserted else {
                continue
            }
            normalizedPaths.append(normalizedPath)
        }

        return normalizedPaths
    }

    private static func normalizeBottlePath(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }
}
