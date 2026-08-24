//
//  Winetricks.swift
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

enum WinetricksCategories: String {
    case apps
    case benchmarks
    case dlls
    case fonts
    case games
    case settings
}

struct WinetricksVerb: Identifiable {
    var id = UUID()

    var name: String
    var description: String
}

struct WinetricksCategory {
    var category: WinetricksCategories
    var verbs: [WinetricksVerb]
}

class Winetricks {
    static let winetricksURL: URL = GIACKWineInstaller.libraryFolder
        .appending(path: "winetricks")

    /// Search the app bundle first and then common PATH entries so public builds
    /// can rely on an external `cabextract` install instead of redistributing it.
    static func cabextractDirectory() -> URL? {
        if let bundledDirectory = Bundle.main.url(forResource: "cabextract", withExtension: nil)?
            .deletingLastPathComponent() {
            return bundledDirectory
        }

        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let fallbackDirectories = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        for directory in pathEntries + fallbackDirectories {
            let directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
            let executableURL = directoryURL.appending(path: "cabextract")
            if FileManager.default.isExecutableFile(atPath: executableURL.path(percentEncoded: false)) {
                return directoryURL
            }
        }

        return nil
    }

    static func hasCabextract() -> Bool {
        cabextractDirectory() != nil
    }

    /// Runs Winetricks in Terminal so the user can monitor long-running verbs
    /// and interact with prompts that are still terminal-driven upstream.
    static func runCommand(command: String, bottle: Bottle) async {
        guard let cabextractDirectory = cabextractDirectory() else {
            await showMissingCabextractAlert()
            return
        }

        // swiftlint:disable:next line_length
        let winetricksCmd = #"PATH=\"\#(GIACKWineInstaller.binFolder.path):\#(cabextractDirectory.path(percentEncoded: false)):$PATH\" WINE=wine64 WINEPREFIX=\"\#(bottle.url.path)\" \"\#(winetricksURL.path(percentEncoded: false))\" \#(command)"#

        let script = """
        tell application "Terminal"
            activate
            do script "\(winetricksCmd.appleScriptEscaped)"
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)

            if let error = error {
                print(error)
                if let description = error["NSAppleScriptErrorMessage"] as? String {
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = String(localized: "alert.message")
                        alert.informativeText = String(localized: "alert.info")
                            + " \(command): "
                            + description
                        alert.alertStyle = .critical
                        alert.addButton(withTitle: String(localized: "button.ok"))
                        alert.runModal()
                    }
                }
            }
        }
    }

    @MainActor
    private static func showMissingCabextractAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "winetricks.cabextract.title",
                                   defaultValue: "cabextract is required for Winetricks")
        alert.informativeText = String(
            localized: "winetricks.cabextract.info",
            defaultValue: "Install cabextract with Homebrew (`brew install cabextract`) and try again."
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "button.ok"))
        alert.runModal()
    }

    static func parseVerbs() async -> [WinetricksCategory] {
        // `verbs.txt` is distributed with the runtime and keeps the UI aligned
        // with the actual Winetricks build available in the installed runtime.
        let verbsURL = GIACKWineInstaller.libraryFolder.appending(path: "verbs.txt")
        let verbs: String
        do {
            verbs = try String(contentsOf: verbsURL, encoding: .utf8)
        } catch {
            return []
        }

        // Read the file line by line
        let lines = verbs.components(separatedBy: "\n")
        var categories: [WinetricksCategory] = []
        var currentCategory: WinetricksCategory?

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            // Categories are label as "===== <name> ====="
            if line.starts(with: "=====") {
                // If we have a current category, add it to the list
                if let currentCategory = currentCategory {
                    categories.append(currentCategory)
                }

                // Create a new category
                // Capitalize the first letter of the category name
                let categoryName = line.replacingOccurrences(of: "=====", with: "").trimmingCharacters(in: .whitespaces)
                if let category = WinetricksCategories(rawValue: categoryName) {
                    currentCategory = WinetricksCategory(category: category,
                                                         verbs: [])
                } else {
                    currentCategory = nil
                }
            } else {
                guard currentCategory != nil else {
                    continue
                }

                // If we have a current category, add the verb to it
                // Verbs eg. "3m_library               3M Cloud Library (3M Company, 2015) [downloadable]"
                let components = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
                guard let verbName = components.first.map(String.init) else {
                    continue
                }
                let verbDescription = components.count > 1
                    ? String(components[1]).trimmingCharacters(in: .whitespaces)
                    : ""
                currentCategory?.verbs.append(WinetricksVerb(name: verbName, description: verbDescription))
            }
        }

        // Add the last category
        if let currentCategory = currentCategory {
            categories.append(currentCategory)
        }

        return categories
    }
}
