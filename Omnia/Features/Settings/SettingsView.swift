import SwiftUI

struct SettingsView: View {
    @Environment(OmniaStore.self) private var store
    @Environment(OmniaAccount.self) private var account
    @Environment(SettingsPreferencesStore.self) private var settings
    @Environment(PluginStore.self) private var plugins
    @Environment(ProfileStore.self) private var profiles
    @State private var searchText = ""
    #if os(macOS)
    @State private var hoveredRoute: SettingsRoute?
    #endif

    var body: some View {
        rootSettingsContent
            .omniaNavigationTitle(AppDestination.settings.title(for: profiles.activeProfile), screen: .settings)
        #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    MacSettingsToolbarSearch(text: $searchText)
                }
            }
        #else
            .searchable(text: $searchText, prompt: "Search Settings")
        #endif
    }

    private var rootSettingsContent: some View {
        settingsContent {
            OmniaSettingsForm(isRoot: true) {
                ForEach(SettingsRoute.filteredRootGroups(query: searchText)) { group in
                    Section(group.section.title) {
                        ForEach(group.routes, id: \.self) { route in
                            NavigationLink {
                                SettingsDestinationView(route: route)
                            } label: {
                                SettingsRouteLabel(route: route, summary: summary(for: route))
                            }
                            #if os(macOS)
                            .buttonStyle(MacSettingsNavigationButtonStyle(isHovered: hoveredRoute == route))
                            .focusEffectDisabled()
                            .onHover { isHovered in
                                if isHovered {
                                    hoveredRoute = route
                                } else if hoveredRoute == route {
                                    hoveredRoute = nil
                                }
                            }
                            #endif
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func settingsContent<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        #if os(macOS)
        MacSettingsContentContainer(content: content)
        #else
        content()
        #endif
    }

    private func summary(for route: SettingsRoute) -> String? {
        switch route {
        case .account:
            let count = profiles.profiles.count
            let people = count == 1 ? "1 profile" : "\(count) profiles"
            return account.user == nil ? "\(people), not signed in" : "\(people), synced to your account"
        case .contentDiscovery:
            return "Add-ons, media servers, Live TV, and plugins"
        case .addons:
            if store.installedAddonsAreLoading {
                return "Loading…"
            }
            let count = store.installedAddons.filter(\.isEnabled).count
            return count == 0 ? "No sources enabled" : "\(count) enabled"
        case .mediaServers:
            let count = MediaServerStore.shared.connections.count
            return count == 0 ? "No servers" : count == 1 ? "1 server" : "\(count) servers"
        case .liveTV:
            return LiveTVStore.shared.hasSources ? "Set up" : "Not set up"
        case .plugins:
            if plugins.repositories.isEmpty { return "No repositories" }
            guard plugins.pluginsEnabled else { return "Turned off" }
            let count = plugins.enabledScraperCount
            return count == 1 ? "1 plugin on" : "\(count) plugins on"
        case .home:
            let catalogs = AddonCatalogStore.catalogs(in: store)
            guard !catalogs.isEmpty else { return "Built-in rows" }
            let visible = catalogs.filter { store.isCatalogEnabled(for: $0.addon, catalog: $0.catalog) }.count
            return "\(visible) of \(catalogs.count) catalogs visible"
        case .catalogs:
            return "Built-in and add-on catalogs"
        case .collections:
            return "Folders of catalogs on Home"
        case .metadata:
            return "TMDB enrichment, MDBList ratings and metadata sources"
        case .progress:
            return account.storageSummary
        case .upcoming:
            return settings.preferences.showUpcoming ? "Shown on Home" : "Hidden from Home"
        case .videoPlayer:
            return "Player, subtitles, and auto-play"
        case .subtitle:
            return "Language and appearance"
        case .appearance:
            return "Home, collections, and detail pages"
        case .about:
            return "Resources, attributions, and licenses"
        case .streamSelection, .playbackResolver, .playbackDiagnostics, .metadataProvider, .aboutSection, .posterCards, .streams, .continueWatching, .detailPage,
             .tmdbEnrichment, .metadataSources, .tracker, .streamSorting:
            return nil
        }
    }
}

struct SettingsDestinationView: View {
    let route: SettingsRoute

    var body: some View {
        settingsContent {
            switch route {
            case .account:
                AccountSettingsView()
            case .contentDiscovery:
                ContentDiscoverySettingsView()
            case .addons:
                AddonsSettingsView()
            case .mediaServers:
                MediaServersSettingsView()
            case .liveTV:
                LiveTVSettingsView()
            case .plugins:
                PluginsSettingsView()
            case .home:
                HomeSettingsView()
            case .catalogs:
                CatalogsSettingsView()
            case .collections:
                CollectionsSettingsView()
            case .metadata:
                MetadataSettingsView()
            case .tmdbEnrichment:
                TMDBEnrichmentSettingsView()
            case .metadataSources:
                MetadataSourcesSettingsView()
            case .progress:
                ProgressSettingsView()
            case .upcoming:
                UpcomingSettingsView()
            case .videoPlayer:
                VideoPlayerSettingsView()
            case .streamSelection:
                StreamSelectionSettingsView()
            case .subtitle:
                SubtitleAppearanceSettingsView()
            case .playbackDiagnostics:
                PlaybackDiagnosticsSettingsView()
            case .playbackResolver:
                PlaybackResolverSettingsView()
            case .appearance:
                AppearanceSettingsView()
            case .posterCards:
                PosterCardSettingsView()
            case .streams:
                StreamsSettingsView()
            case .continueWatching:
                ContinueWatchingSettingsView()
            case .detailPage:
                DetailPageSettingsView()
            case .about:
                AboutSettingsView()
            case let .metadataProvider(id):
                if let provider = MetadataProvider.supported.first(where: { $0.id == id }) {
                    MetadataProviderDetailView(provider: provider)
                } else {
                    ContentUnavailableView(
                        "Provider Unavailable",
                        systemImage: "rectangle.3.group",
                        description: Text("This metadata provider is not supported by this version of Omnia.")
                    )
                }
            case let .tracker(kind):
                TrackerSettingsView(kind: kind)
            case .streamSorting:
                StreamSortingSettingsView()
            case let .aboutSection(section):
                AboutSectionSettingsView(section: section)
            }
        }
    }

    /// Sub-pages are native grouped Forms, which bring their own scrolling,
    /// insets and readable width, so they are not wrapped in the root's
    /// card container.
    @ViewBuilder
    private func settingsContent<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
    }
}

/// A settings row that opens another settings page, styled like the rows on
/// the Settings root. Sub-pages such as Home use it for their own links.
struct SettingsRouteLink: View {
    let route: SettingsRoute
    let summary: String?
    @Environment(\.settingsUsesNativeForm) private var usesNativeForm
    #if os(macOS)
    @State private var isHovered = false
    #endif

    var body: some View {
        if usesNativeForm {
            // Inside a grouped Form the system draws the row, its chevron and
            // its highlight, as in System Settings.
            NavigationLink {
                SettingsDestinationView(route: route)
            } label: {
                LabeledContent {
                    if let summary {
                        Text(summary)
                    }
                } label: {
                    Label(route.title, systemImage: route.systemImage)
                }
            }
        } else {
            NavigationLink {
                SettingsDestinationView(route: route)
            } label: {
                SettingsRouteLabel(route: route, summary: summary)
            }
            #if os(macOS)
            .buttonStyle(MacSettingsNavigationButtonStyle(isHovered: isHovered))
            .focusEffectDisabled()
            .onHover { isHovered = $0 }
            #endif
        }
    }
}

private struct SettingsRouteLabel: View {
    let route: SettingsRoute
    let summary: String?

    var body: some View {
        HStack {
            Label {
                Text(route.title)
                    .foregroundStyle(.primary)
            } icon: {
                #if os(macOS)
                MacSettingsSymbolImage(systemName: route.systemImage)
                #else
                Image(systemName: route.systemImage)
                #endif
            }
            Spacer(minLength: 12)
            if let summary {
                Text(summary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
            #if os(macOS)
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            #endif
        }
    }
}

#if os(macOS)
struct MacSettingsToolbarSearch: View {
    @Binding var text: String

    var body: some View {
        MacSettingsSearchField(text: $text)
            .frame(width: MacSettingsPresentation.searchWidth)
    }
}

/// AppKit's search field, for toolbars that need it beside other items
/// (SwiftUI's searchable field always sits apart at the trailing edge).
struct MacSettingsSearchField: NSViewRepresentable {
    @Binding var text: String
    var prompt = "Search Settings"

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = prompt
        searchField.sendsSearchStringImmediately = true
        searchField.delegate = context.coordinator
        return searchField
    }

    func updateNSView(_ searchField: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if searchField.stringValue != text {
            searchField.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let searchField = notification.object as? NSSearchField else { return }
            text.wrappedValue = searchField.stringValue
        }
    }
}

private struct MacSettingsNavigationButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(
                \.macSettingsSymbolTreatment,
                MacSettingsPresentation.symbolTreatment(
                    isHovered: isHovered,
                    isPressed: configuration.isPressed
                )
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            }
            .contentShape(Rectangle())
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        isPressed || isHovered ? .gray.opacity(isPressed ? 0.28 : 0.20) : .clear
    }
}
#endif
