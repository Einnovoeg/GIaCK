//
//  Bottle+Extensions.swift
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
import AppKit
import GIACKKit
import os.log

extension Bottle {
    func openCDrive() {
        let cDriveURL: URL
        switch runner {
        case .wine:
            cDriveURL = url.appending(path: "drive_c")
        case .dosbox:
            cDriveURL = dosGamesFolder
        }

        do {
            try FileManager.default.createDirectory(at: cDriveURL, withIntermediateDirectories: true)
        } catch {
            print("Failed to create C: drive folder: \(error)")
        }
        if !NSWorkspace.shared.open(cDriveURL) {
            NSWorkspace.shared.open(url)
        }
    }

    func openTerminal() {
        let command: String?

        switch runner {
        case .wine:
            guard let giackCmdURL = Bundle.main.url(forResource: "GIACKCmd", withExtension: nil) else { return }
            let giackCmd = giackCmdURL.path(percentEncoded: false)
            command = "eval \\\"$(\(giackCmd.esc) shellenv \(settings.name.esc))\\\""
        case .dosbox:
            let dosboxCommand = DOSBox.generateRunCommand(bottle: self)
            command = "cd \(dosGamesFolder.path.esc); echo \"DOSBox shell ready for \(settings.name.esc).\"; echo \"Run: \(dosboxCommand.replacingOccurrences(of: "\"", with: "\\\""))\""
        }

        guard let command else { return }

        let script = """
        tell application "Terminal"
        activate
        do script "\(command.appleScriptEscaped)"
        end tell
        """

        Task.detached(priority: .userInitiated) {
            var error: NSDictionary?
            guard let appleScript = NSAppleScript(source: script) else { return }
            appleScript.executeAndReturnError(&error)

            if let error = error {
                Logger.wineKit.error("Failed to run terminal script \(error)")
                guard let description = error["NSAppleScriptErrorMessage"] as? String else { return }
                await self.showRunError(message: String(describing: description))
            }
        }
    }

    /// Resolves Start Menu `.lnk` shortcuts to their target executables.
    ///
    /// Both the global `ProgramData` and every per-user `AppData/Roaming` Start Menu
    /// are scanned. The previous implementation only checked the hardcoded
    /// `users/crossover` profile, which missed bottles that were renamed or that
    /// contain multiple user profiles. Each `.lnk` is parsed via `ShellLinkHeader`,
    /// its target is unix-ified (`C:` → `…/drive_c`), and the resulting `Program`
    /// is returned. The `.lnk` file is removed after successful parsing to avoid
    /// repeated pinning on subsequent scans (mirrors original Whisky behaviour).
    @discardableResult
    func getStartMenuPrograms() -> [Program] {
        guard runner == .wine else {
            return []
        }

        var startMenuRoots: [URL] = []

        // Global Start Menu (all users)
        startMenuRoots.append(
            url.appending(path: "drive_c/ProgramData/Microsoft/Windows/Start Menu")
        )

        // Per-user Start Menus — enumerate every profile under drive_c/users
        let usersRoot = url.appending(path: "drive_c/users")
        if let userDirs = try? FileManager.default.contentsOfDirectory(
            at: usersRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) {
            for userDir in userDirs {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: userDir.path(percentEncoded: false), isDirectory: &isDir), isDir.boolValue else { continue }
                let candidate = userDir
                    .appending(path: "AppData/Roaming/Microsoft/Windows/Start Menu")
                if FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
                    startMenuRoots.append(candidate)
                }
            }
        } else {
            // Fallback to legacy hardcoded path if users enumeration fails
            startMenuRoots.append(
                url.appending(path: "drive_c/users/crossover/AppData/Roaming/Microsoft/Windows/Start Menu")
            )
        }

        var startMenuPrograms: [Program] = []
        var linkURLs: [URL] = []
        for root in startMenuRoots {
            guard FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) else { continue }
            if let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
            ) {
                while let linkURL = enumerator.nextObject() as? URL {
                    if linkURL.pathExtension.lowercased() == "lnk" {
                        linkURLs.append(linkURL)
                    }
                }
            }
        }

        linkURLs.sort(by: { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() })

        for link in linkURLs {
            do {
                if let program = ShellLinkHeader.getProgram(url: link,
                                                            handle: try FileHandle(forReadingFrom: link),
                                                            bottle: self) {
                    if !startMenuPrograms.contains(where: { $0.url == program.url }) {
                        startMenuPrograms.append(program)
                        try FileManager.default.removeItem(at: link)
                    }
                }
            } catch {
                print(error)
            }
        }

        return startMenuPrograms
    }

    /// Comprehensive discovery of installed executables inside the bottle.
    ///
    /// Wine bottles are deliberately scanned broadly: the previous implementation
    /// only checked `Program Files` and `Program Files (x86)`, which missed
    /// portable installs in `drive_c/Games`, `drive_c/GOG Games`, user profiles,
    /// `ProgramData`, and custom folders. DOSBox libraries scan the entire
    /// `DOS Games` folder for `exe/com/bat`. Blocklisted URLs are always excluded,
    /// and pins are re-added even if the underlying file lives outside the normal
    /// roots so manually added shortcuts survive.
    func updateInstalledPrograms() {
        var programs: [Program] = []
        // Use lowercased absolute path for deduplication because the macOS
        // file system is case-insensitive but `URL` hashing is case-sensitive.
        var foundLowerPaths: Set<String> = []
        let blockLower = Set(settings.blocklist.map { $0.path(percentEncoded: false).lowercased() })

        func addIfValid(_ fileURL: URL) {
            guard !fileURL.hasDirectoryPath else { return }
            let ext = fileURL.pathExtension.lowercased()
            guard ext == "exe" else { return }
            let lower = fileURL.path(percentEncoded: false).lowercased()
            // Skip anything still under Windows system hierarchy (already excluded via
            // directory skip, but double-check for case variants).
            if lower.contains("/drive_c/windows/") || lower.contains("\\windows\\") { return }
            if blockLower.contains(lower) { return }
            guard !foundLowerPaths.contains(lower) else { return }
            foundLowerPaths.insert(lower)
            programs.append(Program(url: fileURL, bottle: self))
        }

        switch runner {
        case .wine:
            let driveC = url.appending(path: "drive_c")
            let fileManager = FileManager.default

            // 1) Deep scan of the entire drive_c with system directories pruned.
            // This catches portable installs, GOG, custom folders, user Desktop/Downloads,
            // and any exe outside the two classic Program Files roots.
            if fileManager.fileExists(atPath: driveC.path(percentEncoded: false)) {
                let excludedDirNames: Set<String> = [
                    "windows", "windowssysdir", "perfLogs", "$recycle.bin",
                    "system volume information", "msocache", "recovery", "config.msi",
                    "appdata\\local\\temp", "appdata\\local\\microsoft\\windows\\inetcache"
                ]
                // Lowercased substrings that should never contribute executables.
                let excludedPathSubstrings: [String] = [
                    "/windows/", "\\windows\\",
                    "/windows.old/", "\\windows.old\\"
                ]

                if let enumerator = fileManager.enumerator(
                    at: driveC,
                    includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) {
                    for case let fileURL as URL in enumerator {
                        // Check if this URL is a directory that should be pruned.
                        var isDir: ObjCBool = false
                        if fileManager.fileExists(atPath: fileURL.path(percentEncoded: false), isDirectory: &isDir), isDir.boolValue {
                            let last = fileURL.lastPathComponent.lowercased()
                            if excludedDirNames.contains(last) {
                                enumerator.skipDescendants()
                                continue
                            }
                            let lowerPath = fileURL.path(percentEncoded: false).lowercased()
                            if excludedPathSubstrings.contains(where: { lowerPath.contains($0) }) {
                                enumerator.skipDescendants()
                                continue
                            }
                            continue // don't try to add directories as programs
                        }

                        // Regular file - filter and add
                        addIfValid(fileURL)
                    }
                }
            }

            // 2) Fallback: explicitly ensure Program Files roots are covered even
            // if the broad enumerator above was interrupted early. Deduplication via
            // foundLowerPaths keeps this cheap.
            for folderName in ["Program Files", "Program Files (x86)", "ProgramData", "Games", "GOG Games"] {
                let folderURL = driveC.appending(path: folderName)
                guard fileManager.fileExists(atPath: folderURL.path(percentEncoded: false)) else { continue }
                if let enumerator = fileManager.enumerator(
                    at: folderURL,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) {
                    for case let fileURL as URL in enumerator {
                        addIfValid(fileURL)
                    }
                }
            }

            // 3) User profiles - scan each user folder under drive_c/users if present.
            // This catches Start Menu targets that live in AppData/Local, Desktop, etc.
            let usersRoot = driveC.appending(path: "users")
            if fileManager.fileExists(atPath: usersRoot.path(percentEncoded: false)) {
                if let userDirs = try? fileManager.contentsOfDirectory(at: usersRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                    for userDir in userDirs {
                        var isDir: ObjCBool = false
                        guard fileManager.fileExists(atPath: userDir.path(percentEncoded: false), isDirectory: &isDir), isDir.boolValue else { continue }
                        // Skip default system profiles that contain no real installs
                        let lowerName = userDir.lastPathComponent.lowercased()
                        if ["public", "default", "all users", "default user"].contains(lowerName) { continue }
                        if let enumerator = fileManager.enumerator(
                            at: userDir,
                            includingPropertiesForKeys: [.isRegularFileKey],
                            options: [.skipsHiddenFiles]
                        ) {
                            for case let fileURL as URL in enumerator {
                                // Prune Windows junctions inside user profile if any
                                var isDirectory: ObjCBool = false
                                if fileManager.fileExists(atPath: fileURL.path(percentEncoded: false), isDirectory: &isDirectory), isDirectory.boolValue {
                                    let lowerPath = fileURL.path(percentEncoded: false).lowercased()
                                    if lowerPath.contains("/appdata/local/temp") || lowerPath.contains("\\appdata\\local\\temp") {
                                        enumerator.skipDescendants()
                                        continue
                                    }
                                    continue
                                }
                                addIfValid(fileURL)
                            }
                        }
                    }
                }
            }

        case .dosbox:
            let enumerator = FileManager.default.enumerator(
                at: dosGamesFolder,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            while let url = enumerator?.nextObject() as? URL {
                guard !url.hasDirectoryPath else { continue }
                let ext = url.pathExtension.lowercased()
                guard ["exe", "com", "bat"].contains(ext) else { continue }
                let lower = url.path(percentEncoded: false).lowercased()
                if blockLower.contains(lower) { continue }
                if foundLowerPaths.contains(lower) { continue }
                foundLowerPaths.insert(lower)
                programs.append(Program(url: url, bottle: self))
            }
        }

        // Add missing programs from pins (so manually pinned custom paths survive even if block logic changes)
        for pin in settings.pins {
            guard let pinURL = pin.url else { continue }
            let lower = pinURL.path(percentEncoded: false).lowercased()
            guard !foundLowerPaths.contains(lower) else { continue }
            // Respect blocklist even for pins - user explicitly blocked this path
            if blockLower.contains(lower) { continue }
            // Only add if file still exists or is on removable media (mirrors Bottle.init pin filtering)
            if FileManager.default.fileExists(atPath: pinURL.path(percentEncoded: false)) {
                programs.append(Program(url: pinURL, bottle: self))
                foundLowerPaths.insert(lower)
            }
        }

        self.programs = programs.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    @MainActor
    func move(destination: URL) {
        do {
            if let bottle = BottleVM.shared.bottles.first(where: { $0.url == url }) {
                bottle.inFlight = true
                for index in 0..<bottle.settings.pins.count {
                    let pin = bottle.settings.pins[index]
                    if let url = pin.url {
                        bottle.settings.pins[index].url = url.updateParentBottle(old: url,
                                                                                 new: destination)
                    }
                }

                for index in 0..<bottle.settings.blocklist.count {
                    let blockedUrl = bottle.settings.blocklist[index]
                    bottle.settings.blocklist[index] = blockedUrl.updateParentBottle(old: url,
                                                                                     new: destination)
                }
            }
            try FileManager.default.moveItem(at: url, to: destination)
            if let path = BottleVM.shared.bottlesList.paths.firstIndex(of: url) {
                BottleVM.shared.bottlesList.paths[path] = destination
            }
            BottleVM.shared.loadBottles()
        } catch {
            print("Failed to move bottle")
        }
    }

    func exportAsArchive(destination: URL) {
        do {
            try Tar.tar(folder: url, toURL: destination)
        } catch {
            print("Failed to export bottle")
        }
    }

    @MainActor
    func remove(delete: Bool) {
        do {
            if let bottle = BottleVM.shared.bottles.first(where: { $0.url == url }) {
                bottle.inFlight = true
            }

            if delete {
                try FileManager.default.removeItem(at: url)
            }

            if let path = BottleVM.shared.bottlesList.paths.firstIndex(of: url) {
                BottleVM.shared.bottlesList.paths.remove(at: path)
            }
            BottleVM.shared.loadBottles()
        } catch {
            print("Failed to remove bottle")
        }
    }

    @MainActor
    func rename(newName: String) {
        settings.name = newName
    }

    @MainActor private func showRunError(message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "alert.message")
        alert.informativeText = String(localized: "alert.info")
        + " \(self.url.lastPathComponent): "
        + message
        alert.alertStyle = .critical
        alert.addButton(withTitle: String(localized: "button.ok"))
        alert.runModal()
    }
}
