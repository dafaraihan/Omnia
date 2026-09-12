//
//  HomeView.swift
//  Omnia
//

import SwiftUI

struct HomeView: View {
    @Environment(OmniaStore.self) private var store
    @Environment(LiveMetadataStore.self) private var metadata
    @Environment(SettingsPreferencesStore.self) private var settings
    @State private var resolvedFeatured: MediaItem?
    @State private var upcomingResult: UpcomingResult?
    @State private var isLoadingUpcoming = false
    @State private var heroIndex = 0
    @State private var heroCandidates: [MediaItem] = []
    @State private var sourcePlaybackItem: MediaItem?
    @AppStorage("home-show-continue-watching") private var showsContinueWatching = true
    @AppStorage(HomeShelfPreferences.storageKey) private var disabledHomeShelfIDs = ""

    private var continuing: [MediaItem] {
        let values = store.localMediaSnapshots
            .filter { $0.progress != nil }
            .map(\.item)
        return settings.preferences.continueWatchingLimit.value.map { Array(values.prefix($0)) } ?? values
    }
    /// The pager is deliberately drawn from the live discovery response, not
    /// hard-coded feature art. Prefer titles that can present a proper
    /// cinematic treatment, while retaining useful fallbacks when a provider
    /// has incomplete artwork.
    private var heroCatalogItems: [MediaItem] {
        visibleHomeCatalogs.flatMap(\.items)
            + metadata.movieCatalog
            + metadata.seriesCatalog
            + store.library
    }

    private var visibleHomeCatalogs: [BuiltInHomeCatalog] {
        let preferences = HomeShelfPreferences(rawValue: disabledHomeShelfIDs)
        return metadata.homeCatalogs.filter { preferences.isEnabled($0.shelf) }
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
                        continueWatchingShelf(continuing)
                    }

                    if settings.preferences.showUpcoming {
                        if let upcomingResult, !upcomingResult.items.isEmpty {
                            upcomingShelf(upcomingResult)
                        } else if isLoadingUpcoming {
                            ProgressView("Checking upcoming episodes…")
                                .frame(maxWidth: .infinity, minHeight: 100)
                        }
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

                        ForEach(visibleHomeCatalogs) { catalog in
                            shelf(title: catalog.title, items: Array(catalog.items.prefix(16)), type: catalog.kind == .movie ? .movie : .series, category: catalog.category)
                        }
                    }
                }
                .padding(.horizontal, horizontalInset)
                .padding(.top, 22)
                .padding(.bottom, 56)
                .background {
                    if let featured = displayFeatured {
                        HeroAccentBackground(item: featured)
                    } else {
                        pageBackground
                    }
                }
            }
        }
        .background {
            screenBackground
        }
        #if os(macOS)
        // Home's first section owns the area behind the stable transparent
        // toolbar; shelves below remain an opaque content surface.
        .ignoresSafeArea(edges: .top)
        #endif
        #if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        .omniaNavigationTitle("Home", screen: .home)
        .navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
        .omniaGlassModal(isPresented: showsSourcePicker) {
            if let sourcePlaybackItem {
                PlaybackSourceSheet(
                    item: sourcePlaybackItem,
                    episode: sourcePlaybackItem.resumeEpisode,
                    resumeAt: sourcePlaybackItem.positionSeconds,
                    onClose: { self.sourcePlaybackItem = nil }
                )
            }
        }
        .task(id: featured?.id) {
            guard let featured else {
                resolvedFeatured = nil
                return
            }
            let resolved = await metadata.details(for: featured)
            guard !Task.isCancelled else { return }
            resolvedFeatured = resolved
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
        .task(id: upcomingTaskKey) {
            await loadUpcoming()
        }
        .onChange(of: heroCandidateKey) { _, _ in
            heroIndex = 0
        }
        .onChange(of: heroCatalogItems, initial: true) { _, items in
            heroCandidates = Self.selectHeroCandidates(from: items)
        }
    }

    private func hero(_ featured: MediaItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            HeroArtworkCanvas(item: featured, source: .home, artworkAlignment: .topTrailing)
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
                        #if os(macOS)
                        .omniaCapsuleGlassButton()
                        #else
                        .buttonStyle(.plain)
                        #endif
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

    /// Continue Watching is intentionally not a regular catalogue shelf: its
    /// cards show the actual resume context (episode and time remaining) and
    /// retain the title/year beneath the landscape artwork.
    private func continueWatchingShelf(_ items: [MediaItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Continue Watching")
            ShelfScrollView(
                items: items,
                itemSpan: continueWatchingCardSpan,
                accessibilityLabel: "Continue Watching"
            ) { item in
                ContinueWatchingCard(item: item) {
                    sourcePlaybackItem = item
                }
            }
        }
    }

    private func upcomingShelf(_ result: UpcomingResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Upcoming")
            ShelfScrollView(
                items: result.items,
                itemSpan: continueWatchingCardSpan,
                accessibilityLabel: "Upcoming episodes"
            ) { item in
                UpcomingEpisodeCard(item: item)
            }
        }
    }

    private var upcomingTaskKey: String {
        let preferences = settings.preferences
        let savedIDs = store.localMediaSnapshots.filter(\.isInWatchlist).map(\.mediaID).joined(separator: "|")
        return "\(preferences.showUpcoming)-\(preferences.upcomingLookAhead.rawValue)-\(preferences.upcomingItemLimit.rawValue)-\(savedIDs)"
    }

    private var showsSourcePicker: Binding<Bool> {
        Binding(
            get: { sourcePlaybackItem != nil },
            set: { isPresented in
                if !isPresented { sourcePlaybackItem = nil }
            }
        )
    }

    private func loadUpcoming() async {
        guard settings.preferences.showUpcoming else {
            upcomingResult = nil
            return
        }
        isLoadingUpcoming = true
        defer { isLoadingUpcoming = false }
        let savedSeries = store.localMediaSnapshots
            .filter { $0.isInWatchlist && $0.item.kind == .series }
            .map(\.item)
        let service = UpcomingService(now: { .now }, calendar: .current) { item in
            let enriched = await metadata.details(for: item)
            guard enriched.details?.seasons.contains(where: { !$0.episodes.isEmpty }) == true else {
                throw UpcomingServiceError.metadataUnavailable
            }
            return enriched
        }
        upcomingResult = await service.load(
            savedItems: savedSeries,
            lookAheadDays: settings.preferences.upcomingLookAhead.rawValue,
            itemLimit: settings.preferences.upcomingItemLimit.value
        )
    }

    private var continueWatchingCardSpan: CGFloat {
        #if os(iOS)
        264
        #else
        320
        #endif
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

    @ViewBuilder
    private var screenBackground: some View {
        #if os(macOS)
        Color.clear
        #else
        if let featured = displayFeatured {
            HeroAccentBackground(item: featured)
        } else {
            pageBackground
        }
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

    static func selectHeroCandidates(from items: [MediaItem]) -> [MediaItem] {
        let artworkFirst = items.sorted {
            heroArtworkScore(for: $0) > heroArtworkScore(for: $1)
        }
        var identifiers = Set<String>()
        // Deduplication mutates the set, so evaluate it once before taking a
        // prefix. Lazy collection indexing can evaluate a predicate again.
        return Array(artworkFirst.filter { identifiers.insert($0.id).inserted }.prefix(6))
    }

    private static func heroArtworkScore(for item: MediaItem) -> Int {
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

enum UpcomingEpisodeCardPresentation {
    static func metadataText(for episode: MediaEpisode) -> String {
        "S\(episode.seasonNumber) E\(episode.episodeNumber) · \(episode.title)"
    }
}

private struct UpcomingEpisodeCard: View {
    let item: UpcomingEpisode

    var body: some View {
        NavigationLink(value: item.series) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: item.series.artworkColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    AsyncImage(url: item.episode.stillURL ?? item.series.backdropURL ?? item.series.artworkURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: item.series.symbol)
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                    Text(item.airDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(12)
                }
                .frame(width: 304, height: 171)
                .clipShape(.rect(cornerRadius: 16, style: .continuous))

                Text(item.series.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(UpcomingEpisodeCardPresentation.metadataText(for: item.episode))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 304, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.series.title), season \(item.episode.seasonNumber), episode \(item.episode.episodeNumber), \(item.episode.title)")
        .accessibilityValue(item.airDate.formatted(date: .long, time: .omitted))
        .mediaContextMenu(for: item.series, placement: .browse)
    }
}

/// A resume card deliberately uses backdrop/still artwork rather than a title
/// logo. The card's bottom metadata remains readable over changing artwork,
/// while title and release year live below it as in established TV clients.
struct ContinueWatchingCard: View {
    let item: MediaItem
    let requestPlayback: () -> Void

    @Environment(OmniaStore.self) private var store
    @Environment(SettingsPreferencesStore.self) private var settings

    var body: some View {
        Group {
            if settings.preferences.directContinueWatchingPlayback {
                Button {
                    requestPlayback()
                } label: {
                    cardLabel
                }
            } else {
                NavigationLink(value: item) {
                    cardLabel
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Continue watching \(item.title)")
        .accessibilityValue(cardPresentation.accessibilityValue)
        .accessibilityHint(
            settings.preferences.directContinueWatchingPlayback
                ? "Opens available sources and resumes playback in Omnia"
                : "Opens title details"
        )
        #if os(macOS)
        .accessibilityAction(named: "Remove Watch Progress") {
            store.removeFromContinueWatching(item)
        }
        #endif
    }

    private var cardLabel: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottom) {
                resumeArtwork
                LinearGradient(
                    colors: [.clear, .black.opacity(0.62)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                if let resumePresentation {
                    VStack(spacing: 9) {
                        Text(resumePresentation.continueWatchingMetadataText)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        ResumeProgressBar(progress: resumePresentation.progress)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(.rect(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.24))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(cardPresentation.primaryText)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(cardPresentation.secondaryText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: cardWidth, alignment: .leading)
        }
        .mediaContextMenu(for: item, placement: .continueWatching)
    }

    @ViewBuilder
    private var resumeArtwork: some View {
        let url = item.kind == .series
            ? item.resumeEpisodeStillURL ?? item.backdropURL ?? item.artworkURL
            : item.backdropURL ?? item.artworkURL

        ZStack {
            LinearGradient(colors: item.artworkColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: item.symbol)
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var resumePresentation: ResumeProgressPresentation? {
        ResumeProgressPresentation(item: item)
    }

    private var cardPresentation: ContinueWatchingCardPresentation {
        ContinueWatchingCardPresentation(item: item)
    }

    private var cardWidth: CGFloat {
        #if os(iOS)
        248
        #else
        304
        #endif
    }

    private var cardHeight: CGFloat {
        #if os(iOS)
        140
        #else
        172
        #endif
    }
}

/// A quiet carousel affordance: the chevron is always discoverable, while its
/// material capsule appears only for an active pointer or press state.
private struct HeroNavigationButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 40, height: 72)
        }
        .buttonStyle(HeroNavigationButtonStyle(isHovered: isHovered))
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
        .accessibilityLabel(label)
    }
}

private struct HeroNavigationButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isActive = ButtonInteractionPresentation.isActive(
            isHovered: isHovered,
            isPressed: configuration.isPressed
        )

        configuration.label
            .foregroundStyle(.white.opacity(isActive ? 1 : 0.72))
            .background {
                Capsule()
                    .fill(.clear)
                    .glassEffect(.regular, in: Capsule())
                    .opacity(isActive ? 1 : 0)
            }
            .contentShape(Capsule())
            .animation(.easeInOut(duration: 0.16), value: isActive)
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
        .glassEffect(.regular, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Featured titles")
    }
}

#Preview {
    NavigationStack { HomeView() }
        .environment(OmniaStore.preview)
        .environment(LiveMetadataStore.preview)
        .environment(SettingsPreferencesStore())
}
