import SwiftUI

/// Settings › Search: recent searches and the default filters.
struct ContentDiscoverySettingsView: View {
    @Environment(OmniaStore.self) private var store
    @Environment(LiveMetadataStore.self) private var metadata
    @Environment(SettingsPreferencesStore.self) private var settings
    @State private var history = SearchHistoryStore.shared
    @State private var servers = MediaServerStore.shared

    var body: some View {
        OmniaSettingsForm {
            Section {
                Toggle(isOn: $history.isEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recent Searches")
                        Text("Save recent searches and show them when the search field is empty.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .settingsRow("Recent Searches")
                .toggleStyle(.switch)
                if history.isEnabled, !history.recentSearches.isEmpty {
                    Button("Clear Recent Searches", role: .destructive) { history.clear() }
                    .settingsRow("Clear Recent Searches")
                }
            } header: {
                Text("Search")
            }

            Section {
                SettingsDropdown(
                    "Source",
                    subtitle: "One add-on shows only its own results and posters.",
                    selection: settings.binding(\.searchFilters.source),
                    sections: sourceSections
                ) { source in
                    SearchFilterChoices.sourceTitle(source, addons: store.installedAddons, metadata: metadata)
                }
                .settingsRow("Source")
                SettingsDropdown(
                    "Kind",
                    selection: settings.binding(\.searchFilters.kind),
                    options: [MediaItem.Kind?.none, .movie, .series],
                    label: SearchFilterChoices.kindTitle
                )
                .settingsRow("Kind")
                SettingsDropdown(
                    "Genre",
                    selection: settings.binding(\.searchFilters.genre),
                    options: [String?.none] + SearchFilterChoices.genres(
                        selected: settings.preferences.searchFilters.genre
                    ).map(Optional.some)
                ) { genre in
                    genre ?? "All Genres"
                }
                .settingsRow("Genre")
            } header: {
                Text("Search Filters")
            } footer: {
                Text("The Search page's Filter menu changes these too.")
            }

        }
        .omniaNavigationTitle("Search")
    }

    /// Every source, the metadata service and media servers, then each
    /// add-on with a search catalog.
    private var sourceSections: [[SearchFilterPreferences.Source]] {
        var general: [SearchFilterPreferences.Source] = [.all, .metadata]
        if !servers.connections.isEmpty { general.append(.mediaServers) }
        var addons = SearchFilterChoices.searchableAddons(store.installedAddons)
            .map { SearchFilterPreferences.Source.addon($0.id) }
        // A chosen add-on that was since removed stays listed, so the
        // dropdown can show it.
        let current = settings.preferences.searchFilters.source
        if !general.contains(current), !addons.contains(current) { addons.append(current) }
        return [general, addons]
    }
}
