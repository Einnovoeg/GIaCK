//
//  BottleCreationView.swift
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

struct BottleCreationView: View {
    @Binding var newlyCreatedBottleURL: URL?

    @State private var selectedPreset: BottlePreset = .windowsGame
    @State private var newBottleName = ""
    @State private var newBottleVersion: WinVersion = .win10
    @State private var newBottleRunner: BottleRunner = .wine
    @State private var newBottleURL: URL = UserDefaults.standard.url(forKey: "defaultBottleLocation")
                                           ?? BottleData.defaultBottleDir
    @State private var nameValid = false
    @State private var showsAdvancedOverrides = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Compatibility Preset") {
                    Picker("Preset", selection: $selectedPreset) {
                        ForEach(BottlePreset.allCases) { preset in
                            Label(preset.displayName, systemImage: preset.systemImage)
                                .tag(preset)
                        }
                    }
                    .help("Start from a curated compatibility profile instead of tuning every setting manually.")
                    .onChange(of: selectedPreset) { _, preset in
                        applyPreset(preset)
                    }

                    BottlePresetSummaryCard(preset: selectedPreset)
                    BottlePresetChecklistView(preset: selectedPreset)
                }

                Section("Library") {
                    TextField("create.name", text: $newBottleName)
                        .onChange(of: newBottleName) { _, name in
                            nameValid = !name.isEmpty
                        }
                        .help("Choose the library name shown in the sidebar.")

                    LabeledContent("Runner") {
                        Label(selectedPreset.runner.displayName, systemImage: selectedPreset.runner.systemImage)
                    }
                    .help("The compatibility preset chooses the runner family for this library.")

                    if selectedPreset.runner == .wine {
                        LabeledContent("Windows Version") {
                            Text(newBottleVersion.pretty())
                                .foregroundStyle(.secondary)
                        }
                        .help("This preset currently starts from the shown Windows version.")
                    }

                    ActionView(
                        text: "settings.path",
                        subtitle: newBottleURL.prettyPath(),
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
                                newBottleURL = url
                            }
                        }
                    }
                    .help("Choose where this new library should be created on disk.")
                }

                Section {
                    DisclosureGroup("Advanced Overrides", isExpanded: $showsAdvancedOverrides) {
                        if selectedPreset.runner == .wine {
                            Picker("Windows Version", selection: $newBottleVersion) {
                                ForEach(WinVersion.allCases.reversed(), id: \.self) {
                                    Text($0.pretty())
                                }
                            }
                            .help("Override the preset's starting Windows version for this bottle only.")
                        } else {
                            Text("DOS presets intentionally keep advanced tuning in the Config tab so the creation sheet stays compact.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("create.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("create.cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    .help("Close this sheet without creating a new library.")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("create.create") {
                        submit()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!nameValid)
                    .help("Create the new Wine bottle or DOSBox library using the selected preset.")
                }
            }
            .onSubmit {
                submit()
            }
            .onAppear {
                applyPreset(selectedPreset)
                nameValid = !newBottleName.isEmpty
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: ViewWidth.small)
    }

    private func applyPreset(_ preset: BottlePreset) {
        var stagedSettings = BottleSettings()
        stagedSettings.apply(preset: preset)
        newBottleRunner = preset.runner
        if preset.runner == .wine {
            newBottleVersion = stagedSettings.windowsVersion
        }
    }

    private func submit() {
        newlyCreatedBottleURL = BottleVM.shared.createNewBottle(
            bottleName: newBottleName,
            winVersion: newBottleVersion,
            runner: newBottleRunner,
            bottleURL: newBottleURL,
            preset: selectedPreset
        )
        dismiss()
    }
}

struct BottlePresetSummaryCard: View {
    let preset: BottlePreset

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: preset.systemImage)
                    .foregroundStyle(preset.runner == .wine ? .orange : .green)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.summary)
                        .font(.subheadline)
                    Text(preset.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let recommendedRuntimeSummary = preset.recommendedRuntimeSummary {
                        Text(recommendedRuntimeSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct BottlePresetChecklistView: View {
    let preset: BottlePreset

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(preset.checklist.enumerated()), id: \.offset) { _, step in
                Label(step, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 4)
    }
}

#Preview {
    BottleCreationView(newlyCreatedBottleURL: .constant(nil))
}
