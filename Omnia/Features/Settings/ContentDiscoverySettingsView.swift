import SwiftUI

/// Settings › Content & Discovery, as in Nuvio: Recent Searches, then where
/// titles and streams come from.
struct ContentDiscoverySettingsView: View {
    @Environment(OmniaStore.self) private var store
    @Environment(PluginStore.self) private var plugins
    @State private var history = SearchHistoryStore.shared
    @State private var servers = MediaServerStore.shared
    @State private var live = LiveTVStore.shared

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
                .toggleStyle(.switch)
                if history.isEnabled, !history.recentSearches.isEmpty {
                    Button("Clear Recent Searches", role: .destructive) { history.clear() }
                }
            } header: {
                Text("Search")
            }

            Section {
                SettingsRouteLink(route: .addons, summary: addonsSummary)
                SettingsRouteLink(route: .mediaServers, summary: serversSummary)
                SettingsRouteLink(route: .liveTV, summary: liveTVSummary)
                SettingsRouteLink(route: .plugins, summary: pluginsSummary)
            } header: {
                Text("Sources")
            } footer: {
                Text("Add-ons provide catalogs, titles and streams. Media servers add your Jellyfin or Emby library. Live TV adds channels from M3U playlists, Xtream and Stalker portals. Plugins add more stream sources.")
            }
        }
        .omniaNavigationTitle("Content & Discovery")
    }

    private var addonsSummary: String {
        if store.installedAddonsAreLoading { return "Loading…" }
        let count = store.installedAddons.filter(\.isEnabled).count
        return count == 0 ? "No sources enabled" : "\(count) enabled"
    }

    private var serversSummary: String {
        let count = servers.connections.count
        return count == 0 ? "No servers" : count == 1 ? "1 server" : "\(count) servers"
    }

    private var liveTVSummary: String {
        let count = live.configuration.playlists.count
            + (live.xtreamAccount == nil ? 0 : 1)
            + (live.stalkerAccount == nil ? 0 : 1)
        return count == 0 ? "Not set up" : count == 1 ? "1 source" : "\(count) sources"
    }

    private var pluginsSummary: String {
        if plugins.repositories.isEmpty { return "No repositories" }
        guard plugins.pluginsEnabled else { return "Turned off" }
        let count = plugins.enabledScraperCount
        return count == 1 ? "1 plugin on" : "\(count) plugins on"
    }
}
