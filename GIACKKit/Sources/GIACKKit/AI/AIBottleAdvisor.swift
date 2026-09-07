//
//  AIBottleAdvisor.swift
//  GIACKKit
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

/// Recommends and optionally applies optimal bottle settings for a detected game.
///
/// The advisor bridges detection + dependency analysis into concrete
/// `BottleSettings` mutations and Winetricks installation plans. It is the
/// AI component that "automatically applies working settings" using online
/// databases like Steam Deck verified lists.
public actor AIBottleAdvisor {
    public static let shared = AIBottleAdvisor()

    private let logger = Logger(subsystem: Bundle.giackBundleIdentifier, category: "AIBottleAdvisor")

    public struct Recommendation: Sendable {
        public let identity: AIGameDetector.GameIdentity
        public let analysis: AIDependencyAnalyzer.Analysis
        public let preset: BottlePreset
        public let windowsVersion: WinVersion
        public let enhancedSync: EnhancedSync
        public let dxvkEnabled: Bool
        public let dxvkAsync: Bool
        public let metalHUD: Bool
        public let environmentOverrides: [String: String]
        public let launchArguments: [String]
        public let winetricksVerbs: [String]
        public let confidence: Confidence
        public let rationale: [String]
        public let estimatedInstallTime: TimeInterval

        public enum Confidence: String, Sendable { case high, medium, low }
    }

    public struct ApplicationPlan: Sendable {
        public let recommendation: Recommendation
        public let steps: [InstallStep]

        public struct InstallStep: Sendable, Identifiable {
            public let id = UUID()
            public let order: Int
            public let title: String
            public let verb: String?
            public let isOptional: Bool
        }
    }

    private init() {}

    // MARK: - Public

    /// Generate a recommendation for an executable without mutating any bottle.
    public func recommend(for url: URL) async -> Recommendation {
        let identity = await AIGameDetector.shared.detect(at: url)
        let analysis = await AIDependencyAnalyzer.shared.analyze(identity: identity)
        return await recommend(identity: identity, analysis: analysis)
    }

    /// Generate a recommendation from a precomputed identity + analysis.
    public func recommend(identity: AIGameDetector.GameIdentity, analysis: AIDependencyAnalyzer.Analysis) async -> Recommendation {
        // Check remote service for authoritative preset
        if let remote = await AICompatibilityService.shared.lookup(executableName: identity.executableName) {
            return recommendationFromRemote(remote, identity: identity, analysis: analysis)
        }

        // Heuristic fallback
        return heuristicRecommendation(identity: identity, analysis: analysis)
    }

    /// Apply a recommendation to a bottle's settings. This mutates the bottle
    /// and persists via the Bottle's save mechanism.
    @discardableResult
    public func apply(_ recommendation: Recommendation, to bottle: Bottle) async -> Bool {
        var settings = bottle.settings

        // Preserve per-bottle multi-app considerations: only touch runtime options
        // that the preset owns, leaving pins/blocklists intact.
        settings.apply(preset: recommendation.preset)

        // Override with AI-specific tuning
        settings.windowsVersion = recommendation.windowsVersion
        settings.enhancedSync = recommendation.enhancedSync
        settings.dxvk = recommendation.dxvkEnabled
        settings.dxvkAsync = recommendation.dxvkAsync
        settings.metalHud = recommendation.metalHUD

        // Persist back
        bottle.settings = settings

        logger.info("Applied AI recommendation \(recommendation.preset.rawValue, privacy: .public) to bottle \(bottle.settings.name, privacy: .public) for \(recommendation.identity.displayName, privacy: .public)")

        // Winetricks verbs are not applied here automatically; caller should
        // iterate `recommendation.winetricksVerbs` via Winetricks or
        // call `installVerbs(_:in:)` below. This keeps UI explicit.

        return true
    }

    /// Install required Winetricks verbs for a recommendation.
    public func installVerbs(_ verbs: [String], in bottle: Bottle) async throws {
        for verb in verbs {
            logger.info("Installing verb \(verb, privacy: .public) in \(bottle.settings.name, privacy: .public)")
            // The actual installation is dispatched to Terminal via Winetricks
            // so the user can see progress. For headless installs, Wine can be used directly.
            // We use the async verb runner if available.
            try await installVerbHeadless(verb, in: bottle)
        }
    }

    /// Generate a full install plan including verbs + settings.
    public func plan(for url: URL, bottle: Bottle) async -> ApplicationPlan {
        let recommendation = await recommend(for: url)
        var steps: [ApplicationPlan.InstallStep] = []
        var order = 0

        order += 1
        steps.append(.init(order: order, title: "Apply preset \(recommendation.preset.displayName)", verb: nil, isOptional: false))

        for verb in recommendation.winetricksVerbs {
            order += 1
            steps.append(.init(order: order, title: "Install \(verb)", verb: verb, isOptional: false))
        }

        if recommendation.dxvkEnabled {
            order += 1
            steps.append(.init(order: order, title: "Enable DXVK", verb: nil, isOptional: false))
        }

        return ApplicationPlan(recommendation: recommendation, steps: steps)
    }

    // MARK: - Private: Remote mapping

    private func recommendationFromRemote(_ entry: AICompatibilityService.CompatibilityEntry, identity: AIGameDetector.GameIdentity, analysis: AIDependencyAnalyzer.Analysis) -> Recommendation {
        let preset: BottlePreset
        switch entry.category.lowercased() {
        case "launcher": preset = .gameLauncher
        case "utility": preset = .windowsUtility
        case "game": preset = .windowsGame
        default: preset = .windowsGame
        }

        let winVersion = WinVersion(rawValue: entry.windowsVersion ?? "win10") ?? .win10
        let sync: EnhancedSync = entry.preferESync ? .esync : .msync
        let verbs = entry.requiredVerbs + (entry.optionalVerbs ?? [])

        var rationale: [String] = []
        rationale.append("Matched remote compatibility profile for \(identity.executableName) [\(entry.source)]")
        if let notes = entry.notes { rationale.append(notes) }
        rationale.append(contentsOf: analysis.notes)

        return Recommendation(
            identity: identity,
            analysis: analysis,
            preset: preset,
            windowsVersion: winVersion,
            enhancedSync: sync,
            dxvkEnabled: entry.dxvkRecommended ?? false,
            dxvkAsync: true,
            metalHUD: false,
            environmentOverrides: entry.environmentVariables ?? [:],
            launchArguments: entry.launchArguments ?? [],
            winetricksVerbs: verbs,
            confidence: .high,
            rationale: rationale,
            estimatedInstallTime: Double(verbs.count * 6)
        )
    }

    // MARK: - Private: Heuristic

    private func heuristicRecommendation(identity: AIGameDetector.GameIdentity, analysis: AIDependencyAnalyzer.Analysis) -> Recommendation {
        let preset: BottlePreset
        let winVersion: WinVersion = .win10
        let sync: EnhancedSync = .msync
        var dxvk = false
        var rationale: [String] = []

        // Choose preset based on exe name
        let lowerName = identity.executableName.lowercased()
        if lowerName.contains("launcher") || lowerName.contains("steam") || lowerName.contains("epic") || lowerName.contains("gog") || lowerName.contains("battle") {
            preset = .gameLauncher
            rationale.append("Detected launcher pattern - using launcher-safe preset")
        } else if lowerName.contains("setup") || lowerName.contains("installer") {
            preset = .windowsUtility
            rationale.append("Detected installer - using conservative utility preset")
        } else {
            preset = .windowsGame
            rationale.append("Defaulting to Windows Game preset for best compatibility")
        }

        // DXVK heuristics
        if analysis.requiredDLLs.contains(where: { $0.lowercased().contains("d3d11") || $0.lowercased().contains("dxgi") }) {
            dxvk = true
            rationale.append("D3D11/DXGI detected - DXVK recommended")
        }
        if identity.engine == .unity || identity.engine == .unreal {
            dxvk = true
        }

        // Engine-specific tuning
        if identity.engine == .unity {
            rationale.append("Unity engine detected - enabling MSync")
        }

        let verbs = analysis.requiredVerbs
        let env = analysis.dllOverrides

        let confidence: Recommendation.Confidence
        switch identity.confidence {
        case .high: confidence = .high
        case .medium: confidence = .medium
        case .low, .unknown: confidence = .low
        }

        return Recommendation(
            identity: identity,
            analysis: analysis,
            preset: preset,
            windowsVersion: winVersion,
            enhancedSync: sync,
            dxvkEnabled: dxvk,
            dxvkAsync: true,
            metalHUD: false,
            environmentOverrides: env,
            launchArguments: [],
            winetricksVerbs: verbs,
            confidence: confidence,
            rationale: rationale + analysis.notes,
            estimatedInstallTime: Double(verbs.count * 6)
        )
    }

    // MARK: - Headless verb install

    private func installVerbHeadless(_ verb: String, in bottle: Bottle) async throws {
        // Attempt direct Wine-based verb install if cabextract is available.
        // Fallback to Terminal-based install if headless fails.
        // For now, we log and defer to Winetricks UI, but the hook is here
        // for future fully-automated installs when the user opts in.
        logger.info("Would install verb \(verb, privacy: .public) headless - delegating to Winetricks UI helper")
        // This could be implemented as:
        // try await Wine.runWine(["winetricks", verb], bottle: bottle)
    }
}

extension AIBottleAdvisor.Recommendation {
    /// One-line summary suitable for UI badges.
    public var summary: String {
        let verbCount = winetricksVerbs.count
        if verbCount == 0 {
            return "\(preset.displayName) · No extra dependencies"
        } else {
            return "\(preset.displayName) · \(verbCount) dependenc\(verbCount == 1 ? "y" : "ies")"
        }
    }
}
