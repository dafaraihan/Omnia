import SwiftUI

struct ContinueWatchingCard: View {
    let item: MediaItem
    let requestPlayback: () -> Void
    var isPreview = false
    var maximumWidth: CGFloat? = nil

    @Environment(OmniaStore.self) private var store
    @Environment(SettingsPreferencesStore.self) private var settings
    @Environment(\.displayPreferences) private var display
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    /// Home and Library rows space Continue Watching by the card style
    /// chosen in Settings › Home › Continue Watching.
    static func itemSpan(for display: DisplayPreferences) -> CGFloat {
        width(for: display) + MediaBrowseMetrics.shelfSpacing
    }

    static func width(for display: DisplayPreferences) -> CGFloat {
        display.landscapePosterCardWidth
    }

    private var cornerRadius: CGFloat {
        display.landscapeCornerRadius
    }

    /// The next episode, offered after the previous one ended, before any
    /// of it is watched.
    private var isNextUp: Bool {
        item.kind == .series && item.progress == 0 && item.resumeEpisodeNumber != nil
    }

    private var usesEpisodeStill: Bool {
        item.kind == .series && display.continueWatchingEpisodeThumbnails
    }

    var body: some View {
        Group {
            if isPreview {
                previewContent
            } else if settings.preferences.directContinueWatchingPlayback {
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
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(
            settings.preferences.directContinueWatchingPlayback
                ? "Opens available sources and resumes playback in Omnia"
                : "Opens title details"
        )
        #if os(macOS)
        .accessibilityAction(named: "Remove from Watchlist") {
            store.removeFromContinueWatching(item)
        }
        #endif
        .overlay(alignment: .topLeading) { menuDots }
    }

    private var cardLabel: some View {
        previewContent
            .mediaContextMenu(for: item, placement: .continueWatching)
    }

    private var previewContent: some View {
        card
    }

    /// The three dots sit over the card, not in its link, so a tap on them
    /// opens the menu and not the title.
    @ViewBuilder
    private var menuDots: some View {
        Group {
            if isPreview {
                MediaContextMenuDots()
            } else {
                MediaContextMenuButton(item: item, placement: .continueWatching)
            }
        }
        .offset(y: 6)
        .frame(width: cardWidth, height: cardHeight, alignment: .bottomTrailing)
    }

    /// Apple TV's Up Next: the show's logo on the episode's still, then what's
    /// playing and a thin line, all inside the art. Next Up has no line.
    private var card: some View {
        ZStack(alignment: .bottomLeading) {
            resumeArtwork
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.35),
                    .init(color: .black.opacity(0.8), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 5) {
                if let logoURL = item.logoURL {
                    TitleLogoView(
                        url: logoURL,
                        title: item.title,
                        maximumWidth: cardWidth * 0.55,
                        maximumHeight: cardHeight * 0.3,
                        alignment: .bottomLeading
                    )
                } else {
                    Text(item.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(cardMetadata)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .contentTransition(.numericText())
                    if cardProgress > 0 {
                        progressLine
                    }
                }
                .padding(.trailing, 28)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 11)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        .cardDepth(.continueWatching, cornerRadius: cornerRadius, fallbackBorderOpacity: 0.24)
    }

    private var progressLine: some View {
        Capsule()
            .fill(.white.opacity(0.32))
            .frame(height: 3)
            .overlay {
                GeometryReader { geometry in
                    Capsule()
                        .fill(.white)
                        .frame(width: geometry.size.width * cardProgress)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    /// "42m" or "1h 12m", from what's left to watch.
    private var remainingShort: String? {
        guard cardProgress > 0, let duration = item.durationSeconds, duration.isFinite, duration > 0,
              let position = item.positionSeconds, position.isFinite, position >= 0 else { return nil }
        let minutes = max(Int(((duration - position) / 60).rounded(.up)), 1)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    private var episodeShort: String? {
        guard item.kind == .series, let season = item.resumeSeasonNumber, let episode = item.resumeEpisodeNumber else {
            return nil
        }
        return "S\(season) • E\(episode)"
    }

    /// "S1 • E2 · 38m left" or "1h 12m left". Next Up says which episode.
    private var cardMetadata: String {
        if let remainingShort {
            return [episodeShort, "\(remainingShort) left"].compactMap { $0 }.joined(separator: " · ")
        }
        if let upcomingAirDateText {
            return [episodeShort, upcomingAirDateText].compactMap { $0 }.joined(separator: " · ")
        }
        if isNextUp, let episodeShort { return "Next · \(episodeShort)" }
        return episodeShort ?? (cardProgress > 0 ? "\(Int((cardProgress * 100).rounded()))% watched" : nextUpText)
    }

    private var accessibilityValue: String {
        let status: String? = isNextUp ? "Up next" : remainingShort.map { "\($0) left" }
        return [cardPresentation.accessibilityValue, status]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private var cardBackground: Color {
        display.amoledBlack && colorScheme == .dark ? .black : .omniaWindowBackground
    }

    private var cardProgress: Double {
        guard let progress = item.progress, progress.isFinite else { return 0 }
        return min(max(progress, 0), 1)
    }

    private var upcomingAirDate: Date? {
        guard isNextUp, let episode = item.resumeEpisode,
              let date = NextUpEpisode.airDate(episode),
              date > Date() else { return nil }
        return date
    }

    private var upcomingAirDateText: String? {
        upcomingAirDate.map { $0.formatted(date: .abbreviated, time: .omitted) }
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
        } else if upcomingAirDate != nil {
            item.backdropURL ?? item.artworkURL ?? item.resumeEpisodeStillURL
        } else if usesEpisodeStill {
            item.resumeEpisodeStillURL ?? item.resumeEpisode?.stillURL ?? item.backdropURL ?? item.artworkURL
        } else {
            item.backdropURL ?? item.artworkURL ?? item.resumeEpisodeStillURL
        }
        let episodeStill = item.resumeEpisodeStillURL ?? item.resumeEpisode?.stillURL
        let isUnwatched = isNextUp || cardProgress < 0.9
        let blursArtwork = scene == nil && display.blursNextUp && isUnwatched
            && usesEpisodeStill && episodeStill != nil && url == episodeStill

        let fallbackURL = [item.backdropURL, item.artworkURL].compactMap { $0 }.first(where: { $0 != url })

        ZStack {
            cardBackground
            Image(systemName: item.symbol)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
            if let url {
                RemoteArtworkImage(url: url, fallbackURL: fallbackURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .blur(radius: blursArtwork ? 18 : 0, opaque: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .accessibilityHidden(true)
    }

    private var cardPresentation: ContinueWatchingCardPresentation {
        ContinueWatchingCardPresentation(item: item)
    }

    private var cardWidth: CGFloat {
        min(Self.width(for: display), maximumWidth ?? .greatestFiniteMagnitude)
    }

    private var cardHeight: CGFloat {
        (cardWidth * 9 / 16).rounded()
    }
}
