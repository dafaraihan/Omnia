import SwiftUI

struct SettingsView: View {
    @Environment(OmniaStore.self) private var store
    @Environment(OmniaAccount.self) private var account
    @Environment(SettingsPreferencesStore.self) private var settings
    @State private var searchText = ""

    var body: some View {
        settingsContent {
            VStack(alignment: .leading, spacing: 12) {
                #if os(macOS)
                Text("Settings")
                    .font(.title)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 20)
                #endif

                Form {
                    ForEach(SettingsRoute.filteredRootGroups(query: searchText)) { group in
                        Section(group.section.title) {
                            ForEach(group.routes, id: \.self) { route in
                                NavigationLink(value: route) {
                                    SettingsRouteLabel(route: route, summary: summary(for: route))
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .searchable(text: $searchText, prompt: "Search Settings")
        .navigationDestination(for: SettingsRoute.self) { route in
            destination(for: route)
        }
    }

    @ViewBuilder
    private func destination(for route: SettingsRoute) -> some View {
        settingsContent {
            switch route {
            case .account:
                AccountSettingsView()
            case .addons:
                AddonsSettingsView()
            case .catalogs:
                CatalogsSettingsView()
            case .metadata:
                MetadataSettingsView()
            case .progress:
                ProgressSettingsView()
            case .upcoming:
                UpcomingSettingsView()
            case .videoPlayer:
                VideoPlayerSettingsView()
            case .subtitle:
                SubtitleAppearanceSettingsView()
            case .playbackResolver:
                PlaybackResolverSettingsView()
            case .appearance:
                AppearanceSettingsView()
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
            case let .aboutSection(section):
                AboutSectionSettingsView(section: section)
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
            return account.user?.provider?.capitalized ?? (account.user == nil ? "Not signed in" : "Signed in")
        case .addons:
            let count = store.installedAddons.filter(\.isEnabled).count
            return count == 0 ? "No sources enabled" : "\(count) enabled"
        case .catalogs:
            return "Built-in and add-on catalogs"
        case .metadata:
            return "Providers and fallback order"
        case .progress:
            return "Stored only on this device"
        case .upcoming:
            return settings.preferences.showUpcoming ? "Shown on Home" : "Hidden from Home"
        case .videoPlayer:
            return "Always plays inside Omnia"
        case .subtitle:
            return "Language and appearance"
        case .appearance:
            return store.appearance.title
        case .about:
            return "Resources, attributions, and licenses"
        case .playbackResolver, .metadataProvider, .aboutSection:
            return nil
        }
    }
}

private struct SettingsRouteLabel: View {
    let route: SettingsRoute
    let summary: String?

    var body: some View {
        HStack {
            Label(route.title, systemImage: route.systemImage)
            Spacer(minLength: 12)
            if let summary {
                Text(summary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
        }
    }
}
