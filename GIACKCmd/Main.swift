//
//  Main.swift
//  GIACKCmd
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
import GIACKKit
import SwiftyTextTable
import Progress
import SemanticVersion
import ArgumentParser

extension BottleRunner: @retroactive ExpressibleByArgument {}
extension BottlePreset: @retroactive ExpressibleByArgument {}

@main
struct GIACK: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A CLI interface for GIACK.",
        subcommands: [List.self,
                      Create.self,
                      Add.self,
//                      Export.self,
                      Delete.self,
                      Remove.self,
                      Run.self,
                      Shellenv.self
                      /*Install.self,
                      Uninstall.self*/])
}

extension GIACK {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List existing bottles.")

        mutating func run() throws {
            var bottlesList = BottleData()
            let bottles = bottlesList.loadBottles()

            let nameCol = TextTableColumn(header: "Name")
            let runnerCol = TextTableColumn(header: "Runner")
            let presetCol = TextTableColumn(header: "Preset")
            let profileCol = TextTableColumn(header: "Profile")
            let pathCol = TextTableColumn(header: "Path")

            var table = TextTable(columns: [nameCol, runnerCol, presetCol, profileCol, pathCol])
            for bottle in bottles {
                let profile = bottle.runner == .wine
                    ? bottle.settings.windowsVersion.pretty()
                    : bottle.settings.dosboxCycles.displayName
                let preset = bottle.settings.appliedPreset?.displayName ?? "Custom"
                table.addRow(values: [bottle.settings.name,
                                      bottle.runner.displayName,
                                      preset,
                                      profile,
                                      bottle.url.prettyPath()])
            }

            print(table.render())
        }
    }

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a new bottle.")

        @Argument var name: String
        @Option(name: .shortAndLong, help: "Runner to use: wine or dosbox.") var runner: BottleRunner = .wine
        @Option(name: .shortAndLong, help: "Compatibility preset to apply.") var preset: BottlePreset?

        mutating func run() throws {
            let bottleURL = BottleData.defaultBottleDir.appending(path: UUID().uuidString)
            let resolvedPreset = preset ?? BottlePreset.defaultPreset(for: runner)
            let resolvedRunner = resolvedPreset.runner

            do {
                switch resolvedRunner {
                case .wine:
                    try FileManager.default.createDirectory(atPath: bottleURL.path(percentEncoded: false),
                                                            withIntermediateDirectories: true)
                case .dosbox:
                    try DOSBox.createBottleLayout(at: bottleURL)
                }

                let bottle = Bottle(bottleUrl: bottleURL, inFlight: true)
                bottle.settings.apply(preset: resolvedPreset)
                bottle.settings.bottleRunner = resolvedRunner
                bottle.settings.name = name
                bottle.settings.wineVersion = SemanticVersion(0, 0, 0)
                if resolvedRunner == .dosbox {
                    try DOSBox.writeConfiguration(for: bottle)
                }

                var bottlesList = BottleData()
                _ = bottlesList.registerBottlePath(bottleURL)
                print("Created new \(resolvedRunner.displayName) bottle \"\(name)\" using the \(resolvedPreset.displayName) preset.")
            } catch {
                throw ValidationError("\(error)")
            }
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Add an existing bottle.")

        @Argument var path: String

        mutating func run() throws {
            let bottleURL = URL(filePath: path)
            var bottlesList = BottleData()
            let importedCount = bottlesList.registerBottlePaths(in: bottleURL)

            guard importedCount > 0 else {
                throw ValidationError("No valid bottle directory was found at \"\(path)\".")
            }

            print("Imported \(importedCount) bottle(s).")
        }
    }

    struct Export: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Export an existing bottle.")

        mutating func run() throws {
//            print("Create a bottle")
        }
    }

    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Delete an existing bottle from disk.")

        @Argument var name: String

        mutating func run() throws {
            var bottlesList = BottleData()
            let bottles = bottlesList.loadBottles()

            // Should ask for confirmation
            let bottleToRemove = bottles.first(where: { $0.settings.name == name })
            if let bottleToRemove = bottleToRemove {
                bottlesList.paths.removeAll(where: { $0 == bottleToRemove.url })
                do {
                    try FileManager.default.removeItem(at: bottleToRemove.url)
                    print("Deleted \"\(name)\".")
                } catch {
                    print(error)
                }
            } else {
                throw ValidationError("No bottle called \"\(name)\" found.")
            }
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove an existing bottle from GIACK.",
                                                        discussion: "This will not remove the bottle from disk.")

        @Argument var name: String

        mutating func run() throws {
            var bottlesList = BottleData()
            let bottles = bottlesList.loadBottles()

            let bottleToRemove = bottles.first(where: { $0.settings.name == name })
            if let bottleToRemove = bottleToRemove {
                bottlesList.paths.removeAll(where: { $0 == bottleToRemove.url })
                print("Removed \"\(name)\".")
            } else {
                throw ValidationError("No bottle called \"\(name)\" found.")
            }
        }
    }

    struct Run: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Run a program with GIACK.")

        @Argument var bottleName: String
        @Argument var path: String
        @Argument var args: [String] = []

        mutating func run() throws {
            var bottlesList = BottleData()
            let bottles = bottlesList.loadBottles()

            guard let bottle = bottles.first(where: { $0.settings.name == bottleName }) else {
                throw ValidationError("A bottle with that name doesn't exist.")
            }

            let url = URL(fileURLWithPath: path)
            let program = Program(url: url, bottle: bottle)
            program.runInTerminal()
        }
    }

    struct Shellenv: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Prints export statements for a Bottle for eval.")

        @Argument var bottleName: String

        mutating func run() throws {
            var bottlesList = BottleData()
            let bottles = bottlesList.loadBottles()

            guard let bottle = bottles.first(where: { $0.settings.name == bottleName }) else {
                throw ValidationError("A bottle with that name doesn't exist.")
            }

            let envCmd: String
            switch bottle.runner {
            case .wine:
                envCmd = Wine.generateTerminalEnvironmentCommand(bottle: bottle)
            case .dosbox:
                let alias = DOSBox.executableURL()?.path ?? "dosbox-staging"
                envCmd = """
                cd \"\(bottle.dosGamesFolder.path(percentEncoded: false))\"
                alias dosbox=\"\(alias)\"
                """
            }
            print(envCmd)

        }
    }

    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Install the GPTK runtime.")

        mutating func run() throws {

        }
    }

    struct Uninstall: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Uninstall the GPTK runtime.")

        @Flag(name: [.long, .short], help: "Uninstall the GPTK runtime") var whiskyWine = false

        mutating func run() throws {

        }
    }
}
