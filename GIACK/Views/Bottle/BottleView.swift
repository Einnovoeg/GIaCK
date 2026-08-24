//
//  BottleView.swift
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
import UniformTypeIdentifiers
import GIACKKit

enum BottleStage: String, CaseIterable, Identifiable {
    case overview
    case programs
    case config
    case processes

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .overview:
            "Overview"
        case .programs:
            "tab.programs"
        case .config:
            "tab.config"
        case .processes:
            "Processes"
        }
    }
}

struct BottleView: View {
    @AppStorage("useGlassUI") private var useGlassUI = false
    @ObservedObject var bottle: Bottle
    @State private var path = NavigationPath()
    @State private var selectedStage: BottleStage = .overview
    @State private var programLoading = false
    @State private var showWinetricksSheet = false

    // Keep the quick-launch grid compact so one or two pins do not stretch into an
    // oversized empty panel. The previous adaptive-to-infinity layout is what made
    // the screen feel visually broken even when the underlying actions still worked.
    private let pinGridLayout = [GridItem(.adaptive(minimum: 112, maximum: 132), spacing: 12, alignment: .leading)]

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 16) {
                BottleHeaderView(
                    bottle: bottle,
                    useGlassUI: useGlassUI,
                    programLoading: programLoading,
                    showWinetricks: { showWinetricksSheet = true },
                    runProgram: openRunPicker
                )

                stagePicker

                stageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(useGlassUI ? 18 : 0)
            .disabled(!bottle.isAvailable)
            .navigationTitle(bottle.settings.name)
            .sheet(isPresented: $showWinetricksSheet) {
                WinetricksView(bottle: bottle)
            }
            .onAppear {
                updateStartMenu()
                normalizeSelectedStage()
            }
            .onChange(of: bottle.settings) { oldValue, newValue in
                guard oldValue != newValue else { return }
                BottleVM.shared.bottles = BottleVM.shared.bottles
            }
            .onChange(of: bottle.runner) {
                normalizeSelectedStage()
            }
            .navigationDestination(for: Program.self) { program in
                ProgramView(program: program)
            }
        }
    }

    private var availableStages: [BottleStage] {
        bottle.runner == .wine
        ? [.overview, .programs, .config, .processes]
        : [.overview, .programs, .config]
    }

    private var stagePicker: some View {
        Picker("Section", selection: $selectedStage) {
            ForEach(availableStages) { stage in
                Text(stage.title).tag(stage)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, useGlassUI ? 4 : 0)
        .help("Switch between the bottle overview, installed programs, configuration, and running processes.")
    }

    @ViewBuilder
    private var stageContent: some View {
        switch selectedStage {
        case .overview:
            overviewContent
        case .programs:
            ProgramsView(bottle: bottle, path: $path)
        case .config:
            ConfigView(bottle: bottle)
        case .processes:
            RunningProcessesView(bottle: bottle)
        }
    }

    private var overviewContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PinnedProgramsSection(
                    bottle: bottle,
                    path: $path,
                    pinGridLayout: pinGridLayout,
                    useGlassUI: useGlassUI
                )
                OverviewMetricsSection(bottle: bottle)
                BottleDetailsSection(bottle: bottle, useGlassUI: useGlassUI)
            }
            .padding(.bottom, 18)
        }
        .scrollContentBackground(useGlassUI ? .hidden : .automatic)
    }

    private func normalizeSelectedStage() {
        if !availableStages.contains(selectedStage) {
            selectedStage = .overview
        }
    }

    private func updateStartMenu() {
        bottle.updateInstalledPrograms()

        guard bottle.runner == .wine else {
            return
        }

        let startMenuPrograms = bottle.getStartMenuPrograms()
        for startMenuProgram in startMenuPrograms {
            for program in bottle.programs where
            // Keep the comparison case-insensitive because Wine may vary casing for
            // the same path between discovery passes.
            program.url.path().caseInsensitiveCompare(startMenuProgram.url.path()) == .orderedSame {
                program.pinned = true
                guard !bottle.settings.pins.contains(where: { $0.url == program.url }) else { continue }
                bottle.settings.pins.append(PinnedProgram(
                    name: program.url.deletingPathExtension().lastPathComponent,
                    url: program.url
                ))
            }
        }
    }

    private func openRunPicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        switch bottle.runner {
        case .wine:
            panel.allowedContentTypes = [
                UTType.exe,
                UTType(exportedAs: "com.microsoft.msi-installer"),
                UTType(exportedAs: "com.microsoft.bat")
            ]
            panel.directoryURL = bottle.url.appending(path: "drive_c")
        case .dosbox:
            panel.allowedContentTypes = [
                UTType(filenameExtension: "exe") ?? .data,
                UTType(filenameExtension: "com") ?? .data,
                UTType(filenameExtension: "bat") ?? .data
            ]
            panel.directoryURL = bottle.dosGamesFolder
        }

        panel.begin { result in
            programLoading = true
            Task(priority: .userInitiated) {
                defer {
                    programLoading = false
                    updateStartMenu()
                }

                guard result == .OK, let url = panel.urls.first else {
                    return
                }

                do {
                    switch bottle.runner {
                    case .wine:
                        if url.pathExtension.lowercased() == "bat" {
                            try await Wine.runBatchFile(url: url, bottle: bottle)
                        } else {
                            try await Wine.runProgram(at: url, bottle: bottle)
                        }
                    case .dosbox:
                        try await DOSBox.run(bottle: bottle, programURL: url)
                    }
                } catch {
                    print("Failed to launch program: \(error)")
                }
            }
        }
    }
}

private struct BottleHeaderView: View {
    let bottle: Bottle
    let useGlassUI: Bool
    let programLoading: Bool
    let showWinetricks: () -> Void
    let runProgram: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                        .frame(width: 56, height: 56)
                    Image(systemName: bottle.runner == .wine ? "wineglass.fill" : "opticaldiscdrive.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(bottle.runner == .wine ? .orange : .green)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(bottle.settings.name)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(String(
                        localized: "bottle.overview.subtitle",
                        defaultValue: "Manage this \(bottle.runner.displayName.lowercased()) library and its installed software."
                    ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(bottle.url.path(percentEncoded: false))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 10) {
                    Label(bottle.runner.displayName, systemImage: bottle.runner.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(bottle.runner == .wine ? Color.orange.opacity(0.14) : Color.green.opacity(0.14), in: Capsule())

                    HStack(spacing: 8) {
                        Button {
                            runProgram()
                        } label: {
                            HStack(spacing: 8) {
                                Label(primaryLaunchTitle, systemImage: "play.fill")
                                if programLoading {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(programLoading)
                        .help(primaryLaunchHelp)

                        Menu {
                            Button(openFolderButtonTitle, systemImage: "folder") {
                                bottle.openCDrive()
                            }

                            Button("button.terminal", systemImage: "terminal") {
                                bottle.openTerminal()
                            }

                            if bottle.runner == .wine {
                                Button("button.winetricks", systemImage: "wrench.and.screwdriver") {
                                    showWinetricks()
                                }
                                .disabled(!GIACKWineInstaller.hasWinetricksRuntime())
                            } else {
                                 Button(String(localized: "button.openConfigFile", defaultValue: "Open Config File"), systemImage: "doc.text") {
                                     NSWorkspace.shared.open(bottle.dosboxConfigURL)
                                 }

                            }

                            Divider()

                                 Button(String(localized: "button.showInFinder", defaultValue: "Show in Finder"), systemImage: "folder.badge.gearshape") {
                                     NSWorkspace.shared.activateFileViewerSelecting([bottle.url])
                                 }

                        } label: {
                            Label("Library", systemImage: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Open library actions and advanced utilities.")
                    }
                }
            }

            statusBadges
        }
        .whiskyPanelCard(cornerRadius: 20, padding: useGlassUI ? 18 : 16)
    }

    private var statusBadges: some View {
        ViewThatFits {
            HStack(spacing: 8) {
                if bottle.runner == .wine {
                    statusBadge(title: bottle.settings.windowsVersion.pretty(), icon: "desktopcomputer", tint: .blue)
                    statusBadge(title: renderLabel, icon: bottle.settings.dxvk ? "bolt.fill" : "sparkles", tint: bottle.settings.dxvk ? .orange : .green)
                    statusBadge(title: syncLabel, icon: "speedometer", tint: .pink)
                } else {
                    statusBadge(title: bottle.settings.dosboxCycles.displayName, icon: "terminal.fill", tint: .green)
                    if bottle.settings.dosboxStartupProgram != nil {
                        statusBadge(title: "Startup Game", icon: "play.circle", tint: .blue)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                if bottle.runner == .wine {
                    statusBadge(title: bottle.settings.windowsVersion.pretty(), icon: "desktopcomputer", tint: .blue)
                    statusBadge(title: renderLabel, icon: bottle.settings.dxvk ? "bolt.fill" : "sparkles", tint: bottle.settings.dxvk ? .orange : .green)
                    statusBadge(title: syncLabel, icon: "speedometer", tint: .pink)
                } else {
                    statusBadge(title: bottle.settings.dosboxCycles.displayName, icon: "terminal.fill", tint: .green)
                    if bottle.settings.dosboxStartupProgram != nil {
                        statusBadge(title: "Startup Game", icon: "play.circle", tint: .blue)
                    }
                }
            }
        }
    }

    private func statusBadge(title: String, icon: String, tint: Color) -> some View {
        GIACKGlassBadge(icon: icon, title: title, tint: tint)
    }

    private var renderLabel: String {
        bottle.settings.dxvk ? "DXVK Enabled" : "D3DMetal"
    }

    private var openFolderButtonTitle: LocalizedStringKey {
        bottle.runner == .wine ? "button.cDrive" : "Open DOS Games"
    }

    private var primaryLaunchTitle: LocalizedStringKey {
        if bottle.runner == .dosbox, bottle.settings.dosboxStartupProgram != nil {
            return "Launch Default Game"
        }
        return "button.run"
    }

    private var primaryLaunchHelp: String {
        bottle.runner == .wine
        ? "Browse for a Windows installer or executable and run it in this bottle."
        : "Launch DOSBox, optionally starting the default DOS game configured for this library."
    }

    private var syncLabel: String {
        switch bottle.settings.enhancedSync {
        case .none:
            return "No Sync Boost"
        case .esync:
            return "ESync"
        case .msync:
            return "MSync"
        }
    }
}

private struct OverviewMetricsSection: View {
    let bottle: Bottle

    private let metricGrid = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12, alignment: .leading)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "bottle.overview.title", defaultValue: "Overview"))
                        .font(.headline)
                    Text(String(
                        localized: "bottle.overview.subtitle",
                        defaultValue: "Core compatibility and runtime settings for this library."
                    ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }


            LazyVGrid(columns: metricGrid, alignment: .leading, spacing: 12) {
                if bottle.runner == .wine {
                    OverviewMetricCard(label: "Windows", value: bottle.settings.windowsVersion.pretty(), icon: "desktopcomputer", tint: .blue)
                    OverviewMetricCard(label: "Graphics", value: bottle.settings.dxvk ? "DXVK" : "D3DMetal", icon: bottle.settings.dxvk ? "bolt.fill" : "sparkles", tint: bottle.settings.dxvk ? .orange : .green)
                    OverviewMetricCard(label: "Sync", value: syncLabel, icon: "speedometer", tint: .pink)
                } else {
                    OverviewMetricCard(label: "Cycles", value: bottle.settings.dosboxCycles.displayName, icon: "terminal.fill", tint: .green)
                    OverviewMetricCard(label: "Startup", value: bottle.settings.dosboxStartupProgram.map { ($0 as NSString).lastPathComponent } ?? "Not set", icon: "play.circle", tint: .blue)
                    OverviewMetricCard(label: "Pinned", value: String(bottle.pinnedPrograms.count), icon: "pin.circle", tint: .orange)
                }
            }
        }
        .whiskyPanelCard(cornerRadius: 20)
    }

    private var syncLabel: String {
        switch bottle.settings.enhancedSync {
        case .none:
            return "None"
        case .esync:
            return "ESync"
        case .msync:
            return "MSync"
        }
    }
}

private struct OverviewMetricCard: View {
    let label: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)

            Text(value)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.9)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .help("\(label): \(value)")
    }
}

private struct PinnedProgramsSection: View {
    let bottle: Bottle
    @Binding var path: NavigationPath
    let pinGridLayout: [GridItem]
    let useGlassUI: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "bottle.pinned.title", defaultValue: "Quick Launch"))
                    .font(.headline)
                Text(String(
                    localized: "bottle.pinned.subtitle",
                    defaultValue: "Pin installed programs here for one-click launch."
                ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if bottle.pinnedPrograms.isEmpty {
                    ContentUnavailableView(
                        String(localized: "bottle.pinned.none", defaultValue: "No Pinned Programs"),
                        systemImage: "pin.slash",
                        description: Text(String(
                            localized: "bottle.pinned.none.description",
                            defaultValue: "Add a program to keep your most-used launchers in one place."
                        ))
                    )

                .frame(maxWidth: .infinity)
            }

            LazyVGrid(columns: pinGridLayout, alignment: .leading, spacing: 12) {
                ForEach(bottle.pinnedPrograms, id: \.id) { pinnedProgram in
                    PinView(
                        bottle: bottle,
                        program: pinnedProgram.program,
                        pin: pinnedProgram.pin,
                        path: $path
                    )
                }

                PinAddView(bottle: bottle)
            }
        }
        .whiskyPanelCard(cornerRadius: 20, padding: useGlassUI ? 18 : 16)
    }
}

private struct BottleDetailsSection: View {
    let bottle: Bottle
    let useGlassUI: Bool
    @State private var showsDetails = false

    var body: some View {
        DisclosureGroup("Library Details", isExpanded: $showsDetails) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                BottleDetailRow(label: "Runner", value: bottle.runner.displayName)
                BottleDetailRow(label: "Preset", value: bottle.settings.appliedPreset?.displayName ?? "Custom")
                BottleDetailRow(label: "Path", value: bottle.url.path(percentEncoded: false), selectable: true)
                BottleDetailRow(label: "Pinned Programs", value: String(bottle.pinnedPrograms.count))

                if bottle.runner == .wine {
                    BottleDetailRow(label: "Windows Version", value: bottle.settings.windowsVersion.pretty())
                    BottleDetailRow(label: "Graphics", value: bottle.settings.dxvk ? "DXVK" : "D3DMetal")
                    BottleDetailRow(label: "Sync", value: syncLabel)
                } else {
                    BottleDetailRow(label: "Cycles", value: bottle.settings.dosboxCycles.displayName)
                    BottleDetailRow(label: "DOS Games Folder", value: bottle.dosGamesFolder.path(percentEncoded: false), selectable: true)
                    BottleDetailRow(
                        label: "Startup Game",
                        value: bottle.settings.dosboxStartupProgram.map { ($0 as NSString).lastPathComponent } ?? "None"
                    )
                }
            }
            .padding(.top, 10)
        }
        .whiskyPanelCard(cornerRadius: 20, padding: useGlassUI ? 18 : 16)
    }

    private var syncLabel: String {
        switch bottle.settings.enhancedSync {
        case .none:
            return "None"
        case .esync:
            return "ESync"
        case .msync:
            return "MSync"
        }
    }
}

private struct BottleDetailRow: View {
    let label: String
    let value: String
    var selectable = false

    var body: some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Group {
                if selectable {
                    Text(value)
                        .textSelection(.enabled)
                } else {
                    Text(value)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
