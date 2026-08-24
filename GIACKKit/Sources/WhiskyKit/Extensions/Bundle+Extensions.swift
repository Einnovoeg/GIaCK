//
//  Bundle+Extension.swift
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

public extension Bundle {
    /// User-facing app name used across UI and path decoration.
    static var appDisplayName: String {
        let fallbackName = "GIACK GPTK"
        if let configuredName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !configuredName.isEmpty {
            return configuredName
        }
        return fallbackName
    }

    static var whiskyBundleIdentifier: String {
        if let environmentOverride = ProcessInfo.processInfo.environment["GIACK_BUNDLE_ID_OVERRIDE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !environmentOverride.isEmpty {
            return environmentOverride
        }

        let currentIdentifier = Bundle.main.bundleIdentifier ?? "org.giack.gptk"
        if hasStoredData(for: currentIdentifier) {
            return currentIdentifier
        }

        // Discover historical GIACK bundle identifiers by their suffix so the
        // migration path still works without hard-coding personal bundle IDs.
        let alternates = discoverLegacyBundleIdentifiers()
            .filter { $0 != currentIdentifier }
        for candidate in alternates where hasStoredData(for: candidate) {
            return candidate
        }

        return currentIdentifier
    }

    private static func hasStoredData(for bundleIdentifier: String) -> Bool {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let containers = fileManager.homeDirectoryForCurrentUser
            .appending(path: "Library")
            .appending(path: "Containers")

        return fileManager.fileExists(atPath: appSupport.appending(path: bundleIdentifier).path)
            || fileManager.fileExists(atPath: containers.appending(path: bundleIdentifier).path)
    }

    private static func discoverLegacyBundleIdentifiers() -> [String] {
        let suffixes = [".GIACK", ".GIACKGPTK"]
        var identifiers: Set<String> = ["io.whiskygptk.app"]

        for root in storageRoots() {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for child in children {
                let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                guard isDirectory else {
                    continue
                }

                let name = child.lastPathComponent
                if suffixes.contains(where: name.hasSuffix) {
                    identifiers.insert(name)
                }
            }
        }

        return identifiers.sorted()
    }

    private static func storageRoots() -> [URL] {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let containers = fileManager.homeDirectoryForCurrentUser
            .appending(path: "Library")
            .appending(path: "Containers")
        return [appSupport, containers]
    }
}
