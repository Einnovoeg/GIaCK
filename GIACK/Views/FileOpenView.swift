//
//  FileOpenView.swift
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
import GIACKKit

struct FileOpenView: View {
    var fileURL: URL
    var currentBottle: URL?
    var bottles: [Bottle]

    @State private var selection: URL = URL(filePath: "")
    @Environment(\.dismiss) private var dismiss

    private var availableBottles: [Bottle] {
        bottles.filter(\.isAvailable)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("run.bottle", selection: $selection) {
                    ForEach(availableBottles, id: \.self) {
                        Text("\($0.settings.name) · \($0.runner.displayName)")
                            .tag($0.url)
                    }
                }
                .help("Choose which runtime library should open this file.")
            }
            .frame(maxHeight: .infinity)
            .formStyle(.grouped)
            .navigationTitle(String(format: String(localized: "run.title"), fileURL.lastPathComponent))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("create.cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    .help("Close this sheet without opening the selected file.")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("button.run") {
                        run()
                    }
                    .keyboardShortcut(.defaultAction)
                    .help("Open this file with the selected library.")
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: ViewWidth.small)
        .onAppear {
            // Makes sure there are more than 0 bottles.
            // Otherwise, it will crash on the nil cascade
            if availableBottles.isEmpty {
                dismiss()
                return
            }

            selection = availableBottles.first(where: { $0.url == currentBottle })?.url ?? availableBottles[0].url

            if availableBottles.count == 1 {
                // If the user only has one bottle
                // there's nothing for them to select
                run()
            }
        }
    }

    func run() {
        if let bottle = availableBottles.first(where: { $0.url == selection }) {
            Task.detached(priority: .userInitiated) {
                do {
                    switch bottle.runner {
                    case .wine:
                        if fileURL.pathExtension.lowercased() == "bat" {
                            try await Wine.runBatchFile(url: fileURL, bottle: bottle)
                        } else {
                            try await Wine.runProgram(at: fileURL, bottle: bottle)
                        }
                    case .dosbox:
                        try await DOSBox.run(bottle: bottle, programURL: fileURL)
                    }
                } catch {
                    print(error)
                }
            }
            dismiss()
        }
    }
}
