//
//  Constants.swift
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
import GIACKKit

/// Documents that are bundled with the app so users can inspect notices and
/// install guidance directly from distributed builds.
enum ProjectDocument {
    case readme
    case changelog
    case dependencies
    case notice
    case thirdPartyNotices
    case license

    fileprivate var resourceName: String {
        switch self {
        case .readme:
            "README"
        case .changelog:
            "CHANGELOG"
        case .dependencies:
            "DEPENDENCIES"
        case .notice:
            "NOTICE"
        case .thirdPartyNotices:
            "THIRD_PARTY_NOTICES"
        case .license:
            "LICENSE"
        }
    }

    fileprivate var resourceExtension: String? {
        switch self {
        case .license:
            nil
        case .readme, .changelog, .dependencies, .notice, .thirdPartyNotices:
            "md"
        }
    }
}

enum ProjectInfo {
    static let displayName = Bundle.appDisplayName
    /// Public project URLs are centralized so downstream maintainers can replace
    /// them without scattering host-specific links throughout the application.
    static let repositoryURL = URL(string: "https://github.com/Einnovoeg/GIaCK") ?? fallbackURL
    static let releasesURL = repositoryURL.appending(path: "releases")
    static let issuesURL = repositoryURL.appending(path: "issues")
    static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/Einnovoeg/GIaCK/releases/latest")
    static let applicationDatabaseURL = URL(
        string: "https://raw.githubusercontent.com/Einnovoeg/GIaCK/main/GIACK/Resources/ApplicationDatabase.json"
    )
    static let fundingURL = URL(string: "https://buymeacoffee.com/einnovoeg") ?? fallbackURL

    /// Archived upstream repository retained for source attribution and history.
    static let archivedRepositoryURL = URL(string: "https://github.com/Whisky-App/Whisky") ?? fallbackURL

    /// Maintained external runtime source used by setup and update flows.
    static let runtimeReleasesURL = URL(string: "https://github.com/Gcenx/game-porting-toolkit/releases") ?? fallbackURL

    /// GPL reference used when the bundled license file is unavailable.
    static let gplLicenseURL = URL(string: "https://www.gnu.org/licenses/gpl-3.0-standalone.html") ?? fallbackURL

    static func bundledDocumentURL(_ document: ProjectDocument) -> URL? {
        Bundle.main.url(forResource: document.resourceName, withExtension: document.resourceExtension)
    }

    static func documentURL(_ document: ProjectDocument) -> URL {
        if let bundledURL = bundledDocumentURL(document) {
            return bundledURL
        }

        switch document {
        case .license:
            return gplLicenseURL
        case .readme, .changelog, .dependencies, .notice, .thirdPartyNotices:
            return repositoryURL
        }
    }

    private static let fallbackURL = URL(fileURLWithPath: "/")
}

enum ViewWidth {
    static let small: Double = 400
    static let medium: Double = 500
    static let large: Double = 600
}
