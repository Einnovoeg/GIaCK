//
//  AIDependencyAnalyzer.swift
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

/// Analyzes a game identity and its executable context to determine required
/// Windows libraries, frameworks, and Winetricks verbs.
///
/// The analyzer merges three sources:
///  1. PE import / sibling DLL heuristics
///  2. Local curated profiles (Steam, GOG, Unity, Unreal defaults)
///  3. Remote compatibility databases (Steam Deck, ProtonDB, Wine AppDB via AICompatibilityService)
public actor AIDependencyAnalyzer {
    public static let shared = AIDependencyAnalyzer()

    private let logger = Logger(subsystem: Bundle.giackBundleIdentifier, category: "AIDependencyAnalyzer")

    public struct Analysis: Sendable {
        public let identity: AIGameDetector.GameIdentity
        public let requiredDLLs: [String]
        public let requiredVerbs: [String]
        public let optionalVerbs: [String]
        public let frameworks: [String]
        public let dllOverrides: [String: String]
        public let notes: [String]
        public let confidence: Confidence

        public enum Confidence: String, Sendable { case high, medium, low }

        public var allVerbs: [String] { requiredVerbs + optionalVerbs }
        public var isEmpty: Bool { requiredDLLs.isEmpty && requiredVerbs.isEmpty && frameworks.isEmpty }
    }

    // MARK: - Curated verb mappings

    /// Maps common DLLs to Winetricks verbs that provide them.
    private let dllToVerbs: [String: [String]] = [
        "d3dcompiler_47.dll": ["d3dcompiler_47"],
        "d3dx9_43.dll": ["d3dx9"],
        "d3dx10_43.dll": ["d3dx10"],
        "d3dx11_43.dll": ["d3dx11"],
        "d3d12.dll": ["d3dcompiler_47"],
        "vcruntime140.dll": ["vcrun2022"],
        "vcruntime120.dll": ["vcrun2013"],
        "vcruntime110.dll": ["vcrun2012"],
        "msvcp140.dll": ["vcrun2022"],
        "msvcp120.dll": ["vcrun2013"],
        "msvcr120.dll": ["vcrun2013"],
        "xinput1_3.dll": ["xinput"],
        "xaudio2_7.dll": ["xact"],
        "mf.dll": ["mf"],
        "mfplat.dll": ["mf"],
        "quartz.dll": ["quartz"],
        "devenum.dll": ["quartz"],
        "wmp.dll": ["wmp10"],
        "dotnet": ["dotnet48"],
    ]

    /// Engine defaults that should be applied when no remote profile exists.
    private func engineDefaults(for engine: AIGameDetector.GameIdentity.Engine?) -> Analysis {
        switch engine {
        case .unity:
            return Analysis(
                identity: placeholderIdentity(engine: engine),
                requiredDLLs: ["d3d11.dll"],
                requiredVerbs: ["d3dcompiler_47"],
                optionalVerbs: ["vcrun2022"],
                frameworks: [],
                dllOverrides: [:],
                notes: ["Unity titles typically need d3dcompiler_47 for shader compilation"],
                confidence: .medium
            )
        case .unreal:
            return Analysis(
                identity: placeholderIdentity(engine: engine),
                requiredDLLs: ["d3d11.dll", "d3d12.dll"],
                requiredVerbs: ["d3dcompiler_47", "vcrun2022"],
                optionalVerbs: [],
                frameworks: [],
                dllOverrides: [:],
                notes: ["Unreal titles benefit from DXVK and VCRun 2022"],
                confidence: .medium
            )
        case .rpgMaker:
            return Analysis(
                identity: placeholderIdentity(engine: engine),
                requiredDLLs: ["rgss301.dll"],
                requiredVerbs: ["rpgvxace"],
                optionalVerbs: [],
                frameworks: [],
                dllOverrides: [:],
                notes: ["RPG Maker titles need RGSS runtime"],
                confidence: .medium
            )
        default:
            return Analysis(
                identity: placeholderIdentity(engine: engine),
                requiredDLLs: [],
                requiredVerbs: [],
                optionalVerbs: [],
                frameworks: [],
                dllOverrides: [:],
                notes: [],
                confidence: .low
            )
        }
    }

    private func placeholderIdentity(engine: AIGameDetector.GameIdentity.Engine?) -> AIGameDetector.GameIdentity {
        AIGameDetector.GameIdentity(
            executableName: "placeholder.exe",
            displayName: "Placeholder",
            publisher: nil,
            engine: engine,
            confidence: .unknown,
            detectedVersion: nil,
            architecture: .unknown,
            importedDLLs: [],
            fileSize: 0,
            sha256Prefix: nil
        )
    }

    private init() {}

    // MARK: - Public

    /// Analyze a detected game identity to produce a dependency plan.
    public func analyze(identity: AIGameDetector.GameIdentity) async -> Analysis {
        // Check remote compatibility service first - highest authority
        if let remote = await AICompatibilityService.shared.lookup(executableName: identity.executableName) {
            let analysis = analysisFromRemote(remote, identity: identity)
            logger.info("Using remote profile for \(identity.executableName, privacy: .public): \(analysis.requiredVerbs.count) verbs")
            return analysis
        }

        // Fallback to heuristic analysis
        var requiredDLLs = Set<String>()
        var requiredVerbs = Set<String>()
        var frameworks = Set<String>()
        var dllOverrides: [String: String] = [:]
        var notes: [String] = []

        // DLL heuristics
        for dll in identity.importedDLLs.map({ $0.lowercased() }) {
            if let verbs = dllToVerbs[dll] {
                requiredVerbs.formUnion(verbs)
                requiredDLLs.insert(dll)
            } else if dll.hasPrefix("api-ms-win-") {
                // API sets are usually satisfied by vcrun or dotnet
                requiredVerbs.insert("vcrun2022")
            }
        }

        // Architecture hints
        if identity.architecture == .x32 {
            notes.append("32-bit executable detected - ensure 32-bit Wine prefix support")
        }

        // Engine defaults
        let engineAnalysis = engineDefaults(for: identity.engine)
        requiredDLLs.formUnion(engineAnalysis.requiredDLLs)
        requiredVerbs.formUnion(engineAnalysis.requiredVerbs)
        notes.append(contentsOf: engineAnalysis.notes)

        // File size heuristics: very small exes are often launchers needing dotnet
        if identity.fileSize < 2_000_000 && identity.executableName.lowercased().contains("launcher") {
            requiredVerbs.insert("dotnet48")
            notes.append("Small launcher executable - may require .NET Framework")
        }

        // Common gaming verbs for medium confidence identities
        if identity.confidence == .high || identity.confidence == .medium {
            if !requiredVerbs.contains("d3dcompiler_47") && identity.importedDLLs.contains(where: { $0.lowercased().contains("d3d") }) {
                requiredVerbs.insert("d3dcompiler_47")
            }
        }

        // Framework detection from sibling patterns via identity
        if identity.displayName.lowercased().contains("steam") {
            frameworks.insert("steam")
        }

        // Deduplicate and sort for determinism
        let sortedDLLs = requiredDLLs.sorted()
        let sortedVerbs = requiredVerbs.sorted()
        let optionalVerbs: [String] = []

        // Establish overrides for graphics DLLs when DXVK is recommended
        if sortedVerbs.contains("d3dx11") || sortedVerbs.contains("d3dcompiler_47") {
            for dll in ["d3d11", "dxgi"] where !dllOverrides.keys.contains(dll) {
                dllOverrides[dll] = "native,builtin"
            }
        }

        return Analysis(
            identity: identity,
            requiredDLLs: sortedDLLs,
            requiredVerbs: sortedVerbs,
            optionalVerbs: optionalVerbs,
            frameworks: frameworks.sorted(),
            dllOverrides: dllOverrides,
            notes: notes,
            confidence: confidenceFor(identity: identity, hasRemote: false)
        )
    }

    /// Analyze directly from a file URL (convenience).
    public func analyze(at url: URL) async -> Analysis {
        let identity = await AIGameDetector.shared.detect(at: url)
        return await analyze(identity: identity)
    }

    /// Map analysis to executable Winetricks steps.
    public func winetricksSteps(for analysis: Analysis) -> [String] {
        // Order matters: vcrun before d3dx, dotnet last
        let priority: [String: Int] = [
            "vcrun2022": 0, "vcrun2019": 0, "vcrun2013": 0, "vcrun2012": 0,
            "d3dcompiler_47": 1, "d3dx9": 1, "d3dx10": 1, "d3dx11": 1,
            "xinput": 2, "xact": 2, "mf": 2, "quartz": 2,
            "dotnet48": 99
        ]
        return analysis.requiredVerbs.sorted {
            let a = priority[$0] ?? 50
            let b = priority[$1] ?? 50
            if a != b { return a < b }
            return $0 < $1
        }
    }

    // MARK: - Remote mapping

    private func analysisFromRemote(_ entry: AICompatibilityService.CompatibilityEntry, identity: AIGameDetector.GameIdentity) -> Analysis {
        var dllOverrides: [String: String] = [:]
        for dll in entry.requiredDLLs where dll.lowercased().hasPrefix("d3d") {
            dllOverrides[dll.lowercased().replacingOccurrences(of: ".dll", with: "")] = "native,builtin"
        }
        return Analysis(
            identity: identity,
            requiredDLLs: entry.requiredDLLs,
            requiredVerbs: entry.requiredVerbs,
            optionalVerbs: entry.optionalVerbs ?? [],
            frameworks: entry.frameworks ?? [],
            dllOverrides: dllOverrides,
            notes: entry.notes.map { [$0] } ?? [],
            confidence: .high
        )
    }

    private func confidenceFor(identity: AIGameDetector.GameIdentity, hasRemote: Bool) -> Analysis.Confidence {
        if hasRemote { return .high }
        switch identity.confidence {
        case .high: return .high
        case .medium: return .medium
        case .low, .unknown: return .low
        }
    }
}
