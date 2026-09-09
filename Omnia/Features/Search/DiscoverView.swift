//
//  DiscoverView.swift
//  Omnia
//

import SwiftUI

struct DiscoverView: View {
    @Environment(OmniaStore.self) private var store
    @Environment(LiveMetadataStore.self) private var metadata
    @AppStorage(HomeShelfPreferences.storageKey) private var disabledHomeShelfIDs = ""
    @State private var filters = DiscoverFilterState()

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

    private var availableGenres: [String] {
        Set(allKnownItems.flatMap(\.genres)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
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

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 36) {
                if metadata.isLoadingCatalogs, metadata.movieCatalog.isEmpty, metadata.seriesCatalog.isEmpty {
                    ProgressView("Finding something good…")
                        .frame(maxWidth: .infinity, minHeight: 280)
                } else if metadata.movieCatalog.isEmpty, metadata.seriesCatalog.isEmpty {
                    unavailableState
                } else {
                    discoverShelves
                }
            }
            .padding(.horizontal, MediaBrowseMetrics.pageInset)
            .padding(.vertical, 24)
        }
        .omniaNavigationTitle("Discover", screen: .discover)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                discoverFilterMenu
            }
        }
        .navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
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

        ForEach(enabledAddonCatalogs.indices, id: \.self) { index in
            let source = enabledAddonCatalogs[index]
            if source.catalog.canLoadWithoutExtra,
               showsCatalog(id: source.id, kind: source.catalog.mediaKind) {
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
            ShelfScrollView(items: items, itemSpan: MediaBrowseMetrics.shelfItemSpan, accessibilityLabel: title) { item in
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
            Label {
                Text("Filter and Sort")
            } icon: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.white)
            }
        }
        .tint(.white)
        .help("Filter and sort Discover")
    }

    private var catalogsMenu: some View {
        Menu("Catalogs", systemImage: "rectangle.stack") {
            Button {
                filters.selectedCatalogIDs.removeAll()
            } label: {
                Label("All Catalogs", systemImage: filters.selectedCatalogIDs.isEmpty ? "checkmark" : "rectangle.stack")
            }
            Divider()
            ForEach(catalogChoices, id: \.id) { choice in
                Button {
                    toggleCatalogFilter(choice.id)
                } label: {
                    Label(choice.title, systemImage: filters.selectedCatalogIDs.contains(choice.id) ? "checkmark" : "rectangle.stack")
                }
            }
            Divider()
            NavigationLink("Catalog Settings", destination: CatalogsSettingsView())
        }
    }

    private var genreMenu: some View {
        Menu("Genre", systemImage: "theatermasks") {
            Picker("Genre", selection: $filters.genre) {
                Text("All Genres").tag(String?.none)
                ForEach(availableGenres, id: \.self) { genre in
                    Text(genre).tag(Optional(genre))
                }
            }
        }
    }

    private var kindMenu: some View {
        Menu("Kind", systemImage: "film.stack") {
            Picker("Kind", selection: $filters.kind) {
                Text("All Kinds").tag(MediaItem.Kind?.none)
                Text("Movies").tag(Optional(MediaItem.Kind.movie))
                Text("Series").tag(Optional(MediaItem.Kind.series))
            }
        }
    }

    private var sortMenu: some View {
        Menu("Sort", systemImage: "arrow.up.arrow.down") {
            Picker("Release Period", selection: $filters.releasePeriod) {
                ForEach(DiscoverReleasePeriod.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            if filters.releasePeriod == .chooseYear {
                Picker("Year", selection: $filters.selectedYear) {
                    Text("Any Year").tag(Int?.none)
                    ForEach(availableYears, id: \.self) { year in
                        Text(String(year)).tag(Optional(year))
                    }
                }
            }
            Divider()
            Picker("Sort", selection: $filters.sort) {
                ForEach(DiscoverDateSort.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
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

private struct AddonCatalogShelf: View {
    let addon: InstalledAddon
    let catalog: AddonCatalog
    let filters: DiscoverFilterState

    @State private var items: [MediaItem] = []
    @State private var didFinishLoading = false
    @State private var errorMessage: String?

    private var title: String { catalog.name?.trimmedNonEmpty ?? catalog.id }
    private var visibleItems: [MediaItem] {
        DiscoverFilterPresentation.apply(filters, to: items)
    }

    var body: some View {
        Group {
            if !visibleItems.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeaderLink(title: title) {
                        AddonCatalogBrowseView(addon: addon, catalog: catalog)
                    }
                    ShelfScrollView(items: visibleItems, itemSpan: MediaBrowseMetrics.shelfItemSpan, accessibilityLabel: title) { item in
                        MediaPoster(item: item)
                    }
                }
            } else if !didFinishLoading {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: title)
                    ProgressView().controlSize(.small)
                }
            } else if let errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: title)
                    Text(errorMessage).foregroundStyle(.secondary)
                    Button("Retry", systemImage: "arrow.clockwise") {
                        Task { await load() }
                    }
                }
            }
        }
        .task(id: "\(addon.id):\(catalog.id):\(addon.manifestURL.absoluteString)") {
            await load()
        }
    }

    private func load() async {
        didFinishLoading = false
        errorMessage = nil
        do {
            let metas = try await StremioAddonClient.fetchCatalog(from: addon, catalog: catalog)
            guard !Task.isCancelled else { return }
            items = metas.compactMap { $0.mediaItem(addon: addon) }
        } catch is CancellationError {
            return
        } catch {
            items = []
            errorMessage = "This add-on catalog is unavailable."
        }
        didFinishLoading = true
    }
}

private extension AddonCatalog {
    var mediaKind: MediaItem.Kind {
        type.lowercased() == "series" ? .series : .movie
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
