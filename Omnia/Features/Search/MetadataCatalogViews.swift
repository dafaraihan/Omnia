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

struct GenreCatalogView: View {
    @Environment(LiveMetadataStore.self) private var metadata

    let genre: MetadataGenre
    let type: MediaType
    let titleOverride: String?

    init(genre: MetadataGenre, type: MediaType, titleOverride: String? = nil) {
        self.genre = genre
        self.type = type
        self.titleOverride = titleOverride
    }

    var body: some View {
        PagedMetadataCatalogView(
            title: titleOverride ?? genre.name,
            type: type,
            category: .popular,
            genreID: genre.id
        )
    }
}

struct GenreBrowseRow: View {
    let genres: [MetadataGenre]
    let type: MediaType

    var body: some View {
        ShelfScrollView(
            items: CuratedGenre.allCases,
            itemSpan: MediaBrowseMetrics.genreCardWidth + MediaBrowseMetrics.shelfSpacing,
            accessibilityLabel: "Browse by Genre"
        ) { genre in
            GenreArtworkCard(
                genre: genre,
                providerGenre: genre.match(in: genres),
                type: type
            )
        }
    }

}

private struct GenreArtworkCard: View {
    let genre: CuratedGenre
    let providerGenre: MetadataGenre?
    let type: MediaType

    var body: some View {
        OmniaPageLink {
            if let providerGenre {
                GenreCatalogView(genre: providerGenre, type: type, titleOverride: genre.title)
            } else {
                CuratedGenreFallbackCatalogView(genre: genre, type: type)
            }
        } label: {
            ZStack(alignment: .bottomLeading) {
                GenreArtwork(genre: genre)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.76)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 0) {
                    Text(genre.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }
                .padding(14)
            }
            .frame(width: MediaBrowseMetrics.genreCardWidth, height: MediaBrowseMetrics.genreCardHeight)
            .clipShape(.rect(cornerRadius: MediaBrowseMetrics.genreCornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: MediaBrowseMetrics.genreCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Browse \(genre.title)")
    }

}

struct GenreDirectoryView: View {
    let title: String
    let genres: [MetadataGenre]
    let type: MediaType

    var body: some View {
        GeometryReader { proxy in
            let layout = MediaBrowseMetrics.genreGridLayout(containerWidth: proxy.size.width)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: layout.columns,
                    alignment: .leading,
                    spacing: MediaBrowseMetrics.genreGridSpacing
                ) {
                    ForEach(CuratedGenre.allCases) { genre in
                        GenreDirectoryCard(
                            genre: genre,
                            providerGenre: genre.match(in: genres),
                            type: type,
                            cardWidth: layout.itemWidth
                        )
                    }
                }
                .padding(.horizontal, MediaBrowseMetrics.pageInset)
                .padding(.vertical, 24)
            }
        }
        .omniaNavigationTitle(title)
    }

}

/// Search opens into the same native navigation destinations as the rest of
/// the app. Anime is a browse category here rather than a peer sidebar tab.
struct SearchBrowseDirectoryView: View {
    let genres: [MetadataGenre]
    var recentSearches: [String] = []
    var onSelectRecent: (String) -> Void = { _ in }
    var onRemoveRecent: (String) -> Void = { _ in }

    var body: some View {
        GeometryReader { proxy in
            let layout = MediaBrowseMetrics.genreGridLayout(containerWidth: proxy.size.width)

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
                        columns: layout.columns,
                        alignment: .leading,
                        spacing: MediaBrowseMetrics.genreGridSpacing
                    ) {
                        ForEach(CuratedGenre.allCases) { genre in
                            GenreDirectoryCard(
                                genre: genre,
                                providerGenre: genre.match(in: genres),
                                type: .movie,
                                cardWidth: layout.itemWidth
                            )
                        }

                        AnimeSearchDirectoryCard(cardWidth: layout.itemWidth)
                    }
                }
                .padding(.horizontal, MediaBrowseMetrics.pageInset)
                .padding(.vertical, 24)
            }
        }
    }
}

/// Browse by Genre as one row of cards, for Discover.
struct GenreDirectoryShelf: View {
    let genres: [MetadataGenre]
    private static let cardWidth: CGFloat = 168

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browse by Genre")
                .font(.title2.weight(.bold))
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: MediaBrowseMetrics.genreGridSpacing) {
                    ForEach(CuratedGenre.allCases) { genre in
                        GenreDirectoryCard(
                            genre: genre,
                            providerGenre: genre.match(in: genres),
                            type: .movie,
                            cardWidth: Self.cardWidth
                        )
                    }
                    AnimeSearchDirectoryCard(cardWidth: Self.cardWidth)
                }
            }
            .scrollClipDisabled()
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

private struct AnimeSearchDirectoryCard: View {
    let cardWidth: CGFloat

    var body: some View {
        OmniaPageLink {
            AnimeDiscoveryView()
        } label: {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [.indigo, .purple, .pink],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: "sparkles.tv.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                Text("Anime")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(14)
            }
            .frame(
                width: cardWidth,
                height: cardWidth * 1.5
            )
            .clipShape(RoundedRectangle(cornerRadius: MediaBrowseMetrics.genreCornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: MediaBrowseMetrics.genreCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Browse Anime")
    }
}

private struct GenreDirectoryCard: View {
    let genre: CuratedGenre
    let providerGenre: MetadataGenre?
    let type: MediaType
    let cardWidth: CGFloat

    var body: some View {
        OmniaPageLink {
            if let providerGenre {
                GenreCatalogView(genre: providerGenre, type: type, titleOverride: genre.title)
            } else {
                CuratedGenreFallbackCatalogView(genre: genre, type: type)
            }
        } label: {
            ZStack(alignment: .bottomLeading) {
                GenreArtwork(genre: genre)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                Text(genre.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(14)
            }
            .frame(
                width: cardWidth,
                height: cardWidth * 1.5
            )
            .clipShape(RoundedRectangle(cornerRadius: MediaBrowseMetrics.genreCornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: MediaBrowseMetrics.genreCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct CuratedGenreFallbackCatalogView: View {
    @Environment(LiveMetadataStore.self) private var metadata
    let genre: CuratedGenre
    let type: MediaType

    var body: some View {
        PagedMetadataCatalogView(title: genre.title, type: type, category: .popular)
    }
}

private enum CuratedGenre: String, CaseIterable, Identifiable {
    case action, adventure, scienceFiction, drama, comedy, family, romance, horror, thriller, classics

    var id: String { rawValue }
    var title: String {
        switch self {
        case .action: "Action"
        case .adventure: "Adventures"
        case .scienceFiction: "Sci-Fi"
        case .drama: "Drama"
        case .comedy: "Comedy"
        case .family: "Kids & Family"
        case .romance: "Romance"
        case .horror: "Horror"
        case .thriller: "Thriller"
        case .classics: "Classics"
        }
    }

    var providerNames: [String] {
        switch self {
        case .scienceFiction: ["Science Fiction"]
        case .family: ["Family"]
        case .classics: []
        default: [rawValue.capitalized]
        }
    }

    var colors: [Color] {
        switch self {
        case .action: [.orange, .red]
        case .adventure: [.teal, .green]
        case .scienceFiction: [.indigo, .cyan]
        case .drama: [.blue, .black]
        case .comedy: [.mint, .green]
        case .family: [.pink, .orange]
        case .romance: [.pink, .purple]
        case .horror: [.orange, .black]
        case .thriller: [.red, .black]
        case .classics: [.orange, .brown]
        }
    }

    func match(in genres: [MetadataGenre]) -> MetadataGenre? {
        genres.first { providerNames.contains($0.name) }
    }
}

/// Omnia-owned genre art. These are intentionally abstract compositions, not
/// borrowed title posters, so a genre remains recognizable even as catalogs
/// change or a provider has no artwork available.
private struct GenreArtwork: View {
    let genre: CuratedGenre

    var body: some View {
        ZStack {
            LinearGradient(
                colors: genre.colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            GeometryReader { proxy in
                motif(in: proxy.size)
            }
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.22)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func motif(in size: CGSize) -> some View {
        switch genre {
        case .action:
            ZStack {
                Capsule().fill(.white.opacity(0.28)).frame(width: size.width * 1.45, height: size.height * 0.16).rotationEffect(.degrees(-34))
                Capsule().fill(.black.opacity(0.22)).frame(width: size.width * 1.35, height: size.height * 0.09).rotationEffect(.degrees(-34)).offset(y: size.height * 0.19)
                Circle().fill(.white.opacity(0.28)).frame(width: size.width * 0.32).offset(x: size.width * 0.21, y: -size.height * 0.23)
            }
        case .adventure:
            ZStack(alignment: .bottom) {
                Circle().fill(.yellow.opacity(0.32)).frame(width: size.width * 0.42).offset(x: size.width * 0.18, y: -size.height * 0.25)
                RoundedRectangle(cornerRadius: size.width * 0.12).fill(.black.opacity(0.26)).frame(width: size.width * 0.92, height: size.height * 0.68).rotationEffect(.degrees(45)).offset(y: size.height * 0.34)
                RoundedRectangle(cornerRadius: size.width * 0.1).fill(.white.opacity(0.16)).frame(width: size.width * 0.8, height: size.height * 0.54).rotationEffect(.degrees(-38)).offset(x: -size.width * 0.2, y: size.height * 0.4)
            }
        case .scienceFiction:
            ZStack {
                Ellipse().stroke(.white.opacity(0.38), lineWidth: max(2, size.width * 0.025)).frame(width: size.width * 0.9, height: size.height * 0.32).rotationEffect(.degrees(-28))
                Ellipse().stroke(.white.opacity(0.2), lineWidth: max(2, size.width * 0.02)).frame(width: size.width * 0.72, height: size.height * 0.25).rotationEffect(.degrees(34))
                Circle().fill(.white.opacity(0.75)).frame(width: size.width * 0.16)
                Circle().fill(.cyan.opacity(0.34)).frame(width: size.width * 0.55)
            }
        case .drama:
            HStack(spacing: size.width * 0.08) {
                RoundedRectangle(cornerRadius: size.width * 0.13).fill(.white.opacity(0.14)).frame(width: size.width * 0.26).offset(y: -size.height * 0.15)
                RoundedRectangle(cornerRadius: size.width * 0.13).fill(.black.opacity(0.28)).frame(width: size.width * 0.36).offset(y: size.height * 0.09)
                RoundedRectangle(cornerRadius: size.width * 0.13).fill(.white.opacity(0.12)).frame(width: size.width * 0.22).offset(y: -size.height * 0.28)
            }
            .rotationEffect(.degrees(-15))
        case .comedy:
            ZStack {
                Circle().fill(.yellow.opacity(0.34)).frame(width: size.width * 0.82).offset(x: -size.width * 0.21, y: size.height * 0.1)
                Circle().stroke(.white.opacity(0.38), lineWidth: max(2, size.width * 0.035)).frame(width: size.width * 0.42).offset(x: size.width * 0.23, y: -size.height * 0.2)
                Circle().fill(.white.opacity(0.24)).frame(width: size.width * 0.13).offset(x: size.width * 0.32, y: size.height * 0.26)
            }
        case .family:
            ZStack {
                Circle().fill(.white.opacity(0.22)).frame(width: size.width * 0.72).offset(x: -size.width * 0.18, y: size.height * 0.14)
                Circle().fill(.yellow.opacity(0.34)).frame(width: size.width * 0.42).offset(x: size.width * 0.22, y: -size.height * 0.19)
                Circle().stroke(.white.opacity(0.44), lineWidth: max(2, size.width * 0.028)).frame(width: size.width * 0.88)
            }
        case .romance:
            ZStack {
                Circle().fill(.white.opacity(0.2)).frame(width: size.width * 0.64).offset(x: -size.width * 0.17, y: -size.height * 0.12)
                Circle().fill(.black.opacity(0.14)).frame(width: size.width * 0.59).offset(x: size.width * 0.23, y: size.height * 0.22)
                Capsule().fill(.white.opacity(0.32)).frame(width: size.width * 0.17, height: size.height * 0.76).rotationEffect(.degrees(42))
            }
        case .horror:
            ZStack(alignment: .topTrailing) {
                Circle().fill(.white.opacity(0.26)).frame(width: size.width * 0.56).offset(x: size.width * 0.14, y: -size.height * 0.18)
                RoundedRectangle(cornerRadius: size.width * 0.2).fill(.black.opacity(0.42)).frame(width: size.width * 0.84, height: size.height * 0.64).rotationEffect(.degrees(-15)).offset(x: -size.width * 0.2, y: size.height * 0.28)
            }
        case .thriller:
            ZStack {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(index.isMultiple(of: 2) ? .white.opacity(0.2) : .black.opacity(0.25))
                        .frame(width: size.width * 1.3, height: max(2, size.width * 0.03))
                        .rotationEffect(.degrees(-32))
                        .offset(y: CGFloat(index - 2) * size.height * 0.19)
                }
            }
        case .classics:
            HStack(spacing: size.width * 0.08) {
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: size.width * 0.08)
                        .fill(index.isMultiple(of: 2) ? .white.opacity(0.22) : .black.opacity(0.2))
                        .frame(width: size.width * 0.14, height: size.height * (index.isMultiple(of: 2) ? 0.7 : 0.5))
                }
            }
        }
    }
}
