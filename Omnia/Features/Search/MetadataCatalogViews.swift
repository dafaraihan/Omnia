//
//  MetadataCatalogViews.swift
//  Omnia
//

import SwiftUI

/// A destination for a curated provider shelf. Keeping the destination as a
/// regular navigation page lets every Home and Discover row expose the same
/// simple affordance without manufacturing a second catalog model.
struct MetadataCatalogView: View {
    @Environment(\.displayPreferences) private var display
    let title: String
    let items: [MediaItem]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: MediaBrowseMetrics.posterGridColumns(display),
                alignment: .leading,
                spacing: MediaBrowseMetrics.gridRowSpacing
            ) {
                ForEach(items) { item in
                    MediaPoster(item: item, fillsAvailableWidth: true)
                }
            }
            .padding(.horizontal, MediaBrowseMetrics.pageInset)
            .padding(.vertical, 24)
        }
        .omniaNavigationTitle(title)
        .navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
    }

}

/// A provider-backed catalog that requests the next page only after its last
/// card is visible. The Edge Function serves the seeded Supabase pool first
/// and extends it on demand, so this view never needs to preload thousands of
/// images into memory.
struct PagedMetadataCatalogView: View {
    @Environment(\.displayPreferences) private var display
    @Environment(LiveMetadataStore.self) private var metadata

    let title: String
    let type: MediaType
    let category: MetadataCatalogCategory
    var genreID: Int? = nil

    @State private var items: [MediaItem] = []
    @State private var nextPage = 1
    @State private var isLoading = false
    @State private var hasReachedEnd = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: MediaBrowseMetrics.posterGridColumns(display),
                alignment: .leading,
                spacing: MediaBrowseMetrics.gridRowSpacing
            ) {
                ForEach(items) { item in
                    MediaPoster(item: item, fillsAvailableWidth: true)
                }

                // The centered overlay is the only initial-load indicator.
                // A second spinner inside the empty grid was visible at the
                // upper-left while the same request was still in flight.
                if isLoading && !items.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else if !hasReachedEnd {
                    // Keyed to the count so it asks again after each page;
                    // a plain `.task` ran once and the page stopped growing.
                    Color.clear
                        .frame(height: 1)
                        .task(id: items.count) {
                            await Task { await loadNextPage() }.value
                        }
                }
            }
            .padding(.horizontal, MediaBrowseMetrics.pageInset)
            .padding(.vertical, 24)
        }
        .overlay {
            if items.isEmpty && isLoading {
                ProgressView("Finding titles…")
            } else if items.isEmpty && hasReachedEnd {
                ContentUnavailableView(
                    "No Titles Available",
                    systemImage: "film.stack",
                    description: Text("Try another catalog or check your connection.")
                )
            }
        }
        .omniaNavigationTitle(title)
        .navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
        .task(id: requestKey) {
            items = []
            nextPage = 1
            hasReachedEnd = false
            await loadNextPage()
        }
    }

    private var requestKey: String { "\(type.rawValue):\(category.rawValue):\(genreID ?? 0)" }

    private func loadNextPage() async {
        guard !isLoading, !hasReachedEnd else { return }
        isLoading = true
        let page = nextPage
        let fetched = await metadata.catalogPage(type: type, category: category, genreID: genreID, page: page)
        let existing = Set(items.map(\.id))
        let unique = fetched.filter { !existing.contains($0.id) }
        if fetched.isEmpty || unique.isEmpty {
            hasReachedEnd = true
        } else {
            items.append(contentsOf: unique)
            nextPage += 1
        }
        isLoading = false
    }

}

/// A Browse by Genre card: every genre in `BrowseGenre`, then Anime.
private enum GenreTile: Identifiable, Hashable {
    case genre(BrowseGenre)
    case anime

    static var all: [GenreTile] { BrowseGenre.allCases.map(GenreTile.genre) + [.anime] }

    var id: String {
        switch self {
        case .genre(let genre): genre.id
        case .anime: "anime"
        }
    }
}

private struct GenreTileLink: View {
    let tile: GenreTile
    var width: CGFloat?

    var body: some View {
        switch tile {
        case .genre(let genre):
            OmniaPageLink {
                GenreBrowseView(genre: genre)
            } label: {
                GenreCardLabel(title: genre.title, width: width) { GenreArtwork(genre: genre) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Browse \(genre.title)")
        case .anime:
            OmniaPageLink {
                AnimeDiscoveryView()
            } label: {
                GenreCardLabel(title: "Anime", width: width) { AnimeGenreArtwork() }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Browse Anime")
        }
    }
}

/// Search opens into the same native navigation destinations as the rest of
/// the app. Anime is a browse category here rather than a peer sidebar tab.
struct SearchBrowseDirectoryView: View {
    @Environment(\.displayPreferences) private var display
    var recentSearches: [String] = []
    var onSelectRecent: (String) -> Void = { _ in }
    var onRemoveRecent: (String) -> Void = { _ in }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if !recentSearches.isEmpty {
                    RecentSearchesSection(
                        searches: recentSearches,
                        onSelect: onSelectRecent,
                        onRemove: onRemoveRecent
                    )
                    .padding(.bottom, 12)
                }

                Text("Browse by Genre")
                    .font(.title2.weight(.bold))

                LazyVGrid(
                    columns: [GridItem(
                        .adaptive(minimum: display.posterCardWidth, maximum: .infinity),
                        spacing: MediaBrowseMetrics.gridSpacing,
                        alignment: .top
                    )],
                    alignment: .leading,
                    spacing: MediaBrowseMetrics.gridSpacing
                ) {
                    ForEach(GenreTile.all) { tile in
                        GenreTileLink(tile: tile)
                    }
                }
            }
            .padding(.horizontal, MediaBrowseMetrics.pageInset)
            .padding(.vertical, 24)
        }
    }
}

/// Browse by Genre as one row of cards for Discover, sized and spaced like
/// the poster shelves below it (Dafa, 2026-10-22).
struct GenreDirectoryShelf: View {
    @Environment(\.displayPreferences) private var display

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browse by Genre")
                .font(.title2.weight(.bold))
            ShelfScrollView(
                items: GenreTile.all,
                itemSpan: display.posterCardWidth + MediaBrowseMetrics.shelfSpacing,
                accessibilityLabel: "Browse by Genre"
            ) { tile in
                GenreTileLink(tile: tile, width: display.posterCardWidth)
            }
        }
    }
}

/// Nuvio's Recent Searches list: tap one to search again, or remove it.
struct RecentSearchesSection: View {
    let searches: [String]
    let onSelect: (String) -> Void
    let onRemove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent Searches")
                .font(.title2.weight(.bold))
                .padding(.bottom, 8)

            ForEach(searches, id: \.self) { search in
                HStack(spacing: 12) {
                    Button {
                        onSelect(search)
                    } label: {
                        Label {
                            Text(search)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } icon: {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button("Remove Recent Search", systemImage: "xmark") {
                        onRemove(search)
                    }
                    .buttonStyle(.plain)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)

                if search != searches.last {
                    Divider()
                }
            }
        }
    }
}
