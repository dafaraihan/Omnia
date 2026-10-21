//
//  ContinueWatching.swift
//  Omnia
//
//  Created by Dafa Raihan on 12/08/26.
//

import SwiftUI

/// Settings › Layout › Continue Watching. The row on Home and Library reads
/// every value here.
struct ContinueWatchingSettingsView: View {
    @Environment(SettingsPreferencesStore.self) private var settings
    @AppStorage(HomeView.continueWatchingVisibilityKey) private var showsContinueWatching = true
    /// Read by OmniaStore when it decides a title is finished.
    @AppStorage("playback-completion-threshold") private var completionThreshold = 95

    var body: some View {
        OmniaSettingsForm {
            Section {
                SettingsStyleTilePicker(
                    options: ContinueWatchingStyle.allCases,
                    selection: settings.binding(\.display.continueWatchingStyle),
                    title: \.title,
                    detail: \.detail
                ) { style in
                    ContinueWatchingStylePreview(style: style)
                }
            } header: {
                Text("Card Style")
            }

            Section {
                Toggle("Show on Home", isOn: $showsContinueWatching)
                SettingsDropdown(
                    "Sort By",
                    selection: settings.binding(\.display.continueWatchingSort),
                    options: Array(ContinueWatchingSort.allCases)
                ) { sort in sort.title }
                Toggle(isOn: settings.binding(\.display.continueWatchingEpisodeThumbnails)) {
                    Text("Episode Thumbnails")
                    Text("Wide cards for shows use the episode's still instead of the show's backdrop.")
                }
                .disabled(settings.preferences.display.continueWatchingStyle == .poster)
            } header: {
                Text("Row")
            } footer: {
                Text("Poster cards use the size and corners from Layout › Poster Card Style.")
            }

            Section {
                SettingsDropdown(
                    "Finished At",
                    selection: $completionThreshold,
                    options: [80, 90, 95]
                ) { value in
                    switch value {
                    case 80: "80% watched"
                    case 90: "90% watched"
                    case 95: "95% watched"
                    default: "\(value)"
                    }
                }
            } header: {
                Text("Behavior")
            } footer: {
                Text("A title leaves Continue Watching once you've watched past this point. Direct playback is set in Playback.")
            }

            Section {
                SettingsRouteLink(route: .progress, summary: "Stored only on this device")
            } header: {
                Text("Progress")
            } footer: {
                Text("How many items the row holds, backups of your progress and watchlist, and clearing them.")
            }
        }
        .omniaNavigationTitle("Continue Watching")
    }
}
