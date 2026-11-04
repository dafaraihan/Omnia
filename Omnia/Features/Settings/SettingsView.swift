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
        SettingsLockGate { unlockedSettings }
    }

    private var unlockedSettings: some View {
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
                if OmniaDevice.isPhone, searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section {
                        NavigationLink {
                            SettingsDestinationView(route: .account)
                        } label: {
                            SettingsProfileCard()
                        }
                        #if os(macOS)
                        .buttonStyle(MacSettingsNavigationButtonStyle(isHovered: hoveredRoute == .account))
                        .focusEffectDisabled()
                        .onHover { isHovered in
                            hoveredRoute = isHovered ? .account : (hoveredRoute == .account ? nil : hoveredRoute)
                        }
                        #endif
                    }
                }
                let matchingRows = OmniaDevice.isPhone ? SettingsSearchIndex.matches(searchText) : []
                if !matchingRows.isEmpty {
                    Section("Options") {
                        ForEach(matchingRows.prefix(40)) { row in
                            NavigationLink {
                                SettingsDestinationView(route: row.route)
                                    .environment(\.settingsFocusRow, row.title)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title)
                                        .foregroundStyle(.primary)
                                    Text(row.route.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .settingsLinkRow()
                        }
                    }
                }
                ForEach(SettingsRoute.filteredRootGroups(query: searchText)) { group in
                    Section(group.section.title) {
                        ForEach(group.routes, id: \.self) { route in
                            NavigationLink {
                                SettingsDestinationView(route: route)
                            } label: {
                                SettingsRouteLabel(route: route)
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
}

/// What a page is set to, beside its name.
struct SettingsRouteSummary: View {
    let route: SettingsRoute
    @Environment(OmniaStore.self) private var store
    @Environment(OmniaAccount.self) private var account
    @Environment(SettingsPreferencesStore.self) private var settings
    @Environment(PluginStore.self) private var plugins
    @Environment(ProfileStore.self) private var profiles

    var body: some View {
        if let text = summary(for: route) {
            Text(text)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func largeScreenSummary(for route: SettingsRoute) -> String? {
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
            return "API keys, TMDB enrichment, MDBList ratings and metadata sources"
        case .progress:
            return account.storageSummary
        case .upcoming:
            return settings.preferences.showUpcoming ? "Shown on Home" : "Hidden from Home"
        case .videoPlayer:
            return "Player, subtitles, and auto-play"
        case .subtitle:
            return "Controls, menus and subtitles"
        case .appearance:
            return "Home, collections, and detail pages"
        case .about:
            return "Resources, attributions, and licenses"
        default:
            return nil
        }
    }

    private func summary(for route: SettingsRoute) -> String? {
        guard OmniaDevice.isPhone else { return largeScreenSummary(for: route) }
        let display = settings.preferences.display
        switch route {
        case .appearance:
            return store.appearance.title
        case .navigation:
            return settings.preferences.navigationStyle == .topBar ? display.topBarStyle.title : "Sidebar"
        case .home:
            let catalogs = AddonCatalogStore.catalogs(in: store)
            guard !catalogs.isEmpty else { return "Built-in rows" }
            let visible = catalogs.filter { store.isCatalogEnabled(for: $0.addon, catalog: $0.catalog) }.count
            return "\(visible) of \(catalogs.count) catalogs"
        case .posterCards:
            return display.posterWidth.title
        case .detailPage:
            return display.detailBackground.title
        case .videoPlayer:
            return settings.preferences.autoplayNextEpisode ? "Autoplay on" : "Autoplay off"
        case .streams:
            return settings.preferences.playbackBehavior.autoSelectionMode.title
        case .playerControls:
            return display.playerSize == PlayerSizePreferences() ? "Default size" : "Custom size"
        case .subtitle:
            return settings.preferences.subtitlesEnabled ? "On" : "Off"
        case .addons:
            if store.installedAddonsAreLoading { return "Loading…" }
            let count = store.installedAddons.filter(\.isEnabled).count
            return count == 0 ? "None enabled" : "\(count) enabled"
        case .plugins:
            if plugins.repositories.isEmpty { return "None" }
            guard plugins.pluginsEnabled else { return "Off" }
            return "\(plugins.enabledScraperCount) on"
        case .mediaServers:
            let count = MediaServerStore.shared.connections.count
            return count == 0 ? "None" : count == 1 ? "1 server" : "\(count) servers"
        case .liveTV:
            return LiveTVStore.shared.hasSources ? "Set up" : "Not set up"
        case .notifications:
            return display.episodeNotifications ? "On" : "Off"
        case .privacy:
            let locked = DeviceLock.shared.locksSettings || DeviceLock.shared.locksProfiles
            return locked ? "App Lock on" : "App Lock off"
        case .battery:
            return display.lowPowerMode.title
        case .progress:
            return account.storageSummary
        default:
            return nil
        }
    }
}

/// Face ID, Touch ID or the passcode in front of Settings, when turned on.
struct SettingsLockGate<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if DeviceLock.shared.locksSettings, !DeviceLock.shared.isSettingsUnlocked {
                ContentUnavailableView {
                    Label("Settings Are Locked", systemImage: "lock.fill")
                } actions: {
                    Button("Unlock with \(DeviceLock.shared.methodName)") {
                        Task { await DeviceLock.shared.unlockSettings() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .task { await DeviceLock.shared.unlockSettings() }
            } else {
                content()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { DeviceLock.shared.relock() }
        }
    }
}

/// A page's coloured icon.
struct SettingsIconTile: View {
    let route: SettingsRoute

    var body: some View {
        Image(systemName: route.systemImage)
            .font(.system(size: 14, weight: .medium))
            .symbolVariant(.fill)
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(route.tileColor, in: .rect(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}

extension SettingsRoute {
    var tileColor: Color {
        switch self {
        case .account: .blue
        case .appearance, .liquidGlass: .indigo
        case .navigation: .blue
        case .home, .catalogs, .collections, .continueWatching, .upcoming: .orange
        case .posterCards: .pink
        case .detailPage: .purple
        case .videoPlayer: .red
        case .streams: .teal
        case .playerControls: .mint
        case .subtitle: .cyan
        case .addons, .plugins: .green
        case .mediaServers, .liveTV: .brown
        case .metadata, .metadataProvider, .metadataSources, .tmdbEnrichment, .tvdbEnrichment, .animeEnrichment: .gray
        case .contentDiscovery: .blue
        case .tracking: .red
        case .notifications: .red
        case .privacy: .blue
        case .battery: .green
        case .progress: .gray
        case .about, .aboutSection: .gray
        case .playbackResolver, .playbackDiagnostics, .streamSelection: .gray
        }
    }
}

/// The top of Settings: who this is, and whether they're synced.
struct SettingsProfileCard: View {
    @Environment(OmniaAccount.self) private var account
    @Environment(ProfileStore.self) private var profiles

    var body: some View {
        HStack(spacing: 14) {
            if let profile = profiles.activeProfile {
                ProfileAvatarView(profile: profile, size: 52)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(profiles.activeProfile?.name ?? "Profile")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(account.user == nil ? "Not signed in" : "Synced to your account")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
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
                if OmniaDevice.isPhone { ContentDiscoverySettingsView() } else { LegacyContentDiscoverySettingsView() }
            case .addons:
                AddonsSettingsView()
            case .mediaServers:
                MediaServersSettingsView()
            case .liveTV:
                LiveTVSettingsView()
            case .plugins:
                PluginsSettingsView()
            case .home:
                if OmniaDevice.isPhone { HomeSettingsView() } else { LegacyHomeSettingsView() }
            case .catalogs:
                CatalogsSettingsView()
            case .collections:
                CollectionsSettingsView()
            case .metadata:
                MetadataSettingsView()
            case .tvdbEnrichment:
                TVDBEnrichmentSettingsView()
            case .tmdbEnrichment:
                TMDBEnrichmentSettingsView()
            case .animeEnrichment:
                AnimeEnrichmentSettingsView()
            case .metadataSources:
                MetadataSourcesSettingsView()
            case .progress:
                ProgressSettingsView()
            case .upcoming:
                if OmniaDevice.isPhone { UpcomingSettingsView() } else { LegacyUpcomingSettingsView() }
            case .videoPlayer:
                if OmniaDevice.isPhone { VideoPlayerSettingsView() } else { LegacyVideoPlayerSettingsView() }
            case .subtitle:
                if OmniaDevice.isPhone { SubtitleAppearanceSettingsView() } else { LegacySubtitleAppearanceSettingsView() }
            case .playbackDiagnostics:
                PlaybackDiagnosticsSettingsView()
            case .playbackResolver:
                PlaybackResolverSettingsView()
            case .appearance:
                if OmniaDevice.isPhone { AppearanceSettingsView() } else { LegacyAppearanceSettingsView() }
            case .streamSelection:
                LegacyStreamSelectionSettingsView()
            case .navigation:
                NavigationSettingsView()
            case .playerControls:
                PlayerControlsSettingsView()
            case .notifications:
                NotificationsSettingsView()
            case .privacy:
                PrivacySecuritySettingsView()
            case .battery:
                BatteryPerformanceSettingsView()
            case .liquidGlass:
                if OmniaDevice.isPhone { LiquidGlassSettingsView() } else { LegacyLiquidGlassSettingsView() }
            case .posterCards:
                if OmniaDevice.isPhone { PosterCardSettingsView() } else { LegacyPosterCardSettingsView() }
            case .streams:
                if OmniaDevice.isPhone { StreamsSettingsView() } else { LegacyStreamsSettingsView() }
            case .continueWatching:
                if OmniaDevice.isPhone { ContinueWatchingSettingsView() } else { LegacyContinueWatchingSettingsView() }
            case .detailPage:
                if OmniaDevice.isPhone { DetailPageSettingsView() } else { LegacyDetailPageSettingsView() }
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
            case .tracking:
                TrackingSettingsView()
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
                    if OmniaDevice.isPhone {
                        Label {
                            Text(route.title)
                        } icon: {
                            SettingsIconTile(route: route)
                        }
                    } else {
                        Label(route.title, systemImage: route.systemImage)
                    }
                }
            }
        } else {
            NavigationLink {
                SettingsDestinationView(route: route)
            } label: {
                SettingsRouteLabel(route: route, explicitSummary: summary)
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
    /// Nil shows what the page is set to.
    var explicitSummary: String?

    var body: some View {
        HStack {
            Label {
                Text(route.title)
                    .foregroundStyle(.primary)
            } icon: {
                if OmniaDevice.isPhone {
                    SettingsIconTile(route: route)
                } else {
                    #if os(macOS)
                    MacSettingsSymbolImage(systemName: route.systemImage)
                    #else
                    Image(systemName: route.systemImage)
                    #endif
                }
            }
            Spacer(minLength: 12)
            if let explicitSummary {
                Text(explicitSummary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            } else {
                SettingsRouteSummary(route: route)
            }
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
