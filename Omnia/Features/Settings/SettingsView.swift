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
        rootSettingsContent
            .omniaNavigationTitle("Settings", screen: .settings)
        #if os(macOS)
            .searchable(text: $searchText, placement: MacSettingsPresentation.searchPlacement(for: settings.preferences.navigationStyle), prompt: "Search Settings")

            .background {
                MacSettingsSearchToolbarWidthLimiter(
                    maximumWidth: MacSettingsPresentation.searchWidth(
                        proposedWidth: .greatestFiniteMagnitude
                    )
                )
            }
        #else
            .searchable(text: $searchText, prompt: "Search Settings")
        #endif
    }

    private var rootSettingsContent: some View {
        settingsContent {
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
private struct MacSettingsSearchToolbarWidthLimiter: NSViewRepresentable {
    let maximumWidth: CGFloat

    func makeNSView(context: Context) -> SearchToolbarConfigurationView {
        let view = SearchToolbarConfigurationView()
        view.maximumWidth = maximumWidth
        return view
    }

    func updateNSView(_ nsView: SearchToolbarConfigurationView, context: Context) {
        nsView.maximumWidth = maximumWidth
        nsView.configureAfterToolbarUpdate()
    }

    final class SearchToolbarConfigurationView: NSView {
        var maximumWidth: CGFloat = 320

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureAfterToolbarUpdate()
        }

        func configureAfterToolbarUpdate() {
            if !configureSearchToolbarItem() {
                retryConfigure(attempts: 5)
            }
        }

        private func retryConfigure(attempts: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                if !self.configureSearchToolbarItem() && attempts > 0 {
                    self.retryConfigure(attempts: attempts - 1)
                }
            }
        }

        @discardableResult
        private func configureSearchToolbarItem() -> Bool {
            guard let toolbar = window?.toolbar else { return false }
            var foundSearchField: NSSearchField?
            var searchItemIndex: Int?
            
            for (index, item) in toolbar.items.enumerated() {
                if let searchItem = item as? NSSearchToolbarItem, searchItem.searchField.placeholderString == "Search Settings" {
                    foundSearchField = searchItem.searchField
                    searchItem.preferredWidthForSearchField = maximumWidth
                    searchItemIndex = index
                    break
                }
                
                if let searchField = findSearchField(in: item.view) {
                    foundSearchField = searchField
                    searchItemIndex = index
                    break
                }
            }
            
            guard let searchField = foundSearchField else { return false }

            let identifier = "Omnia.SettingsSearch.MaximumWidth"
            if let constraint = searchField.constraints.first(where: {
                $0.identifier == identifier
            }) {
                constraint.constant = maximumWidth
            } else {
                let constraint = searchField.widthAnchor.constraint(
                    lessThanOrEqualToConstant: maximumWidth
                )
                constraint.identifier = identifier
                constraint.isActive = true
            }

            if let index = searchItemIndex {
                let needsSpace: Bool
                if index == 0 {
                    needsSpace = true
                } else {
                    let prevItem = toolbar.items[index - 1]
                    needsSpace = (prevItem.itemIdentifier != .flexibleSpace)
                }
                
                if needsSpace {
                    toolbar.insertItem(withItemIdentifier: .flexibleSpace, at: index)
                }
            }
            return true
        }
        
        private func findSearchField(in view: NSView?) -> NSSearchField? {
            guard let view = view else { return nil }
            if let searchField = view as? NSSearchField, searchField.placeholderString == "Search Settings" {
                return searchField
            }
            for subview in view.subviews {
                if let found = findSearchField(in: subview) {
                    return found
                }
            }
            return nil
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
