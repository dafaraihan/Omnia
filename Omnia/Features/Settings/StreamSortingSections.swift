//
//  StreamSortingSections.swift
//  Omnia
//

import SwiftUI

/// The sorting and filter sections of Settings › Playback › Stream
/// Selection, after Nuvio's Debrid › Stream sorting and filters (Dafa,
/// 2026-10-27). The order set here is the order sources are listed, the
/// first one auto-play picks, and the order failed sources are replaced in.
struct StreamSortingSections: View {
    @Environment(SettingsPreferencesStore.self) private var settings

    private var sorting: StreamSortPreferences { settings.preferences.playbackBehavior.streamSorting }

    var body: some View {
        Group {
            Section {
                SettingsDropdown(
                    "Minimum Resolution",
                    selection: settings.binding(\.playbackBehavior.streamSorting.minimumResolution),
                    options: StreamSortPreferences.minimumResolutionOptions
                ) { value in value == 0 ? "Any" : "\(value)p" }
                .settingsRow("Minimum Resolution")
                Toggle(isOn: settings.binding(\.playbackBehavior.streamSorting.cachedFirst)) {
                    Text("Ready Debrid Links First")
                    Text("Sources your debrid service already has (⚡, [RD+]) before ones it would still have to download (⏳).")
                }
                .settingsRow("Ready Debrid Links First")
            }

            Section {
                Picker(selection: settings.binding(\.playbackBehavior.streamSorting.profile)) {
                    ForEach(StreamSortProfile.allCases) { profile in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.title)
                            Text(profile.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(profile)
                    }
                } label: {
                    Text("Sort Sources By")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Picking a Source")
            } footer: {
                Text("Sorting reads each source's name, such as 2160p, REMUX, HDR, DV, Atmos, HEVC and its size. Equal sources keep their add-on's order.")
            }
            Section {
                SettingsDropdown(
                    "HDR",
                    selection: settings.binding(\.playbackBehavior.streamSorting.hdr),
                    options: StreamFeatureFilter.allCases
                ) { $0.title }
                .settingsRow("HDR")
                SettingsDropdown(
                    "Dolby Vision",
                    selection: settings.binding(\.playbackBehavior.streamSorting.dolbyVision),
                    options: StreamFeatureFilter.allCases
                ) { $0.title }
                .settingsRow("Dolby Vision")
                SettingsDropdown(
                    "Video Codec",
                    selection: settings.binding(\.playbackBehavior.streamSorting.codec),
                    options: StreamCodecFilter.allCases
                ) { $0.title }
                .settingsRow("Video Codec")
            } header: {
                Text("Filters")
            } footer: {
                Text("Hidden sources don't appear in the list or play automatically. Sources that don't say their resolution are never hidden by the minimum.")
            }

            if sorting != StreamSortPreferences() {
                Section {
                    Button("Restore Sorting Defaults", systemImage: "arrow.counterclockwise") {
                        settings.update { $0.playbackBehavior.streamSorting = StreamSortPreferences() }
                    }
                }
            }
        }
    }
}
