//
//  BottleVM.swift
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
import SemanticVersion
import GIACKKit

/// Shared bottle state for the SwiftUI app.
///
/// Bottle creation is intentionally asynchronous because creating the prefix and
/// querying the runtime version can block for a noticeable amount of time.
/// `@unchecked Sendable` is used here because detached setup work captures this
/// object, but all published UI mutations are marshalled back to `MainActor`.
final class BottleVM: ObservableObject, @unchecked Sendable {
    @MainActor static let shared = BottleVM()

    var bottlesList = BottleData()
    @Published var bottles: [Bottle] = []

    @MainActor
    func loadBottles() {
        bottles = bottlesList.loadBottles()
    }

    func countActive() -> Int {
        bottles.filter { $0.isAvailable == true }.count
    }

    /// Creates the bottle directory immediately and then finishes the heavier
    /// Wine prefix setup off the main thread. The URL is returned up front so
    /// the UI can select and scroll to the placeholder entry while setup runs.
    func createNewBottle(
        bottleName: String,
        winVersion: WinVersion,
        runner: BottleRunner,
        bottleURL: URL,
        preset: BottlePreset? = nil
    ) -> URL {
        let newBottleDir = bottleURL.appending(path: UUID().uuidString)

        Task.detached {
            var bottleId: Bottle?
            do {
                switch runner {
                case .wine:
                    try FileManager.default.createDirectory(atPath: newBottleDir.path(percentEncoded: false),
                                                            withIntermediateDirectories: true)
                case .dosbox:
                    try DOSBox.createBottleLayout(at: newBottleDir)
                }

                let bottle = Bottle(bottleUrl: newBottleDir, inFlight: true)
                bottleId = bottle
                if let preset {
                    bottle.settings.apply(preset: preset)
                }
                bottle.settings.name = bottleName
                bottle.settings.bottleRunner = runner
                if runner == .wine {
                    bottle.settings.windowsVersion = winVersion
                }

                await MainActor.run {
                    // Register the path before prefix creation completes so the
                    // list stays in sync with the in-flight bottle placeholder.
                    self.bottlesList.registerBottlePath(newBottleDir)
                    self.bottles.append(bottle)
                }

                switch runner {
                case .wine:
                    try await Wine.changeWinVersion(bottle: bottle, win: winVersion)
                    do {
                        let wineVer = try await Wine.wineVersion()
                        bottle.settings.wineVersion = SemanticVersion(wineVer) ?? SemanticVersion(0, 0, 0)
                    } catch {
                        print("Failed to determine bottle wine version: \(error)")
                    }
                case .dosbox:
                    try DOSBox.writeConfiguration(for: bottle)
                }

                await MainActor.run {
                    self.loadBottles()
                }
            } catch {
                print("Failed to create new bottle: \(error)")
                // If setup made it far enough to create a real prefix, keep the
                // bottle entry instead of hiding a partially recoverable bottle.
                let keepBottle = BottleData.looksLikeBottleDirectory(newBottleDir)

                await MainActor.run {
                    if keepBottle {
                        self.bottlesList.registerBottlePath(newBottleDir)
                        self.loadBottles()
                    } else if let bottle = bottleId {
                        if let index = self.bottles.firstIndex(of: bottle) {
                            self.bottles.remove(at: index)
                        }
                        self.bottlesList.removeBottlePath(newBottleDir)
                    }
                }
            }
        }
        return newBottleDir
    }
}
