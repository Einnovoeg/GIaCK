//
//  ProgramsView.swift
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

struct ProgramsView: View {
    @ObservedObject var bottle: Bottle
    @State private var blocklist: [URL] = []
    @State private var selectedPrograms = Set<Program>()
    @State private var selectedBlockitems = Set<URL>()
    @Binding var path: NavigationPath
    @State private var sortedPrograms: [Program] = []
    @State private var resortPrograms = false
    @State private var searchText = ""
    @State private var isRescanning = false
    @State private var aiBatchLoading = false
    @State private var aiBatchIdentities: [AIGameDetector.GameIdentity] = []
    @State private var showAIBatch = false

    @AppStorage("areProgramsExpanded") private var areProgramsExpanded = true
    @AppStorage("isBlocklistExpanded") private var isBlocklistExpanded = false

    private var searchResults: [Program] {
        guard !searchText.isEmpty else { return sortedPrograms }
        return sortedPrograms.filter({ $0.name.localizedCaseInsensitiveContains(searchText) })
    }

    private var searchedBlocklists: [URL] {
        guard !searchText.isEmpty else { return blocklist }
        return blocklist.filter({ $0.absoluteString.localizedCaseInsensitiveContains(searchText) })
    }

    private var selectedSearchedPrograms: [Program] {
        searchResults.filter({ selectedPrograms.contains($0) })
    }

    var body: some View {
        Form {
            // Scan status + actions — addresses 2.0 feedback that pre-installed
            // apps in existing bottles were invisible (old scanner only checked
            // Program Files). This header makes the deep drive_c scan explicit
            // and surfaces the AI per-game dependency scan.
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .foregroundStyle(.secondary)
                        Text("\(sortedPrograms.count) executables discovered")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if isRescanning || aiBatchLoading {
                            ProgressView().controlSize(.small)
                        }
                    }
                    Text(bottle.runner == .wine
                         ? "Deep scan of drive_c (Program Files, users, ProgramData, custom folders, Start Menu .lnk) — blocklisted paths excluded."
                         : "Scanning DOS Games folder for exe/com/bat.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button {
                            rescanPrograms()
                        } label: {
                            Label(isRescanning ? "Scanning…" : "Rescan Now", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(isRescanning || aiBatchLoading)
                        .help("Re-scan drive_c (or DOS Games) for executables. Picks up any manually copied or pre-installed apps.")

                        Button {
                            Task { await runAIBatchScan() }
                        } label: {
                            Label(aiBatchLoading ? "Analyzing…" : "AI Scan All", systemImage: "wand.and.stars")
                        }
                        .disabled(aiBatchLoading || isRescanning)
                        .help("Run AI detection (engine, DLLs, dependencies) for every discovered executable.")

                        if !aiBatchIdentities.isEmpty {
                            Button(showAIBatch ? "Hide AI Results" : "Show AI Results (\(aiBatchIdentities.count))") {
                                showAIBatch.toggle()
                            }
                            .help("Toggle AI batch results.")
                        }
                    }
                    .font(.caption)

                    if showAIBatch && !aiBatchIdentities.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            Text("AI Results").font(.caption.weight(.semibold))
                            ForEach(aiBatchIdentities, id: \.executableName) { identity in
                                HStack(spacing: 6) {
                                    Image(systemName: "app")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(identity.displayName).font(.caption.weight(.medium)).lineLimit(1)
                                        Text("\(identity.executableName) · \(identity.confidence.rawValue) · \(identity.engine?.rawValue ?? "unknown engine")")
                                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Text(identity.confidence.rawValue)
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(confidenceTint(identity.confidence).opacity(0.14), in: Capsule())
                                }
                            }
                            Text("Open any program’s detail to see its full recommendation (preset, DXVK, verbs) and apply it.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("program.title", isExpanded: $areProgramsExpanded) {
                List(searchResults, id: \.self, selection: $selectedPrograms) { program in
                    ProgramItemView(
                        bottle: bottle, program: program, path: $path
                    )
                    .contextMenu {
                        let selectedPrograms = selectedSearchedPrograms
                        if selectedPrograms.contains(program) && selectedPrograms.count > 1 {
                            Button("program.add.selected.blocklist", systemImage: "hand.raised") {
                                bottle.settings.blocklist.append(contentsOf: selectedPrograms.map { $0.url })
                                blocklist = bottle.settings.blocklist
                            }
                            .labelStyle(.titleAndIcon)
                        } else {
                            ProgramMenuView(program: program, path: $path)

                            Section {
                                Button("program.add.blocklist", systemImage: "hand.raised") {
                                    bottle.settings.blocklist.append(program.url)
                                    blocklist = bottle.settings.blocklist
                                }
                                .labelStyle(.titleAndIcon)
                            }
                        }
                    }
                }
            }
            .animation(.giackDefault, value: sortedPrograms)

            Section("program.blocklist", isExpanded: $isBlocklistExpanded) {
                List(searchedBlocklists, id: \.self, selection: $selectedBlockitems) { blockedUrl in
                    BlocklistItemView(
                        blockedUrl: blockedUrl, bottle: bottle
                    )
                    .contextMenu {
                        if selectedBlockitems.contains(blockedUrl) {
                            Button("program.remove.selected.blocklist", systemImage: "hand.raised") {
                                bottle.settings.blocklist.removeAll(where: { selectedBlockitems.contains($0) })
                                blocklist = bottle.settings.blocklist
                            }
                            .labelStyle(.titleAndIcon)
                            .symbolVariant(.slash)
                        } else {
                            Button("program.remove.blocklist", systemImage: "hand.raised") {
                                bottle.settings.blocklist.removeAll(where: { $0 == blockedUrl })
                                blocklist = bottle.settings.blocklist
                            }
                            .labelStyle(.titleAndIcon)
                            .symbolVariant(.slash)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .animation(.giackDefault, value: sortedPrograms)
        .animation(.giackDefault, value: bottle.settings.blocklist)
        .animation(.giackDefault, value: searchText)
        .animation(.giackDefault, value: areProgramsExpanded)
        .animation(.giackDefault, value: isBlocklistExpanded)
        .navigationTitle("tab.programs")
        .searchable(text: $searchText)
        .onAppear {
            loadData()
        }
        .onChange(of: resortPrograms) {
            loadPrograms()
        }
        .onChange(of: bottle.settings) {
            loadData()
        }
    }

    private func loadData() {
        loadPrograms()
        blocklist = bottle.settings.blocklist.filter({
            return FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
        })
    }

    private func loadPrograms() {
        let programs = bottle.programs.filter({
            return FileManager.default.fileExists(atPath: $0.url.path(percentEncoded: false))
        })
        sortedPrograms = [
            programs.pinned.sorted { $0.name < $1.name },
            programs.unpinned.sorted { $0.name < $1.name }
        ].flatMap { $0 }
    }

    /// Manual deep rescan — calls the expanded `Bottle.updateInstalledPrograms()`
    /// which now scans the full `drive_c` (not just Program Files) plus per-user
    /// roots and Start Menu targets. This is the user-visible fix for bottles
    /// that claimed “no programs” while files existed on disk.
    private func rescanPrograms() {
        guard !isRescanning else { return }
        isRescanning = true
        // Run on background queue because drive_c enumeration can touch thousands of files.
        Task.detached(priority: .userInitiated) {
            await MainActor.run {
                self.bottle.updateInstalledPrograms()
                self.loadData()
            }
            // Also reconcile Start Menu shortcuts (pins missing targets)
            // This mirrors BottleView.updateStartMenu without duplicating its
            // side-effect of deleting .lnk files.
            await MainActor.run {
                // Trigger a second pass to ensure Start Menu .lnk targets that
                // were outside Program Files are now visible (updateInstalledPrograms
                // is broad enough that most will already be there, but this covers
                // edge-cases like lnk → removable media).
                let startMenuPrograms = self.bottle.getStartMenuPrograms()
                for prog in startMenuPrograms {
                    let lower = prog.url.path(percentEncoded: false).lowercased()
                    if !self.bottle.programs.contains(where: { $0.url.path(percentEncoded: false).lowercased() == lower }) {
                        if FileManager.default.fileExists(atPath: prog.url.path(percentEncoded: false)) {
                            self.bottle.programs.append(prog)
                            self.bottle.programs.sort { $0.name.lowercased() < $1.name.lowercased() }
                        }
                    }
                }
                self.loadData()
                self.isRescanning = false
            }
        }
    }

    /// Batch AI scan for every discovered program in this bottle.
    /// This is the “scan for dependencies for every individual game” path:
    /// it runs `AIGameDetector.detect` + `AIDependencyAnalyzer` for each exe
    /// and surfaces engine/confidence. Individual detail (verbs, preset) is
    /// still per-program in `ProgramView.aiSection` to avoid overloading this list.
    private func runAIBatchScan() async {
        guard !aiBatchLoading else { return }
        await MainActor.run { self.aiBatchLoading = true; self.showAIBatch = true }
        // Ensure databases are warmed (they sync in background on app launch,
        // but a manual scan should ensure at least builtin entries are loaded).
        // AICompatibilityService loads builtin synchronously on first init.

        var identities: [AIGameDetector.GameIdentity] = []
        // Use sortedPrograms as source but also include any newly discovered
        let programsToScan = await MainActor.run { self.sortedPrograms }
        for prog in programsToScan {
            let identity = await AIGameDetector.shared.detect(at: prog.url)
            identities.append(identity)
        }
        // Also include any blocklisted? No - only visible programs.

        await MainActor.run {
            self.aiBatchIdentities = identities.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
            self.aiBatchLoading = false
        }
    }

    private func confidenceTint(_ c: AIGameDetector.GameIdentity.Confidence) -> Color {
        switch c {
        case .high: return .green
        case .medium: return .orange
        case .low: return .secondary
        case .unknown: return .red
        }
    }
}

struct ProgramItemView: View {
    @ObservedObject var bottle: Bottle
    @ObservedObject var program: Program
    @Binding var path: NavigationPath
    @State private var showButtons = false
    @State private var pinHovered = false

    var body: some View {
        HStack {
            Button {
                program.pinned.toggle()
            } label: {
                Image(systemName: "pin")
                    .onHover { hover in
                        pinHovered = hover
                    }
                    .symbolVariant(program.pinned ? pinHovered ? .slash.fill : .fill : .none)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .foregroundColor(program.pinned ? .accentColor : .secondary)
            .opacity(program.pinned ? 1 : showButtons ? 1 : 0)
            .help(program.pinned ? "Unpin this program from Quick Launch." : "Pin this program to Quick Launch.")
            Text(program.name)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showButtons {
                if let peFile = program.peFile,
                   let archString = peFile.architecture.toString() {
                    Text(archString)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(.secondary)
                        )
                }

                Button("program.config", systemImage: "gearshape") {
                    path.append(program)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Open this program's settings.")
                Button("button.run", systemImage: "play") {
                    program.run()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Launch this program.")
            }
        }
        .padding(4)
        .onHover { hover in
            showButtons = hover
        }
    }
}

struct BlocklistItemView: View {
    let blockedUrl: URL
    @ObservedObject var bottle: Bottle
    @State private var showButtons: Bool = false

    var body: some View {
        HStack {
            Text(blockedUrl.prettyPath(bottle))
            Spacer()
            if showButtons {
                Button("program.remove.blocklist", systemImage: "xmark") {
                    bottle.settings.blocklist.removeAll { $0 == blockedUrl }
                }
                .labelStyle(.iconOnly)
                .symbolVariant(.fill.circle)
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Remove this path from the blocklist.")
            }
        }
        .padding(4)
        .onHover { hover in
            showButtons = hover
        }
    }
}
