//
//  GIACKWineDownloadView.swift
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

struct GIACKWineDownloadView: View {
    @State private var fractionProgress: Double = 0
    @State private var completedBytes: Int64 = 0
    @State private var totalBytes: Int64 = 0
    @State private var downloadSpeed: Double = 0
    @State private var downloadError: String?
    @State private var downloadTask: URLSessionDownloadTask?
    @State private var observation: NSKeyValueObservation?
    @State private var startTime: Date?
    @State private var releaseLabel: String = "Resolving latest runtime package..."
    @State private var resolvedDownloadURL: URL?
    @Binding var tarLocation: URL
    @Binding var runtimeVersion: SemanticVersion?
    @Binding var runtimeSource: String
    @Binding var runtimeReleaseName: String?
    @Binding var path: [SetupStage]
    var body: some View {
        VStack {
            VStack {
                Text(
                    String(
                        localized: "setup.whiskygptk.runtime.download",
                        defaultValue: "Download Runtime"
                    )
                )
                    .font(.title)
                    .fontWeight(.bold)
                Text(
                    String(
                        localized: "setup.whiskygptk.runtime.download.subtitle",
                        defaultValue: "Fetching the latest maintained GPTK runtime package."
                    )
                )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(releaseLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let downloadError {
                    Text(downloadError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
                VStack {
                    ProgressView(value: fractionProgress, total: 1)
                    HStack {
                        HStack {
                            Text(String(format: String(localized: "setup.whiskywine.progress"),
                                        formatBytes(bytes: completedBytes),
                                        formatBytes(bytes: totalBytes)))
                            + Text(String(" "))
                            + (shouldShowEstimate() ?
                               Text(String(format: String(localized: "setup.whiskywine.eta"),
                                           formatRemainingTime(remainingBytes: totalBytes - completedBytes)))
                               : Text(String()))
                            Spacer()
                        }
                        .font(.subheadline)
                        .monospacedDigit()
                    }
                }
                .padding(.horizontal)
                if downloadError != nil {
                    Button(String(localized: "button.retry", defaultValue: "Retry")) {
                        guard let resolvedDownloadURL else { return }
                        downloadError = nil
                        fractionProgress = 0
                        completedBytes = 0
                        totalBytes = 0
                        downloadSpeed = 0
                        startDownload(from: resolvedDownloadURL)
                    }
                }
                Spacer()
            }
            Spacer()
        }
        .frame(width: 400, height: 200)
        .onAppear {
            Task {
                let package = await GIACKWineInstaller.latestRuntimePackage()
                runtimeVersion = package?.version
                runtimeSource = package?.source ?? "Legacy Runtime Feed"
                runtimeReleaseName = package?.releaseName
                releaseLabel = package.map { "\($0.releaseName) via \($0.source)" } ?? "Using legacy runtime source"

                let downloadURL = package?.downloadURL ?? GIACKWineInstaller.legacyRuntimeDownloadURL()
                resolvedDownloadURL = downloadURL
                startDownload(from: downloadURL)
            }
        }
        .onDisappear {
            observation?.invalidate()
            downloadTask?.cancel()
        }
    }

    private func startDownload(from url: URL) {
        if url.isFileURL {
            tarLocation = url
            proceed()
            return
        }

        observation?.invalidate()
        downloadTask?.cancel()
        downloadTask = URLSession(configuration: .ephemeral).downloadTask(with: url) { url, _, _ in
            Task.detached {
                await MainActor.run {
                    if let url = url {
                        tarLocation = url
                        proceed()
                    } else {
                        downloadError = String(localized: "setup.whiskywine.download.error",
                                               defaultValue: "Runtime download failed.")
                    }
                }
            }
        }
        observation = downloadTask?.observe(\.countOfBytesReceived) { task, _ in
            Task {
                await MainActor.run {
                    let currentTime = Date()
                    let elapsedTime = currentTime.timeIntervalSince(startTime ?? currentTime)
                    if completedBytes > 0 {
                        downloadSpeed = Double(completedBytes) / elapsedTime
                    }
                    totalBytes = task.countOfBytesExpectedToReceive
                    completedBytes = task.countOfBytesReceived
                    fractionProgress = totalBytes > 0 ? Double(completedBytes) / Double(totalBytes) : 0
                }
            }
        }
        startTime = Date()
        downloadTask?.resume()
    }

    func formatBytes(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.zeroPadsFractionDigits = true
        return formatter.string(fromByteCount: bytes)
    }

    func shouldShowEstimate() -> Bool {
        let elapsedTime = Date().timeIntervalSince(startTime ?? Date())
        return Int(elapsedTime.rounded()) > 5 && completedBytes != 0
    }

    func formatRemainingTime(remainingBytes: Int64) -> String {
        let remainingTimeInSeconds = Double(remainingBytes) / downloadSpeed

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        if shouldShowEstimate() {
            return formatter.string(from: TimeInterval(remainingTimeInSeconds)) ?? ""
        } else {
            return ""
        }
    }

    func proceed() {
        path.append(.giackWineInstall)
    }
}
