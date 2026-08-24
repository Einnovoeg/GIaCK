//
//  Program+Extensions.swift
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
import os.log

extension Program {
    public func run() {
        if NSEvent.modifierFlags.contains(.shift) {
            self.runInTerminal()
        } else {
            self.runInWine()
        }
    }

    func runInWine() {
        let arguments = String.shellSplit(settings.arguments)
        let environment = generateEnvironment()

        Task.detached(priority: .userInitiated) {
            do {
                switch self.bottle.runner {
                case .wine:
                    try await Wine.runProgram(
                        at: self.url, args: arguments, bottle: self.bottle, environment: environment
                    )
                case .dosbox:
                    try await DOSBox.run(bottle: self.bottle, programURL: self.url, arguments: arguments)
                }
            } catch {
                await MainActor.run {
                    self.showRunError(message: error.localizedDescription)
                }
            }
        }
    }

    public func generateTerminalCommand() -> String {
        switch bottle.runner {
        case .wine:
            return Wine.generateRunCommand(
                at: self.url, bottle: bottle, args: settings.arguments, environment: generateEnvironment()
            )
        case .dosbox:
            return DOSBox.generateRunCommand(
                bottle: bottle,
                programURL: self.url,
                arguments: settings.arguments
            )
        }
    }

    public func runInTerminal() {
        let terminalCommand = generateTerminalCommand().appleScriptEscaped

        let script = """
        tell application "Terminal"
            activate
            do script "\(terminalCommand)"
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
