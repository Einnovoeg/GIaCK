//
//  SetupView.swift
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
import SemanticVersion

enum SetupStage {
    case rosetta
    case whiskyWineDownload
    case whiskyWineInstall
}

struct SetupView: View {
    @AppStorage("useGlassUI") private var useGlassUI = false
    @State private var path: [SetupStage] = []
    @State var tarLocation: URL = URL(fileURLWithPath: "")
    @State private var runtimeVersion: SemanticVersion?
    @State private var runtimeSource: String = "Unknown"
    @State private var runtimeReleaseName: String?
    @Binding var showSetup: Bool
    var firstTime: Bool = true

    var body: some View {
        ZStack {
            NavigationStack(path: $path) {
                WelcomeView(path: $path, showSetup: $showSetup, firstTime: firstTime)
                    .navigationBarBackButtonHidden(true)
                    .navigationDestination(for: SetupStage.self) { stage in
                        switch stage {
                        case .rosetta:
                            RosettaView(path: $path, showSetup: $showSetup)
                        case .whiskyWineDownload:
                            GIACKWineDownloadView(
                                tarLocation: $tarLocation,
                                runtimeVersion: $runtimeVersion,
                                runtimeSource: $runtimeSource,
                                runtimeReleaseName: $runtimeReleaseName,
                                path: $path
                            )
                        case .whiskyWineInstall:
                            GIACKWineInstallView(
                                tarLocation: $tarLocation,
                                runtimeVersion: $runtimeVersion,
                                runtimeSource: $runtimeSource,
                                runtimeReleaseName: $runtimeReleaseName,
                                path: $path,
                                showSetup: $showSetup
                            )
                        }
                    }
            }
            .frame(width: useGlassUI ? 440 : nil, height: useGlassUI ? 280 : nil)
            .whiskyGlassCard(cornerRadius: 24)
        }
        .padding(useGlassUI ? 20 : 8)
        .whiskyWindowBackground()
        .interactiveDismissDisabled()
    }
}
