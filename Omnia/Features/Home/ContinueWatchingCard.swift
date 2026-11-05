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
        let posterWidth = display.continueWatchingCard.size.posterWidth(for: display)
        switch display.continueWatchingStyle {
        case .card: return (posterWidth * 180 / 110 * 1.2).rounded()
        case .poster: return posterWidth
        case .wide:
            #if os(iOS)
            let originalWidth: CGFloat = 248
            #else
            let originalWidth: CGFloat = 304
            #endif
            if display.continueWatchingCard.size == .styleDefault { return originalWidth }
            return (originalWidth * posterWidth / PosterWidthPreset.standard.width).rounded()
        }
    }

    private var style: ContinueWatchingStyle { display.continueWatchingStyle }
    private var isPoster: Bool { style == .poster }

    private var cornerRadius: CGFloat {
        display.continueWatchingCard.corners.radius(for: display)
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

    @ViewBuilder
    private var previewContent: some View {
        switch style {
        case .wide: wideCard
        case .card: upNextCard
        case .poster: classicCard
        }
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
                    .padding(.leading, 10)
                    .padding(.trailing, 34)
                    .padding(.bottom, 10)
                } else if isNextUp {
                    Text(nextUpText)
                        .font(isPoster ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.leading, 10)
                        .padding(.trailing, 34)
                        .padding(.bottom, 10)
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .cardDepth(.continueWatching, cornerRadius: cornerRadius, fallbackBorderOpacity: 0.24)

            if display.continueWatchingShowsLabels {
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
        }
    }

    /// Artwork with the play symbol, a long progress bar and what's left.
    private var wideCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                resumeArtwork
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.55),
                        .init(color: .black.opacity(0.72), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.caption)
                    if cardProgress > 0 {
                        progressLine
                    }
                    Text(wideMetadata)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .fixedSize()
                    if cardProgress <= 0 {
                        Spacer(minLength: 0)
                    }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.leading, 12)
                .padding(.trailing, 40)
                .padding(.bottom, 12)
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .cardDepth(.continueWatching, cornerRadius: cornerRadius, fallbackBorderOpacity: 0.24)

            if display.continueWatchingShowsLabels {
                Text(item.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(width: cardWidth, alignment: .leading)
            }
        }
    }

    /// Apple TV's Up Next: the show's logo on the episode's still, a thin line
    /// inside the image, then the episode underneath. Next Up has no line.
    private var upNextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                resumeArtwork
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.45),
                        .init(color: .black.opacity(0.7), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                VStack(alignment: .leading, spacing: 8) {
                    if let logoURL = item.logoURL {
                        TitleLogoView(
                            url: logoURL,
                            title: item.title,
                            maximumWidth: cardWidth * 0.55,
                            maximumHeight: cardHeight * 0.32,
                            alignment: .bottomLeading
                        )
                    } else {
                        Text(item.title)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    if cardProgress > 0 {
                        progressLine
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 40)
                .padding(.bottom, 12)
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .cardDepth(.continueWatching, cornerRadius: cornerRadius, fallbackBorderOpacity: 0.24)

            VStack(alignment: .leading, spacing: 2) {
                Text(upNextMetadata)
                    .contentTransition(.numericText())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(episodeTitle ?? item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .lineLimit(1)
            .frame(width: cardWidth, alignment: .leading)
        }
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
        return "S\(season), E\(episode)"
    }

    private var wideMetadata: String {
        if let remainingShort {
            return [episodeShort, remainingShort].compactMap { $0 }.joined(separator: " · ")
        }
        if cardProgress > 0 {
            return episodeShort ?? "\(Int((cardProgress * 100).rounded()))%"
        }
        if let upcomingAirDateText { return upcomingAirDateText }
        return episodeShort ?? nextUpText
    }

    private var upNextMetadata: String {
        let label = episodeShort ?? (item.kind == .movie ? "Movie" : nil)
        if let remainingShort {
            return [label, "\(remainingShort) left"].compactMap { $0 }.joined(separator: " · ")
        }
        if let upcomingAirDateText {
            return [label, upcomingAirDateText].compactMap { $0 }.joined(separator: " · ")
        }
        if isNextUp, let episodeShort { return "Next · \(episodeShort)" }
        return label ?? nextUpText
    }

    private var accessibilityValue: String {
        let status: String? = isNextUp ? "Up next" : resumePresentation?.remainingText
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
        } else if style == .card && upcomingAirDate != nil {
            item.backdropURL ?? item.artworkURL ?? item.resumeEpisodeStillURL
        } else if usesEpisodeStill {
            item.resumeEpisodeStillURL ?? (style == .card ? item.resumeEpisode?.stillURL : nil) ?? item.backdropURL ?? item.artworkURL
        } else {
            item.backdropURL ?? item.artworkURL ?? (style == .card ? item.resumeEpisodeStillURL : nil)
        }
        let episodeStill = item.resumeEpisodeStillURL ?? item.resumeEpisode?.stillURL
        let isUnwatched = isNextUp || (style == .card && cardProgress < 0.9)
        let blursArtwork = scene == nil && display.blursNextUp && isUnwatched
            && usesEpisodeStill && episodeStill != nil && url == episodeStill

        let fallbackURL = style == .card
            ? [item.backdropURL, item.artworkURL].compactMap { $0 }.first(where: { $0 != url })
            : nil

        ZStack {
            if style == .card {
                cardBackground
            } else {
                MediaItem.placeholderArtworkColor
            }
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

    private var resumePresentation: ResumeProgressPresentation? {
        ResumeProgressPresentation(item: item)
    }

    private var cardPresentation: ContinueWatchingCardPresentation {
        ContinueWatchingCardPresentation(item: item)
    }

    private var cardWidth: CGFloat {
        min(Self.width(for: display), maximumWidth ?? .greatestFiniteMagnitude)
    }

    private var cardHeight: CGFloat {
        switch style {
        case .poster: return cardWidth * 1.5
        case .card: return (cardWidth / 1.77).rounded()
        case .wide:
            #if os(iOS)
            return (cardWidth * 140 / 248).rounded()
            #else
            return (cardWidth * 172 / 304).rounded()
            #endif
        }
    }
}
