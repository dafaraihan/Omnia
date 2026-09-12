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
    @Environment(\.dismiss) private var dismiss
    @State private var resolvedItem: MediaItem?
    @State private var sourceRequest: PlaybackRequest?
    @State private var showsSynopsis = false
    @State private var creditSection: CreditSection = .cast
    @State private var selectedSeasonNumber = 1
    @State private var selectedEpisode: MediaEpisode?
    @State private var ratingsLoader = MDBListRatingsLoader()
    @State private var showsMDBListSettings = false

    private var displayItem: MediaItem { resolvedItem ?? item }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                detailHero
                detailInformation
            }
        }
        .background(screenBackground)
        #if os(macOS)
        // Match Home: the scroll container, not merely its first child,
        // owns the top safe area. The detail hero can therefore meet the
        // stable transparent toolbar instead of leaving a black band.
        .ignoresSafeArea(edges: .top)
        #endif
        .omniaNavigationTitle(displayItem.title, screen: .mediaDetail)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .task(id: item.id) {
            ratingsLoader.cancel()
            async let providerMetadata = metadata.details(for: item)
            async let addonMetadata = StremioAddonClient.fetchMetadata(
                for: item,
                addons: store.installedAddons
            )
            let providerResolved = await providerMetadata
            let fromAddons = await addonMetadata
            let resolved = fromAddons.reduce(providerResolved) { partial, addonItem in
                partial.mergingAddonMetadata(addonItem)
            }
            resolvedItem = resolved
            selectedSeasonNumber = resolved.details?.seasons.first?.seasonNumber ?? 1

            await ratingsLoader.load(
                for: resolved,
                preferences: settings.preferences.mdblistRatings
            )
            if case let .loaded(presentation) = ratingsLoader.state {
                settings.recordMDBListRatingProviders(presentation.discoveredProviderIDs)
            }
        }
        .omniaGlassModal(isPresented: showsSourceSelector) {
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
        .onDisappear {
            ratingsLoader.cancel()
        }
    }

    private var detailHero: some View {
        ZStack(alignment: .bottomLeading) {
            HeroArtworkCanvas(item: displayItem, source: .detail, artworkAlignment: .topTrailing)
                .id(displayItem.id)
                .frame(minHeight: detailHeroHeight, maxHeight: detailHeroHeight)

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
        .frame(maxWidth: .infinity, minHeight: detailHeroHeight, maxHeight: detailHeroHeight)
        #if os(iOS)
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.42), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, horizontalInset)
            .padding(.top, 10)
            .accessibilityLabel("Back")
        }
        #endif
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

            MDBListRatingsView(
                state: currentRatingsState,
                retry: retryRatings,
                openSettings: { showsMDBListSettings = true }
            )
            .frame(width: CinematicHeroLayout.logoWidth, alignment: .leading)

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

            if let details = displayItem.details {
                TitleFactsView(details: details)

                if displayItem.kind == .series, !details.seasons.isEmpty {
                    EpisodeShelf(
                        seasons: details.seasons,
                        selectedSeasonNumber: $selectedSeasonNumber,
                        resumeProgress: resumeProgressPresentation,
                        selectEpisode: { episode in
                            selectedEpisode = episode
                            sourceRequest = PlaybackRequest(item: displayItem, episode: episode, resumeAt: nil)
                        }
                    )
                }

                if !details.trailers.isEmpty {
                    VideoShelf(title: "Trailers", videos: details.trailers)
                }

                if !details.bonusContent.isEmpty {
                    VideoShelf(title: "Bonus Content", videos: details.bonusContent)
                }

                if !displayPeople(for: details).isEmpty {
                    peopleSection(details: details)
                }

                if !details.studioTitles.isEmpty {
                    detailShelf(title: studioShelfTitle(details), items: details.studioTitles)
                }

                if let collection = details.collection, !collection.members.isEmpty {
                    detailShelf(title: collection.name, items: collection.members)
                }

                if !details.recommendations.isEmpty {
                    detailShelf(title: "More Like This", items: details.recommendations)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, horizontalInset)
        .padding(.top, 32)
        .padding(.bottom, 72)
        .background {
            if HeroBackdropPresentation.usesArtworkAccentBelowHero {
                HeroAccentBackground(item: displayItem)
            } else {
                pageBackground
            }
        }
    }

    private var actions: some View {
        HeroActionRow(
            width: CinematicHeroLayout.logoWidth,
            isSaved: store.isSaved(displayItem),
            libraryAction: { store.toggleSaved(displayItem) },
            watchAction: heroWatchAction
        ) {
            Button {
                let intent = playbackIntent
                selectedEpisode = intent.episode
                sourceRequest = PlaybackRequest(item: intent.item, episode: intent.episode, resumeAt: intent.resumeAt)
            } label: {
                HeroPrimaryActionLabel(
                    title: playbackActionTitle,
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
                    episodes: detailEpisodes
                )
            }
        )
    }

    private var currentRatingsState: MDBListRatingsLoadState {
        guard case let .loaded(presentation) = ratingsLoader.state else {
            return ratingsLoader.state
        }
        let current = MDBListRatingsPresentation(
            response: presentation.response,
            preferences: settings.preferences.mdblistRatings
        )
        return current.items.isEmpty ? .empty : .loaded(current)
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
                CreditCard(person: person)
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
        #if os(iOS)
        148
        #else
        170
        #endif
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
        pageBackground
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

private struct MDBListRatingsView: View {
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

private struct MDBListSettingsSheet: View {
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
    let selectEpisode: (MediaEpisode) -> Void
    @State private var showsSeasonChoices = false

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
            Button {
                showsSeasonChoices.toggle()
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
            .buttonStyle(.plain)
            .accessibilityLabel("Choose \(selectedSeason?.title ?? "season")")
            .popover(isPresented: $showsSeasonChoices, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(seasons) { season in
                        Button {
                            selectedSeasonNumber = season.seasonNumber
                            showsSeasonChoices = false
                        } label: {
                            HStack(spacing: 12) {
                                Text(season.title)
                                Spacer(minLength: 0)
                                if season.seasonNumber == selectedSeasonNumber {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                }
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .frame(minWidth: 180)
            }

            if let selectedSeason {
                ShelfScrollView(
                    items: selectedSeason.episodes,
                    itemSpan: episodeCardSpan,
                    accessibilityLabel: selectedSeason.title
                ) { episode in
                    EpisodeCard(
                        episode: episode,
                        resumeProgress: resumeProgress?.matches(episode) == true ? resumeProgress : nil
                    ) {
                        selectEpisode(episode)
                    }
                }
            }
        }
    }
}

private struct EpisodeCard: View {
    let episode: MediaEpisode
    let resumeProgress: ResumeProgressPresentation?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
            AsyncImage(url: episode.stillURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
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
            .frame(width: cardWidth, height: artworkHeight)
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
                    .lineLimit(2)
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
        .frame(width: cardWidth, alignment: .leading)
        }
        .buttonStyle(EpisodeCardButtonStyle())
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Episode \(episode.episodeNumber), \(episode.title)")
        .accessibilityValue(episode.overview)
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

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: video.thumbnailURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                LinearGradient(colors: [.red.opacity(0.7), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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

private struct TitleFactsView: View {
    let details: MediaTitleDetails

    var body: some View {
        let facts = facts
        if !facts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Details")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 18)], alignment: .leading, spacing: 14) {
                    ForEach(facts, id: \.title) { fact in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(fact.title.uppercased())
                                .font(.caption2.weight(.bold))
                                .tracking(0.8)
                                .foregroundStyle(.secondary)
                            Text(fact.value)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
    }

    private var facts: [(title: String, value: String)] {
        var result: [(String, String)] = []
        if !details.studios.isEmpty { result.append(("Studio", details.studios.map(\.name).joined(separator: ", "))) }
        if let runtime = details.runtimeMinutes { result.append(("Runtime", "\(runtime) min")) }
        if let status = details.status { result.append(("Status", status)) }
        if let budget = details.budget, budget > 0 { result.append(("Budget", Self.currency.string(from: NSNumber(value: budget)) ?? "—")) }
        if let revenue = details.revenue, revenue > 0 { result.append(("Revenue", Self.currency.string(from: NSNumber(value: revenue)) ?? "—")) }
        return result
    }

    private static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

private struct CreditCard: View {
    let person: MediaCredit

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            AsyncImage(url: person.profileURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.primary.opacity(0.08))
            }
            .frame(width: 104, height: 104)
            .clipShape(Circle())

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
