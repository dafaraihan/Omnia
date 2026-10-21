//
//  HomeSettingsView.swift
//  Omnia
//

import SwiftUI

/// Settings › Layout › Home Layout, as in Nuvio: the hero, how rows are
/// titled, and the catalog order. Collections, Continue Watching and the
/// Detail Page have their own rows on the Layout page.
struct HomeSettingsView: View {
    @Environment(OmniaStore.self) private var store
    @Environment(HomeLayoutStore.self) private var homeLayout
    @Environment(SettingsPreferencesStore.self) private var settings

    @State private var showsHeroCatalogs = false

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
        // Nuvio's order: Hero Catalogs and Catalogs, both folded until
        // opened, then the Layout switches.
        OmniaSettingsForm {
            if !catalogs.isEmpty && homeLayout.preferences.showsHero {
                heroSection
            }

            CatalogsSettingsView(isEmbedded: true)

            heroTrailerSection

            if !catalogs.isEmpty {
                Section {
                    Toggle(isOn: preferenceBinding(\.showsHero)) {
                        settingLabel("Show Hero", detail: "Display the featured carousel at the top of Home.")
                    }
                    SettingsDropdown(
                        "Hero Style",
                        subtitle: homeLayout.preferences.heroStyle.detail,
                        selection: Binding(
                            get: { homeLayout.preferences.heroStyle },
                            set: { style in homeLayout.update { $0.heroStyle = style } }
                        ),
                        options: HomeLayoutPreferences.HeroStyle.allCases
                    ) { $0.title }
                    .disabled(!homeLayout.preferences.showsHero)
                    Toggle(isOn: preferenceBinding(\.dynamicBackground)) {
                        settingLabel("Dynamic Background Color", detail: "Tint Home below the hero with colours from the featured artwork.")
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
            }
        }
        .omniaNavigationTitle("Home Layout")
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

    /// Nuvio Enhanced's hero trailer options.
    private var heroTrailerSection: some View {
        Section {
            Toggle(isOn: settings.binding(\.heroTrailer.autoplay)) {
                settingLabel(
                    "Hero Trailer Playback",
                    detail: "Autoplay trailers in the hero. While one plays, the hero only moves to the next title when you change it."
                )
            }
            if settings.preferences.heroTrailer.autoplay {
                Toggle(isOn: settings.binding(\.heroTrailer.startsWithSound)) {
                    settingLabel(
                        "Start with Sound",
                        detail: "Play the trailer unmuted. You can still mute it with the speaker button."
                    )
                }
                SettingsDropdown(
                    "Trailer Start Delay",
                    subtitle: "Wait this long after a title appears before its trailer starts.",
                    selection: settings.binding(\.heroTrailer.startDelaySeconds),
                    options: Array(HeroTrailerPreferences.delayRange)
                ) { HeroTrailerPreferences.delayTitle($0) }
            }
        } header: {
            Text("Hero Trailer")
        } footer: {
            Text(homeLayout.preferences.showsHero
                 ? "Trailers play natively in the hero. If a trailer is unavailable, its artwork stays visible. Reduce Motion pauses autoplay."
                 : "Turn on Show Hero below to use hero trailers.")
        }
        .disabled(!homeLayout.preferences.showsHero)
    }

    // MARK: Helpers

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

/// Settings › Layout › Detail Page: how a title's page looks, and which of its
/// sections appear.
struct DetailPageSettingsView: View {
    @Environment(SettingsPreferencesStore.self) private var settings

    var body: some View {
        OmniaSettingsForm {
            Section {
                SettingsDropdown(
                    "Background",
                    selection: settings.binding(\.display.detailBackground),
                    options: Array(DetailBackgroundMode.allCases)
                ) { mode in mode.title }
                Toggle(isOn: settings.binding(\.display.posterTransition)) {
                    Text("Poster Transition")
                    Text("Expand and blur posters when opening details.")
                }
            } header: {
                Text("Page")
            } footer: {
                Text("Artwork Color tints the page below the hero with the title's artwork. Plain uses the window background.")
            }

            Section {
                SettingsStyleTilePicker(
                    options: EpisodeCardLayout.allCases,
                    selection: settings.binding(\.display.episodeLayout),
                    title: \.title,
                    detail: \.detail
                ) { layout in
                    EpisodeCardLayoutPreview(layout: layout)
                }
                Toggle(isOn: settings.binding(\.display.blurUnwatchedEpisodes)) {
                    Text("Blur Unwatched Episodes")
                    Text("Hide the stills of episodes you haven't watched or started, to avoid spoilers.")
                }
                Toggle(isOn: settings.binding(\.display.episodeShuffleAvailable)) {
                    Text("Shuffle")
                    Text("Shuffle episodes from any series. Turning this off pauses shuffle.")
                }
            } header: {
                Text("Episode Cards")
            } footer: {
                Text("Choose how episodes are drawn on a show's page.")
            }

            Section {
                ForEach(Array(sectionOrder.enumerated()), id: \.element) { index, section in
                    sectionRow(section, index: index)
                }
            } header: {
                Text("Sections")
            } footer: {
                Text("Turned-off sections are left out of every title page. Use the arrows to change the order they appear in.")
            }
        }
        .omniaNavigationTitle("Detail Page")
    }

    private var sectionOrder: [DetailSection] {
        DisplayPreferences.completeOrder(settings.preferences.display.detailSectionOrder)
    }

    private func sectionRow(_ section: DetailSection, index: Int) -> some View {
        HStack(spacing: 12) {
            Toggle(section.title, isOn: sectionBinding(section))

            Button {
                settings.update { $0.display.moveDetailSection(section, by: -1) }
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(index == 0)
            .help("Move Up")
            .accessibilityLabel("Move \(section.title) up")

            Button {
                settings.update { $0.display.moveDetailSection(section, by: 1) }
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(index == sectionOrder.count - 1)
            .help("Move Down")
            .accessibilityLabel("Move \(section.title) down")
        }
        .buttonStyle(.borderless)
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
