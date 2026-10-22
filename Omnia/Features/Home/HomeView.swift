//
//  HomeView.swift
//  Omnia
//

import SwiftUI

struct HomeView: View {
    @Environment(OmniaStore.self) private var store
    @Environment(LiveMetadataStore.self) private var metadata
    @Environment(SettingsPreferencesStore.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AddonCatalogStore.self) private var addonCatalogs
    @Environment(HomeLayoutStore.self) private var homeLayout
    @Environment(CollectionsStore.self) private var collections
    @Environment(\.isActiveDestination) private var isActiveDestination
    @Environment(\.displayPreferences) private var display
    @State private var resolvedFeatured: MediaItem?
    @State private var upcomingResult: UpcomingResult?
    @State private var isLoadingUpcoming = false
    @State private var heroIndex = 0
    @State private var heroCandidates: [MediaItem] = []
    @State private var sourcePlaybackItem: MediaItem?
    @State private var resumePromptItem: MediaItem?
    /// The resume prompt is offered once per launch.
    private static var didCheckResumePrompt = false
    @State private var heroTrailer = HomeHeroTrailerModel()
    /// Bumped to play the same trailer again (After Trailer › Replay).
    @State private var heroTrailerReplay = 0
    /// The hero trailer and carousel pause while the hero is scrolled away
    /// or the window can't be seen.
    @State private var heroIsOnScreen = true
    @State private var windowIsVisible = true
    /// Settings › Integrations › MDBList Ratings, under the hero's metadata
    /// line as on a title's page.
    @State private var heroRatings = MDBListRatingsLoader()
    @State private var showsMDBListSettings = false
    @State private var servers = MediaServerStore.shared
    @Environment(PlaybackSession.self) private var playback
    @AppStorage(HomeView.continueWatchingVisibilityKey) private var showsContinueWatching = true
    /// Settings › Home › Continue Watching › Show on Home.
    static let continueWatchingVisibilityKey = "home-show-continue-watching"
    @AppStorage(HomeShelfPreferences.storageKey) private var disabledHomeShelfIDs = ""

    private var continuing: [MediaItem] {
        // Newest played first. The stored order puts a title in My List by
        // the day it was added, so a show watched again stayed where it was.
        let values = store.localMediaSnapshots
            .filter { $0.progress != nil }
            .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
            .map(\.item)
        // Titles in progress on media servers that import watch progress.
        let local = Set(values.map(\.id))
        let imported = servers.importedProgress.filter { !local.contains($0.id) }
        // Sorted before the limit, so Title and Nearly Finished sort the
        // whole row rather than the first few.
        let sorted = display.continueWatchingSort.sorted(values + imported)
        return settings.preferences.continueWatchingLimit.value.map { Array(sorted.prefix($0)) } ?? sorted
    }
    /// The pager is deliberately drawn from the live discovery response, not
    /// hard-coded feature art. Prefer titles that can present a proper
    /// cinematic treatment, while retaining useful fallbacks when a provider
    /// has incomplete artwork.
    private var heroCatalogItems: [MediaItem] {
        if isAddonMode { return addonHeroItems }
        return visibleHomeCatalogs.flatMap(\.items)
            + metadata.movieCatalog
            + metadata.seriesCatalog
            + store.library
    }

    // MARK: Add-on mode

    /// Every add-on catalog that can be a Home row, in the user's Home Layout
    /// order. When there is at least one, Home is built from add-ons only.
    private var addonHomeCatalogs: [AddonHomeCatalog] {
        homeLayout.ordered(AddonCatalogStore.catalogs(in: store))
    }

    private var isAddonMode: Bool { !addonHomeCatalogs.isEmpty || !servers.homeRows.isEmpty }

    private var visibleAddonCatalogs: [AddonHomeCatalog] {
        addonHomeCatalogs.filter { store.isCatalogEnabled(for: $0.addon, catalog: $0.catalog) }
    }

    /// Visible catalogs and collections in Home order.
    private var visibleHomeEntries: [HomeRowEntry] {
        homeLayout.entries(
            catalogs: addonHomeCatalogs,
            collections: collections.collections,
            servers: servers.homeRows
        ).filter { entry in
            switch entry {
            case let .catalog(catalog):
                store.isCatalogEnabled(for: catalog.addon, catalog: catalog.catalog)
            case let .collection(collection):
                collections.isVisible(collection)
            case let .server(row):
                homeLayout.isVisible(row)
            }
        }
    }

    private var heroSourceKeys: [String] {
        homeLayout.preferences.heroSources(
            orderedVisibleKeys: visibleAddonCatalogs.map(\.key),
            allKeys: addonHomeCatalogs.map(\.key)
        )
    }

    /// Titles to load: visible rows plus hidden hero sources.
    private var addonCatalogsToLoad: [AddonHomeCatalog] {
        let keys = Set(visibleAddonCatalogs.map(\.key) + (homeLayout.preferences.showsHero ? heroSourceKeys : []))
        return addonHomeCatalogs.filter { keys.contains($0.key) }
    }

    private var addonLoadKey: String {
        addonCatalogsToLoad.map { "\($0.key)@\($0.addon.manifestURL.absoluteString)" }.joined(separator: "|")
    }

    /// Nuvio's hero: titles from up to two hero-source catalogs, merged,
    /// de-duplicated, shuffled with a seed that changes only when catalogs
    /// reload, and capped at eight. Only each source's first titles are
    /// used, so later pages arriving never reshuffle the hero.
    private var addonHeroItems: [MediaItem] {
        guard homeLayout.preferences.showsHero else { return [] }
        let hidesUnreleased = homeLayout.preferences.hidesUnreleasedContent
        var seen = Set<String>()
        let merged = heroSourceKeys
            .flatMap { addonCatalogs.items(for: $0, hidingUnreleased: hidesUnreleased).prefix(20) }
            .filter { seen.insert($0.id).inserted }
        var generator = SeededRandomNumberGenerator(seed: UInt64(addonCatalogs.generation + 1))
        return Array(merged.shuffled(using: &generator).prefix(HomeLayoutPreferences.heroItemLimit))
    }

    private var showsHeroSlot: Bool {
        !isAddonMode || (homeLayout.preferences.showsHero && !addonHomeCatalogs.isEmpty)
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
                        .onScrollVisibilityChange(threshold: 0.15) { heroIsOnScreen = $0 }
                } else if showsHeroSlot {
                    loadingHero
                } else {
                    // No hero: keep the first row clear of the floating
                    // toolbar.
                    Color.clear.frame(height: herolessTopInset)
                }

                // Lazy so only the rows on screen are built. An add-on such as
                // Xperience adds dozens of rows, each with its own posters.
                LazyVStack(alignment: .leading, spacing: 34) {
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

                    if isAddonMode {
                        let hidesUnreleased = homeLayout.preferences.hidesUnreleasedContent
                        ForEach(visibleHomeEntries) { entry in
                            switch entry {
                            case let .catalog(catalog):
                                AddonHomeCatalogRow(
                                    catalog: catalog,
                                    title: homeLayout.title(for: catalog),
                                    items: addonCatalogs.items(for: catalog.key, hidingUnreleased: hidesUnreleased),
                                    state: addonCatalogs.state(for: catalog.key),
                                    retry: { addonCatalogs.retry(catalog) }
                                )
                            case let .collection(collection):
                                CollectionHomeRow(collection: collection)
                            case let .server(row):
                                MediaServerHomeRowView(
                                    row: row,
                                    items: servers.items(for: row),
                                    state: servers.state(for: row),
                                    retry: { servers.retry(row) }
                                )
                            }
                        }
                        if visibleHomeEntries.isEmpty {
                            ContentUnavailableView(
                                "All Catalogs Are Hidden",
                                systemImage: "rectangle.stack",
                                description: Text("Choose what appears on Home in Settings › Layout › Home Layout › Catalogs.")
                            )
                            .frame(maxWidth: .infinity, minHeight: 220)
                        }
                    } else if metadata.isLoadingCatalogs, metadata.homeCatalogs.isEmpty {
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
                    if let featured = displayFeatured, usesDynamicBackground {
                        #if os(macOS)
                        // The window backdrop already draws the accent behind
                        // the shelves. Drawing it here too blurred a layer as
                        // tall as every row on Home.
                        Color.clear
                        #else
                        HeroAccentBackground(item: featured)
                        #endif
                    } else {
                        pageBackground
                    }
                }
                // Shelves sit on the dark artwork accent, so their primary
                // text must stay light even in Light appearance.
                .environment(\.colorScheme, displayFeatured == nil || !usesDynamicBackground ? colorScheme : .dark)
            }
        }
        .background {
            screenBackground
        }
        #if os(macOS)
        // Home's first section owns the area behind the stable transparent
        // toolbar; shelves below remain an opaque content surface.
        .ignoresSafeArea(edges: .top)
        .modifier(TopBarScrollReporting(destination: .home, hasHero: displayFeatured != nil || showsHeroSlot))
        #endif
        #if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        .omniaNavigationTitle("Home", screen: .home)
        .navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
        .navigationDestination(for: CollectionFolderRoute.self) { route in
            CollectionFolderView(collection: route.collection, folder: route.folder)
        }
        .omniaStreamsPage(isPresented: showsSourcePicker) {
            if let sourcePlaybackItem {
                PlaybackSourceSheet(
                    item: sourcePlaybackItem,
                    episode: sourcePlaybackItem.resumeEpisode,
                    resumeAt: sourcePlaybackItem.positionSeconds,
                    onClose: { self.sourcePlaybackItem = nil }
                )
            }
        }
        .task(id: store.localMediaSnapshots.count) {
            checkResumePrompt()
        }
        .alert(
            "Continue Watching?",
            isPresented: Binding(get: { resumePromptItem != nil }, set: { if !$0 { resumePromptItem = nil } }),
            presenting: resumePromptItem
        ) { item in
            Button("Resume") {
                resumePromptItem = nil
                sourcePlaybackItem = item
            }
            Button("Not Now", role: .cancel) {
                resumePromptItem = nil
            }
        } message: { item in
            Text(resumePromptMessage(for: item))
        }
        .task(id: featured?.id) {
            guard let featured else {
                resolvedFeatured = nil
                return
            }
            let resolved: MediaItem
            if isAddonMode {
                // Add-on mode: the hero's logo, synopsis and genres come from
                // the add-on that listed the title.
                // Not tied to this task: the hero rotates every few seconds,
                // and a cancelled lookup never reached the cache, so slow
                // add-ons left every slide without artwork or logo.
                let addons = store.installedAddons
                resolved = await Task { await AddonMetadataResolver.resolve(featured, addons: addons) }.value ?? featured
            } else {
                resolved = await metadata.details(for: featured)
            }
            guard !Task.isCancelled else { return }
            resolvedFeatured = resolved
        }
        .task(id: "\(resolvedFeatured?.id ?? "")-\(settings.preferences.integrations.mdblistEnabled)") {
            heroRatings.cancel()
            guard let resolvedFeatured, settings.preferences.integrations.mdblistEnabled else { return }
            await heroRatings.load(
                for: resolvedFeatured,
                preferences: settings.preferences.mdblistRatings
            )
            if case let .loaded(presentation) = heroRatings.state {
                settings.recordMDBListRatingProviders(presentation.discoveredProviderIDs)
            }
        }
        .sheet(isPresented: $showsMDBListSettings) {
            MDBListSettingsSheet()
        }
        #if os(macOS)
        .background { WindowVisibilityReader(isVisible: $windowIsVisible) }
        #endif
        .task(id: addonLoadKey) {
            addonCatalogs.load(addonCatalogsToLoad)
        }
        .task(id: servers.rowsSignature) {
            await servers.loadRows()
        }
        .task(id: heroTrailerKey) {
            await heroTrailer.load(
                displayFeatured,
                preferences: settings.preferences.heroTrailer,
                metadata: metadata,
                autoplayAllowed: !reduceMotion
            )
        }
        .task(id: "\(heroCandidateKey)-\(heroIndex)-\(isActiveDestination)-\(heroTrailer.holdsCarousel)-\(reduceMotion)-\(heroIsOnScreen)-\(windowIsVisible)-\(heroCarousel.autoAdvance)-\(heroCarousel.intervalSeconds)") {
            // The carousel pauses while Home sits in a hidden tab, while a
            // hero trailer is waiting to start or playing, while nobody can
            // see the hero, and when Auto-Advance is off.
            guard isActiveDestination, !reduceMotion, heroCandidates.count > 1, !heroTrailer.holdsCarousel,
                  heroIsOnScreen, windowIsVisible, heroCarousel.autoAdvance
            else { return }

            do {
                try await Task.sleep(for: .seconds(heroCarousel.intervalSeconds))
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
        // A trailer played to the end: move on rather than showing the same
        // title's trailer again (Dafa, 2026-10-22).
        .onChange(of: heroTrailer.endCount) { _, _ in
            switch heroCarousel.afterTrailer {
            case .nextTitle:
                if heroCandidates.count > 1 { advanceHero() }
            case .replay:
                heroTrailerReplay += 1
            case .showArtwork:
                break
            }
        }
        .onChange(of: heroCatalogItems, initial: true) { _, items in
            // Add-on hero items are already chosen and shuffled; the built-in
            // pager ranks titles by artwork quality.
            heroCandidates = isAddonMode ? items : Self.selectHeroCandidates(from: items)
        }
        #if os(macOS)
        // Match MediaDetailView: the scroll container owns the top safe area.
        // This ensures the hero artwork meets the translucent Floating Top Bar
        // seamlessly without an empty offset band.
        .ignoresSafeArea(edges: .top)
        #endif
    }

    /// Mark Watched beside View Details, as on a title's page: a movie, or a
    /// show's resume episode (else its first episode).
    private func heroWatchAction(for featured: MediaItem) -> HeroWatchAction? {
        let episodes = featured.details?.seasons.flatMap(\.episodes) ?? []
        let currentEpisode = featured.resumeEpisode
            ?? episodes.first(where: { $0.seasonNumber > 0 })
            ?? episodes.first
        guard let action = MediaDetailWatchActionPresentation.action(
            kind: featured.kind,
            currentEpisode: currentEpisode,
            watchState: store.watchState(for: featured)
        ) else { return nil }
        return HeroWatchAction(
            systemImage: action.systemImage,
            accessibilityLabel: action.accessibilityLabel,
            perform: {
                store.applyWatchCommand(
                    action.command,
                    to: featured,
                    episodes: episodes,
                    leavingContinueWatching: action.leavesContinueWatching
                )
            }
        )
    }

    private func retryHeroRatings(for featured: MediaItem) {
        Task {
            await heroRatings.retry(for: featured, preferences: settings.preferences.mdblistRatings)
            if case let .loaded(presentation) = heroRatings.state {
                settings.recordMDBListRatingProviders(presentation.discoveredProviderIDs)
            }
        }
    }

    private func hero(_ featured: MediaItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            if isCardHero {
                LinearGradient(colors: featured.artworkColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            }

            HeroArtworkCanvas(
                item: featured,
                source: .home,
                artworkAlignment: .topTrailing,
                drawsArtworkLocally: isCardHero
            )
                .id(featured.id)
                .transition(.opacity)

            if isCardHero {
                // The window draws this scrim over full-bleed artwork; the
                // card draws its own.
                LinearGradient(
                    colors: [.clear, .black.opacity(0.22), .black.opacity(0.68)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            }

            HomeHeroTrailerLayer(model: heroTrailer, isPlaying: heroTrailerIsPlaying)

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
                    } else if resolvedFeatured?.id == featured.id {
                        // Details have loaded and there is no logo: show the
                        // title, as Nuvio does, instead of an empty gap.
                        Text(featured.title)
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                            .frame(
                                width: CinematicHeroLayout.logoWidth,
                                height: CinematicHeroLayout.logoHeight,
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

                    if settings.preferences.integrations.mdblistEnabled, resolvedFeatured?.id == featured.id {
                        MDBListRatingsView(
                            state: heroRatings.state.applying(settings.preferences.mdblistRatings),
                            retry: { retryHeroRatings(for: featured) },
                            openSettings: { showsMDBListSettings = true }
                        )
                        .frame(width: CinematicHeroLayout.logoWidth, alignment: .leading)
                    }

                    JustifiedSynopsisText(
                        text: featured.overview,
                        lineLimit: 3,
                        fontSize: CinematicHeroLayout.synopsisFontSize
                    )
                        .frame(width: CinematicHeroLayout.synopsisWidth, alignment: .leading)

                    HeroActionRow(
                        width: CinematicHeroLayout.logoWidth,
                        isSaved: store.isSaved(featured),
                        libraryAction: { store.toggleSaved(featured) },
                        watchAction: heroWatchAction(for: featured)
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
        // The trailer's speaker button belongs to the hero, so it scrolls
        // away with it, in the hero's bottom-right corner (Dafa, 2026-10-22).
        .overlay(alignment: .bottomTrailing) {
            HomeHeroTrailerMuteButton(model: heroTrailer)
                .padding(.trailing, 28)
                .padding(.bottom, 18)
                .animation(.snappy(duration: 0.25), value: heroTrailer.isVisible)
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
        .frame(height: isCardHero ? heroHeight - heroCardTopInset : heroHeight)
        .clipShape(.rect(cornerRadius: isCardHero ? Self.heroCardCornerRadius : 0, style: .continuous))
        .overlay {
            if isCardHero {
                RoundedRectangle(cornerRadius: Self.heroCardCornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.1))
            }
        }
        .shadow(color: .black.opacity(isCardHero ? 0.35 : 0), radius: 24, y: 12)
        .padding(.horizontal, isCardHero ? horizontalInset : 0)
        .padding(.top, isCardHero ? heroCardTopInset : 0)
        .animation(.easeInOut(duration: 0.45), value: featured.id)
        // `.contain` keeps the hero's Play, info and paging buttons reachable
        // by VoiceOver; `.combine` merged them into one unactionable element.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Featured: \(featured.title)")
    }

    private var heroCarousel: HeroTrailerPreferences { settings.preferences.heroTrailer }

    /// Restarts the trailer for a new title or changed trailer settings.
    private var heroTrailerKey: String {
        let preferences = settings.preferences.heroTrailer
        return "\(featured?.id ?? "")-\(preferences.autoplay)-\(preferences.startDelaySeconds)-\(preferences.startsWithSound)-\(reduceMotion)-\(heroTrailerReplay)"
    }

    /// The trailer pauses in a hidden tab, while the streams page is open,
    /// while something else is playing, and while a title page is open.
    private var heroTrailerIsPlaying: Bool {
        isActiveDestination && sourcePlaybackItem == nil && playback.source == nil
            && HeroTrailerFocus.shared.homeMayPlay && heroIsOnScreen && windowIsVisible
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

    /// Nuvio's resume prompt on launch: Omnia was closed while a title was
    /// playing, so offer to continue it once its progress has loaded.
    private func checkResumePrompt() {
        guard !Self.didCheckResumePrompt, !store.localMediaSnapshots.isEmpty else { return }
        Self.didCheckResumePrompt = true
        guard let mediaID = ResumePromptMarker.consume(),
              display.resumePromptOnLaunch,
              playback.source == nil,
              let snapshot = store.localMediaSnapshots.first(where: { $0.mediaID == mediaID }),
              let progress = snapshot.progress, progress > 0
        else { return }
        resumePromptItem = snapshot.item
    }

    private func resumePromptMessage(for item: MediaItem) -> String {
        let remaining = ResumeProgressPresentation(item: item)?.remainingText
        if item.kind == .series, let season = item.resumeSeasonNumber, let episode = item.resumeEpisodeNumber {
            return ["\(item.title), S\(season) E\(episode)", remaining].compactMap { $0 }.joined(separator: " · ")
        }
        return [item.title, remaining].compactMap { $0 }.joined(separator: " · ")
    }

    private func upcomingShelf(_ result: UpcomingResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Upcoming")
            ShelfScrollView(
                items: result.items,
                itemSpan: upcomingCardSpan,
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
        ContinueWatchingCard.itemSpan(for: display)
    }

    private var upcomingCardSpan: CGFloat {
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
            return MediaBrowseMetrics.posterItemSpan(display)
        }
        return cardWidth + 16
    }

    private var pageBackground: some View {
        OmniaPageBackground()
    }

    @ViewBuilder
    private var screenBackground: some View {
        #if os(macOS)
        Color.clear
        #else
        if let featured = displayFeatured, usesDynamicBackground {
            HeroAccentBackground(item: featured)
        } else {
            pageBackground
        }
        #endif
    }

    /// Settings › Layout › Home Layout › Dynamic Background Color.
    private var usesDynamicBackground: Bool {
        homeLayout.preferences.dynamicBackground
    }

    /// Settings › Layout › Home Layout › Hero Style.
    private var isCardHero: Bool {
        homeLayout.preferences.heroStyle == .card
    }

    private var heroCardTopInset: CGFloat {
        #if os(iOS)
        56
        #else
        72
        #endif
    }

    private static let heroCardCornerRadius: CGFloat = 28
    private var heroHeight: CGFloat {
        #if os(iOS)
        700
        #else
        820
        #endif
    }

    private var herolessTopInset: CGFloat {
        #if os(iOS)
        24
        #else
        96
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
                    CachedArtworkImage(
                        url: item.episode.stillURL ?? item.series.backdropURL ?? item.series.artworkURL,
                        size: CGSize(width: 304, height: 171)
                    ) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Image(systemName: item.series.symbol)
                                .font(.largeTitle)
                                .foregroundStyle(.white.opacity(0.7))
                        }
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
    @Environment(\.displayPreferences) private var display

    /// Home and Library rows space Continue Watching by the card style
    /// chosen in Settings › Home › Continue Watching.
    static func itemSpan(for display: DisplayPreferences) -> CGFloat {
        switch display.continueWatchingStyle {
        case .card:
            cardStyleWidth(for: display) + MediaBrowseMetrics.shelfSpacing
        case .poster:
            display.posterCardWidth + MediaBrowseMetrics.shelfSpacing
        case .wide:
            #if os(iOS)
            264
            #else
            320
            #endif
        }
    }

    /// Nuvio's Card style: a landscape card 1.2 times its landscape poster,
    /// so it follows Poster Card Style's width.
    static func cardStyleWidth(for display: DisplayPreferences) -> CGFloat {
        (display.posterCardWidth * 180 / 110 * 1.2).rounded()
    }

    private var style: ContinueWatchingStyle { display.continueWatchingStyle }
    private var isPoster: Bool { style == .poster }

    private var cornerRadius: CGFloat {
        switch style {
        case .poster: display.posterCornerRadius
        case .card: max(display.posterCornerRadius, 10)
        case .wide: 16
        }
    }

    /// The next episode, offered after the previous one ended, before any
    /// of it is watched.
    private var isNextUp: Bool {
        item.kind == .series && item.progress == 0 && item.resumeEpisodeNumber != nil
    }

    private var usesEpisodeStill: Bool {
        !isPoster && item.kind == .series && display.continueWatchingEpisodeThumbnails
    }

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
        .accessibilityValue(isNextUp ? "Up next, \(cardPresentation.accessibilityValue)" : cardPresentation.accessibilityValue)
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

    @ViewBuilder
    private var cardLabel: some View {
        if style == .card {
            landscapeCard
                .mediaContextMenu(for: item, placement: .continueWatching)
        } else {
            classicCard
        }
    }

    private var classicCard: some View {
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
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        ResumeProgressBar(progress: resumePresentation.progress)
                    }
                    .font(isPoster ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, isPoster ? 10 : 14)
                    .padding(.bottom, 10)
                } else if isNextUp {
                    Text(nextUpText)
                        .font(isPoster ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, isPoster ? 10 : 14)
                        .padding(.bottom, 10)
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .cardDepth(.continueWatching, cornerRadius: cornerRadius, fallbackBorderOpacity: 0.24)

            VStack(alignment: .leading, spacing: 2) {
                Text(cardPresentation.primaryText)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(cardPresentation.secondaryText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: cardWidth, alignment: .leading)
        }
        .mediaContextMenu(for: item, placement: .continueWatching)
    }

    /// Nuvio's TV-style card: everything sits on the artwork, with the time
    /// left or Up Next in a badge at the top.
    private var landscapeCard: some View {
        ZStack(alignment: .bottomLeading) {
            resumeArtwork
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.4),
                    .init(color: .black.opacity(0.55), location: 0.72),
                    .init(color: .black.opacity(0.85), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 3) {
                if let code = episodeCode {
                    Text(code)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                if let episodeTitle {
                    Text(episodeTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
                if let resumePresentation {
                    ResumeProgressBar(progress: resumePresentation.progress)
                        .padding(.top, 5)
                }
            }
            .lineLimit(1)
            .padding(12)

            Text(resumePresentation?.remainingText ?? nextUpText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.62), in: Capsule())
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        .cardDepth(.continueWatching, cornerRadius: cornerRadius, fallbackBorderOpacity: 0.24)
    }

    private var episodeCode: String? {
        guard item.kind == .series, let season = item.resumeSeasonNumber, let episode = item.resumeEpisodeNumber else {
            return nil
        }
        return "S\(season) E\(episode)"
    }

    private var episodeTitle: String? {
        let title = item.resumeEpisodeTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? nil : title
    }

    private var nextUpText: String {
        isNextUp ? "Up Next" : item.year
    }

    @ViewBuilder
    private var resumeArtwork: some View {
        // Settings › Continue Watching › Artwork › Paused Scene.
        // Next Up is a new episode, so the scene from the last one doesn't fit.
        let scene = display.continueWatchingArtwork == .pausedScene && !isNextUp
            ? ContinueWatchingSceneStore.shared.sceneURL(for: item.id)
            : nil
        let url: URL? = if let scene {
            scene
        } else if isPoster {
            item.artworkURL ?? item.backdropURL
        } else if usesEpisodeStill {
            item.resumeEpisodeStillURL ?? item.backdropURL ?? item.artworkURL
        } else {
            item.backdropURL ?? item.artworkURL
        }
        // Nuvio blurs only next-up episode stills, which can spoil the episode.
        let blursArtwork = scene == nil && display.blursNextUp && isNextUp && usesEpisodeStill && item.resumeEpisodeStillURL != nil

        ZStack {
            LinearGradient(colors: item.artworkColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: item.symbol)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
            if let url {
                RemoteArtworkImage(url: url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .blur(radius: blursArtwork ? 18 : 0, opaque: true)
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
        switch style {
        case .poster:
            return display.posterCardWidth
        case .card:
            return Self.cardStyleWidth(for: display)
        case .wide:
            #if os(iOS)
            return 248
            #else
            return 304
            #endif
        }
    }

    private var cardHeight: CGFloat {
        switch style {
        case .poster:
            return display.posterCardHeight
        case .card:
            return (cardWidth / 1.77).rounded()
        case .wide:
            #if os(iOS)
            return 140
            #else
            return 172
            #endif
        }
    }
}

extension ContinueWatchingSort {
    /// Recently Watched keeps the stored order, newest first.
    func sorted(_ items: [MediaItem]) -> [MediaItem] {
        switch self {
        case .recent:
            items
        case .title:
            items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .nearlyFinished:
            items.sorted { ($0.progress ?? 0) > ($1.progress ?? 0) }
        }
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
        .environment(AddonCatalogStore())
        .environment(HomeLayoutStore())
        .environment(CollectionsStore(fileURL: nil))
}
