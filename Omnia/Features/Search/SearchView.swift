//
//  SearchView.swift
//  Omnia
//

import SwiftUI

enum SearchViewPresentation {
    case fullPage
    #if os(macOS)
    case popover
    #endif
}

struct SearchView: View {
    @Environment(\.displayPreferences) private var display
    @Environment(OmniaStore.self) private var store
    @Environment(LiveMetadataStore.self) private var metadata
    @State private var query = ""
    @State private var history = SearchHistoryStore.shared
    @State private var addonResults: [MediaItem] = []
    @State private var isSearchingAddons = false
    /// Titles like the best match and titles its lead actors appear in,
    /// shown after the matches themselves.
    @State private var relatedResults: [MediaItem] = []
    #if os(macOS)
    @FocusState private var isPopoverSearchFocused: Bool
    #endif

    let presentation: SearchViewPresentation

    init(presentation: SearchViewPresentation = .fullPage) {
        self.presentation = presentation
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The title asked for first, then other titles whose names match,
    /// then similar titles and the lead actors' titles, each title once.
    private var results: [MediaItem] {
        let matches = SearchResultRanking.ranked(
            SearchResultRanking.unique(addonResults + metadata.searchResults),
            query: trimmedQuery
        )
        return SearchResultRanking.unique(matches + relatedResults)
    }

    var body: some View {
        presentedContent
        .task(id: query) {
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            relatedResults = []
            guard text.count >= 2 else {
                metadata.searchResults = []
                addonResults = []
                isSearchingAddons = false
                return
            }
            // Each search asks every add-on search catalog, so wait until typing
            // pauses rather than searching on every few keystrokes.
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            isSearchingAddons = true
            async let metadataSearch: Void = metadata.search(query)
            async let serverMatches = MediaServerStore.shared.search(text)
            let addonMatches = await StremioAddonClient.searchCatalogs(
                addons: store.installedAddons,
                query: text
            )
            await metadataSearch
            let serverItems = await serverMatches
            guard !Task.isCancelled,
                  text == query.trimmingCharacters(in: .whitespacesAndNewlines)
            else { return }
            addonResults = SearchResultRanking.unique(addonMatches.map(\.item) + serverItems)
            isSearchingAddons = false
            if !results.isEmpty { history.record(text) }
            await loadRelatedResults(for: text)
        }
        .navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
    }

    @ViewBuilder
    private var presentedContent: some View {
        switch presentation {
        case .fullPage:
            searchContent
                .omniaNavigationTitle("Search", screen: .search)
                .searchable(text: $query, prompt: "Titles, people, or genres")
                .searchSuggestions {
                    ForEach(store.library.prefix(3)) { item in
                        Text(item.title).searchCompletion(item.title)
                    }
                }
        #if os(macOS)
        case .popover:
            VStack(spacing: 0) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    TextField("Titles, people, or genres", text: $query)
                        .textFieldStyle(.plain)
                        .focused($isPopoverSearchFocused)

                    if !query.isEmpty {
                        Button("Clear Search", systemImage: "xmark.circle.fill") {
                            query = ""
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .labelStyle(.iconOnly)
                    }
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
                    genres: metadata.movieGenres,
                    recentSearches: trimmedQuery.isEmpty ? history.recentSearches : [],
                    onSelectRecent: { query = $0 },
                    onRemoveRecent: { history.remove($0) }
                )
            } else if (metadata.isSearching || isSearchingAddons) && results.isEmpty {
                // Keep earlier results on screen while the next query runs;
                // only an empty result set shows the spinner.
                ProgressView("Searching…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                GeometryReader { proxy in
                    let layout = MediaBrowseMetrics.posterGridLayout(containerWidth: proxy.size.width, display: display)

                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(
                            columns: layout.columns,
                            alignment: .leading,
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

#Preview {
    NavigationStack { SearchView() }
        .environment(OmniaStore.preview)
        .environment(LiveMetadataStore.preview)
}
