//
//  SearchView.swift
//  Omnia
//

import SwiftUI

enum SearchViewPresentation {
    case fullPage
    /// Results only, for Discover's search field (Dafa, 2026-10-22).
    case embedded
    #if os(macOS)
    case popover
    #endif
}

/// The latest answers for recent searches, in memory only, so going back to
/// a word (or deleting a letter) doesn't start from an empty page.
@MainActor
private enum SearchResultMemory {
    private static var entries: [String: (date: Date, items: [MediaItem])] = [:]
    private static let limit = 24
    private static let maximumAge: TimeInterval = 5 * 60

    static func key(query: String, source: SearchFilterPreferences.Source, addons: [InstalledAddon]) -> String {
        "\(query.lowercased())|\(source)|\(addons.filter(\.isEnabled).map(\.id).joined(separator: ","))"
    }

    static func results(for key: String) -> [MediaItem]? {
        guard let entry = entries[key], Date.now.timeIntervalSince(entry.date) < maximumAge else { return nil }
        return entry.items
    }

    static func remember(_ items: [MediaItem], for key: String) {
        entries[key] = (.now, items)
        if entries.count > limit, let oldest = entries.min(by: { $0.value.date < $1.value.date })?.key {
            entries[oldest] = nil
        }
    }
}

struct SearchView: View {
    @Environment(\.displayPreferences) private var display
    @Environment(OmniaStore.self) private var store
    @Environment(LiveMetadataStore.self) private var metadata
    @Environment(SettingsPreferencesStore.self) private var settings
    @State private var ownQuery = ""
    /// Discover's search text when embedded there.
    private let externalQuery: Binding<String>?
    @State private var history = SearchHistoryStore.shared
    @State private var addonResults: [MediaItem] = []
    @State private var isSearchingAddons = false
    /// Titles like the best match and titles its lead actors appear in,
    /// shown after the matches themselves.
    @State private var relatedResults: [MediaItem] = []
    @State private var searchedSource: SearchFilterPreferences.Source = .all
    #if os(macOS)
    @FocusState private var isPopoverSearchFocused: Bool
    #endif

    let presentation: SearchViewPresentation

    init(presentation: SearchViewPresentation = .fullPage) {
        self.presentation = presentation
        externalQuery = nil
    }

    /// The results for Discover's search field.
    init(query: Binding<String>) {
        presentation = .embedded
        externalQuery = query
    }

    private var queryBinding: Binding<String> { externalQuery ?? $ownQuery }

    private var query: String { queryBinding.wrappedValue }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filters: SearchFilterPreferences {
        settings.preferences.searchFilters
    }

    /// The chosen source, or every source when the chosen add-on is no
    /// longer installed or has no search catalog.
    private var source: SearchFilterPreferences.Source {
        if case let .addon(id) = filters.source,
           !SearchFilterChoices.searchableAddons(store.installedAddons).contains(where: { $0.id == id }) {
            return .all
        }
        return filters.source
    }

    private var includesMetadata: Bool {
        source == .all || source == .metadata
    }

    /// Every title found, before Kind and Genre.
    private var unfilteredResults: [MediaItem] {
        let found = addonResults + (includesMetadata ? metadata.searchResults : [])
        let matches = SearchResultRanking.ranked(SearchResultRanking.unique(found), query: trimmedQuery)
        return SearchResultRanking.unique(matches + (includesMetadata ? relatedResults : []))
    }

    /// The title asked for first, then other titles whose names match,
    /// then similar titles and the lead actors' titles, each title once,
    /// keeping the chosen kind and genre.
    private var results: [MediaItem] {
        unfilteredResults.filter(filters.keeps)
    }

    private struct SearchRequest: Hashable {
        let source: SearchFilterPreferences.Source
        let query: String
        let addons: [InstalledAddon]
    }

    private var searchKey: SearchRequest {
        SearchRequest(source: source, query: query, addons: store.installedAddons)
    }

    var body: some View {
        presentedContent
        .task(id: searchKey) {
            let request = searchKey
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            relatedResults = []
            guard text.count >= 2 else {
                metadata.searchResults = []
                addonResults = []
                isSearchingAddons = false
                return
            }
            // Words searched moments ago show at once, then refresh below.
            let cacheKey = SearchResultMemory.key(query: text, source: source, addons: store.installedAddons)
            if let remembered = SearchResultMemory.results(for: cacheKey) {
                addonResults = remembered
            }
            // Each search asks every add-on search catalog, so wait until typing
            // pauses rather than searching on every few keystrokes.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            isSearchingAddons = true
            // Only the chosen source is asked. Results from the previous
            // source go as soon as the source changes.
            let chosenSource = self.source
            if chosenSource != searchedSource {
                addonResults = []
                searchedSource = chosenSource
            }
            let addons: [InstalledAddon]
            switch chosenSource {
            case .all: addons = store.installedAddons
            case let .addon(id): addons = store.installedAddons.filter { $0.id == id }
            case .metadata, .mediaServers: addons = []
            }
            let searchesMetadata = chosenSource == .all || chosenSource == .metadata
            let searchesServers = chosenSource == .all || chosenSource == .mediaServers
            let metadataSearch = Task {
                if searchesMetadata { await metadata.search(text) }
            }
            let serverMatches = Task { () -> [MediaItem] in
                searchesServers ? await MediaServerStore.shared.search(text) : []
            }
            // Each add-on's results show as soon as it answers.
            let addonMatches = addons.isEmpty ? [] : await StremioAddonClient.searchCatalogs(
                addons: addons,
                query: text
            ) { found in
                guard !Task.isCancelled,
                      request == searchKey
                else { return }
                addonResults = SearchResultRanking.unique(found.map(\.item))
            }
            await metadataSearch.value
            let serverItems = await serverMatches.value
            guard !Task.isCancelled,
                  request == searchKey
            else { return }
            addonResults = SearchResultRanking.unique(addonMatches.map(\.item) + serverItems)
            SearchResultMemory.remember(addonResults, for: cacheKey)
            isSearchingAddons = false
            if !results.isEmpty { history.record(text) }
            if searchesMetadata { await loadRelatedResults(for: text) }
        }
        .modifier(SearchDetailDestination(isEmbedded: presentation == .embedded))
    }

    @ViewBuilder
    private var presentedContent: some View {
        switch presentation {
        case .embedded:
            searchContent
        case .fullPage:
            #if os(macOS)
            // The Filter button sits just before the search field, as its
            // own toolbar item (Dafa, 2026-10-22).
            searchContent
                .omniaNavigationTitle("Search", screen: .search)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        OmniaToolbarSymbol {
                        SearchFilterMenu()
                        }
                    }
                    ToolbarSpacer(.fixed, placement: .primaryAction)
                    ToolbarItem(placement: .primaryAction) {
                        OmniaToolbarSymbol {
                        MacSettingsSearchField(text: queryBinding, prompt: "Titles, people, or genres")
                            .frame(width: 340)
                        }
                    }
                }
            #else
            searchContent
                .omniaNavigationTitle("Search", screen: .search)
                .searchable(text: queryBinding, placement: .navigationBarDrawer(displayMode: .always), prompt: "Titles, people, or genres")
                .searchSuggestions {
                    ForEach(store.library.prefix(3)) { item in
                        Text(item.title).searchCompletion(item.title)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        OmniaToolbarSymbol {
                        SearchFilterMenu()
                        }
                    }
                }
            #endif
        #if os(macOS)
        case .popover:
            VStack(spacing: 0) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    TextField("Titles, people, or genres", text: queryBinding)
                        .textFieldStyle(.plain)
                        .focused($isPopoverSearchFocused)

                    if !query.isEmpty {
                        Button("Clear Search", systemImage: "xmark.circle.fill") {
                            queryBinding.wrappedValue = ""
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .labelStyle(.iconOnly)
                    }

                    SearchFilterMenu()
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(.regularMaterial, in: Capsule())
                .padding(16)

                Divider()

                // Fill the rest of the popover so short states such as
                // "Searching" don't shrink the stack and let it centre,
                // which dropped the field into the middle of the popover.
                searchContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 1040, height: 760, alignment: .top)
            .background(.black.opacity(0.18))
            .onAppear {
                isPopoverSearchFocused = true
            }
        #endif
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        Group {
            if trimmedQuery.count < 2 {
                SearchBrowseDirectoryView(
                    recentSearches: trimmedQuery.isEmpty ? history.recentSearches : [],
                    onSelectRecent: { queryBinding.wrappedValue = $0 },
                    onRemoveRecent: { history.remove($0) }
                )
            } else if (metadata.isSearching || isSearchingAddons) && results.isEmpty {
                // Keep earlier results on screen while the next query runs;
                // only an empty result set shows the spinner.
                OmniaLoadingRow("Searching…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty, filters.isFiltered, !unfilteredResults.isEmpty {
                ContentUnavailableView(
                    "No Matches for These Filters",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("\(unfilteredResults.count) results are hidden by Kind or Genre.")
                )
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                GeometryReader { proxy in
                    let layout = MediaGridLayout.fitting(
                        containerWidth: proxy.size.width,
                        horizontalInset: MediaBrowseMetrics.pageInset,
                        minimumItemWidth: display.landscapePosters ? display.landscapePosterCardWidth : display.posterCardWidth,
                        maximumItemWidth: .greatestFiniteMagnitude,
                        spacing: MediaBrowseMetrics.gridSpacing
                    )
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(
                            columns: layout.columns,
                            alignment: .center,
                            spacing: 18
                        ) {
                            ForEach(results) { item in
                                MediaPoster(item: item, fillsAvailableWidth: true)
                            }
                        }
                        .padding(.horizontal, MediaBrowseMetrics.pageInset)
                        .padding(.vertical, 24)
                    }
                }
            }
        }
    }

    /// For a search that names a title exactly: its similar and recommended
    /// titles, then what its first three cast members are known for.
    private func loadRelatedResults(for text: String) async {
        let candidates = SearchResultRanking.unique(addonResults + metadata.searchResults)
        guard let exact = candidates.first(where: { SearchResultRanking.tier(of: $0, query: text) == 0 })
        else { return }
        let details = await metadata.details(for: exact).details
        guard !Task.isCancelled, let details else { return }
        var related = details.similar + details.recommendations
        relatedResults = related
        for credit in details.cast.prefix(3) where Int(credit.id) != nil {
            guard let page = try? await metadata.person(id: credit.id), !Task.isCancelled else { continue }
            related += page.cast.prefix(12).map(\.item)
            relatedResults = related
        }
    }
}

/// Ordering and de-duplication for Search. Add-ons, media servers and the
/// metadata service often return one title under several IDs, so a title
/// counts as seen when it shares any ID, or its name, year and kind, with
/// one already listed.
enum SearchResultRanking {
    static func unique(_ items: [MediaItem]) -> [MediaItem] {
        var kept: [MediaItem] = []
        var seenKeys = Set<String>()
        for item in items {
            let keys = item.identityKeys.union([item.id, nameKey(item)])
            guard seenKeys.isDisjoint(with: keys) else { continue }
            seenKeys.formUnion(keys)
            kept.append(item)
        }
        return kept
    }

    /// 0: the name is the search. 1: it starts with the search. 2: it has
    /// every word of the search. 3: anything else, such as a match on cast.
    static func tier(of item: MediaItem, query: String) -> Int {
        let title = normalized(item.title)
        let search = normalized(query)
        guard !search.isEmpty else { return 3 }
        if title == search { return 0 }
        if title.hasPrefix(search) { return 1 }
        let words = search.split(separator: " ")
        if words.allSatisfy({ title.contains($0) }) { return 2 }
        return 3
    }

    /// Sorted by tier, keeping each source's own order within a tier.
    static func ranked(_ items: [MediaItem], query: String) -> [MediaItem] {
        items.enumerated()
            .sorted { lhs, rhs in
                let left = tier(of: lhs.element, query: query)
                let right = tier(of: rhs.element, query: query)
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element)
    }

    private static func nameKey(_ item: MediaItem) -> String {
        let year = item.year.prefix { $0.isNumber }
        return "name:\(item.kind.rawValue):\(normalized(item.title)):\(year)"
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ")
            .joined(separator: " ")
    }
}

/// Discover already declares where a title opens, so embedded results
/// don't declare it again.
private struct SearchDetailDestination: ViewModifier {
    let isEmbedded: Bool

    func body(content: Content) -> some View {
        if isEmbedded {
            content
        } else {
            content.navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
        }
    }
}

/// The sources, kinds and genres Search can be narrowed to.
enum SearchFilterChoices {
    /// Enabled add-ons with at least one search catalog.
    static func searchableAddons(_ addons: [InstalledAddon]) -> [InstalledAddon] {
        addons.filter { $0.isEnabled && $0.manifest.catalogs.contains(where: \.supportsSearch) }
    }

    /// The same genres as Browse by Genre, plus a choice saved before that
    /// list existed so it stays visible and can be cleared.
    static func genres(selected: String?) -> [String] {
        var names = BrowseGenre.allCases.map(\.title)
        if let selected, BrowseGenre(name: selected) == nil { names.append(selected) }
        return names
    }

    /// Named after the providers Metadata routes to, such as
    /// "Metadata (TMDB, TVDB, AniList)".
    static func metadataTitle(_ metadata: LiveMetadataStore) -> String {
        let routing = metadata.metadataRouting
        var names: [String] = []
        for provider in [routing.movies.primary, routing.series.primary, routing.anime.primary]
        where !names.contains(provider.title) {
            names.append(provider.title)
        }
        return "Metadata (\(names.joined(separator: ", ")))"
    }

    static func sourceTitle(
        _ source: SearchFilterPreferences.Source,
        addons: [InstalledAddon],
        metadata: LiveMetadataStore
    ) -> String {
        switch source {
        case .all: "All Sources"
        case .metadata: metadataTitle(metadata)
        case .mediaServers: "Media Servers"
        case let .addon(id): addons.first { $0.id == id }?.displayName ?? "Removed Add-on"
        }
    }

    static func kindTitle(_ kind: MediaItem.Kind?) -> String {
        switch kind {
        case nil: "All Kinds"
        case .movie: "Movies"
        case .series: "Series"
        case .episode: "Episodes"
        }
    }
}

/// The Search page's Filter menu: Source, Kind and Genre, the same choices
/// as Settings › Content & Discovery.
struct SearchFilterMenu: View {
    @Environment(OmniaStore.self) private var store
    @Environment(LiveMetadataStore.self) private var metadata
    @Environment(SettingsPreferencesStore.self) private var settings

    private var filters: SearchFilterPreferences { settings.preferences.searchFilters }

    var body: some View {
        Menu {
            // In a menu, a Picker is its own submenu titled with its label.
            Picker(selection: settings.binding(\.searchFilters.source)) {
                Text("All Sources").tag(SearchFilterPreferences.Source.all)
                Text(SearchFilterChoices.metadataTitle(metadata)).tag(SearchFilterPreferences.Source.metadata)
                if !MediaServerStore.shared.connections.isEmpty {
                    Text("Media Servers").tag(SearchFilterPreferences.Source.mediaServers)
                }
                let addons = SearchFilterChoices.searchableAddons(store.installedAddons)
                if !addons.isEmpty {
                    Divider()
                    ForEach(addons) { addon in
                        Text(addon.displayName).tag(SearchFilterPreferences.Source.addon(addon.id))
                    }
                }
            } label: {
                Label("Source", systemImage: "square.stack.3d.up")
            }
            .pickerStyle(.menu)

            Picker(selection: settings.binding(\.searchFilters.kind)) {
                ForEach([MediaItem.Kind?.none, .movie, .series], id: \.self) { kind in
                    Text(SearchFilterChoices.kindTitle(kind)).tag(kind)
                }
            } label: {
                Label("Kind", systemImage: "film.stack")
            }
            .pickerStyle(.menu)

            Picker(selection: settings.binding(\.searchFilters.genre)) {
                Text("All Genres").tag(String?.none)
                ForEach(SearchFilterChoices.genres(selected: filters.genre), id: \.self) { genre in
                    Text(genre).tag(Optional(genre))
                }
            } label: {
                Label("Genre", systemImage: "theatermasks")
            }
            .pickerStyle(.menu)

            if filters.isFiltered {
                Divider()
                Button("Reset Filters", systemImage: "arrow.counterclockwise") {
                    settings.update { $0.searchFilters = .default }
                }
            }
        } label: {
            Label(
                "Filter",
                systemImage: filters.isFiltered
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
        .help("Filter Search")
    }
}

#Preview {
    NavigationStack { SearchView() }
        .environment(OmniaStore.preview)
        .environment(LiveMetadataStore.preview)
}
