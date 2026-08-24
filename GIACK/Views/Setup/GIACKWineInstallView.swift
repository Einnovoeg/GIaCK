//
//  GIACKWineInstallView.swift
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
import SemanticVersion

struct GIACKWineInstallView: View {
    @State var installing: Bool = true
    @State private var installSucceeded = false
    @State private var installError: String?
    @Binding var tarLocation: URL
    @Binding var runtimeVersion: SemanticVersion?
    @Binding var runtimeSource: String
    @Binding var runtimeReleaseName: String?
    @Binding var path: [SetupStage]
    @Binding var showSetup: Bool

    var body: some View {
        VStack {
            VStack {
                Text(
                    String(
                        localized: "setup.whiskygptk.runtime.install",
                        defaultValue: "Install Runtime"
                    )
                )
                    .font(.title)
                    .fontWeight(.bold)
                Text(
                    String(
                        localized: "setup.whiskygptk.runtime.install.subtitle",
                        defaultValue: "Installing the selected GPTK runtime into Application Support."
                    )
                )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if installing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(width: 80)
                } else if installSucceeded {
                    Image(systemName: "checkmark.circle")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "xmark.octagon")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundStyle(.red)
                    if let installError {
                        Text(installError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button(String(localized: "button.retry", defaultValue: "Retry")) {
                        runInstall()
                    }
                }
                Spacer()
            }
            Spacer()
        }
        .frame(width: 400, height: 200)
        .onAppear {
            runInstall()
        }
    }

    private func runInstall() {
        installing = true
        installSucceeded = false
        installError = nil

        let archiveURL = tarLocation
        let version = runtimeVersion
        let source = runtimeSource
        let releaseName = runtimeReleaseName

        Task.detached {
            let success = GIACKWineInstaller.install(
                from: archiveURL,
                versionOverride: version,
                source: source,
                releaseName: releaseName
            )
            await MainActor.run {
                installing = false
                installSucceeded = success
                if !success {
                    installError = String(
                        localized: "setup.whiskywine.install.error",
                        defaultValue: "Runtime installation failed."
                    )
                }
            }
            guard success else { return }
            sleep(2)
            await proceed()
        }
    }

    @MainActor
    func proceed() {
        showSetup = false
    }
}
