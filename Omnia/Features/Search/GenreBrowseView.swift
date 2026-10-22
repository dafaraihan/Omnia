//
//  GenreBrowseView.swift
//  Omnia
//

import SwiftUI

/// A Browse by Genre page. Titles come from the user's own add-on catalogs
/// that offer this genre, with the add-on's posters, and from Omnia's
/// metadata only when no add-on offers it. More titles load at the bottom,
/// and Filter narrows the page by kind and catalog and sorts it
/// (Dafa, 2026-10-22).
struct GenreBrowseView: View {
    @Environment(\.displayPreferences) private var display
    @Environment(OmniaStore.self) private var store
    @Environment(LiveMetadataStore.self) private var metadata

    let genre: BrowseGenre

    @State private var kind: MediaItem.Kind?
    /// Empty means the default sources: add-on catalogs when any offer this
    /// genre, otherwise Omnia's metadata.
    @State private var selectedSourceIDs: Set<String> = []
    @State private var sort: DiscoverDateSort = .catalogOrder
    @State private var feed = GenreBrowseFeed()

    private var sources: [GenreBrowseSource] {
        GenreBrowseSource.all(for: genre, store: store, metadata: metadata)
    }

    private var defaultSourceIDs: Set<String> {
        let addonSources = sources.filter(\.isAddon)
        return Set((addonSources.isEmpty ? sources : addonSources).map(\.id))
    }

    private var chosenSourceIDs: Set<String> {
        selectedSourceIDs.isEmpty ? defaultSourceIDs : selectedSourceIDs
    }

    private var activeSources: [GenreBrowseSource] {
        sources.filter { chosenSourceIDs.contains($0.id) && (kind == nil || $0.kind == kind) }
    }

    private var visibleItems: [MediaItem] {
        DiscoverFilterPresentation.apply(DiscoverFilterState(kind: kind, sort: sort), to: feed.items)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: MediaBrowseMetrics.posterGridColumns(display),
                alignment: .leading,
                spacing: MediaBrowseMetrics.gridRowSpacing
            ) {
                ForEach(visibleItems) { item in
                    MediaPoster(item: item, fillsAvailableWidth: true)
                }
            }

            // More titles load on their own at the bottom. Keyed to each
            // finished page, so it asks again even when a page added nothing
            // this filter shows. Not tied to the marker's own task, so
            // scrolling away mid-request doesn't cancel the page.
            if feed.hasMore {
                Color.clear
                    .frame(height: 1)
                    .task(id: "\(feed.generation)-\(feed.loadedPages)") {
                        await Task { await feed.loadNextPage(metadata: metadata) }.value
                    }
            }
            if feed.isLoading, !feed.items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        }
        .contentMargins(.horizontal, MediaBrowseMetrics.pageInset, for: .scrollContent)
        .contentMargins(.vertical, 24, for: .scrollContent)
        .overlay {
            if feed.items.isEmpty && feed.isLoading {
                ProgressView("Finding \(genre.title) titles…")
            } else if visibleItems.isEmpty && !feed.hasMore && !feed.isLoading {
                ContentUnavailableView {
                    Label("No \(genre.title) Titles", systemImage: "film.stack")
                } description: {
                    Text(activeSources.isEmpty
                         ? "None of your catalogs offer this genre for the chosen kind."
                         : "Try another kind or catalog, or check your connection.")
                } actions: {
                    if feed.didFail {
                        Button("Try Again", systemImage: "arrow.clockwise") {
                            feed.reset(sources: activeSources)
                        }
                    }
                }
            }
        }
        .omniaNavigationTitle(genre.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                filterMenu
            }
        }
        .task(id: requestKey) {
            feed.reset(sources: activeSources)
        }
        .navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
    }

    /// Sorting only reorders what has loaded; kind and catalogs reload.
    private var requestKey: String {
        "\(genre.rawValue)|\(activeSources.map(\.id).joined(separator: ","))"
    }

    // MARK: Filter

    private var filterMenu: some View {
        Menu {
            // In a menu, a Picker is already its own submenu.
            Picker(selection: $kind) {
                Text("All Kinds").tag(MediaItem.Kind?.none)
                Text("Movies").tag(Optional(MediaItem.Kind.movie))
                Text("Series").tag(Optional(MediaItem.Kind.series))
            } label: {
                Label("Kind", systemImage: "film.stack")
            }
            .pickerStyle(.menu)

            Menu("Catalogs", systemImage: "rectangle.stack") {
                Toggle("Default Catalogs", isOn: Binding(
                    get: { selectedSourceIDs.isEmpty },
                    set: { if $0 { selectedSourceIDs.removeAll() } }
                ))
                Divider()
                ForEach(sources) { source in
                    Toggle(isOn: Binding(
                        get: { chosenSourceIDs.contains(source.id) },
                        set: { _ in toggle(source.id) }
                    )) {
                        Text(source.title)
                        Text(source.subtitle)
                    }
                }
            }

            Picker(selection: $sort) {
                ForEach(DiscoverDateSort.allCases) { order in
                    Text(order.title).tag(order)
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .pickerStyle(.menu)
        } label: {
            Label("Filter and Sort", systemImage: "line.3.horizontal.decrease.circle")
        }
        .help("Filter and sort \(genre.title)")
    }

    private func toggle(_ id: String) {
        var chosen = chosenSourceIDs
        if chosen.contains(id) {
            // Keep at least one catalog chosen.
            guard chosen.count > 1 else { return }
            chosen.remove(id)
        } else {
            chosen.insert(id)
        }
        selectedSourceIDs = chosen == defaultSourceIDs ? [] : chosen
    }
}

/// One place a genre page loads titles from.
nonisolated struct GenreBrowseSource: Identifiable, Sendable {
    enum Origin: Sendable {
        /// An add-on catalog, asked with its own name for the genre.
        case addon(InstalledAddon, AddonCatalog, genreOption: String)
        /// Omnia's metadata catalog for a provider genre.
        case metadata(MediaType, genreID: Int)
    }

    let id: String
    let title: String
    let subtitle: String
    let kind: MediaItem.Kind
    let origin: Origin

    var isAddon: Bool {
        if case .addon = origin { true } else { false }
    }

    @MainActor
    static func all(for genre: BrowseGenre, store: OmniaStore, metadata: LiveMetadataStore) -> [GenreBrowseSource] {
        var sources: [GenreBrowseSource] = []
        for addon in store.installedAddons where addon.isEnabled {
            for catalog in addon.manifest.catalogs where store.isCatalogEnabled(for: addon, catalog: catalog) {
                // A catalog that only answers searches can't list a genre.
                let needsSearch = catalog.extra?.contains { $0.name == "search" && $0.isRequired == true } == true
                guard !needsSearch,
                      let options = catalog.extra?.first(where: { $0.name == "genre" })?.options,
                      let option = genre.option(in: options),
                      catalog.resolvingExtras(["genre": option]) != nil
                else { continue }
                let name = catalog.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                sources.append(GenreBrowseSource(
                    id: "addon:\(store.catalogID(for: addon, catalog: catalog))",
                    title: name.isEmpty ? catalog.id : name,
                    subtitle: addon.displayName,
                    kind: MediaItem.Kind(stremioType: catalog.type) ?? .movie,
                    origin: .addon(addon, catalog, genreOption: option)
                ))
            }
        }
        let metadataGenres: [(MediaType, MediaItem.Kind, [MetadataGenre])] = [
            (.movie, .movie, metadata.movieGenres),
            (.series, .series, metadata.seriesGenres)
        ]
        for (type, kind, genres) in metadataGenres {
            guard let match = genres.first(where: { genre.matches($0.name) }) else { continue }
            sources.append(GenreBrowseSource(
                id: "metadata:\(type.rawValue):\(match.id)",
                title: kind == .movie ? "Popular Movies" : "Popular Series",
                subtitle: "Omnia Metadata",
                kind: kind,
                origin: .metadata(type, genreID: match.id)
            ))
        }
        return sources
    }
}

/// The genre page's titles. Each page asks every chosen source for its next
/// page at once and adds the answers in source order, leaving out titles
/// already shown.
@Observable
@MainActor
final class GenreBrowseFeed {
    private(set) var items: [MediaItem] = []
    private(set) var isLoading = false
    private(set) var hasMore = false
    private(set) var didFail = false
    /// Counts finished pages; the bottom marker asks again after each.
    private(set) var loadedPages = 0
    /// Changes with each reset, so a page for old filters is dropped.
    private(set) var generation = 0

    private struct Cursor {
        let source: GenreBrowseSource
        /// `skip` for an add-on, the page number for Omnia's metadata.
        var position: Int
        var isDone = false
    }

    @ObservationIgnored private var cursors: [Cursor] = []
    @ObservationIgnored private var seenKeys = Set<String>()

    func reset(sources: [GenreBrowseSource]) {
        generation += 1
        cursors = sources.map { source in
            if case .metadata = source.origin {
                Cursor(source: source, position: 1)
            } else {
                Cursor(source: source, position: 0)
            }
        }
        items = []
        seenKeys = []
        isLoading = false
        didFail = false
        hasMore = !cursors.isEmpty
        loadedPages = 0
    }

    func loadNextPage(metadata: LiveMetadataStore) async {
        guard !isLoading, hasMore else { return }
        let requestGeneration = generation
        isLoading = true
        defer { if requestGeneration == generation { isLoading = false } }

        let pending = cursors.indices.filter { !cursors[$0].isDone }
        var pages: [Int: Page] = [:]
        await withTaskGroup(of: (Int, Page).self) { group in
            for index in pending {
                let source = cursors[index].source
                let position = cursors[index].position
                group.addTask {
                    (index, await Self.fetch(source, position: position, metadata: metadata))
                }
            }
            for await (index, page) in group {
                pages[index] = page
            }
        }
        guard requestGeneration == generation, !Task.isCancelled else { return }

        var failures = 0
        for index in pending {
            guard let page = pages[index] else { continue }
            if page.failed { failures += 1 }
            let fresh = page.items.filter { seenKeys.insert(Self.key(for: $0)).inserted }
            // An add-on that doesn't page sends its first page again.
            if page.received == 0 || fresh.isEmpty {
                cursors[index].isDone = true
                continue
            }
            if case .metadata = cursors[index].source.origin {
                cursors[index].position += 1
            } else {
                cursors[index].position += page.received
            }
            items.append(contentsOf: fresh)
        }
        didFail = items.isEmpty && failures > 0
        hasMore = cursors.contains { !$0.isDone }
        loadedPages += 1
    }

    private struct Page: Sendable {
        var items: [MediaItem]
        /// How many titles the source sent, before duplicates are removed.
        var received: Int
        var failed = false
    }

    private static func fetch(
        _ source: GenreBrowseSource,
        position: Int,
        metadata: LiveMetadataStore
    ) async -> Page {
        switch source.origin {
        case .addon(let addon, let catalog, let option):
            var extra = ["genre": option]
            if position > 0 { extra["skip"] = String(position) }
            do {
                let metas = try await StremioAddonClient.fetchCatalog(from: addon, catalog: catalog, extra: extra)
                return Page(items: metas.compactMap { $0.mediaItem(addon: addon) }, received: metas.count)
            } catch {
                return Page(items: [], received: 0, failed: true)
            }
        case .metadata(let type, let genreID):
            let items = await metadata.catalogPage(type: type, category: .popular, genreID: genreID, page: position)
            return Page(items: items, received: items.count)
        }
    }

    /// The same title from two catalogs is shown once.
    private static func key(for item: MediaItem) -> String {
        let title = item.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return "\(item.kind)|\(title)|\(item.year)"
    }
}
