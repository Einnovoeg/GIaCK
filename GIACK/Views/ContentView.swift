//
//  ContentView.swift
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
import SemanticVersion
import Foundation

struct ContentView: View {
    @AppStorage("selectedBottleURL") private var selectedBottleURL: URL?
    @AppStorage("checkGIACKWineUpdates") private var checkGIACKWineUpdates = true
    @AppStorage("autoInstallGIACKWineUpdates") private var autoInstallGIACKWineUpdates = true
    @AppStorage("useGlassUI") private var useGlassUI = false
    @AppStorage("uiAppearanceRevision") private var uiAppearanceRevision = 0
    @EnvironmentObject var bottleVM: BottleVM
    @Binding var showSetup: Bool

    @State private var selected: URL?
    @State private var showBottleCreation = false
    @State private var bottlesLoaded = false
    @State private var newlyCreatedBottleURL: URL?
    @State private var openedFileURL: URL?
    @State private var refreshAnimation: Angle = .degrees(0)
    @State private var bottleFilter = ""

    private var appDisplayName: String { Bundle.appDisplayName }
    private var wineBottleCount: Int { bottleVM.bottles.filter { $0.runner == .wine }.count }
    private var dosboxBottleCount: Int { bottleVM.bottles.filter { $0.runner == .dosbox }.count }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 340)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showBottleCreation.toggle()
                } label: {
                    Image(systemName: "plus")
                        .help("Create a new GPTK Wine bottle or DOSBox library.")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    bottleVM.loadBottles()
                    if let bottle = bottleVM.bottles.first(where: { $0.url == selected }) {
                        bottle.updateInstalledPrograms()
                    }
                    withAnimation(.default) {
                        refreshAnimation = .degrees(360)
                    } completion: {
                        refreshAnimation = .degrees(0)
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .help("Refresh bottles, installed programs, and runtime status.")
                        .rotationEffect(refreshAnimation)
                }
            }
        }
        .sheet(isPresented: $showBottleCreation) {
            BottleCreationView(newlyCreatedBottleURL: $newlyCreatedBottleURL)
        }
        .sheet(isPresented: $showSetup) {
            SetupView(showSetup: $showSetup, firstTime: false)
        }
        .sheet(item: $openedFileURL) { url in
            FileOpenView(
                fileURL: url,
                currentBottle: selected,
                bottles: bottleVM.bottles
            )
        }
        .onChange(of: selected) {
            selectedBottleURL = selected
        }
        .handlesExternalEvents(preferring: [], allowing: ["*"])
        .onOpenURL { url in
            openedFileURL = url
        }
        .task {
            applyAppearanceMigrationIfNeeded()
            bottleVM.loadBottles()
            bottlesLoaded = true

            if !bottleVM.bottles.isEmpty {
                if let bottle = bottleVM.bottles.first(where: { $0.url == selectedBottleURL && $0.isAvailable }) {
                    selected = bottle.url
                } else {
                    selected = bottleVM.bottles[0].url
                }
            }

            if !GIACKWineInstaller.isGIACKWineInstalled() && !DOSBox.isInstalled() {
                showSetup = true
            }
            if checkGIACKWineUpdates && GIACKWineInstaller.isGIACKWineInstalled() {
                let task = Task.detached {
                    await GIACKWineInstaller.shouldUpdateGIACKWine()
                }
                let updateInfo = await task.value
                if updateInfo.0 {
                    if autoInstallGIACKWineUpdates {
                        await installLatestRuntimeUpdate()
                        return
                    }

                    let alert = NSAlert()
                    alert.messageText = String(
                        localized: "update.whiskygptk.runtime.title",
                        defaultValue: "New Runtime Available"
                    )
                    alert.informativeText = String(
                        format: String(
                            localized: "update.whiskygptk.runtime.description",
                            defaultValue: "You are running runtime %@, but %@ is available. Would you like to update?"
                        ),
                        String(GIACKWineInstaller.whiskyWineVersion() ?? SemanticVersion(0, 0, 0)),
                        String(updateInfo.1)
                    )
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: String(
                        localized: "update.whiskygptk.runtime.update",
                        defaultValue: "Update Runtime"
                    ))
                    alert.addButton(withTitle: String(localized: "button.removeAlert.cancel"))

                    let response = alert.runModal()

                    if response == .alertFirstButtonReturn {
                        GIACKWineInstaller.uninstall()
                        showSetup = true
                    }
                }
            }
        }
        .whiskyWindowBackground()
    }

    private var sidebar: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                SidebarHeaderView(
                    appDisplayName: appDisplayName,
                    wineBottleCount: wineBottleCount,
                    dosboxBottleCount: dosboxBottleCount,
                    runtimeLabel: runtimeBadgeLabel,
                    runtimeSummary: "\(runtimeReleaseLabel) via \(runtimeSourceLabel)",
                    dosboxStatus: dosboxStatusLabel
                )
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

                List(selection: $selected) {
                    ForEach(filteredBottles) { bottle in
                        Group {
                            if bottle.inFlight {
                                InFlightBottleRow(name: bottle.settings.name)
                            } else {
                                BottleListEntry(
                                    bottle: bottle,
                                    selected: $selected
                                )
                                .selectionDisabled(!bottle.isAvailable)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .id(bottle.url)
                    }
                }
                .listStyle(.sidebar)
                .searchable(text: $bottleFilter, placement: .sidebar)
                .overlay {
                    if filteredBottles.isEmpty, bottlesLoaded {
                        SidebarEmptyResultsView(hasSearchQuery: !bottleFilter.isEmpty)
                    }
                }
            }
            .animation(.default, value: bottleVM.bottles)
            .animation(.default, value: bottleFilter)
            .onChange(of: newlyCreatedBottleURL) { _, url in
                Task {
                    try? await Task.sleep(for: .milliseconds(200))
                    selected = url
                    withAnimation {
                        proxy.scrollTo(url, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let selected,
           let bottle = bottleVM.bottles.first(where: { $0.url == selected }) {
            BottleView(bottle: bottle)
                .disabled(bottle.inFlight)
                .id(bottle.url)
        } else if bottlesLoaded, bottleVM.bottles.isEmpty {
            emptyState
        } else {
            SelectionPlaceholderView(useGlassUI: useGlassUI)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            GIACKBrandIcon(size: 88)

            VStack(spacing: 8) {
                Text("No Libraries Yet")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Create a GPTK Wine bottle for Windows software or a DOSBox library for classic DOS games.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Button {
                showBottleCreation.toggle()
            } label: {
                Label("Create Library", systemImage: "plus")
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .help("Create your first library.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var runtimeBadgeLabel: String {
        GIACKWineInstaller.currentWineRuntime()?.displayName ?? "Runtime Missing"
    }

    private var runtimeReleaseLabel: String {
        GIACKWineInstaller.currentWineRuntime()?.versionSummary ?? "No runtime installed"
    }

    private var runtimeSourceLabel: String {
        GIACKWineInstaller.currentWineRuntime()?.sourceSummary ?? "Runtime not installed"
    }

    private var dosboxStatusLabel: String {
        DOSBox.executableURL()?.lastPathComponent ?? "Not installed"
    }

    private var filteredBottles: [Bottle] {
        if bottleFilter.isEmpty {
            bottleVM.bottles.sorted()
        } else {
            bottleVM.bottles
                .filter { $0.settings.name.localizedCaseInsensitiveContains(bottleFilter) }
                .sorted()
        }
    }

    private func applyAppearanceMigrationIfNeeded() {
        // Earlier releases defaulted into an overbuilt glass-heavy shell. Force one
        // migration back to the restrained layout so existing installs regain a sane
        // sidebar/detail hierarchy without requiring a manual Settings change first.
        guard uiAppearanceRevision < 1 else {
            return
        }

        useGlassUI = false
        uiAppearanceRevision = 1
    }

    @MainActor
    private func installLatestRuntimeUpdate() async {
        guard let package = await GIACKWineInstaller.latestRuntimePackage() else {
            return
        }

        let archiveURL: URL
        if package.downloadURL.isFileURL {
            archiveURL = package.downloadURL
        } else {
            do {
                let (downloadedURL, _) = try await URLSession(configuration: .ephemeral)
                    .download(from: package.downloadURL)
                archiveURL = downloadedURL
            } catch {
                print("Failed to download runtime update: \(error)")
                return
            }
        }

        let version = package.version
        let source = package.source
        let releaseName = package.releaseName

        let installed = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let installed = GIACKWineInstaller.install(
                    from: archiveURL,
                    versionOverride: version,
                    source: source,
                    releaseName: releaseName
                )
                continuation.resume(returning: installed)
            }
        }

        if !installed {
            print("Failed to install runtime update.")
        }
    }
}

private struct SidebarHeaderView: View {
    let appDisplayName: String
    let wineBottleCount: Int
    let dosboxBottleCount: Int
    let runtimeLabel: String
    let runtimeSummary: String
    let dosboxStatus: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                GIACKBrandIcon(size: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text(appDisplayName)
                        .font(.title3.weight(.bold))
                    Text("Windows and DOS game libraries for macOS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("\(wineBottleCount) GPTK Wine • \(dosboxBottleCount) DOSBox", systemImage: "shippingbox")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Label("Runtime \(runtimeLabel)", systemImage: "arrow.down.circle")
                    .font(.caption.weight(.semibold))
                Text(runtimeSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Label("DOSBox \(dosboxStatus)", systemImage: "opticaldiscdrive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .help("Installed libraries and runner status.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .whiskyPanelCard(cornerRadius: 18, padding: 14)
    }
}

private struct InFlightBottleRow: View {
    let name: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox.circle.fill")
                .foregroundStyle(.secondary)
            Text(name)
            Spacer()
            ProgressView()
                .controlSize(.small)
        }
        .opacity(0.75)
    }
}

private struct SidebarEmptyResultsView: View {
    let hasSearchQuery: Bool

    var body: some View {
        ContentUnavailableView(
            hasSearchQuery ? "No Matching Libraries" : "No Libraries",
            systemImage: hasSearchQuery ? "magnifyingglass" : "shippingbox",
            description: Text(hasSearchQuery
                              ? "Try a different search term."
                              : "Create a GPTK Wine bottle or DOSBox library to get started.")
        )
        .padding()
    }
}

private struct SelectionPlaceholderView: View {
    let useGlassUI: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("Select a Library")
                .font(.title2.weight(.semibold))
            Text("Choose a GPTK Wine bottle or DOSBox library from the sidebar to manage it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background {
            if useGlassUI {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.thinMaterial)
                    .padding(24)
            }
        }
    }
}

#Preview {
    ContentView(showSetup: .constant(false))
        .environmentObject(BottleVM.shared)
}
