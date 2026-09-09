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

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var results: [MediaItem] {
        unique(metadata.searchResults + addonResults)
    }

    var body: some View {
        Group {
            if trimmedQuery.count < 2 {
                SearchBrowseDirectoryView(genres: metadata.movieGenres)
            } else if metadata.isSearching || isSearchingAddons {
                ContentUnavailableView("Searching Omnia", systemImage: "magnifyingglass")
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                GeometryReader { proxy in
                    let layout = MediaBrowseMetrics.posterGridLayout(containerWidth: proxy.size.width)

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
        .omniaNavigationTitle("Search", screen: .search)
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
