//
//  ProgramView.swift
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

struct ProgramView: View {
    @ObservedObject var program: Program
    @State var programLoading: Bool = false
    @State var cachedIconImage: Image?
    @AppStorage("configSectionExapnded") private var configSectionExpanded: Bool = true
    @AppStorage("envArgsSectionExpanded") private var envArgsSectionExpanded: Bool = true
    @AppStorage("aiSectionExpanded") private var aiSectionExpanded: Bool = true
    @State private var aiIdentity: AIGameDetector.GameIdentity?
    @State private var aiAnalysis: AIDependencyAnalyzer.Analysis?
    @State private var aiRecommendation: AIBottleAdvisor.Recommendation?
    @State private var aiPlan: AIBottleAdvisor.ApplicationPlan?
    @State private var aiLoading = false
    @State private var aiApplied = false
    @State private var aiInstallState: AIInstallState = .idle

    private enum AIInstallState: Equatable {
        case idle, installing, success, failed(String)
    }

    var body: some View {
        Form {
            aiSection
            Section("program.config", isExpanded: $configSectionExpanded) {
                Picker("locale.title", selection: $program.settings.locale) {
                    ForEach(Locales.allCases, id: \.self) { locale in
                        Text(locale.pretty()).id(locale)
                    }
                }
                .help("Override the program locale that is exported at launch time.")
                VStack {
                    HStack {
                        Text("program.args")
                        Spacer()
                    }
                    TextField("program.args", text: $program.settings.arguments)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .labelsHidden()
                        .help("Optional launch arguments. Quotes keep spaces inside a single argument.")
                }
            }
            EnvironmentArgView(program: program, isExpanded: $envArgsSectionExpanded)
        }
        .bottomBar {
            HStack {
                Spacer()
                Button("button.showInFinder") {
                    NSWorkspace.shared.activateFileViewerSelecting([program.url])
                }
                .help("Reveal this program in Finder.")
                Button("button.createShortcut") {
                    let panel = NSSavePanel()
                    let applicationDir = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask)[0]
                    let name = program.name.replacingOccurrences(of: ".exe", with: "")
                    panel.directoryURL = applicationDir
                    panel.canCreateDirectories = true
                    panel.allowedContentTypes = [UTType.applicationBundle]
                    panel.allowsOtherFileTypes = false
                    panel.isExtensionHidden = true
                    panel.nameFieldStringValue = name + ".app"
                    panel.begin { result in
                        if result == .OK {
                            if let url = panel.url {
                                let name = url.deletingPathExtension().lastPathComponent
                                Task(priority: .userInitiated) {
                                    await ProgramShortcut.createShortcut(program, app: url, name: name)
                                }
                            }
                        }
                    }
                }
                .help("Create a macOS app shortcut that launches this program with its current runner.")
                Button("button.run") {
                    programLoading = true
                    program.run()
                }
                .help("Launch this program now.")
                .disabled(programLoading)
                if programLoading {
                    Spacer()
                        .frame(width: 10)
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding()
        }
        .toolbar {
            if let image = cachedIconImage {
                ToolbarItem(id: "ProgramViewIcon", placement: .navigation) {
                    image
                        .resizable()
                        .frame(width: 25, height: 25)
                        .padding(.trailing, 5)
                }
            } else {
                ToolbarItem(id: "ProgramViewIcon", placement: .navigation) {
                    Image(systemName: "app.dashed")
                        .resizable()
                        .frame(width: 25, height: 25)
                        .padding(.trailing, 5)
                }
            }
        }
        .navigationTitle(program.name)
        .formStyle(.grouped)
        .animation(.giackDefault, value: configSectionExpanded)
        .animation(.giackDefault, value: envArgsSectionExpanded)
        .animation(.giackDefault, value: aiSectionExpanded)
        .animation(.giackDefault, value: aiLoading)
        .task {
            if let fetchedImage = program.peFile?.bestIcon() { self.cachedIconImage = Image(nsImage: fetchedImage) }
            await loadAI()
        }
    }

    // MARK: - AI Analysis (per-game dependency scan)

    /// Per-program AI analysis. This is the “scan for dependencies for every
    /// individual game” path the user asked for in 2.0 feedback. Opening a
    /// program now automatically runs `AIGameDetector.detect → AIDependencyAnalyzer.analyze
    /// → AIBottleAdvisor.recommend` and surfaces the result inline so the user
    /// can apply the recommended bottle preset / Win version / DXVK / verbs or
    /// install missing dependencies without leaving the detail view.
    private var aiSection: some View {
        Section("AI Analysis", isExpanded: $aiSectionExpanded) {
            if aiLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Analyzing executable…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let identity = aiIdentity, let recommendation = aiRecommendation, let analysis = aiAnalysis {
                // Identity header
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: engineIcon(for: identity.engine))
                            .foregroundStyle(.secondary)
                        Text(identity.displayName)
                            .font(.headline)
                        Spacer()
                        Text(identity.confidence.rawValue.capitalized)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(confidenceTint(identity.confidence).opacity(0.14), in: Capsule())
                    }
                    HStack(spacing: 8) {
                        if let publisher = identity.publisher {
                            Label(publisher, systemImage: "building.2")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let engine = identity.engine, engine != .unknown {
                            Label(engine.rawValue.capitalized, systemImage: "cpu")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let arch = identity.architecture.toString() {
                            Label(arch, systemImage: "memorychip")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text(program.url.path(percentEncoded: false))
                        .font(.caption2).foregroundStyle(.secondary)
                        .textSelection(.enabled).lineLimit(2)
                }

                // Recommendation + Analysis
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("Preset").foregroundStyle(.secondary).font(.caption)
                        Text(recommendation.preset.displayName).font(.caption.weight(.semibold))
                    }
                    GridRow {
                        Text("Windows").foregroundStyle(.secondary).font(.caption)
                        Text(recommendation.windowsVersion.pretty()).font(.caption)
                    }
                    GridRow {
                        Text("Sync").foregroundStyle(.secondary).font(.caption)
                        Text(syncLabel(recommendation.enhancedSync)).font(.caption)
                    }
                    GridRow {
                        Text("Graphics").foregroundStyle(.secondary).font(.caption)
                        Text(recommendation.dxvkEnabled ? "DXVK" : "D3DMetal").font(.caption)
                    }
                    if !analysis.requiredVerbs.isEmpty || !analysis.requiredDLLs.isEmpty {
                        GridRow {
                            Text("Dependencies").foregroundStyle(.secondary).font(.caption)
                            VStack(alignment: .leading, spacing: 2) {
                                if !analysis.requiredVerbs.isEmpty {
                                    Text("Verbs: \(analysis.requiredVerbs.joined(separator: ", "))")
                                        .font(.caption).textSelection(.enabled)
                                }
                                if !analysis.requiredDLLs.isEmpty {
                                    Text("DLLs: \(analysis.requiredDLLs.joined(separator: ", "))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if !recommendation.winetricksVerbs.isEmpty {
                        GridRow {
                            Text("Winetricks").foregroundStyle(.secondary).font(.caption)
                            Text(recommendation.winetricksVerbs.joined(separator: ", "))
                                .font(.caption).textSelection(.enabled)
                        }
                    }
                }
                .padding(.vertical, 4)

                if !recommendation.rationale.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Why").font(.caption.weight(.semibold))
                        ForEach(recommendation.rationale, id: \.self) { line in
                            Label(line, systemImage: "lightbulb")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if let plan = aiPlan, !plan.steps.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Install Plan (\(plan.steps.count) steps)").font(.caption.weight(.semibold))
                        ForEach(plan.steps) { step in
                            Label(step.title, systemImage: step.isOptional ? "circle.dashed" : "arrow.right.circle")
                                .font(.caption).foregroundStyle(step.isOptional ? .secondary : .primary)
                        }
                        if let rec = aiRecommendation {
                            Text(String(format: "Estimated time: %.0f s", rec.estimatedInstallTime))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                // Actions
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Button(aiApplied ? "Applied ✓" : "Apply Recommended Settings") {
                            Task { await applyAI() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(aiApplied || aiLoading)
                        .help("Apply the AI-recommended preset, Windows version, sync mode, and DXVK to this program's bottle.")

                        Button("Re-scan") {
                            Task { await loadAI(force: true) }
                        }
                        .help("Re-run detection and dependency analysis for this executable.")
                    }

                    if !recommendation.winetricksVerbs.isEmpty {
                        HStack(spacing: 8) {
                            Button {
                                Task { await installAIVerbs() }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(aiInstallState == .installing ? "Installing…" : "Install Missing Dependencies")
                                    if aiInstallState == .installing {
                                        ProgressView().controlSize(.small)
                                    }
                                }
                            }
                            .disabled(aiInstallState == .installing)
                            .help("Install the Winetricks verbs identified for this game via Winetricks.")

                            if aiInstallState == .success {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Install command queued.")
                            }
                        }
                        if case .failed(let msg) = aiInstallState {
                            Text(msg).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                        }
                        Text("Per-game verb installs are queued individually; DXVK and preset changes apply immediately.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                if aiApplied {
                    Label("Settings applied to bottle “\(program.bottle.settings.name)”", systemImage: "checkmark.seal.fill")
                        .font(.caption).foregroundStyle(.green)
                }

            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No AI result yet. The per-game scan checks the executable’s imports, sibling DLLs, engine hints, and the curated compatibility database.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button("Scan Now") { Task { await loadAI() } }
                            .buttonStyle(.bordered)
                        if let url = AICompatibilityConfig.remoteURL {
                            Link("Compatibility DB", destination: url)
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }

    private func loadAI(force: Bool = false) async {
        if aiLoading { return }
        if !force, aiIdentity != nil { return }
        aiLoading = true
        defer { aiLoading = false }
        let url = program.url
        // Run detection -> analysis -> recommendation on a utility queue
        let identity = await AIGameDetector.shared.detect(at: url)
        let analysis = await AIDependencyAnalyzer.shared.analyze(identity: identity)
        let recommendation = await AIBottleAdvisor.shared.recommend(identity: identity, analysis: analysis)
        let plan = await AIBottleAdvisor.shared.plan(for: url, bottle: program.bottle)
        await MainActor.run {
            self.aiIdentity = identity
            self.aiAnalysis = analysis
            self.aiRecommendation = recommendation
            self.aiPlan = plan
        }
    }

    private func applyAI() async {
        guard let rec = aiRecommendation else { return }
        let ok = await AIBottleAdvisor.shared.apply(rec, to: program.bottle)
        await MainActor.run { self.aiApplied = ok }
    }

    private func installAIVerbs() async {
        guard let rec = aiRecommendation, !rec.winetricksVerbs.isEmpty else { return }
        await MainActor.run { self.aiInstallState = .installing }
        // Install each verb via Winetricks Terminal helper so the user sees
        // progress. This is the per-game dependency path the user asked for:
        // every individual game gets its verbs queued individually.
        // AIBottleAdvisor.installVerbs is kept as a headless fallback in the kit,
        // but the app target's Winetricks.runCommand is the user-visible executor.
        for verb in rec.winetricksVerbs {
            await Winetricks.runCommand(command: verb, bottle: program.bottle)
        }
        await MainActor.run { self.aiInstallState = .success }
    }

    private func confidenceTint(_ c: AIGameDetector.GameIdentity.Confidence) -> Color {
        switch c {
        case .high: return .green
        case .medium: return .orange
        case .low: return .secondary
        case .unknown: return .red
        }
    }

    private func engineIcon(for engine: AIGameDetector.GameIdentity.Engine?) -> String {
        switch engine {
        case .unity: return "cube.fill"
        case .unreal: return "cube.transparent.fill"
        case .cryEngine: return "snowflake"
        case .godot: return "gamecontroller.fill"
        case .rpgMaker: return "wand.and.stars"
        case .source: return "hammer.fill"
        case .idTech: return "scope"
        default: return "questionmark.app.dashed"
        }
    }

    private func syncLabel(_ sync: EnhancedSync) -> String {
        switch sync {
        case .none: return "None"
        case .esync: return "ESync"
        case .msync: return "MSync"
        }
    }
}
