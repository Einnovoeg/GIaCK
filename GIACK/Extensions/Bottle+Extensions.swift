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
            guard let whiskyCmdURL = Bundle.main.url(forResource: "GIACKCmd", withExtension: nil) else { return }
            let whiskyCmd = whiskyCmdURL.path(percentEncoded: false)
            command = "eval \\\"$(\(whiskyCmd.esc) shellenv \(settings.name.esc))\\\""
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

    @discardableResult
    func getStartMenuPrograms() -> [Program] {
        guard runner == .wine else {
            return []
        }

        let globalStartMenu = url
            .appending(path: "drive_c")
            .appending(path: "ProgramData")
            .appending(path: "Microsoft")
            .appending(path: "Windows")
            .appending(path: "Start Menu")

        let userStartMenu = url
            .appending(path: "drive_c")
            .appending(path: "users")
            .appending(path: "crossover")
            .appending(path: "AppData")
            .appending(path: "Roaming")
            .appending(path: "Microsoft")
            .appending(path: "Windows")
            .appending(path: "Start Menu")

        var startMenuPrograms: [Program] = []
        var linkURLs: [URL] = []
        let globalEnumerator = FileManager.default.enumerator(at: globalStartMenu,
                                                              includingPropertiesForKeys: [.isRegularFileKey],
                                                              options: [.skipsHiddenFiles])
        while let url = globalEnumerator?.nextObject() as? URL {
            if url.pathExtension == "lnk" {
                linkURLs.append(url)
            }
        }

        let userEnumerator = FileManager.default.enumerator(at: userStartMenu,
                                                            includingPropertiesForKeys: [.isRegularFileKey],
                                                            options: [.skipsHiddenFiles])
        while let url = userEnumerator?.nextObject() as? URL {
            if url.pathExtension == "lnk" {
                linkURLs.append(url)
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

    func updateInstalledPrograms() {
        var programs: [Program] = []
        var foundURLS: Set<URL> = []

        switch runner {
        case .wine:
            let driveC = url.appending(path: "drive_c")

            for folderName in ["Program Files", "Program Files (x86)"] {
                let folderURL = driveC.appending(path: folderName)
                let enumerator = FileManager.default.enumerator(
                    at: folderURL, includingPropertiesForKeys: [.isExecutableKey], options: [.skipsHiddenFiles]
                )

                while let url = enumerator?.nextObject() as? URL {
                    guard !url.hasDirectoryPath && url.pathExtension == "exe" else { continue }
                    guard !settings.blocklist.contains(url) else { continue }
                    foundURLS.insert(url)
                    programs.append(Program(url: url, bottle: self))
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
                guard !settings.blocklist.contains(url) else { continue }
                foundURLS.insert(url)
                programs.append(Program(url: url, bottle: self))
            }
        }

        // Add missing programs from pins
        for pin in settings.pins {
            guard let url = pin.url else { continue }
            guard !foundURLS.contains(url) else { continue }
            programs.append(Program(url: url, bottle: self))
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
