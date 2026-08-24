//
//  GIACKApp.swift
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

import SwiftUI
import Sparkle
import GIACKKit

@main
struct GIACKApp: App {
    @State var showSetup: Bool = false
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openURL) var openURL
    private let updaterController: SPUStandardUpdaterController?

    init() {
        let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        if let feedURL = feedURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !feedURL.isEmpty {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        } else {
            updaterController = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(showSetup: $showSetup)
                .frame(minWidth: ViewWidth.large, minHeight: 316)
                .environmentObject(BottleVM.shared)
                .onAppear {
                    NSWindow.allowsAutomaticWindowTabbing = false

                    Task.detached {
                        await GIACKApp.deleteOldLogs()
                    }
                }
        }
        .handlesExternalEvents(preferring: [], allowing: ["*"])
        .commands {
            CommandGroup(after: .appInfo) {
                if let updater = updaterController?.updater {
                    SparkleView(updater: updater)
                }
            }
            CommandGroup(before: .systemServices) {
                Divider()
                Button("open.setup") {
                    showSetup = true
                }
                Button(String(localized: "install.cli", defaultValue: "Install GIACK CLI...")) {
                    Task {
                        await GIACKCmd.install()
                    }
                }
            }
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("open.bottle") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = false
                    panel.begin { result in
                        if result == .OK {
                            if let url = panel.urls.first {
                                let importedCount = BottleVM.shared.bottlesList.registerBottlePaths(in: url)
                                BottleVM.shared.loadBottles()
                                if importedCount == 0 {
                                    GIACKApp.showBottleImportAlert()
                                }
                            }
                        }
                    }
                }
                .keyboardShortcut("I", modifiers: [.command])
            }
            CommandGroup(after: .importExport) {
                Button("open.logs") {
                    GIACKApp.openLogsFolder()
                }
                .keyboardShortcut("L", modifiers: [.command])
                Button("kill.bottles") {
                    GIACKApp.killBottles()
                }
                .keyboardShortcut("K", modifiers: [.command, .shift])
                Button("wine.clearShaderCaches") {
                    GIACKApp.killBottles() // Better not make things more complicated for ourselves
                    GIACKApp.wipeShaderCaches()
                }
            }
            CommandGroup(replacing: .help) {
                Button(String(localized: "help.repository", defaultValue: "Project Repository")) {
                    openURL(ProjectInfo.repositoryURL)
                }
                Button(String(localized: "help.releases", defaultValue: "Latest Releases")) {
                    openURL(ProjectInfo.releasesURL)
                }
                Button(String(localized: "help.issues", defaultValue: "Report an Issue")) {
                    openURL(ProjectInfo.issuesURL)
                }
                if let readmeURL = ProjectInfo.bundledDocumentURL(.readme) {
                    Button(String(localized: "help.readme", defaultValue: "Installation Guide")) {
                        openURL(readmeURL)
                    }
                }
                if let changelogURL = ProjectInfo.bundledDocumentURL(.changelog) {
                    Button(String(localized: "help.changelog", defaultValue: "Changelog")) {
                        openURL(changelogURL)
                    }
                }
                Button(String(localized: "help.upstream", defaultValue: "Archived Upstream Repository")) {
                    openURL(ProjectInfo.archivedRepositoryURL)
                }
                Button(String(localized: "help.runtime", defaultValue: "Game Porting Toolkit Releases")) {
                    openURL(ProjectInfo.runtimeReleasesURL)
                }
                Button(String(localized: "help.notices", defaultValue: "Third-Party Notices")) {
                    openURL(ProjectInfo.documentURL(.thirdPartyNotices))
                }
                Button(String(localized: "help.license", defaultValue: "Project License")) {
                    openURL(ProjectInfo.documentURL(.license))
                }
                Button(String(localized: "help.support", defaultValue: "Buy Me a Coffee")) {
                    openURL(ProjectInfo.fundingURL)
                }
            }
        }
        Settings {
            SettingsView()
        }
    }

    static func killBottles() {
        for bottle in BottleVM.shared.bottles {
            Wine.killBottle(bottle: bottle)
        }
    }

    static func openLogsFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: Wine.logsFolder.path)
    }

    static func deleteOldLogs() {
        let pastDate = Date().addingTimeInterval(-7 * 24 * 60 * 60)

        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: Wine.logsFolder,
            includingPropertiesForKeys: [.creationDateKey]) else {
            return
        }

        let logs = urls.filter { url in
            url.pathExtension == "log"
        }

        let oldLogs = logs.filter { url in
            do {
                let resourceValues = try url.resourceValues(forKeys: [.creationDateKey])

                return resourceValues.creationDate ?? Date() < pastDate
            } catch {
                return false
            }
        }

        for log in oldLogs {
            do {
                try FileManager.default.removeItem(at: log)
            } catch {
                print("Failed to delete log: \(error)")
            }
        }
    }

    static func wipeShaderCaches() {
        let getconf = Process()
        getconf.executableURL = URL(fileURLWithPath: "/usr/bin/getconf")
        getconf.arguments = ["DARWIN_USER_CACHE_DIR"]
        let pipe = Pipe()
        getconf.standardOutput = pipe
        do {
            try getconf.run()
        } catch {
            return
        }
        getconf.waitUntilExit()
        let getconfOutput: Data
        do {
            getconfOutput = try pipe.fileHandleForReading.readToEnd() ?? Data()
        } catch {
            getconfOutput = pipe.fileHandleForReading.readDataToEndOfFile()
        }
        guard let getconfOutputString = String(data: getconfOutput, encoding: .utf8) else { return }
        let d3dmPath = URL(fileURLWithPath: getconfOutputString.trimmingCharacters(in: .whitespacesAndNewlines))
            .appending(path: "d3dm").path
        do {
            try FileManager.default.removeItem(atPath: d3dmPath)
        } catch {
            return
        }
    }

    @MainActor
    static func showBottleImportAlert() {
        let alert = NSAlert()
        alert.messageText = String(
            localized: "alert.importBottle.message",
            defaultValue: "No bottles were imported."
        )
        alert.informativeText = String(
            localized: "alert.importBottle.info",
            defaultValue: "Select a bottle folder, or a folder that contains bottle folders with a Metadata.plist or drive_c directory."
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "button.ok"))
        alert.runModal()
    }
}
