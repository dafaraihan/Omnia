//
//  HomeView.swift
//  Omnia
//

import SwiftUI

struct HomeView: View {
    @Environment(OmniaStore.self) private var store
    @Environment(LiveMetadataStore.self) private var metadata
    @Environment(SettingsPreferencesStore.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(AddonCatalogStore.self) private var addonCatalogs
    @Environment(HomeLayoutStore.self) private var homeLayout
    @Environment(CollectionsStore.self) private var collections
    @Environment(\.isActiveDestination) private var isActiveDestination
    @Environment(\.isOnboardingPreview) private var isOnboardingPreview
    @Environment(\.displayPreferences) private var display
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif
    @State private var viewportSize: CGSize = .zero
    @State private var resolvedFeatured: MediaItem?
    @State private var resolvedHeroSource = ""
    @State private var upcomingResult: UpcomingResult?
    @State private var isLoadingUpcoming = false
    @State private var heroIndex = 0
    /// How much of the page's leading edge the iPad sidebar covers.
    @State private var sidebarInset: CGFloat = 0
    /// A sideways swipe is under way, so lifting the finger mustn't open
    /// the title.
    @State private var isSwipingHero = false
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
    @State private var ratingsCredentialEpoch = UUID()
    @State private var enrichmentCredentialEpoch = UUID()
    @State private var showsMDBListSettings = false
    @State private var servers = MediaServerStore.shared
    @Environment(PlaybackSession.self) private var playback
    @AppStorage(HomeView.continueWatchingVisibilityKey) private var showsContinueWatching = true
    /// Settings › Home › Continue Watching › Show on Home.
    static let continueWatchingVisibilityKey = "home-show-continue-watching"
    @AppStorage(HomeShelfPreferences.storageKey) private var disabledHomeShelfIDs = ""
    /// Continue Watching from a tracker instead of Omnia's own progress.
    @State private var trackerLibrary = TrackerLibraryStore.shared

    private var continueWatchingSource: TrackerLibrarySource {
        trackerLibrary.effectiveSource(trackerLibrary.continueWatchingSource)
    }

    private var continuing: [MediaItem] {
        if isOnboardingPreview { return [] }
        if continueWatchingSource.tracker != nil || continueWatchingSource.addsAniListAnime {
            let local = continueWatchingSource.tracker == nil ? localContinuing : []
            let items = trackerLibrary.progressItems(continueWatchingSource, local: local)
            let sorted = display.continueWatchingSort.sorted(items)
            return settings.preferences.continueWatchingLimit.value.map { Array(sorted.prefix($0)) } ?? sorted
        }
        return localContinuing
    }

    /// Omnia's own progress, plus media servers that import theirs.
    private var localContinuing: [MediaItem] {
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

    private var isAddonMode: Bool { !isOnboardingPreview && (!addonHomeCatalogs.isEmpty || !servers.homeRows.isEmpty) }

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
                    // A tracker's row stays, even empty, so its menu can
                    // switch back.
                    if showsContinueWatching, !isOnboardingPreview, !continuing.isEmpty || continueWatchingSource != .local {
                        continueWatchingShelf(continuing)
                    }

                    if settings.preferences.showUpcoming {
                        if let upcomingResult, !upcomingResult.items.isEmpty {
                            upcomingShelf(upcomingResult)
                        } else if isLoadingUpcoming {
                            OmniaLoadingRow("Checking upcoming episodes…")
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
                        OmniaLoadingRow("Loading your cinema…")
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
                .padding(.leading, sidebarInset)
                .padding(.top, 22)
                .padding(.bottom, 56)
                .background {
                    HomeArtworkBackground(item: displayFeatured, isEnabled: usesDynamicBackground)
                }
                // The wash is always a dark colour, in Light appearance too,
                // so text on the rows has to stay light.
                .environment(\.colorScheme, usesDynamicBackground ? .dark : colorScheme)
            }
        }
        .background {
            // Under the home indicator too: on iPad the bottom safe area
            // otherwise showed the window's light colour as a white bar.
            screenBackground.ignoresSafeArea()
        }
        #if os(macOS)
        // Home's first section owns the area behind the stable transparent
        // toolbar; shelves below remain an opaque content surface.
        .ignoresSafeArea(edges: .top)
        #endif
        #if os(iOS)
        // iPad: the page runs behind the floating sidebar, as the sidebar's
        // glass expects. Text and buttons keep clear using sidebarInset.
        .ignoresSafeArea(edges: UIDevice.current.userInterfaceIdiom == .pad ? [.top, .leading] : .top)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.leading } action: { leading in
            sidebarInset = UIDevice.current.userInterfaceIdiom == .pad ? leading : 0
        }
        #endif
        .modifier(TopBarScrollReporting(destination: .home, hasHero: displayFeatured != nil || showsHeroSlot))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewportSize = $0 }
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
            guard !isOnboardingPreview else { return }
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
        .task(id: heroMetadataRequestKey) {
            guard let featured else {
                resolvedFeatured = nil
                return
            }
            // Same-title refreshes retain visible content. A different source
            // configuration must not reuse the previous add-on's private fields.
            if resolvedHeroSource != heroSourceConfigurationKey { resolvedFeatured = nil }
            resolvedHeroSource = heroSourceConfigurationKey
            let resolved = await resolveHeroMetadata(featured, showsProgress: true)
            guard !Task.isCancelled else { return }
            resolvedFeatured = resolved
        }
        .task(id: heroRatingsRequestKey) {
            heroRatings.cancel()
            guard !isOnboardingPreview, isActiveDestination,
                  let featured = displayFeatured, settings.preferences.integrations.mdblistEnabled else { return }
            await heroRatings.load(for: featured, preferences: settings.preferences.mdblistRatings)
            guard !Task.isCancelled else { return }
            if case let .loaded(presentation) = heroRatings.state {
                settings.recordMDBListRatingProviders(presentation.discoveredProviderIDs)
            }
        }
        .task(id: nextHeroPreparationKey) {
            guard !isOnboardingPreview, isActiveDestination, let nextHero else { return }
            await prepareNextHero(nextHero)
        }
        .onReceive(NotificationCenter.default.publisher(for: .providerCredentialDidChange)) { change in
            if change.object as? String == UserManagedProviderCredential.mdblist.rawValue {
                heroRatings.reset()
                ratingsCredentialEpoch = UUID()
            } else if ["tmdb", "tvdb"].contains(change.object as? String ?? "") {
                enrichmentCredentialEpoch = UUID()
            }
        }
        .onDisappear { heroRatings.cancel() }
        .sheet(isPresented: $showsMDBListSettings) {
            MDBListSettingsSheet()
        }
        #if os(macOS)
        .background { WindowVisibilityReader(isVisible: $windowIsVisible) }
        #endif
        .task(id: addonLoadKey) {
            guard !isOnboardingPreview else { return }
            addonCatalogs.load(addonCatalogsToLoad)
        }
        .task(id: servers.rowsSignature) {
            guard !isOnboardingPreview else { return }
            await servers.loadRows()
        }
        .task(id: heroTrailerKey) {
            guard !isOnboardingPreview else { return }
            await heroTrailer.load(
                displayFeatured,
                preferences: settings.preferences.heroTrailer,
                metadata: metadata,
                autoplayAllowed: !reduceMotion && !usesLowPower
            )
        }
        .task(id: "\(heroCandidateKey)-\(heroIndex)-\(isActiveDestination)-\(heroTrailer.holdsCarousel)-\(reduceMotion)-\(heroIsOnScreen)-\(windowIsVisible)-\(heroCarousel.autoAdvance)-\(heroCarousel.intervalSeconds)-\(playback.isPresentingPlayer)-\(playback.hasPlayer)-\(scenePhase)") {
            // The carousel pauses while Home sits in a hidden tab, while a
            // hero trailer is waiting to start or playing, while nobody can
            // see the hero, and when Auto-Advance is off.
            guard !isOnboardingPreview, isActiveDestination, !reduceMotion, heroCandidates.count > 1, !heroTrailer.holdsCarousel,
                  heroIsOnScreen, windowIsVisible, heroCarousel.autoAdvance, !playback.isPresentingPlayer, !playback.hasPlayer, scenePhase == .active
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
            guard !isOnboardingPreview else { return }
            await loadUpcoming()
        }
        .task(id: episodeReminderKey) {
            guard !isOnboardingPreview, settings.preferences.display.episodeNotifications else { return }
            await scheduleEpisodeReminders()
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

    private var heroSourceConfigurationKey: String {
        store.installedAddons.filter { $0.isEnabled && $0.manifest.supportsMeta }
            .map { $0.manifestURL.absoluteString }.joined(separator: "|")
    }

    private var heroMetadataRequestKey: String {
        let enrichment = metadata.enrichmentRequestIdentity(integrations: settings.preferences.integrations)
        return "\(featured?.id ?? "")|\(addonLoadKey)|\(heroSourceConfigurationKey)|\(enrichment)|\(enrichmentCredentialEpoch)"
    }

    private var heroRatingsRequestKey: String {
        let route = displayFeatured.flatMap { try? MDBListMetadataClient.lookupRoute(for: $0) }
        return "\(featured?.id ?? "")|\(String(describing: route))|\(settings.preferences.integrations.mdblistEnabled)|\(isActiveDestination)|\(ratingsCredentialEpoch)"
    }

    private var nextHero: MediaItem? {
        guard heroCandidates.count > 1 else { return nil }
        return heroCandidates[(heroIndex + 1) % heroCandidates.count]
    }

    private var nextHeroPreparationKey: String {
        "\(nextHero?.id ?? "")|\(heroMetadataRequestKey)|\(settings.preferences.integrations.mdblistEnabled)|\(isActiveDestination)|\(displayScale)|\(ratingsCredentialEpoch)"
    }

    private func resolveHeroMetadata(_ item: MediaItem, showsProgress: Bool = false) async -> MediaItem {
        guard isAddonMode else { return await metadata.details(for: item) }
        let addon = await AddonMetadataResolver.resolve(item, addons: store.installedAddons)
        guard !Task.isCancelled else { return item }
        if showsProgress, let addon { resolvedFeatured = addon }
        if let addon {
            return await metadata.enrichedDetails(for: addon, integrations: settings.preferences.integrations)
        }
        return await metadata.details(for: item)
    }

    /// Prepare only the next candidate, using the existing request caches.
    private func prepareNextHero(_ item: MediaItem) async {
        async let initialRatings: Void = prepareRatings(for: item)
        async let initialLogo: Void = prepareLogo(item.logoURL)
        let resolved = await resolveHeroMetadata(item)
        if !Task.isCancelled {
            async let logo: Void = prepareLogo(resolved.logoURL)
            if (try? MDBListMetadataClient.lookupRoute(for: resolved)) != (try? MDBListMetadataClient.lookupRoute(for: item)) {
                await prepareRatings(for: resolved)
            }
            await logo
        }
        _ = await (initialRatings, initialLogo)
    }

    private func prepareRatings(for item: MediaItem) async {
        guard !Task.isCancelled, settings.preferences.integrations.mdblistEnabled else { return }
        _ = try? await MDBListMetadataClient().titleRatings(for: item)
    }

    private func prepareLogo(_ url: URL?) async {
        guard !Task.isCancelled, let url else { return }
        let scale = max(displayScale, 1) * 1.05
        let target = RemoteArtworkTarget(
            width: RemoteArtworkCache.bucket(CinematicHeroLayout.logoWidth * scale),
            height: RemoteArtworkCache.bucket(CinematicHeroLayout.logoHeight * scale),
            fills: false
        )
        _ = await RemoteArtworkCache.shared.image(for: url, target: target)
    }

    /// Mark Watched for a movie, or the show's resume/first episode.
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
                MediaItem.placeholderArtworkColor
            }

            Group {
                #if os(iOS)
                if isPortraitPhone {
                    PortraitHeroArtwork(item: featured, blendsIntoPage: usesDynamicBackground)
                } else {
                    landscapeHeroArtwork(featured)
                }
                #else
                landscapeHeroArtwork(featured)
                #endif
            }
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

            // Dynamic Background Color: the hero melts into the artwork's
            // colour, the same one the rows below sit on, so there is no edge.
            // On iPad and Mac a playing trailer stays uncovered.
            if settings.preferences.display.heroBlend.isEnabled, !isCardHero, OmniaDevice.isPhone || !heroTrailer.isVisible {
                HeroBottomBlend(item: featured, usesWash: usesDynamicBackground)
                    .transition(.opacity)
            }
            if heroTrailer.isVisible, !isCardHero {
                HeroTrailerTopFade(item: featured, usesWash: usesDynamicBackground)
                    .transition(.opacity)
            }

            // FeaturedBackdrop correctly opts out of hit-testing so it can be
            // reused behind detail content. Give Home a separate clear link
            // above the image instead; this makes the artwork tappable without
            // stealing taps from the action buttons and carousel controls.
            if showsPlayingHeroTrailer {
                Button { openHeroTrailer(featured) } label: {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isSwipingHero)
                .accessibilityLabel("Play trailer for \(featured.title) full screen")
            } else {
                NavigationLink(value: featured) {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isSwipingHero)
                .accessibilityLabel("View details for \(featured.title)")
            }

            Group {
                #if os(iOS)
                if isPortraitPhone {
                    portraitHeroIdentity(featured)
                } else {
                    landscapeHeroIdentity(featured)
                }
                #else
                landscapeHeroIdentity(featured)
                #endif
            }
        }
        .overlay {
            // A swipe moves the hero on iPhone and iPad; the Mac has arrows.
            if heroCandidates.count > 1, showsHeroArrows {
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
        // away with it: bottom-right, or top-right on iPhone, where the
        // bottom of the hero holds the title and its buttons.
        .overlay(alignment: OmniaDevice.isPhone ? .topTrailing : .bottomTrailing) {
            HomeHeroTrailerMuteButton(model: heroTrailer)
                .padding(.trailing, OmniaDevice.isPhone ? 16 : 28)
                .padding(.top, OmniaDevice.isPhone ? 62 : 0)
                .padding(.bottom, OmniaDevice.isPhone ? 0 : 18)
                .animation(.snappy(duration: 0.25), value: heroTrailer.isVisible)
        }
        .overlay(alignment: .bottom) {
            if heroCandidates.count > 1 {
                HeroPageControl(
                    count: heroCandidates.count,
                    isCompact: isPortraitPad,
                    selection: heroIndex % heroCandidates.count,
                    select: { index in
                        withAnimation(.easeInOut(duration: 0.45)) {
                            heroIndex = index
                        }
                    }
                )
                .padding(.bottom, isPortraitPad ? 12 : 22)
                // Centred in the part of the hero the sidebar leaves visible.
                .padding(.leading, sidebarInset)
            }
        }
        #if os(iOS)
        .simultaneousGesture(heroSwipe)
        #endif
        .frame(maxWidth: .infinity)
        .modifier(HeroFrame(
            height: isCardHero ? heroHeight - heroCardTopInset : heroHeight,
            followsPosterShape: isPortraitHeroFrame
        ))
        .clipShape(.rect(cornerRadius: isCardHero ? Self.heroCardCornerRadius : 0, style: .continuous))
        .overlay {
            if isCardHero {
                RoundedRectangle(cornerRadius: Self.heroCardCornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.1))
            }
        }
        .shadow(color: .black.opacity(isCardHero ? 0.35 : 0), radius: 24, y: 12)
        .padding(.horizontal, isCardHero ? horizontalInset : 0)
        .padding(.leading, isCardHero ? sidebarInset : 0)
        .padding(.top, isCardHero ? heroCardTopInset : 0)
        .animation(.easeInOut(duration: 0.45), value: featured.id)
        // `.contain` keeps the hero's Play, info and paging buttons reachable
        // by VoiceOver; `.combine` merged them into one unactionable element.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Featured: \(featured.title)")
    }

    private var heroCarousel: HeroTrailerPreferences { settings.preferences.heroTrailer }

    /// Restarts the trailer for a new title or changed trailer settings.
    private var showsPlayingHeroTrailer: Bool {
        heroTrailer.isVisible && heroTrailerIsPlaying && scenePhase == .active
    }

    private func openHeroTrailer(_ featured: MediaItem) {
        guard showsPlayingHeroTrailer, let handoff = heroTrailer.consumeForPlayback() else { return }
        playback.startTrailer(item: featured, source: handoff.source, startAt: handoff.position, preferences: settings.preferences)
    }

    private var usesLowPower: Bool {
        LowPowerMonitor.shared.isActive(settings.preferences.display.lowPowerMode)
    }

    private var heroTrailerKey: String {
        let preferences = settings.preferences.heroTrailer
        return "\(usesLowPower)-\(featured?.id ?? "")-\(preferences.autoplay)-\(preferences.startDelaySeconds)-\(preferences.startsWithSound)-\(reduceMotion)-\(heroTrailerReplay)"
    }

    /// The trailer pauses in a hidden tab, while the streams page is open,
    /// while something else is playing, and while a title page is open.
    private var heroTrailerIsPlaying: Bool {
        !isOnboardingPreview && isActiveDestination && sourcePlaybackItem == nil && !playback.isPresentingPlayer && !playback.hasPlayer && !playback.isPictureInPictureActive && scenePhase == .active
            && HeroTrailerFocus.shared.homeMayPlay && heroIsOnScreen && windowIsVisible
            && !ProcessInfo.processInfo.isLowPowerModeEnabled
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
            SectionHeader(title: "Continue Watching") {
                if trackerLibrary.availableSources.count > 1 {
                    TrackerSourceMenu(selection: $trackerLibrary.continueWatchingSource)
                        .padding(.leading, 6)
                }
            }
            ForEach(continueWatchingSource.trackers) { tracker in
                TrackerSyncStatusLine(kind: tracker)
            }
            if items.isEmpty, continueWatchingSource != .local {
                Text(continueWatchingSource.trackers.contains { trackerLibrary.state($0) == .syncing }
                     ? "Reading \(continueWatchingSource.title)…"
                     : "Nothing in progress on \(continueWatchingSource.title).")
                    .foregroundStyle(.secondary)
            } else {
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
        .task(id: continueWatchingSource) {
            for tracker in continueWatchingSource.trackers {
                trackerLibrary.syncIfNeeded(tracker, addons: store.installedAddons)
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

    private var reminderSeries: [MediaItem] {
        store.localMediaSnapshots
            .filter { $0.item.kind == .series && ($0.isInWatchlist || ($0.item.progress ?? 0) > 0) }
            .map(\.item)
    }

    private var episodeReminderKey: String {
        let day = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
        let ids = reminderSeries.map(\.id).joined(separator: "|")
        return "\(settings.preferences.display.episodeNotifications)-\(day)-\(ids)"
    }

    /// Looks further ahead than the Home shelf, whose range is its own setting.
    private func scheduleEpisodeReminders() async {
        let service = UpcomingService(now: { .now }, calendar: .current) { item in
            let enriched = await metadata.details(for: item)
            guard enriched.details?.seasons.contains(where: { !$0.episodes.isEmpty }) == true else {
                throw UpcomingServiceError.metadataUnavailable
            }
            return enriched
        }
        let result = await service.load(savedItems: reminderSeries, lookAheadDays: 60, itemLimit: nil)
        guard !Task.isCancelled else { return }
        await EpisodeNotifications.schedule(result.items)
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
        // The shared window layer owns full-bleed hero artwork on Mac.
        Color.clear
        #else
        HomeArtworkBackground(item: displayFeatured, isEnabled: usesDynamicBackground)
            .environment(\.colorScheme, usesDynamicBackground ? .dark : colorScheme)
        #endif
    }

    /// Settings › Layout › Home Layout › Dynamic Background Color.
    private var usesDynamicBackground: Bool {
        homeLayout.preferences.dynamicBackground
    }

    private func landscapeHeroArtwork(_ featured: MediaItem) -> some View {
        HeroArtworkCanvas(
            item: featured,
            source: .home,
            artworkAlignment: .topTrailing,
            drawsArtworkLocally: isCardHero
        )
    }

    #if os(iOS)
    /// An iPhone held upright: a backdrop would be cropped to a sliver, so
    /// the hero draws portrait art.
    private var isPortraitPhone: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .regular
    }
    #endif

    private var showsHeroArrows: Bool {
        #if os(iOS)
        false
        #else
        true
        #endif
    }

    /// The portrait hero takes a poster's 2:3 shape, so a textless poster
    /// fills it without cropping at any iPhone width.
    private var isPortraitHeroFrame: Bool {
        #if os(iOS)
        isPortraitPhone && !isCardHero
        #else
        false
        #endif
    }

    private var isPortraitPad: Bool {
        #if os(iOS)
        horizontalSizeClass == .regular && viewportSize.height > viewportSize.width
        #else
        false
        #endif
    }

    private var isLandscapePhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone && verticalSizeClass == .compact
        #else
        false
        #endif
    }

    private var homeIdentityWidth: CGFloat {
        isPortraitPad ? 280 : CinematicHeroLayout.logoWidth
    }

    private var homeLogoHeight: CGFloat {
        isPortraitPad ? 78 : CinematicHeroLayout.logoHeight
    }

    @ViewBuilder
    private func landscapeHeroIdentity(_ featured: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Anchor identity in the lower third while letting the local
            // hero artwork breathe above it.
            Spacer(minLength: heroTopSpacing)

            VStack(alignment: .leading, spacing: isLandscapePhone ? 6 : (isPortraitPad ? 8 : 12)) {
                if let logoURL = featured.logoURL {
                    TitleLogoView(
                        url: logoURL,
                        title: featured.title,
                        maximumWidth: homeIdentityWidth,
                        maximumHeight: homeLogoHeight,
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
                            width: homeIdentityWidth,
                            height: homeLogoHeight,
                            alignment: .center
                        )
                } else {
                    // A basic catalog item can arrive before the detail
                    // request has supplied its transparent logo. Preserve
                    // the logo canvas instead of flashing a duplicate
                    // plain-text title for one render pass.
                    Color.clear
                        .frame(
                            width: homeIdentityWidth,
                            height: homeLogoHeight,
                            alignment: .center
                        )
                        .accessibilityHidden(true)
                }

                HeroMetadataLine(item: featured, width: homeIdentityWidth)

                if settings.preferences.integrations.mdblistEnabled {
                    MDBListRatingsView(
                        state: heroRatings.state(forItemID: featured.id).applying(settings.preferences.mdblistRatings),
                        retry: { retryHeroRatings(for: featured) },
                        openSettings: { showsMDBListSettings = true }
                    )
                    .frame(width: homeIdentityWidth, alignment: .leading)
                }

                JustifiedSynopsisText(
                    text: featured.overview,
                    lineLimit: 3,
                    fontSize: CinematicHeroLayout.synopsisFontSize
                )
                    .frame(width: homeIdentityWidth, alignment: .leading)

                HeroActionRow(
                    width: homeIdentityWidth,
                    isSaved: store.isSaved(featured),
                    libraryAction: { store.toggleSaved(featured) },
                    watchAction: heroWatchAction(for: featured) ?? HeroWatchAction(
                        systemImage: "eye",
                        accessibilityLabel: resolvedFeatured?.id == featured.id
                            ? "Episode information unavailable" : "Loading episode information",
                        perform: {},
                        isEnabled: false
                    )
                ) {
                    NavigationLink(value: featured) {
                        HeroPrimaryActionLabel(title: "View Details")
                    }
                    .omniaCapsuleGlassButton()
                }
            }
            // AsyncImage keeps state while SwiftUI reuses a view tree.
            // A title-specific identity prevents a previous transparent
            // logo from appearing over the next title's backdrop.
            .frame(width: homeIdentityWidth, alignment: .leading)
            .controlSize(isPortraitPad ? .small : .regular)
            .id(featured.id)
            .transition(.opacity)
        }
        .frame(maxHeight: .infinity, alignment: .leading)
        .padding(.leading, CinematicHeroLayout.horizontalInset + sidebarInset)
            .padding(.bottom, isPortraitPad ? 56 : 38)
    }

    #if os(iOS)
    private func portraitHeroIdentity(_ featured: MediaItem) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            PortraitHeroIdentity(
                item: featured,
                showsTitleWithoutLogo: resolvedFeatured?.id == featured.id,
                isSaved: store.isSaved(featured),
                libraryAction: { store.toggleSaved(featured) },
                watchAction: heroWatchAction(for: featured) ?? HeroWatchAction(
                    systemImage: "eye",
                    accessibilityLabel: resolvedFeatured?.id == featured.id
                        ? "Episode information unavailable" : "Loading episode information",
                    perform: {},
                    isEnabled: false
                ),
                ratings: { portraitHeroRatings(featured) }
            ) {
                NavigationLink(value: featured) {
                    HeroPrimaryActionLabel(title: "View Details")
                }
                .omniaCapsuleGlassButton()
            }
            .id(featured.id)
            .transition(.heroIdentity)
            // Room for the page dots under the buttons.
            .padding(.bottom, heroCandidates.count > 1 ? 46 : 22)
        }
    }

    @ViewBuilder
    private func portraitHeroRatings(_ featured: MediaItem) -> some View {
        if settings.preferences.integrations.mdblistEnabled {
            MDBListRatingsView(
                state: heroRatings.state(forItemID: featured.id).applying(settings.preferences.mdblistRatings),
                retry: { retryHeroRatings(for: featured) },
                openSettings: { showsMDBListSettings = true },
                alignment: .center
            )
        }
    }

    /// Next or previous title by swiping the hero sideways, as in Nuvio.
    private var heroSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                if !isSwipingHero, abs(value.translation.width) > abs(value.translation.height) {
                    isSwipingHero = true
                }
            }
            .onEnded { value in
                let dx = value.translation.width
                if heroCandidates.count > 1, abs(dx) > 50, abs(dx) > abs(value.translation.height) {
                    moveHero(by: dx < 0 ? 1 : -1)
                }
                Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    isSwipingHero = false
                }
            }
    }
    #endif

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
        isLandscapePhone ? max(360, viewportSize.height) : 700
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
        // iPad's larger logo and synopsis need more of the hero.
        isLandscapePhone ? 64 : (horizontalSizeClass == .regular ? 340 : 410)
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
                    MediaItem.placeholderArtworkColor
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
                    .omniaGlass(.panels, in: Capsule())
                    .opacity(isActive ? 1 : 0)
            }
            .contentShape(Capsule())
            .animation(.easeInOut(duration: 0.16), value: isActive)
    }
}

private struct HeroPageControl: View {
    let count: Int
    var isCompact = false
    let selection: Int
    let select: (Int) -> Void

    var body: some View {
        HStack(spacing: isCompact ? 5 : 7) {
            ForEach(0..<count, id: \.self) { index in
                Button {
                    select(index)
                } label: {
                    Circle()
                        .fill(.white.opacity(index == selection ? 1 : 0.42))
                        .frame(width: index == selection ? (isCompact ? 6 : 8) : (isCompact ? 4 : 6),
                               height: index == selection ? (isCompact ? 6 : 8) : (isCompact ? 4 : 6))
                        .frame(width: 20, height: 20)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Feature \(index + 1) of \(count)")
                .accessibilityValue(index == selection ? "Current feature" : "")
            }
        }
        .padding(.horizontal, 8)
        // No backing shape, so a soft shadow keeps the dots clear of bright art.
        .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
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
