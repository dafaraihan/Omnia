//
//  ContinueWatching.swift
//  Omnia
//
//  Created by Dafa Raihan on 12/08/26.
//

import SwiftUI

/// Settings › Home › Continue Watching. The row on Home and Library reads
/// every value here.
struct ContinueWatchingSettingsView: View {
    @Environment(SettingsPreferencesStore.self) private var settings
    @AppStorage(HomeView.continueWatchingVisibilityKey) private var showsContinueWatching = true
    /// Read by OmniaStore when it decides a title is finished.
    @AppStorage("playback-completion-threshold") private var completionThreshold = 95

    var body: some View {
        OmniaSettingsForm {
            Section {
                Toggle("Show on Home", isOn: $showsContinueWatching)
                Picker("Card Style", selection: settings.binding(\.display.continueWatchingStyle)) {
                    ForEach(ContinueWatchingStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                Picker("Sort By", selection: settings.binding(\.display.continueWatchingSort)) {
                    ForEach(ContinueWatchingSort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                Toggle(isOn: settings.binding(\.display.continueWatchingEpisodeThumbnails)) {
                    Text("Episode Thumbnails")
                    Text("Wide cards for shows use the episode's still instead of the show's backdrop.")
                }
                .disabled(settings.preferences.display.continueWatchingStyle == .poster)
            } header: {
                Text("Row")
            } footer: {
                Text("Poster cards use the size and corners from Appearance › Poster Cards.")
            }

            Section {
                Picker("Finished At", selection: $completionThreshold) {
                    Text("80% watched").tag(80)
                    Text("90% watched").tag(90)
                    Text("95% watched").tag(95)
                }
            } header: {
                Text("Behavior")
            } footer: {
                Text("A title leaves Continue Watching once you've watched past this point. The number of items is set in Progress, and direct playback in Video Player.")
            }
        }
        .omniaNavigationTitle("Continue Watching")
    }
}
