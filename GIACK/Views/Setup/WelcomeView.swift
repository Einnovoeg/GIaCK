//
//  WelcomeView.swift
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

struct WelcomeView: View {
    @State var rosettaInstalled: Bool?
    @State var runtimeInstalled: Bool?
    @State var shouldCheckInstallStatus: Bool = false
    @Binding var path: [SetupStage]
    @Binding var showSetup: Bool
    var firstTime: Bool
    private var appDisplayName: String { Bundle.appDisplayName }
    private var welcomeTitle: String {
        if firstTime {
            return String(
                localized: "setup.whiskygptk.welcome",
                defaultValue: "Welcome to \(appDisplayName)"
            )
        }

        return String(
            localized: "setup.whiskygptk.dependencies",
            defaultValue: "Runtime Setup"
        )
    }
    private var welcomeSubtitle: String {
        if firstTime {
            return String(
                localized: "setup.whiskygptk.welcome.subtitle",
                defaultValue: "Install Rosetta and the GPTK runtime needed to run Windows software on macOS."
            )
        }

        return String(
            localized: "setup.whiskygptk.dependencies.subtitle",
            defaultValue: "Review and install the required runtime components for this Mac."
        )
    }

    var body: some View {
        VStack {
            VStack {
                GIACKBrandIcon(size: 72)
                    .padding(.bottom, 6)
                Text(welcomeTitle)
                    .font(.title)
                    .fontWeight(.bold)
                Text(welcomeSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            Spacer()
            Form {
                InstallStatusView(isInstalled: $rosettaInstalled,
                                  shouldCheckInstallStatus: $shouldCheckInstallStatus,
                                  dependency: .rosetta)
                InstallStatusView(isInstalled: $runtimeInstalled,
                                  shouldCheckInstallStatus: $shouldCheckInstallStatus,
                                  dependency: .runtime)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .giackGlassCard(cornerRadius: 26)
            .onAppear {
                checkInstallStatus()
            }
            .onChange(of: shouldCheckInstallStatus) {
                checkInstallStatus()
            }
            Spacer()
            HStack {
                if let rosettaInstalled = rosettaInstalled,
                   let runtimeInstalled = runtimeInstalled {
                    if !rosettaInstalled || !runtimeInstalled {
                        Button("setup.quit") {
                            exit(0)
                        }
                        .keyboardShortcut(.cancelAction)
                        .help("Close setup without installing Rosetta or the GPTK runtime.")
                    }
                    Spacer()
                    Button(rosettaInstalled && runtimeInstalled ? "setup.done" : "setup.next") {
                        if !rosettaInstalled {
                            path.append(.rosetta)
                            return
                        }

                        if !runtimeInstalled {
                            path.append(.giackWineDownload)
                            return
                        }

                        showSetup = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .help(rosettaInstalled && runtimeInstalled
                          ? "Finish setup and open the app."
                          : "Continue to the next required dependency step.")
                }
            }
        }
        .frame(width: 400, height: 200)
    }

    func checkInstallStatus() {
        rosettaInstalled = Rosetta2.isRosettaInstalled
        runtimeInstalled = GIACKWineInstaller.isGIACKWineInstalled()
    }
}

enum SetupDependency {
    case rosetta
    case runtime

    var displayName: String {
        switch self {
        case .rosetta:
            return "Rosetta"
        case .runtime:
            return "GPTK Runtime"
        }
    }

    var showsUninstall: Bool {
        self == .runtime
    }

    func uninstallIfNeeded() {
        guard self == .runtime else { return }
        GIACKWineInstaller.uninstall()
    }
}

struct InstallStatusView: View {
    @Binding var isInstalled: Bool?
    @Binding var shouldCheckInstallStatus: Bool
    let dependency: SetupDependency
    @State var text: String = String(localized: "setup.install.checking")

    var body: some View {
        HStack {
            Group {
                if let installed = isInstalled {
                    Circle()
                        .foregroundColor(installed ? .green : .red)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(width: 10)
            Text(String(format: text, dependency.displayName))
            Spacer()
            if let installed = isInstalled {
                if installed && dependency.showsUninstall {
                    Button("setup.uninstall") {
                        uninstall()
                    }
                    .help("Remove the installed GPTK runtime files from the app support directory.")
                }
            }
        }
        .onChange(of: isInstalled) {
            if let installed = isInstalled {
                if installed {
                    text = String(localized: "setup.install.installed")
                } else {
                    text = String(localized: "setup.install.notInstalled")
                }
            } else {
                text = String(localized: "setup.install.checking")
            }
        }
    }

    func uninstall() {
        dependency.uninstallIfNeeded()
        shouldCheckInstallStatus.toggle()
    }
}
