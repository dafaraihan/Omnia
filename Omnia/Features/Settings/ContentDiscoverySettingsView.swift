import SwiftUI

/// Settings › Content & Discovery, as in Nuvio: where titles and streams
/// come from. Media servers and recent searches join it when they arrive.
struct ContentDiscoverySettingsView: View {
    @Environment(OmniaStore.self) private var store
    @Environment(PluginStore.self) private var plugins

    var body: some View {
        OmniaSettingsForm {
            Section {
                SettingsRouteLink(route: .addons, summary: addonsSummary)
                SettingsRouteLink(route: .plugins, summary: pluginsSummary)
            } header: {
                Text("Sources")
            } footer: {
                Text("Add-ons provide catalogs, titles and streams. Plugins add more stream sources.")
            }
        }
        .omniaNavigationTitle("Content & Discovery")
    }

    private var addonsSummary: String {
        if store.installedAddonsAreLoading { return "Loading…" }
        let count = store.installedAddons.filter(\.isEnabled).count
        return count == 0 ? "No sources enabled" : "\(count) enabled"
    }

    private var pluginsSummary: String {
        if plugins.repositories.isEmpty { return "No repositories" }
        guard plugins.pluginsEnabled else { return "Turned off" }
        let count = plugins.enabledScraperCount
        return count == 1 ? "1 plugin on" : "\(count) plugins on"
    }
}
