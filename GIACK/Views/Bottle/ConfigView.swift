//
//  ConfigView.swift
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

enum LoadingState {
    case loading
    case modifying
    case success
    case failed
}

struct ConfigView: View {
    @ObservedObject var bottle: Bottle
    @State private var selectedPreset: BottlePreset = .windowsGame
    @State private var buildVersion: Int = 0
    @State private var retinaMode: Bool = false
    @State private var dpiConfig: Int = 96
    @State private var presetApplyingState: LoadingState = .success
    @State private var winVersionLoadingState: LoadingState = .loading
    @State private var buildVersionLoadingState: LoadingState = .loading
    @State private var retinaModeLoadingState: LoadingState = .loading
    @State private var dpiConfigLoadingState: LoadingState = .loading
    @State private var dpiSheetPresented: Bool = false
    @AppStorage("wineSectionExpanded") private var wineSectionExpanded: Bool = true
    @AppStorage("dxvkSectionExpanded") private var dxvkSectionExpanded: Bool = true
    @AppStorage("metalSectionExpanded") private var metalSectionExpanded: Bool = true
    @AppStorage("dosboxSectionExpanded") private var dosboxSectionExpanded: Bool = true
    @AppStorage("dosboxStartupExpanded") private var dosboxStartupExpanded: Bool = true

    var body: some View {
        Form {
            presetSection
            if bottle.runner == .wine {
                wineSections
            } else {
                dosboxSections
            }
        }
        .formStyle(.grouped)
        .animation(.whiskyDefault, value: wineSectionExpanded)
        .animation(.whiskyDefault, value: dxvkSectionExpanded)
        .animation(.whiskyDefault, value: metalSectionExpanded)
        .animation(.whiskyDefault, value: dosboxSectionExpanded)
        .animation(.whiskyDefault, value: dosboxStartupExpanded)
        .bottomBar {
            HStack {
                Spacer()
                if bottle.runner == .wine {
                    Button("config.controlPanel") {
                        Task(priority: .userInitiated) {
                            do {
                                try await Wine.control(bottle: bottle)
                            } catch {
                                print("Failed to launch control")
                            }
                        }
                    }
                    .help("Open the Windows Control Panel inside this bottle.")

                    Button("config.regedit") {
                        Task(priority: .userInitiated) {
                            do {
                                try await Wine.regedit(bottle: bottle)
                            } catch {
                                print("Failed to launch regedit")
                            }
                        }
                    }
                    .help("Edit the Wine registry for this bottle.")

                    Button("config.winecfg") {
                        Task(priority: .userInitiated) {
                            do {
                                try await Wine.cfg(bottle: bottle)
                            } catch {
                                print("Failed to launch winecfg")
                            }
                        }
                    }
                    .help("Open Wine configuration for this bottle.")
                } else {
                    Button("Open Config File") {
                        NSWorkspace.shared.open(bottle.dosboxConfigURL)
                    }
                    .help("Inspect the generated DOSBox Staging configuration file.")

                    Button("Open DOS Games") {
                        bottle.openCDrive()
                    }
                    .help("Open the DOS Games folder for this library.")

                    Button(dosboxLaunchButtonTitle) {
                        launchDOSBox()
                    }
                    .help("Start DOSBox using the settings and optional startup game saved for this library.")
                }
            }
            .padding()
        }
        .navigationTitle("tab.config")
        .onAppear {
            initializePresetSelection()
            if bottle.runner == .wine {
                loadWineConfiguration()
            } else {
                try? DOSBox.writeConfiguration(for: bottle)
            }
        }
        .onChange(of: bottle.settings) { _, _ in
            guard bottle.runner == .dosbox else { return }
            try? DOSBox.writeConfiguration(for: bottle)
        }
        .onChange(of: bottle.runner) { _, runner in
            selectedPreset = bottle.settings.appliedPreset
                .flatMap { $0.runner == runner ? $0 : nil }
                ?? BottlePreset.defaultPreset(for: runner)
        }
        .onChange(of: bottle.settings.windowsVersion) { _, newValue in
            guard bottle.runner == .wine else { return }
            if winVersionLoadingState == .success {
                winVersionLoadingState = .loading
                buildVersionLoadingState = .loading
                Task(priority: .userInitiated) {
                    do {
                        try await Wine.changeWinVersion(bottle: bottle, win: newValue)
                        winVersionLoadingState = .success
                        bottle.settings.windowsVersion = newValue
                        loadBuildName()
                    } catch {
                        print(error)
                        winVersionLoadingState = .failed
                    }
                }
            }
        }
        .onChange(of: dpiConfig) {
            guard bottle.runner == .wine else { return }
            if dpiConfigLoadingState == .success {
                Task(priority: .userInitiated) {
                    dpiConfigLoadingState = .modifying
                    do {
                        try await Wine.changeDpiResolution(bottle: bottle, dpi: dpiConfig)
                        dpiConfigLoadingState = .success
                    } catch {
                        print(error)
                        dpiConfigLoadingState = .failed
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var presetSection: some View {
        Section("Compatibility Preset") {
            Picker("Preset", selection: $selectedPreset) {
                ForEach(compatiblePresets) { preset in
                    Label(preset.displayName, systemImage: preset.systemImage)
                        .tag(preset)
                }
            }
            .help("Apply a curated compatibility recipe for this library's current runner.")

            BottlePresetSummaryCard(preset: selectedPreset)
            BottlePresetChecklistView(preset: selectedPreset)

            HStack {
                Button(presetApplyingState == .modifying ? "Applying…" : "Apply Preset") {
                    Task {
                        await applySelectedPreset()
                    }
                }
                .disabled(presetApplyingState == .modifying)
                .help("Reapply the selected compatibility preset to this library.")

                if presetApplyingState == .failed {
                    Text("Failed to apply the selected preset.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder
    private var wineSections: some View {
        Section("config.title.wine", isExpanded: $wineSectionExpanded) {
            SettingItemView(title: "config.winVersion", loadingState: winVersionLoadingState) {
                Picker("config.winVersion", selection: $bottle.settings.windowsVersion) {
                    ForEach(WinVersion.allCases.reversed(), id: \.self) {
                        Text($0.pretty())
                    }
                }
            }
            SettingItemView(title: "config.buildVersion", loadingState: buildVersionLoadingState) {
                TextField("config.buildVersion", value: $buildVersion, formatter: NumberFormatter())
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        buildVersionLoadingState = .modifying
                        Task(priority: .userInitiated) {
                            do {
                                try await Wine.changeBuildVersion(bottle: bottle, version: buildVersion)
                                buildVersionLoadingState = .success
                            } catch {
                                print("Failed to change build version")
                                buildVersionLoadingState = .failed
                            }
                        }
                    }
            }
            SettingItemView(title: "config.retinaMode", loadingState: retinaModeLoadingState) {
                Toggle("config.retinaMode", isOn: $retinaMode)
                    .onChange(of: retinaMode) { _, newValue in
                        Task(priority: .userInitiated) {
                            retinaModeLoadingState = .modifying
                            do {
                                try await Wine.changeRetinaMode(bottle: bottle, retinaMode: newValue)
                                retinaModeLoadingState = .success
                            } catch {
                                print("Failed to change Retina mode")
                                retinaModeLoadingState = .failed
                            }
                        }
                    }
            }
            Picker("config.enhancedSync", selection: $bottle.settings.enhancedSync) {
                Text("config.enhancedSync.none").tag(EnhancedSync.none)
                Text("config.enhancedSync.esync").tag(EnhancedSync.esync)
                Text("config.enhancedSync.msync").tag(EnhancedSync.msync)
            }
            .help("Wine 11.0 added NTSYNC upstream, but macOS GPTK builds still rely on ESync and MSync.")

            SettingItemView(title: "config.dpi", loadingState: dpiConfigLoadingState) {
                Button("config.inspect") {
                    dpiSheetPresented = true
                }
                .help("Inspect or change the emulated display DPI for this bottle.")
                .sheet(isPresented: $dpiSheetPresented) {
                    DPIConfigSheetView(
                        dpiConfig: $dpiConfig,
                        isRetinaMode: $retinaMode,
                        presented: $dpiSheetPresented
                    )
                }
            }

            if #available(macOS 15, *) {
                Toggle(isOn: $bottle.settings.avxEnabled) {
                    VStack(alignment: .leading) {
                        Text("config.avx")
                        if bottle.settings.avxEnabled {
                            HStack(alignment: .firstTextBaseline) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .symbolRenderingMode(.multicolor)
                                    .font(.subheadline)
                                Text("config.avx.warning")
                                    .fontWeight(.light)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                .help("Advertise AVX support through Rosetta for software that requires it.")
            }
        }

        Section("config.title.dxvk", isExpanded: $dxvkSectionExpanded) {
            if !GIACKWineInstaller.hasDXVKRuntime() {
                Text(
                    String(
                        localized: "config.dxvk.unavailable",
                        defaultValue: "DXVK is unavailable in the installed runtime package."
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle(isOn: $bottle.settings.dxvk) {
                Text("config.dxvk")
            }
            .disabled(!GIACKWineInstaller.hasDXVKRuntime())
            .help("Use DXVK instead of the D3DMetal path when the runtime package includes it.")

            Toggle(isOn: $bottle.settings.dxvkAsync) {
                Text("config.dxvk.async")
            }
            .disabled(!GIACKWineInstaller.hasDXVKRuntime() || !bottle.settings.dxvk)
            .help("Allow asynchronous shader compilation for DXVK-enabled bottles.")

            Picker("config.dxvkHud", selection: $bottle.settings.dxvkHud) {
                Text("config.dxvkHud.full").tag(DXVKHUD.full)
                Text("config.dxvkHud.partial").tag(DXVKHUD.partial)
                Text("config.dxvkHud.fps").tag(DXVKHUD.fps)
                Text("config.dxvkHud.off").tag(DXVKHUD.off)
            }
            .disabled(!GIACKWineInstaller.hasDXVKRuntime() || !bottle.settings.dxvk)
            .help("Choose how much DXVK performance data to show on screen.")
        }

        Section("config.title.metal", isExpanded: $metalSectionExpanded) {
            Toggle(isOn: $bottle.settings.metalHud) {
                Text("config.metalHud")
            }
            .help("Display Metal performance information inside the bottle.")

            Toggle(isOn: $bottle.settings.metalTrace) {
                Text("config.metalTrace")
                Text("config.metalTrace.info")
            }
            .help("Capture a Metal trace for debugging graphical issues.")

            if let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.apple9) {
                Toggle(isOn: $bottle.settings.dxrEnabled) {
                    Text("config.dxr")
                    Text("config.dxr.info")
                }
                .help("Enable experimental DXR support on compatible Apple GPUs.")
            }
        }
    }

    @ViewBuilder
    private var dosboxSections: some View {
        Section("DOSBox Runtime", isExpanded: $dosboxSectionExpanded) {
            Toggle("Launch fullscreen", isOn: $bottle.settings.dosboxFullscreen)
                .help("Start DOSBox in fullscreen for this library.")
            Toggle("Capture mouse automatically", isOn: $bottle.settings.dosboxCaptureMouse)
                .help("Keep the pointer inside the DOSBox window until you release it.")
            Picker("CPU core", selection: $bottle.settings.dosboxCore) {
                ForEach(DOSBoxCore.allCases, id: \.self) { core in
                    Text(core.displayName).tag(core)
                }
            }
            .help("Choose the DOSBox CPU emulation core used for this library.")
            Picker("CPU cycles", selection: $bottle.settings.dosboxCycles) {
                ForEach(DOSBoxCycles.allCases, id: \.self) { cycles in
                    Text(cycles.displayName).tag(cycles)
                }
            }
            .help("Tune how fast the emulated CPU runs.")
            Picker("Display filter", selection: $bottle.settings.dosboxScaler) {
                ForEach(DOSBoxScaler.allCases, id: \.self) { scaler in
                    Text(scaler.displayName).tag(scaler)
                }
            }
            .help("Choose the current DOSBox Staging shader or display filter preset for this library.")
        }

        Section("Startup", isExpanded: $dosboxStartupExpanded) {
            ActionView(
                text: "Default DOS game",
                subtitle: bottle.settings.dosboxStartupProgram ?? "Launch into a DOS shell",
                actionName: "Choose"
            ) {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = false
                panel.canChooseFiles = true
                panel.allowsMultipleSelection = false
                panel.directoryURL = bottle.dosGamesFolder
                panel.allowedContentTypes = dosboxContentTypes
                panel.begin { result in
                    guard result == .OK, let url = panel.urls.first else { return }
                    bottle.settings.dosboxStartupProgram = try? DOSBox.relativeProgramPath(for: url, in: bottle)
                }
            }

            Button("Clear default game") {
                bottle.settings.dosboxStartupProgram = nil
            }
            .help("Remove the startup game and launch into a DOS shell instead.")
            .disabled(bottle.settings.dosboxStartupProgram == nil)
        }

        Section("Compatibility Notes") {
            Text("Wine 11.0's headline NTSYNC feature is Linux-only, so this macOS build keeps MSync for Wine bottles and uses DOSBox for DOS-era games instead of forcing them through Wine.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("The newer WoW64 work in Wine 11.0 is useful for future GPTK adoption, but DOS titles still get their best compatibility through DOSBox Staging.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var dosboxContentTypes: [UTType] {
        [
            UTType(filenameExtension: "exe") ?? .data,
            UTType(filenameExtension: "com") ?? .data,
            UTType(filenameExtension: "bat") ?? .data
        ]
    }

    private var compatiblePresets: [BottlePreset] {
        BottlePreset.presets(for: bottle.runner)
    }

    private var dosboxLaunchButtonTitle: String {
        bottle.settings.dosboxStartupProgram == nil ? "Launch DOSBox" : "Launch Default Game"
    }

    private func launchDOSBox() {
        Task(priority: .userInitiated) {
            do {
                try await DOSBox.run(bottle: bottle)
            } catch {
                print("Failed to launch DOSBox: \(error)")
            }
        }
    }

    @MainActor
    private func initializePresetSelection() {
        selectedPreset = bottle.settings.appliedPreset
            .flatMap { $0.runner == bottle.runner ? $0 : nil }
            ?? BottlePreset.defaultPreset(for: bottle.runner)
    }

    @MainActor
    private func applySelectedPreset() async {
        presetApplyingState = .modifying
        let previousSettings = bottle.settings
        bottle.settings.apply(preset: selectedPreset)

        do {
            switch bottle.runner {
            case .wine:
                try await Wine.changeWinVersion(bottle: bottle, win: bottle.settings.windowsVersion)
                loadWineConfiguration()
            case .dosbox:
                try DOSBox.writeConfiguration(for: bottle)
            }
            presetApplyingState = .success
        } catch {
            bottle.settings = previousSettings
            presetApplyingState = .failed
        }
    }

    private func loadWineConfiguration() {
        winVersionLoadingState = .success
        loadBuildName()

        Task(priority: .userInitiated) {
            do {
                retinaMode = try await Wine.retinaMode(bottle: bottle)
                retinaModeLoadingState = .success
            } catch {
                print(error)
                retinaModeLoadingState = .failed
            }
        }

        Task(priority: .userInitiated) {
            do {
                dpiConfig = try await Wine.dpiResolution(bottle: bottle) ?? 0
                dpiConfigLoadingState = .success
            } catch {
                print(error)
                // If DPI has not yet been edited, there will be no registry entry.
                dpiConfigLoadingState = .success
            }
        }
    }

    func loadBuildName() {
        Task(priority: .userInitiated) {
            do {
                if let buildVersionString = try await Wine.buildVersion(bottle: bottle) {
                    buildVersion = Int(buildVersionString) ?? 0
                } else {
                    buildVersion = 0
                }

                buildVersionLoadingState = .success
            } catch {
                print(error)
                buildVersionLoadingState = .failed
            }
        }
    }
}

struct DPIConfigSheetView: View {
    @Binding var dpiConfig: Int
    @Binding var isRetinaMode: Bool
    @Binding var presented: Bool
    @State var stagedChanges: Float
    @FocusState var textFocused: Bool

    init(dpiConfig: Binding<Int>, isRetinaMode: Binding<Bool>, presented: Binding<Bool>) {
        self._dpiConfig = dpiConfig
        self._isRetinaMode = isRetinaMode
        self._presented = presented
        self.stagedChanges = Float(dpiConfig.wrappedValue)
    }

    var body: some View {
        VStack {
            HStack {
                Text("configDpi.title")
                    .fontWeight(.bold)
                Spacer()
            }
            Divider()
            GroupBox(label: Label("configDpi.preview", systemImage: "text.magnifyingglass")) {
                VStack {
                    HStack {
                        Text("configDpi.previewText")
                            .padding(16)
                            .font(.system(size:
                                (10 * CGFloat(stagedChanges)) / 72 *
                                          (isRetinaMode ? 0.5 : 1)
                            ))
                        Spacer()
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: 80)
            }
            HStack {
                Slider(value: $stagedChanges, in: 96...480, step: 24, onEditingChanged: { _ in
                    textFocused = false
                })
                TextField(String(), value: $stagedChanges, format: .number)
                    .frame(width: 40)
                    .focused($textFocused)
                Text("configDpi.dpi")
            }
            Spacer()
            HStack {
                Spacer()
                Button("create.cancel") {
                    presented = false
                }
                .keyboardShortcut(.cancelAction)
                .help("Discard the staged DPI change.")
                Button("button.ok") {
                    dpiConfig = Int(stagedChanges)
                    presented = false
                }
                .keyboardShortcut(.defaultAction)
                .help("Apply the selected DPI value.")
            }
        }
        .padding()
        .frame(width: ViewWidth.medium, height: 240)
    }
}

struct SettingItemView<Content: View>: View {
    let title: String.LocalizationValue
    let loadingState: LoadingState
    @ViewBuilder var content: () -> Content

    @Namespace private var viewId
    @Namespace private var progressViewId

    var body: some View {
        HStack {
            Text(String(localized: title))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                switch loadingState {
                case .loading, .modifying:
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .matchedGeometryEffect(id: progressViewId, in: viewId)
                case .success:
                    content()
                        .labelsHidden()
                        .disabled(loadingState != .success)
                case .failed:
                    Text("config.notAvailable")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.trailing)
                }
            }
            .animation(.default, value: loadingState)
        }
    }
}
