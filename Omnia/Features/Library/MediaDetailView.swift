//
//  MediaDetailView.swift
//  Omnia
//

import SwiftUI

struct MediaDetailView: View {
    let item: MediaItem
    @Environment(OmniaStore.self) private var store
    @Environment(LiveMetadataStore.self) private var metadata
    @Environment(SettingsPreferencesStore.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif
    @Environment(\.displayPreferences) private var display
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isActiveDestination) private var isActiveDestination
    @Environment(\.isOnboardingPreview) private var isOnboardingPreview
    @Environment(PlaybackSession.self) private var playback
    /// Account › Tracking: More Like This source and Trakt comments.
    @State private var trackerLibrary = TrackerLibraryStore.shared
    @State private var resolvedItem: MediaItem?
    @State private var sourceRequest: PlaybackRequest?
    @State private var showsSynopsis = false
    @State private var creditSection: CreditSection = .cast
    @State private var selectedSeasonNumber = 1
    @State private var selectedEpisode: MediaEpisode?
    @State private var ratingsLoader = MDBListRatingsLoader()
    @State private var ratingsCredentialEpoch = UUID()
    @State private var showsMDBListSettings = false
    @State private var showsShuffle = false
    /// The random episode the Play button starts while shuffle is on.
    @State private var shufflePrimary: MediaEpisode?
    /// Settings › Layout › Detail Page › Poster Transition.
    @State private var posterTransition: PosterTransitionCenter.Anchor?
    @State private var hasTakenPosterTransition = false
    /// The Home hero's trailer, played in this page's hero with the same
    /// Settings › Home Layout › Hero options.
    @State private var heroTrailer = HomeHeroTrailerModel()
    @State private var trailerToken = UUID()
    /// The trailer pauses while the hero is scrolled away or the window
    /// can't be seen.
    @State private var heroIsOnScreen = true
    @State private var windowIsVisible = true

    private var displayItem: MediaItem { resolvedItem ?? item }

    /// Settings › Home › Detail Page › Background.
    private var usesArtworkBackground: Bool {
        HeroBackdropPresentation.usesArtworkAccentBelowHero && display.detailBackground == .artworkColor
    }

    private var watchState: LocalMediaWatchState {
        store.localMediaSnapshots.first(where: { $0.mediaID == displayItem.id })?.watchState ?? .empty
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                detailHero
                    .onScrollVisibilityChange(threshold: 0.15) { heroIsOnScreen = $0 }
                detailInformation
            }
        }
        // Under the home indicator too, so the page doesn't end in a band.
        .background { screenBackground.ignoresSafeArea() }
        .overlay {
            if let posterTransition {
                PosterTransitionOverlay(anchor: posterTransition) {
                    self.posterTransition = nil
                }
            }
        }
        .onAppear {
            // Only the first appearance after a poster click animates, not
            // returning to the page from a title opened on it.
            guard !isOnboardingPreview, !hasTakenPosterTransition else { return }
            hasTakenPosterTransition = true
            if display.posterTransition {
                posterTransition = PosterTransitionCenter.shared.consume(itemID: item.id)
            }
        }
        // Match Home: the scroll container, not merely its first child,
        // owns the top safe area. The detail hero can therefore meet the
        // stable transparent toolbar (or iPad's tab bar) instead of leaving
        // a band above it.
        .ignoresSafeArea(edges: .top)
        #if os(iOS)
        // Outside the page's safe-area override, so it stays below the
        // status and tab bars and in place while the page scrolls.
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    // Tinted glass stays visible over light artwork and over
                    // the dark page once the hero scrolls away.
                    .glassEffect(.regular.tint(.black.opacity(0.35)).interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, horizontalInset)
            .padding(.top, 10)
            .accessibilityLabel("Back")
        }
        #endif
        .omniaNavigationTitle(displayItem.title, screen: .mediaDetail)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .task(id: item.id) {
            if isOnboardingPreview {
                let resolved = await metadata.details(for: item)
                guard !Task.isCancelled else { return }
                resolvedItem = resolved
                return
            }
            if let fromServer = await MediaServerStore.shared.serverDetails(for: item) {
                // A media server title that keeps the server's own details
                // (Use Add-on Metadata off).
                guard !Task.isCancelled else { return }
                resolvedItem = fromServer
                selectedSeasonNumber = fromServer.details?.seasons.first(where: { $0.seasonNumber > 0 })?.seasonNumber
                    ?? fromServer.details?.seasons.first?.seasonNumber ?? 1
            } else if AddonCatalogStore.isAddonMode(store) {
                _ = await loadAddonFirstDetails()
            } else {
                _ = await loadProviderFirstDetails()
            }
        }
        .task(id: ratingsRequestKey) {
            ratingsLoader.cancel()
            guard !isOnboardingPreview, settings.preferences.integrations.mdblistEnabled else { return }
            await ratingsLoader.load(
                for: displayItem,
                preferences: settings.preferences.mdblistRatings
            )
            guard !Task.isCancelled else { return }
            if case let .loaded(presentation) = ratingsLoader.state {
                settings.recordMDBListRatingProviders(presentation.discoveredProviderIDs)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .providerCredentialDidChange)) { change in
            guard change.object as? String == UserManagedProviderCredential.mdblist.rawValue else { return }
            ratingsLoader.reset()
            ratingsCredentialEpoch = UUID()
        }
        .omniaStreamsPage(isPresented: showsSourceSelector) {
            if let request = sourceRequest {
                PlaybackSourceSheet(
                    item: request.item,
                    episode: request.episode,
                    resumeAt: request.resumeAt,
                    onClose: { sourceRequest = nil }
                )
                .id(request.id)
            }
        }
        .omniaGlassModal(isPresented: $showsSynopsis) {
            SynopsisSheet(
                title: displayItem.title,
                synopsis: displayItem.overview,
                onClose: { showsSynopsis = false }
            )
        }
        .sheet(isPresented: $showsMDBListSettings) {
            MDBListSettingsSheet()
        }
        .sheet(isPresented: $showsShuffle) {
            EpisodeShuffleSheet(
                item: displayItem,
                episodes: detailEpisodes,
                watchState: watchState
            ) { episode in
                selectedEpisode = episode
                sourceRequest = PlaybackRequest(item: displayItem, episode: episode, resumeAt: nil)
            }
        }
        .task(id: shuffleKey) {
            guard !isOnboardingPreview else { return }
            shufflePrimary = isShuffleActive ? pickShuffleEpisode() : nil
        }
        .task(id: heroTrailerKey) {
            // Wait for the page's own details so the trailer matches what
            // the page shows instead of fetching them a second time.
            guard !isOnboardingPreview, resolvedItem != nil else { return }
            await heroTrailer.load(
                displayItem,
                preferences: settings.preferences.heroTrailer,
                metadata: metadata,
                autoplayAllowed: !reduceMotion
            )
        }
        #if os(macOS)
        .background { WindowVisibilityReader(isVisible: $windowIsVisible) }
        #endif
        .onAppear {
            if !isOnboardingPreview { HeroTrailerFocus.shared.appear(trailerToken) }
        }
        .onDisappear {
            ratingsLoader.cancel()
            if !isOnboardingPreview { HeroTrailerFocus.shared.disappear(trailerToken) }
        }
    }

    private var heroTrailerKey: String {
        let preferences = settings.preferences.heroTrailer
        return "\(item.id)-\(resolvedItem != nil)-\(displayItem.details?.heroTrailer?.id ?? "")-\(preferences.autoplay)-\(preferences.startDelaySeconds)-\(preferences.startsWithSound)-\(reduceMotion)"
    }

    /// Paused while the streams page is open, while something is playing,
    /// and while another title page is on top of this one.
    private var heroTrailerIsPlaying: Bool {
        !isOnboardingPreview && isActiveDestination && sourceRequest == nil && playback.source == nil
            && HeroTrailerFocus.shared.titlePageMayPlay(trailerToken)
            && heroIsOnScreen && windowIsVisible
    }

    private var detailHero: some View {
        ZStack(alignment: .bottomLeading) {
            #if os(iOS)
            if horizontalSizeClass == .compact && verticalSizeClass == .regular {
                PortraitHeroArtwork(item: displayItem)
            } else {
                HeroArtworkCanvas(item: displayItem, source: .detail, artworkAlignment: .topTrailing)
            }
            #else
            HeroArtworkCanvas(item: displayItem, source: .detail, artworkAlignment: .topTrailing)
            #endif

            HomeHeroTrailerLayer(model: heroTrailer, isPlaying: heroTrailerIsPlaying)

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                CinematicHeroColumn {
                    detailIdentity
                    actions
                }
            }
            .padding(.leading, CinematicHeroLayout.horizontalInset)
            .padding(.bottom, 34)
        }
        // In the hero's bottom-right corner, scrolling away with it
        // (Dafa, 2026-10-22).
        .overlay(alignment: .bottomTrailing) {
            HomeHeroTrailerMuteButton(model: heroTrailer)
                .padding(.trailing, 28)
                .padding(.bottom, 34)
                .animation(.snappy(duration: 0.25), value: heroTrailer.isVisible)
        }
        .frame(maxWidth: .infinity, minHeight: detailHeroHeight, maxHeight: detailHeroHeight)
        // The hero owns the top safe area on every platform. On macOS the
        // compact system Back control floats above this artwork; it must not
        // create a separate black titlebar band.
        .ignoresSafeArea(edges: .top)
    }

    private var detailIdentity: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let logoURL = displayItem.logoURL {
                TitleLogoView(
                    url: logoURL,
                    title: displayItem.title,
                    maximumWidth: CinematicHeroLayout.logoWidth,
                    maximumHeight: CinematicHeroLayout.logoHeight,
                    alignment: .center
                )
            } else if resolvedItem != nil {
                // Details have loaded and the provider has no logo: show the
                // title as text instead of an empty gap.
                Text(displayItem.title)
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
                // Detail metadata may update with a transparent logo after
                // the first render. Reserve its canvas rather than showing a
                // flash of duplicate title text.
                Color.clear
                    .frame(
                        width: CinematicHeroLayout.logoWidth,
                        height: CinematicHeroLayout.logoHeight,
                        alignment: .center
                    )
                    .accessibilityHidden(true)
            }

            HeroMetadataLine(item: displayItem)

            if settings.preferences.integrations.mdblistEnabled {
                MDBListRatingsView(
                    state: currentRatingsState,
                    retry: retryRatings,
                    openSettings: { showsMDBListSettings = true }
                )
                .frame(width: CinematicHeroLayout.logoWidth, alignment: .leading)
            }

            Button {
                showsSynopsis = true
            } label: {
                JustifiedSynopsisText(
                    text: displayItem.overview,
                    lineLimit: synopsisLineLimit,
                    fontSize: CinematicHeroLayout.synopsisFontSize
                )
                    .frame(width: CinematicHeroLayout.synopsisWidth, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Synopsis")
            .accessibilityHint("Opens the full synopsis")

        }
    }

    private var detailInformation: some View {
        VStack(alignment: .leading, spacing: 34) {
            ForEach(display.orderedDetailSections) { section in
                detailSection(section)
            }
            // Account › Tracking › Trakt Comments.
            if trackerLibrary.showsTraktComments, TraktExtrasClient.clientID != nil {
                TraktCommentsSection(item: displayItem)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, horizontalInset)
        .padding(.top, 32)
        .padding(.bottom, 72)
        .background {
            if usesArtworkBackground {
                HeroAccentBackground(item: displayItem)
            } else {
                pageBackground
            }
        }
        // The info sections sit on the dark artwork accent; keep their
        // text light in Light appearance.
        .environment(\.colorScheme, usesArtworkBackground ? .dark : colorScheme)
    }

    /// One of the page's sections, drawn in the order chosen in Settings ›
    /// Layout › Detail Page. Empty sections draw nothing.
    @ViewBuilder
    private func detailSection(_ section: DetailSection) -> some View {
        switch section {
        case .genres:
            if !displayItem.genres.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Genres")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    FlowLayout(spacing: 8) {
                        ForEach(displayItem.genres, id: \.self) { genre in
                            Text(genre)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(.primary.opacity(0.08), in: Capsule())
                        }
                    }
                }
            }
        case .facts:
            if let details = displayItem.details {
                TitleFactsView(details: details, isSeries: displayItem.kind == .series)
            }
        case .episodes:
            if let details = displayItem.details, displayItem.kind == .series, !details.seasons.isEmpty {
                EpisodeShelf(
                    seasons: details.seasons,
                    selectedSeasonNumber: $selectedSeasonNumber,
                    resumeProgress: resumeProgressPresentation,
                    watchState: watchState,
                    selectEpisode: { episode in
                        selectedEpisode = episode
                        sourceRequest = PlaybackRequest(item: displayItem, episode: episode, resumeAt: nil)
                    }
                )
            }
        case .trailers:
            if let details = displayItem.details, !details.trailers.isEmpty {
                VideoShelf(title: "Trailers", videos: details.trailers)
            }
        case .bonusContent:
            if let details = displayItem.details, !details.bonusContent.isEmpty {
                VideoShelf(title: "Bonus Content", videos: details.bonusContent)
            }
        case .people:
            if let details = displayItem.details, !displayPeople(for: details).isEmpty {
                peopleSection(details: details)
            }
        case .production:
            if let details = displayItem.details, !productionEntities(details).isEmpty {
                productionSection(details: details)
            }
        case .studio:
            if let details = displayItem.details, !details.studioTitles.isEmpty {
                if let studio = details.studios.first, studio.hasTMDBPage {
                    detailShelf(title: studioShelfTitle(details), items: details.studioTitles) {
                        EntityTitlesView(
                            kind: .company,
                            entityID: studio.id,
                            name: studio.name,
                            logoURL: studio.logoURL,
                            initialType: mediaType
                        )
                    }
                } else {
                    detailShelf(title: studioShelfTitle(details), items: details.studioTitles)
                }
            }
        case .collection:
            if let collection = displayItem.details?.collection, !collection.members.isEmpty {
                detailShelf(title: collection.name, items: collection.members) {
                    TitleListView(title: collection.name, items: collection.members)
                }
            }
        case .recommendations:
            // Account › Tracking › More Like This Source.
            if trackerLibrary.moreLikeThisSource == .trakt, TraktExtrasClient.clientID != nil {
                TraktRelatedShelf(item: displayItem) { tmdbRecommendations }
            } else {
                tmdbRecommendations
            }
        case .similar:
            if let details = displayItem.details, !details.similar.isEmpty {
                relatedShelf(.similar, title: "Similar Titles", items: details.similar, details: details)
            }
        }
    }

    @ViewBuilder
    private var tmdbRecommendations: some View {
        if let details = displayItem.details, !details.recommendations.isEmpty {
            relatedShelf(.recommendations, title: "More Like This", items: details.recommendations, details: details)
        }
    }

    private var ratingsRequestKey: String {
        let route = try? MDBListMetadataClient.lookupRoute(for: displayItem)
        return "\(item.id)|\(String(describing: route))|\(settings.preferences.integrations.mdblistEnabled)|\(ratingsCredentialEpoch)"
    }

    /// Add-on mode (Nuvio's model): the add-on that listed the title is the
    /// source of truth. TMDB/TVDB only fills what the add-on left empty, such
    /// as cast photos or recommendations, limited to the modules turned on in
    /// Settings › Integrations › TMDB Enrichment. When no add-on answers,
    /// TMDB supplies the whole page, as in Nuvio.
    private func loadAddonFirstDetails() async -> MediaItem {
        let enrichment = settings.preferences.integrations.tmdb
        // Start the independent provider lookup while add-ons are answering.
        async let providerMetadata = initialAddonEnrichment(enabled: enrichment.enabled)
        let fromAddon = await AddonMetadataResolver.resolve(item, addons: store.installedAddons)
        guard !Task.isCancelled else { return fromAddon ?? item }
        let addonFirst = fromAddon ?? item
        if fromAddon != nil {
            resolvedItem = addonFirst
            selectedSeasonNumber = addonFirst.details?.seasons.first(where: { $0.seasonNumber > 0 })?.seasonNumber
                ?? addonFirst.details?.seasons.first?.seasonNumber ?? 1
            guard enrichment.enabled else { return addonFirst }
        }

        var fetched = await providerMetadata
        // An add-on may supply identifiers missing from the catalog item.
        if !enrichment.enabled || (fetched.details == nil && addonFirst.externalIDs != item.externalIDs) {
            fetched = await metadata.details(for: addonFirst)
        }
        guard !Task.isCancelled else { return addonFirst }
        let provider = fromAddon == nil ? fetched : fetched.restricted(to: enrichment)
        let resolved = addonFirst.fillingGaps(from: provider)
        resolvedItem = resolved
        if addonFirst.details?.seasons.isEmpty != false {
            selectedSeasonNumber = resolved.details?.seasons.first?.seasonNumber ?? 1
        }
        return resolved
    }

    private func initialAddonEnrichment(enabled: Bool) async -> MediaItem {
        guard enabled else { return item }
        let fetched = await metadata.details(for: item)
        guard !Task.isCancelled else { return item }
        // Keep the catalog's identity and fields while the owning add-on loads.
        // Its eventual answer still takes precedence in loadAddonFirstDetails.
        resolvedItem = item.fillingGaps(from: fetched.restricted(to: settings.preferences.integrations.tmdb))
        selectedSeasonNumber = resolvedItem?.details?.seasons.first?.seasonNumber ?? 1
        return fetched
    }

    /// Without catalog add-ons, Omnia's own providers lead and add-ons fill
    /// gaps.
    private func loadProviderFirstDetails() async -> MediaItem {
        async let providerMetadata = metadata.details(for: item)
        async let addonMetadata = StremioAddonClient.fetchMetadata(
            for: item,
            addons: store.installedAddons
        )
        let providerResolved = await providerMetadata
        // Show provider metadata as soon as it arrives. Add-on meta requests
        // can take up to their 20 second timeout, and waiting on them left
        // the page without seasons or cast for that whole time.
        guard !Task.isCancelled else { return providerResolved }
        resolvedItem = providerResolved
        selectedSeasonNumber = providerResolved.details?.seasons.first?.seasonNumber ?? 1

        let fromAddons = await addonMetadata
        guard !Task.isCancelled else { return providerResolved }
        let resolved = fromAddons.reduce(providerResolved) { partial, addonItem in
            partial.mergingAddonMetadata(addonItem)
        }
        resolvedItem = resolved
        if providerResolved.details?.seasons.isEmpty != false {
            selectedSeasonNumber = resolved.details?.seasons.first?.seasonNumber ?? 1
        }
        return resolved
    }

    private var actions: some View {
        HeroActionRow(
            width: CinematicHeroLayout.logoWidth,
            isSaved: store.isSaved(displayItem),
            libraryAction: { store.toggleSaved(displayItem) },
            watchAction: heroWatchAction,
            shuffleAction: heroShuffleAction
        ) {
            Button {
                let intent = playbackIntent
                // Shuffle (Nuvio): an episode in progress resumes; otherwise
                // Play starts the random pick.
                if intent.resumeAt == nil, let shuffled = shufflePrimary {
                    selectedEpisode = shuffled
                    sourceRequest = PlaybackRequest(item: intent.item, episode: shuffled, resumeAt: nil)
                    shufflePrimary = pickShuffleEpisode(excluding: shuffled) ?? shuffled
                    return
                }
                selectedEpisode = intent.episode
                sourceRequest = PlaybackRequest(item: intent.item, episode: intent.episode, resumeAt: intent.resumeAt)
            } label: {
                HeroPrimaryActionLabel(
                    title: shuffledPlayTitle ?? playbackActionTitle,
                    resumeProgress: playbackActionTitle == "Resume" ? resumeProgressPresentation : nil
                )
            }
            #if os(macOS)
            .omniaCapsuleGlassButton()
            #else
            .buttonStyle(.plain)
            #endif
        }
    }

    /// Settings › Layout › Detail Page › Shuffle.
    private var heroShuffleAction: HeroWatchAction? {
        guard display.episodeShuffleAvailable, displayItem.kind == .series, !detailEpisodes.isEmpty else { return nil }
        let isOn = EpisodeShuffleStore.shared.settings(for: displayItem.id).enabled
        return HeroWatchAction(
            systemImage: "shuffle",
            accessibilityLabel: isOn ? "Shuffle On" : "Shuffle",
            perform: { showsShuffle = true }
        )
    }

    private var isShuffleActive: Bool {
        EpisodeShuffleStore.shared.isActive(for: displayItem, display: display) && !detailEpisodes.isEmpty
    }

    private var shuffleKey: String {
        let settings = EpisodeShuffleStore.shared.settings(for: displayItem.id)
        return "\(isShuffleActive)|\(settings.includeWatched)|\(detailEpisodes.count)"
    }

    private var shuffledPlayTitle: String? {
        guard playbackIntent.resumeAt == nil, let shufflePrimary else { return nil }
        return "Play S\(shufflePrimary.seasonNumber) E\(shufflePrimary.episodeNumber)"
    }

    private func pickShuffleEpisode(excluding episode: MediaEpisode? = nil) -> MediaEpisode? {
        EpisodeShuffleStore.shared.pick(
            for: displayItem.id,
            episodes: detailEpisodes,
            watchState: watchState,
            includeWatched: EpisodeShuffleStore.shared.settings(for: displayItem.id).includeWatched,
            excluding: episode
        )
    }

    private var detailEpisodes: [MediaEpisode] {
        displayItem.details?.seasons.flatMap(\.episodes) ?? []
    }

    private var showsSourceSelector: Binding<Bool> {
        Binding(
            get: { sourceRequest != nil },
            set: { if !$0 { sourceRequest = nil } }
        )
    }

    private var currentDetailEpisode: MediaEpisode? {
        selectedEpisode
            ?? displayItem.resumeEpisode
            ?? detailEpisodes.first(where: { $0.seasonNumber == selectedSeasonNumber })
            ?? detailEpisodes.first
    }

    private var heroWatchAction: HeroWatchAction? {
        guard let action = MediaDetailWatchActionPresentation.action(
            kind: displayItem.kind,
            currentEpisode: currentDetailEpisode,
            watchState: store.watchState(for: displayItem)
        ) else { return nil }
        return HeroWatchAction(
            systemImage: action.systemImage,
            accessibilityLabel: action.accessibilityLabel,
            perform: {
                store.applyWatchCommand(
                    action.command,
                    to: displayItem,
                    episodes: detailEpisodes,
                    leavingContinueWatching: action.leavesContinueWatching
                )
            }
        )
    }

    private var currentRatingsState: MDBListRatingsLoadState {
        ratingsLoader.state(forItemID: item.id).applying(settings.preferences.mdblistRatings)
    }

    private func retryRatings() {
        let title = displayItem
        Task {
            await ratingsLoader.retry(
                for: title,
                preferences: settings.preferences.mdblistRatings
            )
            if case let .loaded(presentation) = ratingsLoader.state {
                settings.recordMDBListRatingProviders(presentation.discoveredProviderIDs)
            }
        }
    }

    private func peopleSection(details: MediaTitleDetails) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("People")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Picker("People", selection: $creditSection) {
                    ForEach(CreditSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.menu)
                .tint(.primary)
            }

            ShelfScrollView(
                items: displayPeople(for: details),
                spacing: 14,
                itemSpan: 126,
                accessibilityLabel: "People"
            ) { person in
                if Int(person.id) != nil {
                    OmniaPageLink {
                        PersonDetailView(
                            personID: person.id,
                            name: person.name,
                            photoURL: person.profileURL,
                            prefersCrew: creditSection != .cast
                        )
                    } label: {
                        CreditCard(person: person)
                    }
                    .buttonStyle(.plain)
                } else {
                    CreditCard(person: person)
                }
            }
        }
    }

    private func detailShelf(title: String, items: [MediaItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title)
            ShelfScrollView(items: items, itemSpan: posterItemSpan, accessibilityLabel: title) { related in
                MediaPoster(item: related)
            }
        }
    }

    /// A shelf whose header opens the section's own page, as in Nuvio.
    private func detailShelf<Destination: View>(
        title: String,
        items: [MediaItem],
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderLink(title: title, destination: destination)
            ShelfScrollView(items: items, itemSpan: posterItemSpan, accessibilityLabel: title) { related in
                MediaPoster(item: related)
            }
        }
    }

    /// More Like This and Similar open every TMDB title on their own page;
    /// a list from an add-on shows on a page as it is.
    @ViewBuilder
    private func relatedShelf(
        _ kind: MetadataRelatedKind,
        title: String,
        items: [MediaItem],
        details: MediaTitleDetails
    ) -> some View {
        if let tmdbID = details.tmdbID {
            detailShelf(title: title, items: items) {
                RelatedTitlesView(kind: kind, tmdbID: tmdbID, type: mediaType, title: "\(title) · \(displayItem.title)")
            }
        } else {
            detailShelf(title: title, items: items) {
                TitleListView(title: "\(title) · \(displayItem.title)", items: items)
            }
        }
    }

    private var mediaType: MediaType {
        displayItem.kind == .series ? .series : .movie
    }

    /// Nuvio's Production section: a show's networks, or a film's studios,
    /// as logo chips that open the company's or network's page.
    private func productionEntities(_ details: MediaTitleDetails) -> [(studio: MediaStudio, kind: MetadataEntityKind)] {
        let networks = details.networks.map { ($0, MetadataEntityKind.network) }
        let companies = (details.productionCompanies.isEmpty ? details.studios : details.productionCompanies)
            .map { ($0, MetadataEntityKind.company) }
        let entities = displayItem.kind == .series
            ? (networks.isEmpty ? companies : networks)
            : (companies.isEmpty ? networks : companies)
        return Array(entities.prefix(8))
    }

    private func productionSection(details: MediaTitleDetails) -> some View {
        let isNetworks = productionEntities(details).first?.kind == .network
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: isNetworks ? "Networks" : "Production")
            FlowLayout(spacing: 10) {
                ForEach(productionEntities(details), id: \.studio.id) { entity in
                    if entity.studio.hasTMDBPage {
                        OmniaPageLink {
                            EntityTitlesView(
                                kind: entity.kind,
                                entityID: entity.studio.id,
                                name: entity.studio.name,
                                logoURL: entity.studio.logoURL,
                                initialType: mediaType
                            )
                        } label: {
                            ProductionChip(studio: entity.studio)
                        }
                        .buttonStyle(.plain)
                        .help("Show titles from \(entity.studio.name)")
                    } else {
                        ProductionChip(studio: entity.studio)
                    }
                }
            }
        }
    }

    private func displayPeople(for details: MediaTitleDetails) -> [MediaCredit] {
        switch creditSection {
        case .cast:
            return details.cast
        case .directors:
            return details.crew.filter { $0.role?.compare("Director", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        case .writers:
            return details.crew.filter {
                guard let role = $0.role?.lowercased() else { return false }
                return role.contains("writer") || role.contains("screenplay") || role.contains("story")
            }
        case .editors:
            return details.crew.filter { $0.role?.localizedCaseInsensitiveContains("editor") == true }
        }
    }

    private func studioShelfTitle(_ details: MediaTitleDetails) -> String {
        guard let studio = details.studios.first?.name, !studio.isEmpty else { return "Similar Titles" }
        return "More from \(studio)"
    }

    private var playbackActionTitle: String {
        playbackIntent.title
    }

    private var playbackIntent: MediaDetailPlaybackIntent {
        MediaDetailPlaybackIntent(
            displayItem: displayItem,
            persistedItem: persistedPlaybackItem,
            episodes: detailEpisodes
        )
    }

    private var persistedPlaybackItem: MediaItem? {
        store.localMediaSnapshots.first(where: { $0.mediaID == displayItem.id })?.item
            ?? store.library.first(where: { $0.id == displayItem.id })
    }

    private var resumeProgressPresentation: ResumeProgressPresentation? {
        persistedPlaybackItem.flatMap(ResumeProgressPresentation.init(item:))
    }

    private var horizontalInset: CGFloat {
        #if os(iOS)
        20
        #else
        48
        #endif
    }

    private var posterItemSpan: CGFloat {
        MediaBrowseMetrics.posterItemSpan(display)
    }

    private var pageBackground: some View {
        OmniaPageBackground()
    }

    @ViewBuilder
    private var screenBackground: some View {
        #if os(macOS)
        Color.clear
        #else
        // The same accent as the info sections, so the page doesn't end in
        // a light band under them or when it bounces.
        if usesArtworkBackground {
            HeroAccentBackground(item: displayItem)
        } else {
            pageBackground
        }
        #endif
    }

    private var detailHeroHeight: CGFloat {
        #if os(iOS)
        700
        #else
        820
        #endif
    }

    private var synopsisLineLimit: Int {
        #if os(iOS)
        3
        #else
        3
        #endif
    }

    private var titleFontSize: CGFloat {
        #if os(iOS)
        30
        #else
        38
        #endif
    }
}

/// The MDBList ratings row, on the title page and the Home hero.
struct MDBListRatingsView: View {
    let state: MDBListRatingsLoadState
    let retry: () -> Void
    let openSettings: () -> Void

    @ViewBuilder
    var body: some View {
        switch state {
        case .idle, .empty:
            EmptyView()
        case .loading:
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text("Loading ratings")
                    .font(.caption)
            }
            .foregroundStyle(.white.opacity(0.82))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Loading ratings")
        case let .loaded(presentation):
            FlowLayout(spacing: 8) {
                ForEach(presentation.items) { item in
                    MDBListRatingValueView(item: item)
                }
            }
        case let .failed(error, recovery):
            HStack(spacing: 8) {
                Text(failureText(for: error))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.82))
                if recovery == .retry {
                    Button("Retry", action: retry)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .accessibilityHint("Requests MDBList ratings again")
                } else if recovery == .openSettings {
                    Button("Open MDBList Settings", action: openSettings)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private func failureText(for error: MDBListMetadataError) -> String {
        switch error {
        case .authenticationRequired:
            "Ratings need your MDBList key"
        case .rateLimited:
            "MDBList request limit reached"
        case .noSupportedIdentifier, .notFound:
            ""
        case .temporarilyUnavailable, .malformedResponse, .responseTooLarge:
            "Ratings unavailable"
        }
    }
}

private struct MDBListRatingValueView: View {
    let item: MDBListRatingPresentationItem

    var body: some View {
        HStack(spacing: 4) {
            if let assetName = item.assetName {
                Image(assetName)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(height: 14)
                    .accessibilityHidden(true)
            } else {
                Text(item.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            Text(item.formattedValue)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let value = item.formattedValue.replacingOccurrences(of: "%", with: " percent")
        let kind = item.isAggregate ? "score" : "rating"
        return "\(item.displayName) \(kind) \(value)"
    }
}

struct MDBListSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if let provider = MetadataProvider.supported.first(where: { $0.id == "mdblist" }) {
                MetadataProviderDetailView(provider: provider)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { dismiss() }
                        }
                    }
            } else {
                ContentUnavailableView(
                    "MDBList Unavailable",
                    systemImage: "star.slash",
                    description: Text("MDBList settings are unavailable in this build.")
                )
            }
        }
    }
}

private enum CreditSection: String, CaseIterable, Identifiable {
    case cast, directors, writers, editors

    var id: String { rawValue }
    var title: String {
        switch self {
        case .cast: "Cast"
        case .directors: "Director"
        case .writers: "Writer"
        case .editors: "Editor"
        }
    }
}

/// A TV-specific shelf. The season menu changes the source episode list while
/// preserving the broad, artwork-led cards used by the Apple TV reference.
private struct EpisodeShelf: View {
    let seasons: [MediaSeason]
    @Binding var selectedSeasonNumber: Int
    let resumeProgress: ResumeProgressPresentation?
    let watchState: LocalMediaWatchState
    let selectEpisode: (MediaEpisode) -> Void
    @Environment(\.displayPreferences) private var display

    private var selectedSeason: MediaSeason? {
        seasons.first(where: { $0.seasonNumber == selectedSeasonNumber }) ?? seasons.first
    }

    private var episodeCardSpan: CGFloat {
        #if os(iOS)
        264
        #else
        320
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // A native menu gives the standard checkmark, keyboard
            // navigation and VoiceOver behaviour for the season list.
            Menu {
                Picker("Season", selection: $selectedSeasonNumber) {
                    ForEach(seasons) { season in
                        Text(season.title).tag(season.seasonNumber)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                HStack(spacing: 8) {
                    Text(selectedSeason?.title ?? "Season")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 28)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Choose \(selectedSeason?.title ?? "season")")

            if let selectedSeason {
                switch display.episodeLayout {
                case .horizontal:
                    ShelfScrollView(
                        items: selectedSeason.episodes,
                        itemSpan: episodeCardSpan,
                        accessibilityLabel: selectedSeason.title
                    ) { episode in
                        card(for: episode)
                    }
                case .list:
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(selectedSeason.episodes) { episode in
                            card(for: episode)
                        }
                    }
                }
            }
        }
    }

    private func card(for episode: MediaEpisode) -> some View {
        let progress = resumeProgress?.matches(episode) == true ? resumeProgress : nil
        return EpisodeCard(
            episode: episode,
            resumeProgress: progress,
            layout: display.episodeLayout,
            // Blur Unwatched hides the still of every episode not yet
            // watched or started, so thumbnails can't spoil it.
            blursArtwork: display.blurUnwatchedEpisodes
                && progress == nil
                && watchState.isWatched(episode) != true
        ) {
            selectEpisode(episode)
        }
    }
}

private struct EpisodeCard: View {
    let episode: MediaEpisode
    let resumeProgress: ResumeProgressPresentation?
    var layout: EpisodeCardLayout = .horizontal
    var blursArtwork = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            switch layout {
            case .horizontal:
                VStack(alignment: .leading, spacing: 10) {
                    artwork(width: cardWidth, height: artworkHeight)
                    information
                }
                .frame(width: cardWidth, alignment: .leading)
            case .list:
                HStack(alignment: .top, spacing: 16) {
                    artwork(width: listArtworkWidth, height: listArtworkWidth / cardWidth * artworkHeight)
                    information
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(EpisodeCardButtonStyle())
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Episode \(episode.episodeNumber), \(episode.title)")
        .accessibilityValue(episode.overview)
    }

    private func artwork(width: CGFloat, height: CGFloat) -> some View {
        CachedArtworkImage(url: episode.stillURL, size: CGSize(width: width, height: height)) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
                    .blur(radius: blursArtwork ? 18 : 0, opaque: true)
            } else {
                LinearGradient(
                    colors: [.indigo.opacity(0.84), .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: "play.rectangle.fill")
                        .font(.title)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .overlay {
            LinearGradient(
                colors: [.clear, .black.opacity(0.34)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .overlay(alignment: .bottom) {
            if let resumeProgress {
                VStack(spacing: 7) {
                    Text(resumeProgress.remainingText)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    ResumeProgressBar(progress: resumeProgress.progress)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.bottom, 9)
            }
        }
        .overlay {
            Image(systemName: "play.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 42, height: 42)
                .background(.white, in: Circle())
                .opacity(isHovered ? 1 : 0)
                .animation(.easeInOut(duration: 0.14), value: isHovered)
        }
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .cardDepth(.episodes, cornerRadius: 16)
    }

    private var information: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("EPISODE \(episode.episodeNumber)")
                .font(.caption2.weight(.bold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
            Text(episode.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(episode.overview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(layout == .list ? 3 : 2)
                .multilineTextAlignment(.leading)
            HStack(spacing: 7) {
                if let releaseDateText {
                    Text(releaseDateText)
                }
                if releaseDateText != nil, episode.runtimeMinutes != nil {
                    Text("•")
                }
                if let runtime = episode.runtimeMinutes {
                    Text(runtimeText(runtime))
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var listArtworkWidth: CGFloat {
        #if os(iOS)
        168
        #else
        240
        #endif
    }

    private func runtimeText(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 { return "\(hours)h \(remainder)m" }
        return "\(minutes)m"
    }

    private var cardWidth: CGFloat {
        #if os(iOS)
        248
        #else
        304
        #endif
    }

    private var artworkHeight: CGFloat {
        #if os(iOS)
        140
        #else
        172
        #endif
    }

    private var releaseDateText: String? {
        guard let airDate = episode.airDate,
              let date = Self.sourceDateFormatter.date(from: airDate)
        else { return nil }
        return Self.displayDateFormatter.string(from: date)
    }

    private static let sourceDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "d MMM yyyy"
        return formatter
    }()
}

private struct EpisodeCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        // Native press state preserves feedback without installing a gesture
        // that competes with the enclosing horizontal ScrollView.
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct VideoShelf: View {
    let title: String
    let videos: [MediaVideo]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title)
            ShelfScrollView(items: videos, itemSpan: videoCardSpan, accessibilityLabel: title) { video in
                Link(destination: video.watchURL) {
                    VideoCard(video: video)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play \(video.title) in YouTube")
            }
        }
    }

    private var videoCardSpan: CGFloat {
        #if os(iOS)
        264
        #else
        320
        #endif
    }
}

/// TMDB's official YouTube metadata contains a watch-page key, not a native
/// HLS/MP4 asset. A Link therefore opens the provider's official player rather
/// than attempting unsupported playback through AVPlayer.
private struct VideoCard: View {
    let video: MediaVideo
    @State private var thumbnailSize = CGSize.zero

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .onGeometryChange(for: CGSize.self) { $0.size } action: { thumbnailSize = $0 }
                .overlay {
                    CachedArtworkImage(url: video.thumbnailURL, size: thumbnailSize) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            LinearGradient(colors: [.red.opacity(0.7), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                        }
                    }
                }
                .clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .center, endPoint: .bottom)
            Image(systemName: "play.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 42, height: 42)
                .background(.white, in: Circle())
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(video.type.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.75))
                Text(video.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
            .padding(14)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .cardDepth(.trailers, cornerRadius: 16)
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

/// Nuvio's Movie Details / Show Details: who made it, then the facts.
private struct TitleFactsView: View {
    let details: MediaTitleDetails
    let isSeries: Bool

    var body: some View {
        let facts = facts
        if !facts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(isSeries ? "Show Details" : "Movie Details")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 18)], alignment: .leading, spacing: 14) {
                    ForEach(facts, id: \.title) { fact in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(fact.title.uppercased())
                                .font(.caption2.weight(.bold))
                                .tracking(0.8)
                                .foregroundStyle(.secondary)
                            Text(fact.value)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(3)
                        }
                    }
                }
            }
        }
    }

    private var facts: [(title: String, value: String)] {
        var result: [(title: String, value: String)] = []
        func names(_ credits: [MediaCredit]) -> String? {
            var seen = Set<String>()
            let unique = credits.map(\.name).filter { seen.insert($0).inserted }
            return unique.isEmpty ? nil : unique.prefix(4).joined(separator: ", ")
        }
        func crew(_ matches: (String) -> Bool) -> [MediaCredit] {
            details.crew.filter { $0.role.map { matches($0.lowercased()) } ?? false }
        }
        if let creators = names(details.creators) { result.append(("Created By", creators)) }
        if let directors = names(crew { $0 == "director" }) { result.append(("Director", directors)) }
        if let writers = names(crew { $0.contains("writer") || $0.contains("screenplay") }) { result.append(("Writer", writers)) }
        if let status = details.status { result.append(("Status", status)) }
        if let release = details.releaseDate.flatMap(TitleFactFormat.date) {
            result.append((isSeries ? "First Aired" : "Release Date", release))
        }
        if let runtime = details.runtimeMinutes { result.append(("Runtime", Self.runtime(runtime))) }
        if let rating = details.ageRating { result.append(("Certification", rating)) }
        if !details.originCountries.isEmpty {
            result.append(("Origin Country", details.originCountries.map(TitleFactFormat.country).joined(separator: ", ")))
        }
        if let language = details.originalLanguage { result.append(("Original Language", TitleFactFormat.language(language))) }
        if !details.studios.isEmpty { result.append(("Studio", details.studios.map(\.name).joined(separator: ", "))) }
        if let budget = details.budget, budget > 0 { result.append(("Budget", TitleFactFormat.usd(budget))) }
        if let revenue = details.revenue, revenue > 0 { result.append(("Revenue", TitleFactFormat.usd(revenue))) }
        return result
    }

    private static func runtime(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

/// A company's or network's logo on a light chip, or its name when TMDB has
/// no logo.
private struct ProductionChip: View {
    let studio: MediaStudio

    var body: some View {
        Group {
            if let logoURL = studio.logoURL {
                CachedArtworkImage(url: logoURL, size: CGSize(width: 72, height: 26), contentMode: .fit) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        Text(studio.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(white: 0.2))
                    }
                }
                .frame(width: 72, height: 26)
            } else {
                Text(studio.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(white: 0.2))
                    .frame(height: 26)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(white: 0.96, opacity: 0.9), in: .rect(cornerRadius: 12, style: .continuous))
        .accessibilityLabel(studio.name)
    }
}

private struct CreditCard: View {
    let person: MediaCredit

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            CachedArtworkImage(url: person.profileURL, size: CGSize(width: 104, height: 104)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.primary.opacity(0.08))
                }
            }
            .frame(width: 104, height: 104)
            .clipShape(Circle())
            .cardDepth(.cast, shape: Circle())

            Text(person.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if let subtitle = person.character ?? person.role {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 112, alignment: .leading)
    }
}

private struct SynopsisSheet: View {
    let title: String
    let synopsis: String
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Done") { closePresentation() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .frame(height: 52)

            Divider()

            ScrollView {
                Text(synopsis)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
            }
        }
        #if os(macOS)
        .frame(width: 560, height: 340)
        .omniaModalGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        #else
        .presentationDetents([.medium, .large])
        #endif
    }

    private func closePresentation() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}
