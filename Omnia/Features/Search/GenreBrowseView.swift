//
//  GenreBrowseView.swift
//  Omnia
//

import SwiftUI

/// What a Browse by Genre page lists: one of Omnia's genres, or Anime.
nonisolated enum GenreBrowseTopic: Hashable, Sendable {
    case genre(BrowseGenre)
    case anime

    var title: String {
        switch self {
        case .genre(let genre): genre.title
        case .anime: "Anime"
        }
    }

    var key: String {
        switch self {
        case .genre(let genre): genre.rawValue
        case .anime: "anime"
        }
    }

    /// The option an add-on catalog offers for this topic, if any.
    func option(in options: [String]) -> String? {
        switch self {
        case .genre(let genre):
            genre.option(in: options)
        case .anime:
            options.first {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .compare("Anime", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
        }
    }
}

/// A Browse by Genre page. Titles come from the user's own add-on catalogs
/// that offer this genre, with the add-on's posters, and from Omnia's
/// metadata only when no add-on offers it. More titles load at the bottom,
/// and Filter narrows the page by kind and catalog and sorts it
/// (Dafa, 2026-10-22). Anime uses the same page: add-on anime catalogs,
/// then Omnia's anime route when none are installed (Dafa, 2026-10-26).
struct GenreBrowseView: View {
    @Environment(\.displayPreferences) private var display
    @Environment(OmniaStore.self) private var store
    @Environment(LiveMetadataStore.self) private var metadata

    let topic: GenreBrowseTopic

    @State private var kind: MediaItem.Kind?
    /// Empty means the default sources: add-on catalogs when any offer this
    /// genre, otherwise Omnia's metadata.
    @State private var selectedSourceIDs: Set<String> = []
    @State private var sort: DiscoverDateSort = .catalogOrder
    @State private var feed = GenreBrowseFeed()

    init(topic: GenreBrowseTopic) {
        self.topic = topic
    }

    init(genre: BrowseGenre) {
        self.init(topic: .genre(genre))
    }

    /// The page's sources, worked out once per update. Listing them walks
    /// every catalog of every add-on, so the menu, the empty state and the
    /// request key share this instead of each listing them again.
    private struct SourcePlan {
        let all: [GenreBrowseSource]
        let defaultIDs: Set<String>
        let chosenIDs: Set<String>
        let active: [GenreBrowseSource]

        var requestKey: String { active.map(\.id).joined(separator: ",") }
    }

    private func sourcePlan() -> SourcePlan {
        let all = GenreBrowseSource.all(for: topic, store: store, metadata: metadata)
        let addonSources = all.filter(\.isAddon)
        let defaultIDs = Set((addonSources.isEmpty ? all : addonSources).map(\.id))
        let chosenIDs = selectedSourceIDs.isEmpty ? defaultIDs : selectedSourceIDs
        return SourcePlan(
            all: all,
            defaultIDs: defaultIDs,
            chosenIDs: chosenIDs,
            active: all.filter { chosenIDs.contains($0.id) && (kind == nil || $0.kind == kind) }
        )
    }

    var body: some View {
        let plan = sourcePlan()
        let visibleItems = DiscoverFilterPresentation.apply(DiscoverFilterState(kind: kind, sort: sort), to: feed.items)

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
                OmniaLoadingRow("Finding \(topic.title) titles…")
            } else if visibleItems.isEmpty && !feed.hasMore && !feed.isLoading {
                ContentUnavailableView {
                    Label("No \(topic.title) Titles", systemImage: "film.stack")
                } description: {
                    Text(plan.active.isEmpty
                         ? "None of your catalogs offer this genre for the chosen kind."
                         : "Try another kind or catalog, or check your connection.")
                } actions: {
                    if feed.didFail {
                        Button("Try Again", systemImage: "arrow.clockwise") {
                            feed.reset(sources: plan.active)
                        }
                    }
                }
            }
        }
        .omniaNavigationTitle(topic.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                filterMenu(plan)
            }
        }
        // Sorting only reorders what has loaded; kind and catalogs reload.
        .task(id: "\(topic.key)|\(plan.requestKey)") {
            feed.reset(sources: plan.active)
        }
        .navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
    }

    // MARK: Filter

    private func filterMenu(_ plan: SourcePlan) -> some View {
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
                ForEach(plan.all) { source in
                    Toggle(isOn: Binding(
                        get: { plan.chosenIDs.contains(source.id) },
                        set: { _ in toggle(source.id, in: plan) }
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
        .help("Filter and sort \(topic.title)")
    }

    private func toggle(_ id: String, in plan: SourcePlan) {
        var chosen = plan.chosenIDs
        if chosen.contains(id) {
            // Keep at least one catalog chosen.
            guard chosen.count > 1 else { return }
            chosen.remove(id)
        } else {
            chosen.insert(id)
        }
        selectedSourceIDs = chosen == plan.defaultIDs ? [] : chosen
    }
}

/// One place a genre page loads titles from.
nonisolated struct GenreBrowseSource: Identifiable, Sendable {
    enum Origin: Sendable {
        /// An add-on catalog, asked with its own name for the genre, or with
        /// no genre when the whole catalog is the topic (an anime catalog).
        case addon(InstalledAddon, AddonCatalog, genreOption: String?)
        /// Omnia's metadata catalog for a provider genre.
        case metadata(MediaType, genreID: Int)
        /// Omnia's anime route: AniList, TMDB or TVDB, as Settings orders them.
        case anime(MetadataCatalogCategory)
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
    static func all(for topic: GenreBrowseTopic, store: OmniaStore, metadata: LiveMetadataStore) -> [GenreBrowseSource] {
        var sources: [GenreBrowseSource] = []
        for addon in store.installedAddons where addon.isEnabled {
            for catalog in addon.manifest.catalogs where store.isCatalogEnabled(for: addon, catalog: catalog) {
                // A catalog that only answers searches can't list a genre.
                let needsSearch = catalog.extra?.contains { $0.name == "search" && $0.isRequired == true } == true
                guard !needsSearch else { continue }
                let genreOption: String?
                if let options = catalog.extra?.first(where: { $0.name == "genre" })?.options,
                   let option = topic.option(in: options) {
                    genreOption = option
                } else if topic == .anime, isAnimeCatalog(catalog) {
                    genreOption = nil
                } else {
                    continue
                }
                let extra = genreOption.map { ["genre": $0] } ?? [:]
                guard catalog.resolvingExtras(extra) != nil else { continue }
                let name = catalog.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                sources.append(GenreBrowseSource(
                    id: "addon:\(store.catalogID(for: addon, catalog: catalog))",
                    title: name.isEmpty ? catalog.id : name,
                    subtitle: addon.displayName,
                    kind: MediaItem.Kind(stremioType: catalog.type) ?? .movie,
                    origin: .addon(addon, catalog, genreOption: genreOption)
                ))
            }
        }
        if topic == .anime {
            sources += xperienceAnimeSources(store: store, listed: Set(sources.map(\.id)))
        }
        switch topic {
        case .genre(let genre):
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
        case .anime:
            let categories: [(MetadataCatalogCategory, String)] = [
                (.trending, "Trending Anime"),
                (.popular, "Popular Anime"),
                (.topRated, "Top Rated Anime")
            ]
            for (category, title) in categories {
                sources.append(GenreBrowseSource(
                    id: "anime:\(category.rawValue)",
                    title: title,
                    subtitle: "Omnia Metadata",
                    kind: .series,
                    origin: .anime(category)
                ))
            }
        }
        return sources
    }

    /// Xperience's anime catalogs. Its manifest lists only the catalogs
    /// picked in its web configuration, and none of those is anime unless
    /// chosen there, yet Xperience answers these for every configuration
    /// (as Home collections already rely on), with its posters.
    static let xperienceAnimeCatalogs: [(type: String, id: String, name: String)] = [
        ("series", "anime_trending_series", "Trending Anime"),
        ("movie", "anime_trending_movies", "Trending Anime Movies"),
        ("series", "anime_airing_series", "Airing Anime"),
        ("series", "anime_latest_series", "Latest Anime"),
        ("movie", "anime_latest_movies", "Latest Anime Movies"),
        ("series", "anime_toprated_series", "Top Rated Anime"),
        ("movie", "anime_toprated_movies", "Top Rated Anime Movies"),
        ("series", "anime_best_series", "Best Anime"),
        ("movie", "anime_best_movies", "Best Anime Movies"),
        ("series", "anime_upcoming_series", "Upcoming Anime"),
        ("movie", "anime_upcoming_movies", "Upcoming Anime Movies")
    ]

    @MainActor
    private static func xperienceAnimeSources(store: OmniaStore, listed: Set<String>) -> [GenreBrowseSource] {
        var sources: [GenreBrowseSource] = []
        for addon in store.installedAddons
        where addon.isEnabled && addon.manifest.id.hasPrefix("app.xperience.") && addon.manifest.supportsCatalogs {
            for entry in xperienceAnimeCatalogs {
                // A catalog the configuration already lists was added above.
                guard !addon.manifest.catalogs.contains(where: { $0.id == entry.id && $0.type == entry.type }) else { continue }
                let catalog = AddonCatalog(
                    type: entry.type,
                    id: entry.id,
                    name: entry.name,
                    extra: [AddonCatalogExtra(name: "skip", isRequired: false, options: nil, optionsLimit: nil)]
                )
                let id = "addon:\(store.catalogID(for: addon, catalog: catalog))"
                guard !listed.contains(id), store.isCatalogEnabled(for: addon, catalog: catalog) else { continue }
                sources.append(GenreBrowseSource(
                    id: id,
                    title: entry.name,
                    subtitle: addon.displayName,
                    kind: entry.type == "movie" ? .movie : .series,
                    origin: .addon(addon, catalog, genreOption: nil)
                ))
            }
        }
        return sources
    }

    /// Add-ons mark anime catalogs in different ways: AIOMetadata types them
    /// `anime`, `anime.series` or `anime.movie`; Xperience and others keep a
    /// series or movie type and say "Anime" in the catalog's name or id
    /// ("Trending Anime", `anime-popular`), or list an anime database
    /// (MyAnimeList, Kitsu, AniList, AniDB) in the id.
    static func isAnimeCatalog(_ catalog: AddonCatalog) -> Bool {
        let type = catalog.type.lowercased()
        if type == "anime" || type.hasPrefix("anime.") || type.hasSuffix(".anime") { return true }
        let words = [catalog.id, catalog.name ?? ""]
            .joined(separator: " ")
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
        let animeWords: Set<Substring> = ["anime", "animes", "mal", "myanimelist", "kitsu", "anilist", "anidb"]
        return words.contains { animeWords.contains($0) }
    }
}

/// The genre page's titles. Each page asks every chosen source for its next
/// page at once and shows each answer as it arrives, leaving out titles
/// already shown, so one slow add-on doesn't hold back the others.
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
            if case .addon = source.origin {
                Cursor(source: source, position: 0)
            } else {
                Cursor(source: source, position: 1)
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
        var failures = 0
        await withTaskGroup(of: (Int, Page).self) { group in
            for index in pending {
                let source = cursors[index].source
                let position = cursors[index].position
                group.addTask {
                    (index, await Self.fetch(source, position: position, metadata: metadata))
                }
            }
            for await (index, page) in group {
                guard requestGeneration == generation, !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                if page.failed { failures += 1 }
                add(page, from: index)
            }
        }
        guard requestGeneration == generation, !Task.isCancelled else { return }

        didFail = items.isEmpty && failures > 0
        hasMore = cursors.contains { !$0.isDone }
        loadedPages += 1
    }

    private func add(_ page: Page, from index: Int) {
        let fresh = page.items.filter { seenKeys.insert(Self.key(for: $0)).inserted }
        // An add-on that doesn't page sends its first page again.
        if page.received == 0 || fresh.isEmpty {
            cursors[index].isDone = true
            return
        }
        if case .addon = cursors[index].source.origin {
            cursors[index].position += page.received
        } else {
            cursors[index].position += 1
        }
        items.append(contentsOf: fresh)
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
            var extra: [String: String] = [:]
            if let option { extra["genre"] = option }
            if position > 0 { extra["skip"] = String(position) }
            guard let resolved = catalog.resolvingExtras(extra) else {
                return Page(items: [], received: 0, failed: true)
            }
            do {
                let metas = try await StremioAddonClient.fetchCatalog(from: addon, catalog: catalog, extra: resolved)
                return Page(items: metas.compactMap { $0.mediaItem(addon: addon) }, received: metas.count)
            } catch {
                return Page(items: [], received: 0, failed: true)
            }
        case .metadata(let type, let genreID):
            let items = await metadata.catalogPage(type: type, category: .popular, genreID: genreID, page: position)
            return Page(items: items, received: items.count)
        case .anime(let category):
            let items = await metadata.animeCatalogPage(category: category, page: position)
            return Page(items: items, received: items.count)
        }
    }

    /// The same title from two catalogs is shown once.
    private static func key(for item: MediaItem) -> String {
        let title = item.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return "\(item.kind)|\(title)|\(item.year)"
    }
}
