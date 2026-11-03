//
//  DiscoverView.swift
//  Omnia
//

import SwiftUI

struct DiscoverView: View {
    @Environment(\.displayPreferences) private var display
    @Environment(OmniaStore.self) private var store
    @Environment(LiveMetadataStore.self) private var metadata
    @AppStorage(HomeShelfPreferences.storageKey) private var disabledHomeShelfIDs = ""
    @State private var filters = DiscoverFilterState()
    /// Search lives on Discover (Dafa, 2026-10-22): two or more letters
    /// show results in place of the shelves.
    @State private var query = ""
    @State private var history = SearchHistoryStore.shared

    private var shelfPreferences: HomeShelfPreferences {
        HomeShelfPreferences(rawValue: disabledHomeShelfIDs)
    }

    private var enabledAddonCatalogs: [(id: String, addon: InstalledAddon, catalog: AddonCatalog)] {
        store.installedAddons.flatMap { addon in
            addon.manifest.catalogs
                .filter { store.isCatalogEnabled(for: addon, catalog: $0) }
                .map { (store.catalogID(for: addon, catalog: $0), addon, $0) }
        }
    }

    private var hasBuiltInCatalogs: Bool {
        !metadata.movieCatalog.isEmpty || !metadata.seriesCatalog.isEmpty
    }

    /// Catalogs with a required filter open on its first option, as in
    /// Stremio; search-only catalogs stay in Search.
    private var discoverAddonCatalogs: [(id: String, addon: InstalledAddon, catalog: AddonCatalog)] {
        enabledAddonCatalogs.filter { $0.addon.isEnabled && $0.catalog.canLoadWithDefaults }
    }

    private var visibleBuiltInCatalogs: [BuiltInHomeCatalog] {
        metadata.homeCatalogs.filter { catalog in
            DiscoverFilterPresentation.showsCatalog(
                id: catalog.id,
                kind: catalog.kind,
                state: filters,
                builtInShelf: catalog.shelf,
                preferences: shelfPreferences
            )
        }
    }

    private var allKnownItems: [MediaItem] {
        metadata.topMovies + metadata.topSeries + metadata.homeCatalogs.flatMap(\.items) + store.library
    }

    /// The same genres as the Browse by Genre cards.
    private var availableGenres: [String] {
        BrowseGenre.allCases.map(\.title)
    }

    private var availableYears: [Int] {
        Set(allKnownItems.compactMap { Int($0.year) }).sorted(by: >)
    }

    private var catalogChoices: [(id: String, title: String)] {
        var choices: [(String, String)] = [
            ("top-movies", "Top 10 Movies"),
            ("top-series", "Top 10 Series")
        ]
        choices += metadata.homeCatalogs.compactMap { catalog in
            shelfPreferences.isEnabled(catalog.shelf) ? (catalog.id, catalog.title) : nil
        }
        if !store.library.isEmpty { choices.append(("saved", "Saved For You")) }
        choices += enabledAddonCatalogs.map { source in
            (source.id, source.catalog.name?.trimmedNonEmpty ?? source.catalog.id)
        }
        return choices
    }

    private var isSearching: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    var body: some View {
        Group {
            if isSearching {
                SearchView(query: $query)
            } else {
                browseContent
            }
        }
        .modifier(TopBarScrollReporting(destination: .discover))
        .omniaNavigationTitle("Discover", screen: .discover)
        #if os(macOS)
        // The Filter button just before the search field, each its own
        // toolbar item. While searching it holds Search's filters.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                filterMenu
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                MacSettingsSearchField(text: $query, prompt: "Titles, people, or genres")
                    .frame(width: 320)
            }
        }
        #else
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Titles, people, or genres")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                filterMenu
            }
        }
        #endif
        .navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
    }

    @ViewBuilder
    private var filterMenu: some View {
        if isSearching {
            SearchFilterMenu()
        } else {
            discoverFilterMenu
        }
    }

    /// Recent searches and genres, then the shelves.
    private var browseContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 36) {
                if query.isEmpty, !history.recentSearches.isEmpty {
                    RecentSearchesSection(
                        searches: Array(history.recentSearches.prefix(3)),
                        onSelect: { query = $0 },
                        onRemove: { history.remove($0) }
                    )
                }
                GenreDirectoryShelf()
                // Add-on shelves don't depend on Omnia's own metadata, so
                // Discover only gives up when neither has anything to show.
                if hasBuiltInCatalogs || !discoverAddonCatalogs.isEmpty {
                    discoverShelves
                } else if metadata.isLoadingCatalogs {
                    ProgressView("Finding something good…")
                        .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    unavailableState
                }
            }
            .padding(.horizontal, MediaBrowseMetrics.pageInset)
            .padding(.vertical, 24)
        }
    }

    private var unavailableState: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                "Built-in Discovery Is Unavailable",
                systemImage: "wifi.exclamationmark",
                description: Text(metadata.errorMessage ?? "Try again in a moment.")
            )
            Button("Try Again", systemImage: "arrow.clockwise") {
                Task { await metadata.loadDefaultCatalogs() }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    @ViewBuilder
    private var discoverShelves: some View {
        let topMovies = filtered(metadata.topMovies)
        if showsCatalog(id: "top-movies", kind: .movie), !topMovies.isEmpty {
            catalogShelf(title: "Top 10 Movies", items: Array(topMovies.prefix(10)), type: .movie, category: .topRated)
        }

        let topSeries = filtered(metadata.topSeries)
        if showsCatalog(id: "top-series", kind: .series), !topSeries.isEmpty {
            catalogShelf(title: "Top 10 Series", items: Array(topSeries.prefix(10)), type: .series, category: .topRated)
        }

        ForEach(visibleBuiltInCatalogs) { catalog in
            let items = filtered(catalog.items)
            if !items.isEmpty {
                catalogShelf(
                    title: catalog.title,
                    items: Array(items.prefix(18)),
                    type: catalog.kind == .movie ? .movie : .series,
                    category: catalog.category
                )
            }
        }

        let saved = filtered(Array(store.library.reversed()))
        if showsSavedCatalog, !saved.isEmpty {
            catalogShelf(title: "Saved For You", items: saved)
        }

        let addonCatalogs = discoverAddonCatalogs
        ForEach(addonCatalogs.indices, id: \.self) { index in
            let source = addonCatalogs[index]
            if showsCatalog(id: source.id, kind: source.catalog.mediaKind) {
                AddonCatalogShelf(addon: source.addon, catalog: source.catalog, filters: filters)
            }
        }
    }

    private var showsSavedCatalog: Bool {
        (filters.selectedCatalogIDs.isEmpty || filters.selectedCatalogIDs.contains("saved"))
    }

    private func filtered(_ items: [MediaItem]) -> [MediaItem] {
        DiscoverFilterPresentation.apply(filters, to: items)
    }

    private func showsCatalog(id: String, kind: MediaItem.Kind) -> Bool {
        DiscoverFilterPresentation.showsCatalog(
            id: id,
            kind: kind,
            state: filters,
            preferences: shelfPreferences
        )
    }

    private func catalogShelf(
        title: String,
        items: [MediaItem],
        type: MediaType? = nil,
        category: MetadataCatalogCategory? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderLink(title: title) {
                if let type, let category {
                    PagedMetadataCatalogView(title: title, type: type, category: category)
                } else {
                    MetadataCatalogView(title: title, items: items)
                }
            }
            ShelfScrollView(items: items, itemSpan: MediaBrowseMetrics.posterItemSpan(display), accessibilityLabel: title) { item in
                MediaPoster(item: item)
            }
        }
    }

    private var discoverFilterMenu: some View {
        Menu {
            catalogsMenu
            genreMenu
            kindMenu
            sortMenu
        } label: {
            Label("Filter and Sort", systemImage: "line.3.horizontal.decrease.circle")
        }
        .help("Filter and sort Discover")
    }

    private var catalogsMenu: some View {
        Menu("Catalogs", systemImage: "rectangle.stack") {
            // Toggles draw the native menu checkmark.
            Toggle("All Catalogs", isOn: Binding(
                get: { filters.selectedCatalogIDs.isEmpty },
                set: { if $0 { filters.selectedCatalogIDs.removeAll() } }
            ))
            Divider()
            ForEach(catalogChoices, id: \.id) { choice in
                Toggle(choice.title, isOn: Binding(
                    get: { filters.selectedCatalogIDs.contains(choice.id) },
                    set: { _ in toggleCatalogFilter(choice.id) }
                ))
            }
            Divider()
            NavigationLink("Catalog Settings", destination: CatalogsSettingsView())
        }
    }

    // In a menu, a Picker is already its own submenu titled with its label.
    // Wrapping it in another Menu of the same name added a second level
    // (Genre ▸ Genre ▸ list).
    private var genreMenu: some View {
        Picker(selection: $filters.genre) {
            Text("All Genres").tag(String?.none)
            ForEach(availableGenres, id: \.self) { genre in
                Text(genre).tag(Optional(genre))
            }
        } label: {
            Label("Genre", systemImage: "theatermasks")
        }
        .pickerStyle(.menu)
    }

    private var kindMenu: some View {
        Picker(selection: $filters.kind) {
            Text("All Kinds").tag(MediaItem.Kind?.none)
            Text("Movies").tag(Optional(MediaItem.Kind.movie))
            Text("Series").tag(Optional(MediaItem.Kind.series))
        } label: {
            Label("Kind", systemImage: "film.stack")
        }
        .pickerStyle(.menu)
    }

    private var sortMenu: some View {
        Menu("Sort", systemImage: "arrow.up.arrow.down") {
            Picker("Release Period", selection: $filters.releasePeriod) {
                ForEach(DiscoverReleasePeriod.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            .pickerStyle(.inline)
            if filters.releasePeriod == .chooseYear {
                Picker("Year", selection: $filters.selectedYear) {
                    Text("Any Year").tag(Int?.none)
                    ForEach(availableYears, id: \.self) { year in
                        Text(String(year)).tag(Optional(year))
                    }
                }
                .pickerStyle(.menu)
            }
            Divider()
            Picker("Order", selection: $filters.sort) {
                ForEach(DiscoverDateSort.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
            .pickerStyle(.inline)
        }
    }

    private func toggleCatalogFilter(_ id: String) {
        if filters.selectedCatalogIDs.isEmpty {
            filters.selectedCatalogIDs = [id]
        } else if filters.selectedCatalogIDs.contains(id) {
            filters.selectedCatalogIDs.remove(id)
        } else {
            filters.selectedCatalogIDs.insert(id)
        }
    }
}

/// One add-on catalog as a shelf. Discover passes its filters; Home shows the
/// catalog exactly as the add-on orders it.
struct AddonCatalogShelf: View {
    @Environment(\.displayPreferences) private var display
    let addon: InstalledAddon
    let catalog: AddonCatalog
    var filters: DiscoverFilterState?

    @State private var items: [MediaItem] = []
    @State private var didFinishLoading = false
    @State private var isLoading = false
    @State private var loadedRequest: RequestIdentity?
    @State private var errorMessage: String?

    private struct RequestIdentity: Hashable {
        let addon: InstalledAddon
        let catalog: AddonCatalog
    }

    private var requestIdentity: RequestIdentity { RequestIdentity(addon: addon, catalog: catalog) }
    /// With the type, as on Home: Cinemeta has a "Popular" for movies and for series.
    private var title: String {
        let name = catalog.name?.trimmedNonEmpty ?? catalog.id
        return "\(name) - \(AddonHomeCatalog.typeLabel(for: catalog.type))"
    }
    private var visibleItems: [MediaItem] {
        guard let filters else { return items }
        return DiscoverFilterPresentation.apply(filters, to: items)
    }

    var body: some View {
        Group {
            if !visibleItems.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeaderLink(title: title) {
                        AddonCatalogBrowseView(addon: addon, catalog: catalog)
                    }
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.secondary)
                        retryButton
                    } else if isLoading {
                        ProgressView("Refreshing catalog…").controlSize(.small)
                    }
                    ShelfScrollView(items: visibleItems, itemSpan: MediaBrowseMetrics.posterItemSpan(display), accessibilityLabel: title) { item in
                        MediaPoster(item: item)
                    }
                }
            } else if !didFinishLoading {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: title)
                    ProgressView("Loading catalog…").controlSize(.small)
                }
            } else if let errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: title)
                    Text(errorMessage).foregroundStyle(.secondary)
                    retryButton
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: title)
                    Text(items.isEmpty ? "This catalog has no titles." : "No titles match these filters.")
                        .foregroundStyle(.secondary)
                    retryButton
                }
            }
        }
        .task(id: requestIdentity) {
            await load()
        }
    }

    private var retryButton: some View {
        Button("Retry", systemImage: "arrow.clockwise") {
            Task { await load(forceRefresh: true) }
        }
        .disabled(isLoading)
    }

    /// The same saved copy Home and collection folders use.
    private var cacheKey: String {
        AddonCatalogCache.key(addon: addon, catalog: catalog, extra: catalog.resolvingExtras([:]) ?? [:])
    }

    private func load(forceRefresh: Bool = false) async {
        let request = requestIdentity
        let key = cacheKey
        if loadedRequest != request {
            items = []
            didFinishLoading = false
            loadedRequest = request
        } else if isLoading {
            return
        }
        isLoading = true
        defer { if request == requestIdentity { isLoading = false } }
        // Shelves are rebuilt each time Discover opens and each time one
        // scrolls back into view; reuse what was fetched this session.
        if !forceRefresh, let fresh = AddonCatalogShelfCache.items(for: key) {
            items = fresh
            errorMessage = nil
            didFinishLoading = true
            return
        }
        errorMessage = nil
        // Draw the copy saved last time at once, then refresh it.
        if items.isEmpty, let saved = await AddonCatalogCache.previews(for: [key])[key] {
            guard !Task.isCancelled, request == requestIdentity else { return }
            items = saved.compactMap { $0.mediaItem(addon: addon) }
        }
        didFinishLoading = !items.isEmpty
        do {
            let metas = try await StremioAddonClient.fetchCatalog(from: addon, catalog: catalog)
            guard !Task.isCancelled, request == requestIdentity else { return }
            items = metas.compactMap { $0.mediaItem(addon: addon) }
            AddonCatalogShelfCache.store(items, for: key)
            Task { await AddonCatalogCache.save(metas, for: key) }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, request == requestIdentity else { return }
            errorMessage = items.isEmpty
                ? "This add-on catalog is unavailable."
                : "Couldn’t refresh this catalog. Showing saved titles."
        }
        didFinishLoading = true
    }
}

/// Discover's add-on shelves for this session, kept for 30 minutes.
private enum AddonCatalogShelfCache {
    private static var entries: [String: (items: [MediaItem], storedAt: Date)] = [:]
    private static let maximumAge: TimeInterval = 30 * 60

    static func items(for key: String) -> [MediaItem]? {
        guard let entry = entries[key], Date.now.timeIntervalSince(entry.storedAt) < maximumAge else { return nil }
        return entry.items
    }

    static func store(_ items: [MediaItem], for key: String) {
        entries[key] = (items, .now)
    }
}

private extension AddonCatalog {
    var mediaKind: MediaItem.Kind {
        MediaItem.Kind(stremioType: type) ?? .movie
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
