//
//  SearchView.swift
//  Omnia
//

import SwiftUI

struct SearchView: View {
    @Environment(OmniaStore.self) private var store
    @Environment(LiveMetadataStore.self) private var metadata
    @State private var query = ""
    @State private var addonResults: [MediaItem] = []
    @State private var isSearchingAddons = false

    private var results: [MediaItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 2 ? unique(metadata.searchResults + addonResults) : topSearchCards
    }

    /// Search opens into provider discovery—not a user's private library—so
    /// the empty query is immediately useful even for a first-launch account.
    private var topSearchCards: [MediaItem] {
        let candidates = metadata.topMovies
            + metadata.topSeries
            + metadata.movieCatalog
            + metadata.seriesCatalog
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.id).inserted }.prefix(40).map { $0 }
    }

    var body: some View {
        Group {
            if metadata.isSearching || isSearchingAddons {
                ContentUnavailableView("Searching Omnia", systemImage: "magnifyingglass")
            } else if results.isEmpty, query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                ContentUnavailableView.search(text: query)
            } else if results.isEmpty {
                ContentUnavailableView(
                    "Explore Top Titles",
                    systemImage: "magnifyingglass",
                    description: Text("Discovery cards will appear here as Omnia loads metadata.")
                )
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: minimumCardWidth), spacing: 18)],
                        alignment: .leading,
                        spacing: 26
                    ) {
                        ForEach(results) { item in
                            MediaPoster(item: item, fillsAvailableWidth: true)
                        }
                    }
                    .padding(.horizontal, horizontalInset)
                    .padding(.vertical, 24)
                }
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Titles, people, or genres")
        .task(id: query) {
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 2 else {
                metadata.searchResults = []
                addonResults = []
                isSearchingAddons = false
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            isSearchingAddons = true
            async let metadataSearch: Void = metadata.search(query)
            let addonMatches = await StremioAddonClient.searchCatalogs(
                addons: store.installedAddons,
                query: text
            )
            await metadataSearch
            guard !Task.isCancelled,
                  text == query.trimmingCharacters(in: .whitespacesAndNewlines)
            else { return }
            addonResults = unique(addonMatches.map(\.item))
            isSearchingAddons = false
        }
        .searchSuggestions {
            ForEach(store.library.prefix(3)) { item in
                Text(item.title).searchCompletion(item.title)
            }
        }
        .navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
    }

    private var minimumCardWidth: CGFloat {
        #if os(iOS)
        132
        #else
        154
        #endif
    }

    private var horizontalInset: CGFloat {
        #if os(iOS)
        20
        #else
        32
        #endif
    }

    private func unique(_ items: [MediaItem]) -> [MediaItem] {
        var seen = Set<String>()
        return items.filter { item in
            let identity = item.externalIDs["imdb"] ?? item.metadataProviderID ?? item.id
            return seen.insert(identity).inserted
        }
    }
}

#Preview {
    NavigationStack { SearchView() }
        .environment(OmniaStore.preview)
        .environment(LiveMetadataStore.preview)
}
