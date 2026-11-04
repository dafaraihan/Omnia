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
    @Environment(OmniaAccount.self) private var account
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
                ContinueWatchingLivePreview(style: settings.preferences.display.continueWatchingStyle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                if settings.preferences.display.continueWatchingStyle != .card {
                    Toggle(isOn: settings.binding(\.display.continueWatchingShowsLabels)) {
                        Text("Show Labels")
                        Text("The title and details under each card.")
                    }
                    .settingsRow("Show Labels")
                }
                SettingsDropdown(
                    "Size",
                    selection: settings.binding(\.display.continueWatchingCard.size),
                    options: Array(ContinueWatchingCardPreferences.Size.allCases)
                ) { $0.title }
                .settingsRow("Size")
                SettingsDropdown(
                    "Corners",
                    selection: settings.binding(\.display.continueWatchingCard.corners),
                    options: Array(ContinueWatchingCardPreferences.Corners.allCases)
                ) { $0.title }
                .settingsRow("Corners")
            } header: {
                Text("Card Style")
            }

            Section {
                Toggle("Show on Home", isOn: $showsContinueWatching)
                .settingsRow("Show on Home")
                SettingsDropdown(
                    "Sort By",
                    selection: settings.binding(\.display.continueWatchingSort),
                    options: Array(ContinueWatchingSort.allCases)
                ) { sort in sort.title }
                .settingsRow("Sort By")
                SettingsDropdown(
                    "Artwork",
                    selection: settings.binding(\.display.continueWatchingArtwork),
                    options: Array(ContinueWatchingArtwork.allCases)
                ) { artwork in artwork.title }
                .settingsRow("Artwork")
                Toggle(isOn: settings.binding(\.display.continueWatchingEpisodeThumbnails)) {
                    Text("Episode Thumbnails")
                    Text("Wide cards for shows use the episode's still instead of the show's backdrop.")
                }
                .settingsRow("Episode Thumbnails")
                .disabled(settings.preferences.display.continueWatchingStyle == .poster)
            } header: {
                Text("Row")
            } footer: {
                Text("Paused Scene shows the frame where you stopped, saved when you close the player; titles you haven't played since use their artwork. Style Default keeps each layout’s original size and corners. Poster Card Style can apply its own to these with one button.")
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
                Toggle(isOn: settings.binding(\.display.blursNextUp)) {
                    Text("Blur Unwatched in Continue Watching")
                    Text("Blurs next-up episode stills so they don't spoil the episode.")
                }
                .settingsRow("Blur Unwatched in Continue Watching")
                .disabled(!settings.preferences.display.continueWatchingEpisodeThumbnails
                    || settings.preferences.display.continueWatchingStyle == .poster)
            } header: {
                Text("Next Up Behavior")
            }

            Section {
                Toggle(isOn: settings.binding(\.display.resumePromptOnLaunch)) {
                    Text("Resume Prompt on Launch")
                    Text("When Omnia was closed during playback, offers to continue where you left off the next time it opens.")
                }
                .settingsRow("Resume Prompt on Launch")
            } header: {
                Text("On Launch")
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
                .settingsRow("Finished At")
            } header: {
                Text("Behavior")
            } footer: {
                Text("A title leaves Continue Watching once you've watched past this point. Direct playback is set in Playback.")
            }

            Section {
                SettingsRouteLink(route: .progress, summary: account.storageSummary)
            } header: {
                Text("Progress")
            } footer: {
                Text("How many items the row holds, backups of your progress and watchlist, and clearing them.")
            }
        }
        .omniaNavigationTitle("Continue Watching")
    }
}
