//
//  DiscoverView.swift
//  Omnia
//

import SwiftUI

struct DiscoverView: View {
    @Environment(OmniaStore.self) private var store
    @Environment(LiveMetadataStore.self) private var metadata

    private var enabledAddonCatalogs: [(addon: InstalledAddon, catalog: AddonCatalog)] {
        store.installedAddons.flatMap { addon in
            addon.manifest.catalogs
                .filter { store.isCatalogEnabled(for: addon, catalog: $0) }
                .map { (addon, $0) }
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 36) {
                if metadata.isLoadingCatalogs, metadata.movieCatalog.isEmpty, metadata.seriesCatalog.isEmpty {
                    ProgressView("Finding something good…")
                        .frame(maxWidth: .infinity, minHeight: 280)
                } else if metadata.movieCatalog.isEmpty, metadata.seriesCatalog.isEmpty {
                    ContentUnavailableView(
                        "Built-in Discovery Is Unavailable",
                        systemImage: "wifi.exclamationmark",
                        description: Text(metadata.errorMessage ?? "Try again in a moment.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    if !metadata.topMovies.isEmpty {
                        catalogShelf(
                            title: "Top 10 Movies",
                            items: Array(metadata.topMovies.prefix(10)),
                            type: .movie,
                            category: .topRated
                        )
                    }

                    if !metadata.topSeries.isEmpty {
                        catalogShelf(
                            title: "Top 10 Series",
                            items: Array(metadata.topSeries.prefix(10)),
                            type: .series,
                            category: .topRated
                        )
                    }

                    if !metadata.movieGenres.isEmpty {
                        genreShelf(title: "Browse Movies by Genre", genres: metadata.movieGenres, type: .movie)
                    }

                    if !metadata.seriesGenres.isEmpty {
                        genreShelf(title: "Browse Series by Genre", genres: metadata.seriesGenres, type: .series)
                    }

                    ForEach(metadata.homeCatalogs) { catalog in
                        catalogShelf(
                            title: catalog.title,
                            items: Array(catalog.items.prefix(18)),
                            type: catalog.kind == .movie ? .movie : .series,
                            category: catalog.category
                        )
                    }

                    if !store.library.isEmpty {
                        catalogShelf(
                            title: "Saved For You",
                            items: Array(store.library.reversed())
                        )
                    }

                    addonCatalogs
                }
            }
            .padding(.horizontal, horizontalInset)
            .padding(.vertical, 24)
        }
        .navigationTitle("Discover")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    CatalogsSettingsView()
                } label: {
                    Label("Catalogs", systemImage: "slider.horizontal.3")
                }
            }
        }
        .navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
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
            ShelfScrollView(items: items, itemSpan: posterItemSpan, accessibilityLabel: title) { item in
                MediaPoster(item: item)
            }
        }
    }

    private func genreShelf(title: String, genres: [MetadataGenre], type: MediaType) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderLink(title: title) {
                GenreDirectoryView(title: title, genres: genres, type: type)
            }
            GenreBrowseRow(genres: genres, type: type)
        }
    }

    @ViewBuilder
    private var addonCatalogs: some View {
        if !enabledAddonCatalogs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Add-on Catalogs")
                ForEach(enabledAddonCatalogs.indices, id: \.self) { index in
                    let source = enabledAddonCatalogs[index]
                    Label(source.catalog.name ?? source.catalog.id, systemImage: "puzzlepiece.extension")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var horizontalInset: CGFloat {
        #if os(iOS)
        20
        #else
        32
        #endif
    }

    private var posterItemSpan: CGFloat {
        #if os(iOS)
        148
        #else
        170
        #endif
    }
}
