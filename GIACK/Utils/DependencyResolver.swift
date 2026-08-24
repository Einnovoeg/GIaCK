//
//  DependencyResolver.swift
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
import os.log
import GIACKKit

actor DependencyResolver {
    static let shared = DependencyResolver()

    private let logger = Logger(subsystem: Bundle.giackBundleIdentifier, category: "DependencyResolver")
    private let database = RemoteDatabase.shared

    typealias ProgressCallback = @Sendable (String, Double) -> Void
    private var progressCallback: ProgressCallback?
    private var lastProgressMessage: String = ""
    private var lastProgressValue: Double = 0

    struct ResolvedApplication: Sendable {
        let name: String
        let entry: RemoteDatabase.DatabaseEntry?
        let detectedDependencies: [DependencyInfo]
        let missingDependencies: [DependencyInfo]
        let installableDependencies: [DependencyInfo]
        let recommendations: [String]
        let configuration: AppConfiguration?
    }

    struct AppConfiguration: Sendable {
        let windowsVersion: String?
        let dxvkEnabled: Bool
        let environmentVariables: [String: String]
        let launchArguments: [String]
        let customDllOverrides: [String: String]
    }

    struct ResolutionResult: Sendable {
        let application: ResolvedApplication
        let steps: [InstallStep]
        let estimatedTime: TimeInterval
        let requiresManualIntervention: Bool
    }

    struct InstallStep: Identifiable, Sendable {
        let id = UUID()
        let order: Int
        let description: String
        let action: Action
        let isOptional: Bool

        enum Action: Sendable {
            case installVerb(String)
            case overrideDll(String, source: String)
            case setWindowsVersion(String)
            case enableDXVK
            case setEnvironment(String, value: String)
            case launchArguments([String])
            case customConfig(String)
            case manual(String)
        }
    }

    func resolve(executableName: String, at url: URL? = nil) async -> ResolutionResult {
        let entry = await database.lookup(byName: executableName)

        let dependencies = entry.map { await database.dependencies(for: $0) } ?? []
        let missing = await filterMissing(dependencies)
        let installable = missing.filter { $0.autoInstallable }

        let recommendations = generateRecommendations(for: executableName, entry: entry)
        let config = entry.map { buildConfiguration(for: $0) }

        let resolved = ResolvedApplication(
            name: executableName,
            entry: entry,
            detectedDependencies: dependencies,
            missingDependencies: missing,
            installableDependencies: installable,
            recommendations: recommendations,
            configuration: config
        )

        let steps = buildInstallSteps(for: resolved)
        let estimatedTime = estimateInstallTime(steps: steps)
        let requiresManual = steps.contains { $0.action == .manual("") }

        return ResolutionResult(
            application: resolved,
            steps: steps,
            estimatedTime: estimatedTime,
            requiresManualIntervention: requiresManual
        )
    }

    func autoConfigure(bottlePath: URL, for executableName: String) async throws {
        let result = await resolve(executableName: executableName)

        guard let config = result.application.configuration else { return }

        if let winVersion = config.windowsVersion {
            try await Wine.changeWinVersion(bottle: bottlePath, version: winVersion)
        }

        for step in result.steps where !step.isOptional {
            try await executeStep(step, bottlePath: bottlePath)
        }
    }

    func suggestApplications(in folder: URL) async -> [ResolvedApplication] {
        var suggestions: [ResolvedApplication] = []

        let executables = findExecutables(in: folder)
        for exe in executables {
            let result = await resolve(executableName: exe.lastPathComponent, at: exe)
            suggestions.append(result.application)
        }

        return suggestions.sorted { lhs, rhs in
            if lhs.entry != nil && rhs.entry == nil { return true }
            if lhs.entry == nil && rhs.entry != nil { return false }
            return lhs.name < rhs.name
        }
    }

    // MARK: - Private

    private func filterMissing(_ dependencies: [DependencyInfo]) async -> [DependencyInfo] {
        var missing: [DependencyInfo] = []

        for dep in dependencies {
            let isInstalled = await checkDependencyInstalled(dep)
            if !isInstalled {
                missing.append(dep)
            }
        }

        return missing
    }

    private func checkDependencyInstalled(_ dep: DependencyInfo) async -> Bool {
        switch dep.type {
        case .dll:
            break
        case .verb:
            break
        case .framework:
            break
        case .registry:
            break
        }
        return false
    }

    private func generateRecommendations(for name: String, entry: RemoteDatabase.DatabaseEntry?) -> [String] {
        var recs: [String] = []

        if let entry = entry {
            if entry.dxvkRequired {
                recs.append("Enable DXVK for better graphics performance")
            }
            if entry.difficulty == .difficult {
                recs.append("This application may require manual configuration")
            }
            if let issues = entry.knownIssues, !issues.isEmpty {
                recs.append("Known issues: \(issues.joined(separator: "; "))")
            }
        } else {
            recs.append("Application not in database - using heuristic detection")
            recs.append("Check winehq.org for compatibility information")
        }

        return recs
    }

    private func buildConfiguration(for entry: RemoteDatabase.DatabaseEntry) -> AppConfiguration {
        var envVars: [String: String] = [:]
        var dllOverrides: [String: String] = [:]

        if entry.dxvkRequired {
            envVars["DXVK_HUD"] = "fps"
        }

        for dll in entry.requiredDlls {
            if dll.hasPrefix("d3d") || dll.hasPrefix("dxgi") {
                dllOverrides[dll.lowercased()] = "native,builtin"
            }
        }

        return AppConfiguration(
            windowsVersion: entry.windowsVersion,
            dxvkEnabled: entry.dxvkRequired,
            environmentVariables: envVars,
            launchArguments: entry.launchArguments ?? [],
            customDllOverrides: dllOverrides
        )
    }

    private func buildInstallSteps(for app: ResolvedApplication) -> [InstallStep] {
        var steps: [InstallStep] = []
        var order = 0

        if let config = app.configuration, let winVer = config.windowsVersion {
            order += 1
            steps.append(InstallStep(
                order: order,
                description: "Set Windows version to \(winVer)",
                action: .setWindowsVersion(winVer),
                isOptional: false
            ))
        }

        if app.configuration?.dxvkEnabled == true {
            order += 1
            steps.append(InstallStep(
                order: order,
                description: "Enable DXVK for graphics acceleration",
                action: .enableDXVK,
                isOptional: false
            ))
        }

        for dep in app.missingDependencies where dep.autoInstallable {
            order += 1
            switch dep.type {
            case .verb:
                steps.append(InstallStep(
                    order: order,
                    description: "Install \(dep.name) verb",
                    action: .installVerb(dep.name),
                    isOptional: false
                ))
            case .dll:
                steps.append(InstallStep(
                    order: order,
                    description: "Override \(dep.name)",
                    action: .overrideDll(dep.name, source: "builtin"),
                    isOptional: true
                ))
            default:
                break
            }
        }

        if let config = app.configuration {
            for (key, value) in config.environmentVariables {
                order += 1
                steps.append(InstallStep(
                    order: order,
                    description: "Set environment variable \(key)",
                    action: .setEnvironment(key, value: value),
                    isOptional: true
                ))
            }
        }

        return steps
    }

    private func estimateInstallTime(steps: [InstallStep]) -> TimeInterval {
        var time: TimeInterval = 0
        for step in steps {
            switch step.action {
            case .installVerb: time += 5
            case .overrideDll: time += 1
            case .setWindowsVersion: time += 2
            case .enableDXVK: time += 3
            case .setEnvironment: time += 0.5
            case .launchArguments: time += 0.5
            case .customConfig: time += 2
            case .manual: time += 30
            }
        }
        return time
    }

    private func executeStep(_ step: InstallStep, bottlePath: URL) async throws {
        switch step.action {
        case .installVerb(let verb):
            try await Winetricks.installVerb(verb, in: bottlePath)
        case .overrideDll(let dll, let source):
            logger.info("DLL override: \(dll) = \(source)")
        case .setWindowsVersion(let version):
            try await Wine.changeWinVersion(bottle: bottlePath, version: version)
        case .enableDXVK:
            logger.info("Enabling DXVK")
        case .setEnvironment(let key, let value):
            logger.info("Environment: \(key) = \(value)")
        case .launchArguments:
            break
        case .customConfig:
            break
        case .manual(let instruction):
            logger.info("Manual step required: \(instruction)")
        }
    }

    private func findExecutables(in folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: folder,
                                                             includingPropertiesForKeys: [.isRegularFileKey],
                                                             options: [.skipsHiddenFiles]) else {
            return []
        }

        var executables: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "exe" {
                executables.append(url)
            }
        }
        return executables
    }
}
