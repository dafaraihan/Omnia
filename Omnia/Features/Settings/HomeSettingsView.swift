//
//  HomeSettingsView.swift
//  Omnia
//

import SwiftUI

/// Everything that shapes Home in one place: the hero, how rows are titled,
/// and links to Catalogs, Collections and Upcoming. Continue Watching and the
/// title page join this list as they arrive.
struct HomeSettingsView: View {
    @Environment(OmniaStore.self) private var store
    @Environment(HomeLayoutStore.self) private var homeLayout
    @Environment(SettingsPreferencesStore.self) private var settings
    @Environment(CollectionsStore.self) private var collections

    @State private var showsHeroCatalogs = false
    @AppStorage(HomeView.continueWatchingVisibilityKey) private var showsContinueWatching = true

    private var catalogs: [AddonHomeCatalog] {
        homeLayout.ordered(AddonCatalogStore.catalogs(in: store))
    }

    private var visibleCatalogs: [AddonHomeCatalog] {
        catalogs.filter { store.isCatalogEnabled(for: $0.addon, catalog: $0.catalog) }
    }

    private var heroSourceKeys: [String] {
        homeLayout.preferences.heroSources(
            orderedVisibleKeys: visibleCatalogs.map(\.key),
            allKeys: catalogs.map(\.key)
        )
    }

    private var heroLimitReached: Bool {
        heroSourceKeys.count >= HomeLayoutPreferences.heroSourceLimit
    }

    var body: some View {
        OmniaSettingsForm {
            if catalogs.isEmpty {
                Section {
                    SettingsRouteLink(route: .catalogs, summary: "Built-in rows")
                    SettingsRouteLink(route: .collections, summary: collectionsSummary)
                    SettingsRouteLink(route: .continueWatching, summary: continueWatchingSummary)
                    SettingsRouteLink(route: .upcoming, summary: upcomingSummary)
                    SettingsRouteLink(route: .detailPage, summary: detailPageSummary)
                } header: {
                    Text("Home")
                } footer: {
                    Text("Home shows Omnia's built-in rows. Install an add-on that provides catalogs, such as Xperience or AIOMetadata, and its catalogs replace them.")
                }
            } else {
                Section {
                    SettingsRouteLink(route: .catalogs, summary: catalogsSummary)
                    SettingsRouteLink(route: .collections, summary: collectionsSummary)
                    SettingsRouteLink(route: .continueWatching, summary: continueWatchingSummary)
                    SettingsRouteLink(route: .upcoming, summary: upcomingSummary)
                    SettingsRouteLink(route: .detailPage, summary: detailPageSummary)
                } header: {
                    Text("Home")
                }

                Section {
                    Toggle(isOn: preferenceBinding(\.showsHero)) {
                        settingLabel("Show Hero", detail: "Display the featured carousel at the top of Home.")
                    }
                    Toggle(isOn: preferenceBinding(\.showsCatalogType)) {
                        settingLabel("Show Catalog Type", detail: "Add the type after each catalog name, as in “Popular - Movies”.")
                    }
                    Toggle(isOn: preferenceBinding(\.hidesUnreleasedContent)) {
                        settingLabel("Hide Unreleased Content", detail: "Leave out movies and shows that haven't been released yet.")
                    }
                } header: {
                    Text("Layout")
                }

                if homeLayout.preferences.showsHero {
                    heroSection
                }
            }
        }
        .omniaNavigationTitle("Home")
    }

    private var heroSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showsHeroCatalogs) {
                ForEach(catalogs) { catalog in
                    let isSource = heroSourceKeys.contains(catalog.key)
                    Toggle(isOn: heroBinding(for: catalog)) {
                        settingLabel(homeLayout.title(for: catalog), detail: heroDetail(for: catalog, isSource: isSource))
                    }
                    .disabled(!isSource && heroLimitReached)
                    .padding(.vertical, 2)
                }
            } label: {
                settingLabel(
                    "\(heroSourceKeys.count) of \(HomeLayoutPreferences.heroSourceLimit) selected",
                    detail: heroSourceTitles.isEmpty ? "No hero catalogs" : heroSourceTitles
                )
            }
        } header: {
            Text("Hero Catalogs")
        } footer: {
            Text("The hero shows up to \(HomeLayoutPreferences.heroItemLimit) titles mixed from these catalogs.")
        }
    }

    // MARK: Helpers

    private var catalogsSummary: String {
        "\(visibleCatalogs.count) of \(catalogs.count) visible"
    }

    private var collectionsSummary: String {
        let all = collections.collections
        guard !all.isEmpty else { return "None" }
        let visible = all.filter { collections.isVisible($0) }.count
        return visible == all.count ? "\(all.count) on Home" : "\(visible) of \(all.count) on Home"
    }

    private var continueWatchingSummary: String {
        guard showsContinueWatching else { return "Hidden from Home" }
        return "\(settings.preferences.display.continueWatchingStyle.title) cards"
    }

    private var detailPageSummary: String {
        let hidden = settings.preferences.display.hiddenDetailSections.count
        return hidden == 0 ? "All sections shown" : "\(hidden) hidden"
    }

    private var upcomingSummary: String {
        settings.preferences.showUpcoming ? "Shown on Home" : "Hidden from Home"
    }

    private var heroSourceTitles: String {
        heroSourceKeys
            .compactMap { key in catalogs.first { $0.key == key }.map(homeLayout.title(for:)) }
            .joined(separator: ", ")
    }

    private func heroDetail(for catalog: AddonHomeCatalog, isSource: Bool) -> String {
        if !isSource && heroLimitReached {
            return "\(catalog.addon.displayName) • Limit reached (max \(HomeLayoutPreferences.heroSourceLimit))"
        }
        return catalog.addon.displayName
    }

    private func settingLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func preferenceBinding(_ keyPath: WritableKeyPath<HomeLayoutPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { homeLayout.preferences[keyPath: keyPath] },
            set: { value in homeLayout.update { $0[keyPath: keyPath] = value } }
        )
    }

    private func heroBinding(for catalog: AddonHomeCatalog) -> Binding<Bool> {
        Binding(
            get: { heroSourceKeys.contains(catalog.key) },
            set: { isOn in
                homeLayout.setHeroSource(catalog.key, isEnabled: isOn, current: heroSourceKeys)
            }
        )
    }
}

/// Settings › Home › Detail Page: how a title's page looks, and which of its
/// sections appear.
struct DetailPageSettingsView: View {
    @Environment(SettingsPreferencesStore.self) private var settings

    var body: some View {
        OmniaSettingsForm {
            Section {
                Picker("Background", selection: settings.binding(\.display.detailBackground)) {
                    ForEach(DetailBackgroundMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } header: {
                Text("Page")
            } footer: {
                Text("Artwork Color tints the page below the hero with the title's artwork. Plain uses the window background.")
            }

            Section {
                Picker("Layout", selection: settings.binding(\.display.episodeLayout)) {
                    ForEach(EpisodeCardLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                Toggle(isOn: settings.binding(\.display.blurUnwatchedEpisodes)) {
                    Text("Blur Unwatched Episodes")
                    Text("Hide the stills of episodes you haven't watched or started, to avoid spoilers.")
                }
            } header: {
                Text("Episodes")
            }

            Section {
                ForEach(DetailSection.allCases) { section in
                    Toggle(section.title, isOn: sectionBinding(section))
                }
            } header: {
                Text("Sections")
            } footer: {
                Text("Turned-off sections are left out of every title page.")
            }
        }
        .omniaNavigationTitle("Detail Page")
    }

    private func sectionBinding(_ section: DetailSection) -> Binding<Bool> {
        Binding(
            get: { settings.preferences.display.shows(section) },
            set: { isOn in
                settings.update {
                    if isOn {
                        $0.display.hiddenDetailSections.remove(section)
                    } else {
                        $0.display.hiddenDetailSections.insert(section)
                    }
                }
            }
        )
    }
}
