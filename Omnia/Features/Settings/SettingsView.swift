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
        OmniaSettingsForm(isRoot: true) {
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
            let matchingRows = SettingsSearchIndex.matches(searchText)
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

    private func summary(for route: SettingsRoute) -> String? {
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
        case .landscapeCards:
            return display.continueWatchingStyle.title
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
                    .omniaAccentForeground()
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

/// The top of Settings: who this is, and whether they're synced.
struct SettingsProfileCard: View {
    var avatarSize: CGFloat = 52
    @Environment(OmniaAccount.self) private var account
    @Environment(ProfileStore.self) private var profiles

    var body: some View {
        HStack(spacing: 14) {
            if let profile = profiles.activeProfile {
                ProfileAvatarView(profile: profile, size: avatarSize)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(profiles.activeProfile?.name ?? "Profile")
                    .font(avatarSize < 52 ? .headline : .title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(account.user == nil ? "Not signed in" : "Synced to your account")
                    .font(avatarSize < 52 ? .caption : .subheadline)
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
        page
    }

    private var page: some View {
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
            case .videoPlayer:
                VideoPlayerSettingsView()
            case .subtitle:
                SubtitleAppearanceSettingsView()
            case .playbackDiagnostics:
                PlaybackDiagnosticsSettingsView()
            case .playbackResolver:
                PlaybackResolverSettingsView()
            case .appearance:
                AppearanceSettingsView()
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
                LiquidGlassSettingsView()
            case .posterCards:
                PosterCardSettingsView()
            case .landscapeCards:
                LandscapeCardSettingsView()
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
                    Label {
                        Text(route.title)
                    } icon: {
                        SettingsRouteIcon(route: route)
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

private struct SettingsRouteIcon: View {
    let route: SettingsRoute

    var body: some View {
        #if os(macOS)
        MacSettingsSymbolImage(systemName: route.systemImage)
        #else
        // Plain, which a Form row would otherwise tint and enlarge.
        Image(systemName: route.systemImage)
            .symbolRenderingMode(.monochrome)
            .imageScale(.medium)
            .font(.body)
            .foregroundStyle(.primary)
        #endif
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
                SettingsRouteIcon(route: route)
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
