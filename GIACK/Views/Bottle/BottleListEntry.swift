//
//  BottleListEntry.swift
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
import UniformTypeIdentifiers

struct BottleListEntry: View {
    @AppStorage("useGlassUI") private var useGlassUI = false
    let bottle: Bottle
    @Binding var selected: URL?

    @State private var showBottleRename = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconBackground)
                    .frame(width: 30, height: 30)
                Image(systemName: bottle.isAvailable ? bottle.runner.systemImage : "externaldrive.badge.xmark")
                    .foregroundStyle(bottle.isAvailable ? runnerTint : .secondary)
            }
            .help(bottle.isAvailable
                  ? "Runner: \(bottle.runner.displayName)"
                  : "This library is unavailable because its runtime is missing.")

            VStack(alignment: .leading, spacing: 2) {
                Text(bottle.settings.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if !bottle.isAvailable {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            if useGlassUI && isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    }
            }
        }
        .opacity(bottle.isAvailable ? 1.0 : 0.6)
        .sheet(isPresented: $showBottleRename) {
            RenameView("rename.bottle.title", name: bottle.settings.name) { newName in
                bottle.rename(newName: newName)
            }
        }
        .contextMenu {
            Button("button.rename", systemImage: "pencil.line") {
                showBottleRename.toggle()
            }
            .disabled(!bottle.isAvailable)
            .labelStyle(.titleAndIcon)

            Button("button.removeAlert", systemImage: "trash") {
                showRemoveAlert(bottle: bottle)
            }
            .labelStyle(.titleAndIcon)

            Divider()

            Button("button.moveBottle", systemImage: "shippingbox.and.arrow.backward") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.canCreateDirectories = true
                panel.begin { result in
                    if result == .OK, let url = panel.urls.first {
                        let newBottlePath = url.appending(path: bottle.url.lastPathComponent)
                        bottle.move(destination: newBottlePath)
                        selected = newBottlePath
                    }
                }
            }
            .disabled(!bottle.isAvailable)
            .labelStyle(.titleAndIcon)

            Button("button.exportBottle", systemImage: "arrowshape.turn.up.right") {
                let panel = NSSavePanel()
                panel.canCreateDirectories = true
                panel.allowedContentTypes = [UTType.gzip]
                panel.allowsOtherFileTypes = false
                panel.isExtensionHidden = false
                panel.nameFieldStringValue = bottle.settings.name + ".tar"
                panel.begin { result in
                    if result == .OK, let url = panel.url {
                        Task.detached(priority: .background) {
                            bottle.exportAsArchive(destination: url)
                        }
                    }
                }
            }
            .disabled(!bottle.isAvailable)
            .labelStyle(.titleAndIcon)

            Divider()

            Button("button.showInFinder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([bottle.url])
            }
            .disabled(!bottle.isAvailable)
            .labelStyle(.titleAndIcon)
        }
    }

    private var isSelected: Bool {
        selected == bottle.url
    }

    private var subtitle: String {
        if bottle.runner == .wine {
            let runtimeLabel: String = {
                switch bottle.settings.effectiveWineRuntime {
                case .gptkManaged: return "GPTK"
                case .wineStable: return "Stable"
                case .wineDevel: return "Devel"
                case .wineStaging: return "Staging"
                }
            }()
            var parts = [runtimeLabel, bottle.settings.windowsVersion.pretty(), bottle.settings.dxvk ? "DXVK" : "D3DMetal"]
            if bottle.settings.perBottleWineRuntimeSelection != nil {
                parts.append("Per-Bottle")
            }
            if bottle.settings.avxEnabled {
                parts.append("AVX")
            }
            return parts.joined(separator: " • ")
        }

        var parts = [bottle.settings.dosboxCycles.displayName]
        if bottle.settings.dosboxStartupProgram != nil {
            parts.append("Startup Game")
        }
        return parts.joined(separator: " • ")
    }

    private var runnerTint: Color {
        switch bottle.runner {
        case .wine:
            return .pink
        case .dosbox:
            return .orange
        }
    }

    private var iconBackground: Color {
        useGlassUI ? Color.white.opacity(0.08) : Color.secondary.opacity(0.10)
    }

    private func showRemoveAlert(bottle: Bottle) {
        let checkbox = NSButton(
            checkboxWithTitle: String(localized: "button.removeAlert.checkbox"),
            target: self,
            action: nil
        )
        let alert = NSAlert()
        alert.messageText = String(
            format: String(localized: "button.removeAlert.msg"),
            bottle.settings.name
        )
        alert.informativeText = String(localized: "button.removeAlert.info")
        alert.alertStyle = .warning
        let delete = alert.addButton(withTitle: String(localized: "button.removeAlert.delete"))
        delete.hasDestructiveAction = true
        alert.addButton(withTitle: String(localized: "button.removeAlert.cancel"))
        if bottle.isAvailable {
            alert.accessoryView = checkbox
        }

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            Task(priority: .userInitiated) {
                if selected == bottle.url {
                    selected = nil
                }

                bottle.remove(delete: checkbox.state == .on)
            }
        }
    }
}

#Preview {
    BottleListEntry(
        bottle: Bottle(bottleUrl: URL(filePath: "")),
        selected: .constant(nil)
    )
}
