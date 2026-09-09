import SwiftUI

struct SettingsView: View {
    @Environment(OmniaStore.self) private var store
    @Environment(OmniaAccount.self) private var account
    @Environment(SettingsPreferencesStore.self) private var settings
    @State private var searchText = ""
    #if os(macOS)
    @State private var hoveredRoute: SettingsRoute?
    #endif

    var body: some View {
        settingsContent {
            VStack(alignment: .leading, spacing: 12) {
                OmniaSettingsForm {
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
        .omniaNavigationTitle("Settings", screen: .settings)
        #if os(macOS)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search Settings")
        #else
        .searchable(text: $searchText, prompt: "Search Settings")
        #endif
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
            if store.installedAddonsAreLoading {
                return "Loading…"
            }
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

struct SettingsDestinationView: View {
    let route: SettingsRoute

    var body: some View {
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
