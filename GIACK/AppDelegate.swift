//
//  AppDelegate.swift
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
import SwiftUI
import GIACKKit

@MainActor
final class GIACKActivityController {
    static let shared = GIACKActivityController()
    private var appNapActivity: NSObjectProtocol?

    private init() {}

    func applyPreferences() {
        setAppNapDisabled(UserDefaults.standard.object(forKey: "disableAppNap") as? Bool ?? true)
    }

    func setAppNapDisabled(_ disabled: Bool) {
        if disabled {
            guard appNapActivity == nil else { return }
            appNapActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated],
                reason: "Preventing App Nap for bottle stability"
            )
        } else if let appNapActivity {
            ProcessInfo.processInfo.endActivity(appNapActivity)
            self.appNapActivity = nil
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    @AppStorage("hasShownMoveToApplicationsAlert") private var hasShownMoveToApplicationsAlert = false

    func application(_ application: NSApplication, open urls: [URL]) {
        // Test if automatic window tabbing is enabled
        // as it is disabled when ContentView appears
        if NSWindow.allowsAutomaticWindowTabbing, let url = urls.first {
            // Reopen the file after GIACK has been opened
            // so that the `onOpenURL` handler is actually called
            NSWorkspace.shared.open(url)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        GIACKActivityController.shared.applyPreferences()

        if !hasShownMoveToApplicationsAlert && !AppDelegate.insideAppsFolder {
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                NSApp.activate(ignoringOtherApps: true)
                self.showAlertOnFirstLaunch()
                self.hasShownMoveToApplicationsAlert = true
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if UserDefaults.standard.bool(forKey: "killOnTerminate") {
            GIACKApp.killBottles()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    private static var appUrl: URL? {
        Bundle.main.resourceURL?.deletingLastPathComponent().deletingLastPathComponent()
    }

    private static var expectedURL: URL {
        URL(fileURLWithPath: "/Applications")
            .appending(path: Bundle.main.bundleURL.lastPathComponent)
    }

    private static var appDisplayName: String {
        Bundle.appDisplayName
    }

    private static var insideAppsFolder: Bool {
        if let url = appUrl {
            return url.path.contains("Xcode") || url.path.contains(expectedURL.path)
        }
        return false
    }

    @MainActor
    private func showAlertOnFirstLaunch() {
        let alert = NSAlert()
        alert.messageText = localizedStringWithDisplayName("showAlertOnFirstLaunch.messageText")
        alert.informativeText = localizedStringWithDisplayName("showAlertOnFirstLaunch.informativeText")
        alert.addButton(withTitle: String(localized: "showAlertOnFirstLaunch.button.moveToApplications"))
        alert.addButton(withTitle: String(localized: "showAlertOnFirstLaunch.button.dontMove"))

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            let appURL = Bundle.main.bundleURL

            do {
                _ = try FileManager.default.replaceItemAt(AppDelegate.expectedURL, withItemAt: appURL)
                NSWorkspace.shared.open(AppDelegate.expectedURL)
            } catch {
                print("Failed to move the app: \(error)")
            }
        }
    }

    private func localizedStringWithDisplayName(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
            .replacingOccurrences(of: "GIACK", with: AppDelegate.appDisplayName)
            .replacingOccurrences(of: "Whiskey", with: AppDelegate.appDisplayName)
    }
}
