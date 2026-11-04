//
//  HomeSettingsView.swift
//  Omnia
//

import SwiftUI
import UniformTypeIdentifiers

/// Settings › Layout › Home Layout, as in Nuvio: the hero, how rows are
/// titled, and the catalog order. Collections, Continue Watching and the
/// Detail Page have their own rows on the Layout page.
struct HomeSettingsView: View {
    @Environment(OmniaStore.self) private var store
    @Environment(HomeLayoutStore.self) private var homeLayout
    @Environment(SettingsPreferencesStore.self) private var settings

    @Environment(CollectionsStore.self) private var collections
    @AppStorage(HomeView.continueWatchingVisibilityKey) private var showsContinueWatching = true
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
        OmniaSettingsForm {
            heroSection

            if !catalogs.isEmpty {
                Section {
                    Toggle(isOn: preferenceBinding(\.showsCatalogType)) {
                        settingLabel("Show Catalog Type", detail: "Add the type after each catalog's name.")
                    }
                    .settingsRow("Show Catalog Type")
                    Toggle(isOn: preferenceBinding(\.hidesUnreleasedContent)) {
                        settingLabel("Hide Unreleased Content", detail: "Leave out movies and shows that haven't come out.")
                    }
                    .settingsRow("Hide Unreleased Content")
                } header: {
                    Text("Rows")
                }
            }

            Section {
                SettingsRouteLink(route: .catalogs, summary: visibleCatalogSummary)
                SettingsRouteLink(route: .collections, summary: collectionsSummary)
                SettingsRouteLink(route: .continueWatching, summary: continueWatchingSummary)
                SettingsRouteLink(route: .upcoming, summary: settings.preferences.showUpcoming ? "On Home" : "Hidden")
            } header: {
                Text("On Home")
            }
        }
        .omniaNavigationTitle("Home")
    }

    private var visibleCatalogSummary: String {
        catalogs.isEmpty ? "Built-in rows" : "\(visibleCatalogs.count) of \(catalogs.count)"
    }

    private var collectionsSummary: String {
        let all = collections.collections
        guard !all.isEmpty else { return "None" }
        let visible = all.filter { collections.isVisible($0) }.count
        return visible == all.count ? "\(all.count) on Home" : "\(visible) of \(all.count)"
    }

    private var continueWatchingSummary: String {
        showsContinueWatching ? "\(settings.preferences.display.continueWatchingStyle.title) cards" : "Hidden"
    }

    /// Everything about the hero, in one section.
    private var heroSection: some View {
        Section {
            if !catalogs.isEmpty {
                Toggle(isOn: preferenceBinding(\.showsHero)) {
                    settingLabel("Show Hero", detail: "Display the featured carousel at the top of Home.")
                }
                .settingsRow("Show Hero")
                SettingsDropdown(
                    "Hero Style",
                    subtitle: homeLayout.preferences.heroStyle.detail,
                    selection: Binding(
                        get: { homeLayout.preferences.heroStyle },
                        set: { style in homeLayout.update { $0.heroStyle = style } }
                    ),
                    options: HomeLayoutPreferences.HeroStyle.allCases
                ) { $0.title }
                .settingsRow("Hero Style")
                .disabled(!homeLayout.preferences.showsHero)
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
                        "Hero Catalogs: \(heroSourceKeys.count) of \(HomeLayoutPreferences.heroSourceLimit)",
                        detail: heroSourceTitles.isEmpty ? "No hero catalogs" : heroSourceTitles
                    )
                }
                .disabled(!homeLayout.preferences.showsHero)
            }
            Group {
            Toggle(isOn: settings.binding(\.heroTrailer.autoAdvance)) {
                settingLabel(
                    "Auto-Advance",
                    detail: "Move to the next title on its own."
                )
            }
            .settingsRow("Auto-Advance")
            if settings.preferences.heroTrailer.autoAdvance {
Group {
                SettingsDropdown(
                    "Title Duration",
                    subtitle: "How long a title stays in the hero when no trailer is playing.",
                    selection: settings.binding(\.heroTrailer.intervalSeconds),
                    options: Array(HeroTrailerPreferences.intervalRange)
                ) { "\($0) s" }
                .settingsRow("Title Duration")
            }
.settingsDependentRows()
}
            Toggle(isOn: settings.binding(\.heroTrailer.autoplay)) {
                settingLabel(
                    "Hero Trailer Playback",
                    detail: "Autoplay trailers in the hero. While one plays, the hero stays on its title."
                )
            }
            .settingsRow("Hero Trailer Playback")
            if settings.preferences.heroTrailer.autoplay {
Group {
                Toggle(isOn: settings.binding(\.heroTrailer.startsWithSound)) {
                    settingLabel(
                        "Start with Sound",
                        detail: "Play the trailer unmuted. You can still mute it with the speaker button."
                    )
                }
                .settingsRow("Start with Sound")
                SettingsDropdown(
                    "Trailer Start Delay",
                    subtitle: "Wait this long after a title appears before its trailer starts.",
                    selection: settings.binding(\.heroTrailer.startDelaySeconds),
                    options: Array(HeroTrailerPreferences.delayRange)
                ) { HeroTrailerPreferences.delayTitle($0) }
                .settingsRow("Trailer Start Delay")
                SettingsDropdown(
                    "After Trailer",
                    subtitle: "What the hero does when a trailer finishes.",
                    selection: settings.binding(\.heroTrailer.afterTrailer),
                    options: HeroTrailerEndAction.allCases
                ) { $0.title }
                .settingsRow("After Trailer")
            }
.settingsDependentRows()
}
            }
            .disabled(!homeLayout.preferences.showsHero)
            Toggle(isOn: Binding(
                get: { homeLayout.preferences.dynamicBackground },
                set: { enabled in homeLayout.update { $0.dynamicBackground = enabled } }
            )) {
                settingLabel("Dynamic Background Color", detail: "Blend the featured artwork color into Home's background.")
            }
            .settingsRow("Dynamic Background Color")
            Toggle(isOn: settings.binding(\.display.heroBlend.isEnabled)) {
                settingLabel("Gradient Overlay", detail: "Fades the hero into the page below it. Needs Dynamic Background Color, or Artwork Color on title pages.")
            }
            .settingsRow("Gradient Overlay")
            if settings.preferences.display.heroBlend.isEnabled {
Group {
                SettingsDeferredSlider(title: "Overlay Strength", value: settings.binding(\.display.heroBlend.strength), range: 0.2 ... 1)
                .settingsRow("Overlay Strength")
                SettingsDeferredSlider(title: "Overlay Height", value: settings.binding(\.display.heroBlend.height), range: 0.2 ... 1)
                .settingsRow("Overlay Height")
            }
.settingsDependentRows()
}
        } header: {
            SettingsSectionHeader("Hero", resetTitle: "Reset Overlay", canReset: !(settings.preferences.display.heroBlend == HeroBlendPreferences())) {
                    settings.update { $0.display.heroBlend = HeroBlendPreferences() }

            }
        } footer: {
            Text("The hero shows up to \(HomeLayoutPreferences.heroItemLimit) titles from its catalogs.")
        }
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
    @State private var draggedSection: DetailSection?

    var body: some View {
        OmniaSettingsForm {
            Section {
                SettingsDropdown(
                    "Page Background",
                    selection: settings.binding(\.display.detailBackground),
                    options: Array(DetailBackgroundMode.allCases)
                ) { mode in mode.title }
                .settingsRow("Page Background")
                Toggle(isOn: settings.binding(\.display.posterTransition)) {
                    Text("Poster Transition")
                    Text("Expand and blur posters when opening details.")
                }
                .settingsRow("Poster Transition")
            } header: {
                Text("Page")
            } footer: {
                Text("Artwork Color tints the page with the title's artwork.")
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
                .settingsRow("Blur Unwatched Episodes")
                Toggle(isOn: settings.binding(\.display.episodeShuffleAvailable)) {
                    Text("Shuffle")
                    Text("Shuffle episodes from any series. Turning this off pauses shuffle.")
                }
                .settingsRow("Shuffle")
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
                Text("Drag to reorder. Turned-off sections are left out.")
            }
        }
        .omniaNavigationTitle("Title Page")
    }

    private var sectionOrder: [DetailSection] {
        DisplayPreferences.completeOrder(settings.preferences.display.detailSectionOrder)
    }

    /// Drag a row onto another to reorder, as on the Add-ons page.
    private func sectionRow(_ section: DetailSection, index: Int) -> some View {
        Toggle(section.title, isOn: sectionBinding(section))
            .opacity(draggedSection == section ? 0.72 : 1)
            .onDrag {
                draggedSection = section
                return NSItemProvider(object: section.rawValue as NSString)
            }
            .onDrop(
                of: [.text],
                delegate: DetailSectionDropDelegate(
                    target: section,
                    order: { sectionOrder },
                    draggedSection: $draggedSection,
                    move: { source, destination in
                        settings.update { $0.display.moveDetailSections(fromOffsets: source, toOffset: destination) }
                    }
                )
            )
            .accessibilityAction(named: "Move earlier") {
                settings.update { $0.display.moveDetailSection(section, by: -1) }
            }
            .accessibilityAction(named: "Move later") {
                settings.update { $0.display.moveDetailSection(section, by: 1) }
            }
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

private struct DetailSectionDropDelegate: DropDelegate {
    let target: DetailSection
    let order: () -> [DetailSection]
    @Binding var draggedSection: DetailSection?
    let move: (IndexSet, Int) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedSection,
              draggedSection != target,
              let source = order().firstIndex(of: draggedSection),
              let destination = order().firstIndex(of: target).flatMap({ AddonReorder.destination(from: source, over: $0) }) else {
            return
        }
        withAnimation(.easeInOut(duration: 0.16)) {
            move(IndexSet(integer: source), destination)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedSection = nil
        return true
    }
}
