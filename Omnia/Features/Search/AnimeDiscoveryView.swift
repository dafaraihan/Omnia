//
//  AnimeDiscoveryView.swift
//  Omnia
//

import SwiftUI

/// Anime discovery follows the same browse grammar as Discover: a native
/// navigation title, platform toolbar, section links, shelf controls, and
/// Omnia's shared poster cards. The selected source is informational chrome,
/// never a parallel, custom-designed card.
struct AnimeDiscoveryView: View {
    @Environment(OmniaStore.self) private var store
    @Environment(LiveMetadataStore.self) private var metadata
    @State private var query = ""

    private var isSearching: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    var body: some View {
        Group {
            if isSearching {
                animeSearchResults
            } else {
                animeBrowse
            }
        }
        .omniaNavigationTitle("Anime")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Section("Primary Source") {
                        Label(store.metadataRouting.anime.primary.title, systemImage: sourceSymbol)
                    }
                    if store.metadataRouting.anime.fallbackEnabled,
                       !store.metadataRouting.anime.fallbackOrder.isEmpty {
                        Section("Fallback Sources") {
                            ForEach(store.metadataRouting.anime.fallbackOrder) { provider in
                                Label(provider.title, systemImage: "arrow.turn.down.right")
                            }
                        }
                    }
                } label: {
                    Label("Anime Sources", systemImage: "point.3.connected.trianglepath.dotted")
                }
            }
        }
        .searchable(text: $query, prompt: "Search anime")
        .task(id: query) {
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 2 else {
                metadata.searchResults = []
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await metadata.searchAnime(text)
        }
        .navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
    }

    private var animeBrowse: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 36) {
                if metadata.isLoadingCatalogs, metadata.animeCatalogs.isEmpty {
                    ProgressView("Finding anime…")
                        .frame(maxWidth: .infinity, minHeight: 280)
                } else if metadata.animeCatalogs.isEmpty {
                    ContentUnavailableView(
                        "Anime Discovery Is Unavailable",
                        systemImage: "sparkles.tv",
                        description: Text("Check your selected metadata source or try again in a moment.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    ForEach(metadata.animeCatalogs) { catalog in
                        AnimeCatalogShelf(catalog: catalog)
                    }
                }
            }
            .padding(.horizontal, MediaBrowseMetrics.pageInset)
            .padding(.vertical, 24)
        }
    }

    @ViewBuilder
    private var animeSearchResults: some View {
        if metadata.isSearching {
            ContentUnavailableView("Searching Anime", systemImage: "magnifyingglass")
        } else if metadata.searchResults.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: MediaBrowseMetrics.posterGridColumns,
                    alignment: .leading,
                    spacing: MediaBrowseMetrics.gridRowSpacing
                ) {
                    ForEach(metadata.searchResults) { item in
                        MediaPoster(item: item, fillsAvailableWidth: true)
                    }
                }
                .padding(.horizontal, MediaBrowseMetrics.pageInset)
                .padding(.vertical, 24)
            }
        }
    }

    private var sourceSymbol: String {
        store.metadataRouting.anime.primary == .anilist ? "sparkles" : "rectangle.stack.fill"
    }

}

private struct AnimeCatalogShelf: View {
    let catalog: BuiltInAnimeCatalog

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderLink(title: catalog.title) {
                PagedAnimeCatalogView(title: catalog.title, category: catalog.category)
            }
            ShelfScrollView(items: catalog.items, itemSpan: posterItemSpan, accessibilityLabel: catalog.title) { item in
                MediaPoster(item: item)
            }
        }
    }

    private var posterItemSpan: CGFloat {
        MediaBrowseMetrics.shelfItemSpan
    }
}

private struct PagedAnimeCatalogView: View {
    @Environment(LiveMetadataStore.self) private var metadata

    let title: String
    let category: MetadataCatalogCategory

    @State private var items: [MediaItem] = []
    @State private var nextPage = 1
    @State private var isLoading = false
    @State private var hasReachedEnd = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: MediaBrowseMetrics.posterGridColumns,
                alignment: .leading,
                spacing: MediaBrowseMetrics.gridRowSpacing
            ) {
                ForEach(items) { item in
                    MediaPoster(item: item, fillsAvailableWidth: true)
                }

                if isLoading && !items.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else if !hasReachedEnd {
                    Color.clear
                        .frame(height: 1)
                        .task { await loadNextPage() }
                }
            }
            .padding(.horizontal, MediaBrowseMetrics.pageInset)
            .padding(.vertical, 24)
        }
        .overlay {
            if items.isEmpty && isLoading {
                ProgressView("Finding anime…")
            } else if items.isEmpty && hasReachedEnd {
                ContentUnavailableView("No Anime Available", systemImage: "sparkles.tv")
            }
        }
        .omniaNavigationTitle(title)
        .navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
        .task(id: category.rawValue) {
            items = []
            nextPage = 1
            hasReachedEnd = false
            await loadNextPage()
        }
    }

    private func loadNextPage() async {
        guard !isLoading, !hasReachedEnd else { return }
        isLoading = true
        let fetched = await metadata.animeCatalogPage(category: category, genre: nil, page: nextPage)
        let existing = Set(items.map(\.id))
        let unique = fetched.filter { !existing.contains($0.id) }
        if unique.isEmpty {
            hasReachedEnd = true
        } else {
            items.append(contentsOf: unique)
            nextPage += 1
        }
        isLoading = false
    }

}

#Preview {
    NavigationStack { AnimeDiscoveryView() }
        .environment(OmniaStore.preview)
        .environment(LiveMetadataStore.preview)
}
