//
//  ProgramMenuView.swift
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

struct ProgramMenuView: View {
    @ObservedObject var program: Program
    @Binding var path: NavigationPath

    var body: some View {
        Button("button.run", systemImage: "play") {
            program.run()
        }
        .labelStyle(.titleAndIcon)
        .help("Launch this program now.")
        Section("program.settings") {
            Button("program.config", systemImage: "gearshape") {
                path.append(program)
            }
            .labelStyle(.titleAndIcon)
            .help("Open this program's runner, locale, and shortcut settings.")

            let buttonName = program.pinned
            ? String(localized: "button.unpin")
            : String(localized: "button.pin")

            Button(buttonName, systemImage: "pin") {
                program.pinned.toggle()
            }
            .labelStyle(.titleAndIcon)
            .symbolVariant(program.pinned ? .slash : .none)
            .help(program.pinned
                  ? "Remove this program from Quick Launch."
                  : "Pin this program to Quick Launch.")
        }
    }
}
