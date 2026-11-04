// Settings on iPad and Mac, as they were before the iPhone redesign.
//
//  HomeSettingsView.swift
//  Omnia
//

import SwiftUI
import UniformTypeIdentifiers

/// Settings › Layout › Home Layout, as in Nuvio: the hero, how rows are
/// titled, and the catalog order. Collections, Continue Watching and the
/// Detail Page have their own rows on the Layout page.
struct LegacyHomeSettingsView: View {
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

    /// The hero carousel's pace and Nuvio Enhanced's hero trailer options.
    private var heroTrailerSection: some View {
        Section {
            Toggle(isOn: settings.binding(\.heroTrailer.autoAdvance)) {
                settingLabel(
                    "Auto-Advance",
                    detail: "Move to the next title on its own."
                )
            }
            if settings.preferences.heroTrailer.autoAdvance {
                SettingsDropdown(
                    "Title Duration",
                    subtitle: "How long a title stays in the hero when no trailer is playing.",
                    selection: settings.binding(\.heroTrailer.intervalSeconds),
                    options: Array(HeroTrailerPreferences.intervalRange)
                ) { "\($0) s" }
            }
            Toggle(isOn: settings.binding(\.heroTrailer.autoplay)) {
                settingLabel(
                    "Hero Trailer Playback",
                    detail: "Autoplay trailers in the hero. While one plays, the hero stays on its title."
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
                SettingsDropdown(
                    "After Trailer",
                    subtitle: "What the hero does when a trailer finishes.",
                    selection: settings.binding(\.heroTrailer.afterTrailer),
                    options: HeroTrailerEndAction.allCases
                ) { $0.title }
            }
        } header: {
            Text("Hero")
        } footer: {
            Text(homeLayout.preferences.showsHero
                 ? "Trailers play natively in the hero. If a trailer is unavailable, its artwork stays visible. Reduce Motion pauses autoplay."
                 : "Turn on Show Hero below to use these options.")
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
struct LegacyDetailPageSettingsView: View {
    @Environment(SettingsPreferencesStore.self) private var settings
    @State private var draggedSection: DetailSection?

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
                Text("Turned-off sections are left out of every title page. Drag a section to change the order they appear in.")
            }
        }
        .omniaNavigationTitle("Detail Page")
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
