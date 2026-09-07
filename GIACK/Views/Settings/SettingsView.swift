//
//  SettingsView.swift
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

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case appearance
    case runners
    case updates
    case resources

    var id: Self { self }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .appearance:
            return "Appearance"
        case .runners:
            return "Runners"
        case .updates:
            return "Updates"
        case .resources:
            return "Resources"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "gearshape"
        case .appearance:
            return "paintbrush"
        case .runners:
            return "shippingbox"
        case .updates:
            return "arrow.triangle.2.circlepath"
        case .resources:
            return "doc.text"
        }
    }
}

struct SettingsView: View {
    @AppStorage("SUEnableAutomaticChecks") var whiskyUpdate = true
    @AppStorage("killOnTerminate") var killOnTerminate = true
    @AppStorage("checkGIACKWineUpdates") var checkGIACKWineUpdates = true
    @AppStorage("autoInstallGIACKWineUpdates") var autoInstallGIACKWineUpdates = true
    @AppStorage("preferLocalGPTKRuntime") var preferLocalGPTKRuntime = true
    @AppStorage("useGlassUI") var useGlassUI = false
    @AppStorage("disableAppNap") var disableAppNap = true
    @AppStorage("wrapProgramShortcuts") var wrapProgramShortcuts = true
    @AppStorage("defaultBottleLocation") var defaultBottleLocation = BottleData.defaultBottleDir
    @AppStorage("selectedWineRuntimeSelection") var selectedWineRuntimeSelection = GIACKWineInstaller.RuntimeSelection.gptkManaged.rawValue
    @State private var latestRuntimePackage: GIACKWineInstaller.RuntimePackage?
    @State private var latestRuntimeSummary = String(
        localized: "settings.runtime.checking",
        defaultValue: "Checking latest runtime..."
    )
    @State private var dosboxVersionSummary = "Detecting DOSBox..."
    @State private var runtimeActionMessage: String?
    @State private var runnerActionMessage: String?
    @State private var isRefreshingRuntime = false
    @State private var isInstallingRuntime = false
    @State private var isRefreshingRunners = false
    @State private var isManagingWineRuntime = false
    @State private var isManagingDOSBox = false
    @State private var selectedTab: SettingsTab = .general
    @State private var systemScanReport: SystemScanReport?
    @State private var selectedWineStatus: HomebrewCaskStatus?
    @State private var dosboxCaskStatus: HomebrewCaskStatus?
    private let hasAppUpdateFeed: Bool = {
        guard let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String else {
            return false
        }
        return !feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }()
    private var appVersionSummary: String {
        let marketingVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "0"
        return "\(marketingVersion) (\(buildNumber))"
    }
    private var managedRuntimeSummary: String {
        let version = GIACKWineInstaller.giackWineVersion().map(String.init) ?? String(
            localized: "settings.runtime.notInstalled",
            defaultValue: "Not installed"
        )
        let source = GIACKWineInstaller.runtimeSource() ?? String(
            localized: "settings.runtime.unknownSource",
            defaultValue: "Unknown source"
        )
        return "\(version) · \(source)"
    }
    private var activeWineSummary: String {
        GIACKWineInstaller.activeWineRuntimeSummary()
    }
    private var runtimeSelection: GIACKWineInstaller.RuntimeSelection {
        GIACKWineInstaller.RuntimeSelection(rawValue: selectedWineRuntimeSelection) ?? .gptkManaged
    }
    private var selectedWineCask: HomebrewCask? {
        switch runtimeSelection {
        case .gptkManaged:
            return nil
        case .wineStable:
            return .wineStable
        case .wineDevel:
            return .wineDevel
        case .wineStaging:
            return .wineStaging
        }
    }
    private var selectedWineStatusSummary: String {
        selectedWineStatus?.summary ?? "Select a Homebrew Wine runtime to see install status."
    }
    private var dosboxPathSummary: String {
        DOSBox.executableURL()?.prettyPath() ?? "Not installed"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem {
                    Label(SettingsTab.general.title, systemImage: SettingsTab.general.systemImage)
                }
                .tag(SettingsTab.general)

            appearanceTab
                .tabItem {
                    Label(SettingsTab.appearance.title, systemImage: SettingsTab.appearance.systemImage)
                }
                .tag(SettingsTab.appearance)

            runnersTab
                .tabItem {
                    Label(SettingsTab.runners.title, systemImage: SettingsTab.runners.systemImage)
                }
                .tag(SettingsTab.runners)

            updatesTab
                .tabItem {
                    Label(SettingsTab.updates.title, systemImage: SettingsTab.updates.systemImage)
                }
                .tag(SettingsTab.updates)

            resourcesTab
                .tabItem {
                    Label(SettingsTab.resources.title, systemImage: SettingsTab.resources.systemImage)
                }
                .tag(SettingsTab.resources)
        }
        .frame(width: 660, height: 520)
        .task {
            await refreshLatestRuntime()
            await refreshRunnerStatus()
        }
    }

    private var generalTab: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 14) {
                    GIACKBrandIcon(size: 56)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(ProjectInfo.displayName)
                            .font(.title3.weight(.semibold))
                        Text(String(
                            localized: "settings.general.version",
                            defaultValue: "Version \(appVersionSummary)"
                        ))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(String(
                            localized: "settings.general.runtime",
                            defaultValue: "Runtime \(activeWineSummary)"
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if useGlassUI {
                        GIACKGlassBadge(
                            icon: "sparkles.rectangle.stack",
                            title: "Maintained Build",
                            tint: GIACKBrandPalette.amber
                        )
                    }
                }
                .padding(.vertical, 4)
            }

            Section("General") {
                Toggle(
                    String(
                        localized: "settings.toggle.kill.on.terminate",
                        defaultValue: "Terminate Wine processes when \(ProjectInfo.displayName) closes"
                    ),
                    isOn: $killOnTerminate
                )

                Toggle(
                    String(
                        localized: "settings.toggle.appNap",
                        defaultValue: "Prevent App Nap to improve stability"
                    ),
                    isOn: $disableAppNap
                )
                .onChange(of: disableAppNap) { _, isDisabled in
                    GIACKActivityController.shared.setAppNapDisabled(isDisabled)
                }

                ActionView(
                    text: "settings.path",
                    subtitle: defaultBottleLocation.prettyPath(),
                    actionName: "create.browse"
                ) {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = true
                    panel.directoryURL = BottleData.containerDir
                    panel.begin { result in
                        if result == .OK, let url = panel.urls.first {
                            defaultBottleLocation = url
                        }
                    }
                }
                .help("Choose where newly created bottles and DOS libraries are stored by default.")
            }
        }
        .formStyle(.grouped)
    }

    private var appearanceTab: some View {
        Form {
            Section("Window Style") {
                Toggle(
                    String(localized: "settings.toggle.glass", defaultValue: "Use glass effects"),
                    isOn: $useGlassUI
                )
                .help("Enable the newer glass treatment across the app.")

                Toggle(
                    String(
                        localized: "settings.toggle.wrapShortcuts",
                        defaultValue: "Wrap shortcut icons with app styling"
                    ),
                    isOn: $wrapProgramShortcuts
                )
                .help("Apply GIACK styling when generating macOS shortcuts.")
            }

                Section("Notes") {
                    Text(String(
                        localized: "settings.appearance.notes",
                        defaultValue: "Keep glass effects off if you want the quietest, most traditional window appearance."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

        }
        .formStyle(.grouped)
    }

    private var runnersTab: some View {
        Form {
            Section("System Scan") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(systemScanReport?.summary ?? "Scanning this Mac...")
                        .font(.subheadline)

                    Text(String(
                        localized: "settings.runners.scan.title",
                        defaultValue: "Active Wine: \(systemScanReport?.activeWineSummary ?? activeWineSummary)"
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(
                        localized: "settings.runners.scan.dosbox",
                        defaultValue: "DOSBox: \(systemScanReport?.dosboxSummary ?? dosboxVersionSummary)"
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let findings = systemScanReport?.findings, !findings.isEmpty {
                        ForEach(findings) { finding in
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(finding.title)
                                        .font(.caption.weight(.semibold))
                                    Text(finding.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: finding.severity == .ready ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(finding.severity == .ready ? .green : .orange)
                            }
                        }
                    }

                    HStack {
                        Button(isRefreshingRunners ? "Scanning…" : "Scan This Mac") {
                            Task {
                                await refreshRunnerStatus()
                            }
                        }
                        .disabled(isRefreshingRunners || isManagingWineRuntime || isManagingDOSBox)
                        .help("Scan this Mac and summarize which runner components still need attention.")

                        Button(String(localized: "settings.runners.scan.applyDefaults", defaultValue: "Apply Recommended Defaults")) {
                            applyRecommendedDefaults()
                            Task {
                                await refreshRunnerStatus()
                            }
                        }
                        .disabled(isRefreshingRunners || isManagingWineRuntime || isManagingDOSBox)
                        .help("Enable the recommended stability and runtime-update defaults for this app.")
                    }
                }
            }

            Section("Wine Runtime") {
                Picker("Active runtime", selection: Binding(
                    get: { runtimeSelection },
                    set: { newValue in
                        selectedWineRuntimeSelection = newValue.rawValue
                        GIACKWineInstaller.setSelectedRuntimeSelection(newValue)
                        if newValue != .gptkManaged {
                            Task {
                                await installOrUpdateSelectedWineRuntime()
                            }
                        } else {
                            Task {
                                await refreshRunnerStatus()
                            }
                        }
                    }
                )) {
                    ForEach(GIACKWineInstaller.RuntimeSelection.allCases, id: \.self) { selection in
                        Text(selection.displayName).tag(selection)
                    }
                }
                .help("Choose which Wine runtime family should own Windows libraries on this Mac.")

                Text(runtimeSelection.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if runtimeSelection == .gptkManaged {
                    Text(String(
                        localized: "settings.runners.managedRuntime",
                        defaultValue: "Managed GPTK runtime: \(managedRuntimeSummary)"
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(
                        localized: "settings.runners.managedRuntime.info",
                        defaultValue: "GPTK installs and updates stay on the Updates tab so runner selection stays focused."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(selectedWineStatusSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(isManagingWineRuntime ? "Working…" : "Install or Update Selected Runtime") {
                        Task {
                            await installOrUpdateSelectedWineRuntime()
                        }
                    }
                    .disabled(isRefreshingRunners || isManagingWineRuntime || selectedWineCask == nil)
                    .help("Install or update the selected Homebrew Wine runtime.")
                }

                if let runnerActionMessage {
                    Text(runnerActionMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(
                    String(
                        localized: "settings.runners.perBottle.note",
                        defaultValue: "Per-bottle overrides can be set in each library's Config tab. Bottles with no override follow this global runtime."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("DOSBox") {
                Text(dosboxCaskStatus?.summary ?? dosboxVersionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(isManagingDOSBox ? "Working…" : "Install or Update DOSBox") {
                    Task {
                        await installOrUpdateDOSBox()
                    }
                }
                .disabled(isRefreshingRunners || isManagingDOSBox)
                .help("Install or update DOSBox Staging using Homebrew.")

                ActionView(
                    text: "DOSBox executable",
                    subtitle: dosboxPathSummary,
                    actionName: "Choose"
                ) {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
                    panel.begin { result in
                        if result == .OK, let url = panel.urls.first {
                            DOSBox.setOverrideExecutableURL(url)
                            Task {
                                await refreshRunnerStatus()
                            }
                        }
                    }
                }
                .help("Point GIACK at a specific DOSBox or DOSBox Staging binary.")

                Button(String(localized: "settings.runners.dosbox.autoDetect", defaultValue: "Use Auto-Detected DOSBox")) {
                    DOSBox.setOverrideExecutableURL(nil)
                    Task {
                        await refreshRunnerStatus()
                    }
                }
                .help("Clear the manual DOSBox path and fall back to standard macOS install locations.")
            }

            Section("Runner Notes") {
                Text(
                    String(
                        localized: "settings.runners.notes",
                        defaultValue: "Wine 11 stable is now available as a selectable macOS runtime. DOSBox Staging can be installed and updated from here. Lutris itself is Linux-first, so this app follows the same launcher idea with native macOS runners instead of exposing a fake Lutris runtime."
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var updatesTab: some View {
        Form {
            Section("Application") {
                if hasAppUpdateFeed {
                    Toggle(
                        String(
                            localized: "settings.toggle.whisky.updates",
                            defaultValue: "Automatically check for app updates"
                        ),
                        isOn: $whiskyUpdate
                    )
                    .help("Check for newer GIACK application releases.")
                } else {
                    Text(String(localized: "settings.appfeed.unconfigured",
                                defaultValue: "App update feed is not configured for this build."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Runtime") {
                Toggle(
                    String(
                        localized: "settings.toggle.whiskywine.updates",
                        defaultValue: "Automatically check for runtime updates"
                    ),
                    isOn: $checkGIACKWineUpdates
                )
                .help("Check for newer GPTK Wine runtime packages.")

                Toggle(
                    String(localized: "settings.toggle.whiskywine.autoInstall",
                           defaultValue: "Automatically install runtime updates"),
                    isOn: $autoInstallGIACKWineUpdates
                )
                .disabled(!checkGIACKWineUpdates)
                .help("Install newer GPTK runtime packages without prompting.")

                Toggle(
                    String(localized: "settings.toggle.runtime.preferLocal",
                           defaultValue: "Prefer local mounted GPTK runtime"),
                    isOn: $preferLocalGPTKRuntime
                )
                .help("Prefer locally mounted Apple GPTK images when they are newer than the remote runtime.")

                Text(
                    String(
                        format: String(
                            localized: "settings.runtime.installed",
                            defaultValue: "Installed Runtime: %@"
                        ),
                        managedRuntimeSummary
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(
                    String(
                        format: String(
                            localized: "settings.runtime.latest",
                            defaultValue: "Latest Available: %@"
                        ),
                        latestRuntimeSummary
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if let runtimeActionMessage {
                    Text(runtimeActionMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button(
                        String(
                            localized: "settings.runtime.checkNow",
                            defaultValue: "Check Now"
                        )
                    ) {
                        Task {
                            await refreshLatestRuntime()
                        }
                    }
                    .disabled(isRefreshingRuntime || isInstallingRuntime)
                    .help("Fetch the latest GPTK runtime metadata now.")

                    Button(isInstallingRuntime
                           ? String(localized: "settings.runtime.installing", defaultValue: "Installing…")
                           : String(localized: "settings.runtime.installNow", defaultValue: "Install Latest Runtime")) {
                        Task {
                            await installLatestRuntime()
                        }
                    }
                    .disabled(isRefreshingRuntime || isInstallingRuntime || latestRuntimePackage == nil)
                    .help("Download and install the latest GPTK runtime package.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var resourcesTab: some View {
        Form {
            Section("Documentation") {
                if let readmeURL = ProjectInfo.bundledDocumentURL(.readme) {
                    Link(
                        String(localized: "settings.resources.readme", defaultValue: "Installation Guide"),
                        destination: readmeURL
                    )
                }
                if let changelogURL = ProjectInfo.bundledDocumentURL(.changelog) {
                    Link(
                        String(localized: "settings.resources.changelog", defaultValue: "Changelog"),
                        destination: changelogURL
                    )
                }
                if let dependenciesURL = ProjectInfo.bundledDocumentURL(.dependencies) {
                    Link(
                        String(localized: "settings.resources.dependencies", defaultValue: "Dependencies"),
                        destination: dependenciesURL
                    )
                }
            }

            Section("Project") {
                Link(
                    String(localized: "settings.resources.repository", defaultValue: "Project Repository"),
                    destination: ProjectInfo.repositoryURL
                )
                Link(
                    String(localized: "settings.resources.releases", defaultValue: "Latest Releases"),
                    destination: ProjectInfo.releasesURL
                )
                Link(
                    String(localized: "settings.resources.issues", defaultValue: "Report an Issue"),
                    destination: ProjectInfo.issuesURL
                )
                Link(
                    String(localized: "settings.resources.upstream", defaultValue: "Archived Upstream Repository"),
                    destination: ProjectInfo.archivedRepositoryURL
                )
                Link(
                    String(localized: "settings.resources.runtime", defaultValue: "GPTK Runtime Releases"),
                    destination: ProjectInfo.runtimeReleasesURL
                )
            }

            Section("Compliance") {
                Link(
                    String(localized: "settings.resources.notices", defaultValue: "Third-Party Notices"),
                    destination: ProjectInfo.documentURL(.thirdPartyNotices)
                )
                Link(
                    String(localized: "settings.resources.license", defaultValue: "Project License"),
                    destination: ProjectInfo.documentURL(.license)
                )
            }

            Section {
                Link(
                    String(localized: "settings.resources.support", defaultValue: "Buy Me a Coffee"),
                    destination: ProjectInfo.fundingURL
                )
            } header: {
                Text("Support")
            } footer: {
                Text(
                    String(
                        localized: "settings.resources.footer",
                        defaultValue: "This build bundles install guidance, notices, and license texts for redistribution compliance."
                    )
                )
                .font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    @MainActor
    private func refreshLatestRuntime() async {
        isRefreshingRuntime = true
        defer { isRefreshingRuntime = false }

        let package = await GIACKWineInstaller.latestRuntimePackage()
        latestRuntimePackage = package
        latestRuntimeSummary = package.map { "\($0.version) · \($0.source)" } ?? String(
            localized: "settings.runtime.unavailable",
            defaultValue: "Unable to resolve latest runtime"
        )
    }

    @MainActor
    private func installLatestRuntime() async {
        if latestRuntimePackage == nil {
            await refreshLatestRuntime()
        }

        guard let package = latestRuntimePackage else {
            runtimeActionMessage = String(
                localized: "settings.runtime.installUnavailable",
                defaultValue: "Runtime download source is unavailable."
            )
            return
        }

        isInstallingRuntime = true
        runtimeActionMessage = nil

        let archiveURL: URL
        if package.downloadURL.isFileURL {
            archiveURL = package.downloadURL
        } else {
            do {
                let (downloadedURL, _) = try await URLSession(configuration: .ephemeral)
                    .download(from: package.downloadURL)
                archiveURL = downloadedURL
            } catch {
                isInstallingRuntime = false
                runtimeActionMessage = String(
                    localized: "settings.runtime.downloadFailed",
                    defaultValue: "Failed to download the selected runtime."
                )
                return
            }
        }

        let packageVersion = package.version
        let packageSource = package.source
        let packageReleaseName = package.releaseName
        let success = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let success = GIACKWineInstaller.install(
                    from: archiveURL,
                    versionOverride: packageVersion,
                    source: packageSource,
                    releaseName: packageReleaseName
                )
                continuation.resume(returning: success)
            }
        }

        isInstallingRuntime = false
        runtimeActionMessage = success
            ? String(
                localized: "settings.runtime.installSuccess",
                defaultValue: "Installed %@."
            )
            .replacingOccurrences(of: "%@", with: package.releaseName)
            : String(
                localized: "settings.runtime.installFailed",
                defaultValue: "Runtime installation failed."
            )
        await refreshLatestRuntime()
    }

    @MainActor
    private func refreshRunnerStatus() async {
        isRefreshingRunners = true
        defer { isRefreshingRunners = false }

        GIACKWineInstaller.setSelectedRuntimeSelection(runtimeSelection)
        systemScanReport = await GIACKSystemScan.scan()
        if let selectedWineCask {
            selectedWineStatus = await HomebrewRuntimeManager.status(for: selectedWineCask)
        } else {
            selectedWineStatus = nil
        }
        dosboxCaskStatus = await HomebrewRuntimeManager.status(for: .dosboxStaging)
        await refreshDOSBoxSummary()
    }

    @MainActor
    private func installOrUpdateSelectedWineRuntime() async {
        guard let selectedWineCask else {
            runnerActionMessage = "Switch to a Homebrew Wine runtime to install Wine 11 from this tab."
            return
        }

        isManagingWineRuntime = true
        defer { isManagingWineRuntime = false }

        let result = await HomebrewRuntimeManager.installOrUpgrade(selectedWineCask)
        let failureSummary = result.output
            .split(whereSeparator: \.isNewline)
            .last
            .map(String.init) ?? "Unknown Homebrew error."
        runnerActionMessage = result.success
            ? "\(selectedWineCask.displayName) is ready."
            : "Failed to install \(selectedWineCask.displayName): \(failureSummary)"
        await refreshRunnerStatus()
    }

    @MainActor
    private func installOrUpdateDOSBox() async {
        isManagingDOSBox = true
        defer { isManagingDOSBox = false }

        let result = await HomebrewRuntimeManager.installOrUpgrade(.dosboxStaging)
        let failureSummary = result.output
            .split(whereSeparator: \.isNewline)
            .last
            .map(String.init) ?? "Unknown Homebrew error."
        runnerActionMessage = result.success
            ? "DOSBox Staging is ready."
            : "Failed to install DOSBox Staging: \(failureSummary)"
        await refreshRunnerStatus()
    }

    private func applyRecommendedDefaults() {
        disableAppNap = true
        GIACKActivityController.shared.setAppNapDisabled(true)
        checkGIACKWineUpdates = true
        autoInstallGIACKWineUpdates = true
        preferLocalGPTKRuntime = true

        if runtimeSelection != .gptkManaged,
           GIACKWineInstaller.currentWineRuntime() == nil {
            selectedWineRuntimeSelection = GIACKWineInstaller.RuntimeSelection.gptkManaged.rawValue
            GIACKWineInstaller.setSelectedRuntimeSelection(.gptkManaged)
        }
    }

    @MainActor
    private func refreshDOSBoxSummary() async {
        if let executableURL = DOSBox.executableURL() {
            let version = (try? await DOSBox.version()) ?? executableURL.lastPathComponent
            dosboxVersionSummary = "\(version) · \(executableURL.lastPathComponent)"
        } else {
            dosboxVersionSummary = "Not installed"
        }
    }
}

#Preview {
    SettingsView()
}
