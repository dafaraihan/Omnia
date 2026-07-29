//
//  HomeView.swift
//  Omnia
//

import SwiftUI

struct HomeView: View {
    @Environment(OmniaStore.self) private var store
    @Environment(LiveMetadataStore.self) private var metadata
    @State private var resolvedFeatured: MediaItem?
    @State private var heroIndex = 0
    @AppStorage("home-show-continue-watching") private var showsContinueWatching = true
    @AppStorage("home-show-movie-shelf") private var showsMovieShelf = true
    @AppStorage("home-show-series-shelf") private var showsSeriesShelf = true

    private var continuing: [MediaItem] { store.library.filter { $0.progress != nil } }
    /// The pager is deliberately drawn from the live discovery response, not
    /// hard-coded feature art. Prefer titles that can present a proper
    /// cinematic treatment, while retaining useful fallbacks when a provider
    /// has incomplete artwork.
    private var heroCandidates: [MediaItem] {
        let catalogItems = metadata.homeCatalogs.flatMap(\.items)
            + metadata.movieCatalog
            + metadata.seriesCatalog
            + store.library

        let artworkFirst = catalogItems.sorted { lhs, rhs in
            heroArtworkScore(for: lhs) > heroArtworkScore(for: rhs)
        }

        var identifiers = Set<String>()
        return artworkFirst.filter { identifiers.insert($0.id).inserted }.prefix(6).map { $0 }
    }

    private var featured: MediaItem? {
        guard !heroCandidates.isEmpty else { return nil }
        return heroCandidates[heroIndex % heroCandidates.count]
    }

    private var displayFeatured: MediaItem? {
        guard let featured else { return nil }
        return resolvedFeatured?.id == featured.id ? resolvedFeatured : featured
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let featured = displayFeatured {
                    hero(featured)
                } else {
                    loadingHero
                }

                VStack(alignment: .leading, spacing: 34) {
                    if showsContinueWatching, !continuing.isEmpty {
                        shelf(title: "Continue Watching", items: continuing, style: .landscape)
                    }

                    if metadata.isLoadingCatalogs, metadata.homeCatalogs.isEmpty {
                        ProgressView("Loading your cinema…")
                            .frame(maxWidth: .infinity, minHeight: 180)
                    } else if metadata.homeCatalogs.isEmpty, continuing.isEmpty {
                        ContentUnavailableView(
                            "Built-in Discovery Is Unavailable",
                            systemImage: "wifi.exclamationmark",
                            description: Text(metadata.errorMessage ?? "Try again in a moment.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        if !metadata.topMovies.isEmpty {
                        rankedShelf(title: "Top 10 Movies", items: Array(metadata.topMovies.prefix(10)), type: .movie)
                        }

                        if !metadata.topSeries.isEmpty {
                        rankedShelf(title: "Top 10 Series", items: Array(metadata.topSeries.prefix(10)), type: .series)
                        }

                        if !metadata.movieGenres.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeaderLink(title: "Browse by Genre") {
                                    GenreDirectoryView(title: "Browse by Genre", genres: metadata.movieGenres, type: .movie)
                                }
                                GenreBrowseRow(genres: metadata.movieGenres, type: .movie)
                            }
                        }

                        ForEach(metadata.homeCatalogs) { catalog in
                            if (catalog.kind == .movie && showsMovieShelf) || (catalog.kind == .series && showsSeriesShelf) {
                                shelf(title: catalog.title, items: Array(catalog.items.prefix(16)), type: catalog.kind == .movie ? .movie : .series, category: catalog.category)
                            }
                        }
                    }
                }
                .padding(.horizontal, horizontalInset)
                .padding(.top, 22)
                .padding(.bottom, 56)
                .background(pageBackground)
            }
        }
        .background(pageBackground)
        #if os(macOS)
        // Home's first section owns the area behind the stable transparent
        // toolbar; shelves below remain an opaque content surface.
        .ignoresSafeArea(edges: .top)
        #endif
        #if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        .navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
        .task(id: featured?.id) {
            guard let featured else {
                resolvedFeatured = nil
                return
            }
            resolvedFeatured = await metadata.details(for: featured)
        }
        .task(id: "\(heroCandidateKey)-\(heroIndex)") {
            guard heroCandidates.count > 1 else { return }

            do {
                try await Task.sleep(nanoseconds: 9_000_000_000)
                guard !Task.isCancelled else { return }
                advanceHero()
            } catch {
                // A selection or catalog update cancels the old timer. The
                // replacement task begins immediately with a fresh interval.
            }
        }
        .onChange(of: heroCandidateKey) { _, _ in
            heroIndex = 0
        }
    }

    private func hero(_ featured: MediaItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            FeaturedBackdrop(item: featured, artworkAlignment: .topTrailing)
                .id(featured.id)
                .transition(.opacity)

            // FeaturedBackdrop correctly opts out of hit-testing so it can be
            // reused behind detail content. Give Home a separate clear link
            // above the image instead; this makes the artwork tappable without
            // stealing taps from the action buttons and carousel controls.
            NavigationLink(value: featured) {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View details for \(featured.title)")

            VStack(alignment: .leading, spacing: 0) {
                // Anchor identity in the lower third while letting the local
                // hero artwork breathe above it.
                Spacer(minLength: heroTopSpacing)

                CinematicHeroColumn {
                    if let logoURL = featured.logoURL {
                        TitleLogoView(
                            url: logoURL,
                            title: featured.title,
                            maximumWidth: CinematicHeroLayout.logoWidth,
                            maximumHeight: CinematicHeroLayout.logoHeight,
                            alignment: .center
                        )
                    } else {
                        // A basic catalog item can arrive before the detail
                        // request has supplied its transparent logo. Preserve
                        // the logo canvas instead of flashing a duplicate
                        // plain-text title for one render pass.
                        Color.clear
                            .frame(
                                width: CinematicHeroLayout.logoWidth,
                                height: CinematicHeroLayout.logoHeight,
                                alignment: .center
                            )
                            .accessibilityHidden(true)
                    }

                    HeroMetadataLine(item: featured)

                    JustifiedSynopsisText(
                        text: featured.overview,
                        lineLimit: 3,
                        fontSize: CinematicHeroLayout.synopsisFontSize
                    )
                        .frame(width: CinematicHeroLayout.synopsisWidth, alignment: .leading)

                    HeroActionRow(
                        width: CinematicHeroLayout.logoWidth,
                        isSaved: store.isSaved(featured),
                        libraryAction: { store.toggleSaved(featured) }
                    ) {
                        NavigationLink(value: featured) {
                            HeroPrimaryActionLabel(title: "View Details")
                        }
                        .buttonStyle(.plain)
                    }
                }
                // AsyncImage keeps state while SwiftUI reuses a view tree.
                // A title-specific identity prevents a previous transparent
                // logo from appearing over the next title's backdrop.
                .id(featured.id)
                .transition(.opacity)
            }
            .frame(maxHeight: .infinity, alignment: .leading)
            .padding(.leading, CinematicHeroLayout.horizontalInset)
                .padding(.bottom, 38)
        }
        .overlay {
            if heroCandidates.count > 1 {
                HStack {
                    heroNavigationButton(symbol: "chevron.left", label: "Previous feature") {
                        moveHero(by: -1)
                    }
                    Spacer()
                    heroNavigationButton(symbol: "chevron.right", label: "Next feature") {
                        moveHero(by: 1)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .overlay(alignment: .bottom) {
            if heroCandidates.count > 1 {
                HeroPageControl(
                    count: heroCandidates.count,
                    selection: heroIndex % heroCandidates.count,
                    select: { index in
                        withAnimation(.easeInOut(duration: 0.45)) {
                            heroIndex = index
                        }
                    }
                )
                .padding(.bottom, 22)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: heroHeight)
        .clipped()
        .animation(.easeInOut(duration: 0.45), value: featured.id)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Featured: \(featured.title)")
    }

    private var loadingHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer(minLength: heroTopSpacing)
            ProgressView().tint(.white)
            Text("Loading Omnia")
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: 680, minHeight: heroHeight, alignment: .leading)
        .padding(.horizontal, horizontalInset)
        .padding(.bottom, 30)
    }

    private func shelf(
        title: String,
        items: [MediaItem],
        type: MediaType? = nil,
        category: MetadataCatalogCategory? = nil,
        style: MediaPoster.Style = .poster
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderLink(title: title) {
                    if let type, let category {
                        PagedMetadataCatalogView(title: title, type: type, category: category)
                    } else {
                        MetadataCatalogView(title: title, items: items)
                    }
            }
            ShelfScrollView(
                items: items,
                itemSpan: shelfItemSpan(style),
                accessibilityLabel: title
            ) { item in
                MediaPoster(item: item, style: style)
            }
        }
    }

    private func rankedShelf(title: String, items: [MediaItem], type: MediaType) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderLink(title: title) {
                PagedMetadataCatalogView(title: title, type: type, category: .topRated)
            }
            ShelfScrollView(
                items: items,
                itemSpan: shelfItemSpan(.poster),
                accessibilityLabel: title
            ) { item in
                RankedMediaPoster(item: item, rank: (items.firstIndex(where: { $0.id == item.id }) ?? 0) + 1)
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

    private func shelfItemSpan(_ style: MediaPoster.Style) -> CGFloat {
        let cardWidth: CGFloat
        switch style {
        case .landscape:
            #if os(iOS)
            cardWidth = 248
            #else
            cardWidth = 304
            #endif
        case .poster:
            #if os(iOS)
            cardWidth = 132
            #else
            cardWidth = 154
            #endif
        }
        return cardWidth + 16
    }

    private var pageBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
    private var heroHeight: CGFloat {
        #if os(iOS)
        700
        #else
        820
        #endif
    }

    private var heroTopSpacing: CGFloat {
        #if os(iOS)
        410
        #else
        470
        #endif
    }

    private var heroCandidateKey: String {
        heroCandidates.map(\.id).joined(separator: "|")
    }

    private func heroArtworkScore(for item: MediaItem) -> Int {
        var score = 0
        if item.backdropURL != nil { score += 4 }
        if item.logoURL != nil { score += 2 }
        if !item.overview.isEmpty { score += 1 }
        return score
    }

    private func advanceHero() {
        moveHero(by: 1)
    }

    private func moveHero(by offset: Int) {
        guard !heroCandidates.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.45)) {
            heroIndex = (heroIndex + offset + heroCandidates.count) % heroCandidates.count
        }
    }

    private func heroNavigationButton(
        symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        HeroNavigationButton(symbol: symbol, label: label, action: action)
    }

}

/// A quiet carousel affordance: the chevron is always discoverable, while its
/// material capsule appears only for an active pointer or press state.
private struct HeroNavigationButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressing = false

    private var isActive: Bool { isHovered || isPressing }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(isActive ? 1 : 0.72))
                .frame(width: 40, height: 72)
                .background {
                    Capsule()
                        .fill(.thinMaterial)
                        .opacity(isActive ? 1 : 0)
                }
                .contentShape(Capsule())
                .animation(.easeInOut(duration: 0.16), value: isActive)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressing = true }
                .onEnded { _ in isPressing = false }
        )
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
        .accessibilityLabel(label)
    }
}

private struct HeroPageControl: View {
    let count: Int
    let selection: Int
    let select: (Int) -> Void

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { index in
                Button {
                    select(index)
                } label: {
                    Circle()
                        .fill(.white.opacity(index == selection ? 1 : 0.42))
                        .frame(width: index == selection ? 8 : 6, height: index == selection ? 8 : 6)
                        .frame(width: 20, height: 20)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Feature \(index + 1) of \(count)")
                .accessibilityValue(index == selection ? "Current feature" : "")
            }
        }
        .padding(.horizontal, 8)
        .background(.black.opacity(0.18), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Featured titles")
    }
}

#Preview {
    NavigationStack { HomeView() }
        .environment(OmniaStore.preview)
        .environment(LiveMetadataStore.preview)
}
