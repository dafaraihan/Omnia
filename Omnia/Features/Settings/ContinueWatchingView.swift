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
        Group {
            OmniaSettingsForm {
            Section {
                Toggle("Show on Home", isOn: $showsContinueWatching)
                .settingsRow("Show on Home")
                SettingsDropdown(
                    "Sort By",
                    selection: settings.binding(\.display.continueWatchingSort),
                    options: Array(ContinueWatchingSort.allCases)
                ) { sort in sort.title }
                .settingsRow("Sort By")
                Toggle(isOn: settings.binding(\.display.resumePromptOnLaunch)) {
                    Text("Resume Prompt on Launch")
                    Text("When Omnia was closed during playback, offers to continue where you left off the next time it opens.")
                }
                .settingsRow("Resume Prompt on Launch")
                SettingsRouteLink(
                    route: .landscapeCards,
                    summary: settings.preferences.display.continueWatchingCard.size.title
                )
            }

            Section {
                SettingsDropdown(
                    "Artwork",
                    selection: settings.binding(\.display.continueWatchingArtwork),
                    options: Array(ContinueWatchingArtwork.allCases)
                ) { artwork in artwork.title }
                .settingsRow("Artwork")
                Toggle(isOn: settings.binding(\.display.continueWatchingEpisodeThumbnails)) {
                    Text("Episode Thumbnails")
                    Text("Cards for shows use the episode's still instead of the show's backdrop.")
                }
                .settingsRow("Episode Thumbnails")
                Toggle(isOn: settings.binding(\.display.blursNextUp)) {
                    Text("Blur Unwatched in Continue Watching")
                    Text("Blurs next-up episode stills so they don't spoil the episode.")
                }
                .settingsRow("Blur Unwatched in Continue Watching")
                .disabled(!settings.preferences.display.continueWatchingEpisodeThumbnails)
            } header: {
                Text("Cards")
            } footer: {
                Text("Paused Scene shows the frame where you stopped.")
            }
            Section {
                Toggle(isOn: settings.binding(\.display.nextUpFromFurthestEpisode)) {
                    Text("Next Up From Furthest Episode")
                    Text("After an episode ends, offers the one after the furthest episode you've watched. Turn off for rewatches to follow the episode you just finished.")
                }
                .settingsRow("Next Up From Furthest Episode")
                Toggle(isOn: settings.binding(\.display.showsUnairedNextUp)) {
                    Text("Show Unaired Next Up Episodes")
                    Text("Keeps a show in the row when its next episode hasn't aired yet.")
                }
                .settingsRow("Show Unaired Next Up Episodes")
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
                .settingsRow("Finished At")
            } header: {
                Text("Next Up")
            } footer: {
                Text("A title leaves the row once you've watched past this point.")
            }
                }
        }
        .omniaNavigationTitle("Continue Watching")
    }
}
