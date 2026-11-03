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
        .accessibilityAction(named: "Remove Watch Progress") {
            store.removeFromContinueWatching(item)
        }
        #endif
    }

    private var cardLabel: some View {
        previewContent
            .mediaContextMenu(for: item, placement: .continueWatching)
    }

    @ViewBuilder
    private var previewContent: some View {
        if style == .card {
            landscapeCard
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
    }

    /// Landscape presentation follows the poster-size setting; typography uses
    /// native text styles so the system remains responsible for text scaling.
    private var landscapeCard: some View {
        ZStack(alignment: .bottomLeading) {
            resumeArtwork
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.45),
                    .init(color: cardBackground.opacity(0.70), location: 0.78),
                    .init(color: cardBackground.opacity(0.95), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: cardMetrics.gap) {
                if let code = episodeCode {
                    Text(code)
                        .font(cardMetrics.metadataFont.weight(.semibold))
                }
                Text(item.title)
                    .font(cardMetrics.titleFont.weight(.semibold))
                if let subtitle = episodeTitle ?? upcomingAirDateText {
                    Text(subtitle)
                        .font(cardMetrics.metadataFont.weight(.medium))
                        .foregroundStyle(.primary.opacity(contrast == .increased ? 1 : 0.72))
                }
            }
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(cardMetrics.contentPadding)

            Text(badgeText)
                .font(cardMetrics.badgeFont.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, cardMetrics.badgeHorizontalPadding)
                .padding(.vertical, cardMetrics.badgeVerticalPadding)
                .background(.black.opacity(0.80), in: RoundedRectangle(cornerRadius: 4))
                .padding(cardMetrics.badgeInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            if cardProgress > 0 {
                GeometryReader { geometry in
                    Capsule()
                        .fill(.black.opacity(0.30))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(display.accentStyle)
                                .frame(width: geometry.size.width * cardProgress)
                        }
                }
                .frame(height: 3)
                .padding(.horizontal, cardMetrics.progressInset)
                .padding(.bottom, cardMetrics.progressBottomPadding)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        .cardDepth(.continueWatching, cornerRadius: cornerRadius, fallbackBorderOpacity: 0.24)
        .accessibilityElement(children: .ignore)
    }

    private var accessibilityValue: String {
        let status: String? = style == .card ? badgeText : (isNextUp ? "Up next" : resumePresentation?.remainingText)
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

    private var badgeText: String {
        if cardProgress > 0 {
            if let duration = item.durationSeconds, duration.isFinite, duration > 0,
               let position = item.positionSeconds, position.isFinite, position >= 0,
               let remaining = item.progressText {
                return remaining
            }
            return "\(Int((cardProgress * 100).rounded()))% watched"
        }
        // A release date is evidence of an upcoming episode. The persisted
        // model has no release-alert kind, so never infer New Episode/Season.
        return upcomingAirDateText ?? nextUpText
    }

    private var cardMetrics: CardMetrics {
        if display.continueWatchingCard.size.posterWidth(for: display) <= 108 { return .small }
        if display.continueWatchingCard.size.posterWidth(for: display) <= 120 { return .medium }
        return .large
    }

    private struct CardMetrics {
        let contentPadding: CGFloat
        let gap: CGFloat
        let badgeInset: CGFloat
        let badgeHorizontalPadding: CGFloat
        let badgeVerticalPadding: CGFloat
        let progressInset: CGFloat
        let progressBottomPadding: CGFloat
        let titleFont: Font
        let metadataFont: Font
        let badgeFont: Font

        static let small = CardMetrics(contentPadding: 8, gap: 1, badgeInset: 6,
            badgeHorizontalPadding: 6, badgeVerticalPadding: 2, progressInset: 8,
            progressBottomPadding: 3, titleFont: .caption, metadataFont: .caption2, badgeFont: .caption2)
        static let medium = CardMetrics(contentPadding: 9, gap: 1, badgeInset: 6,
            badgeHorizontalPadding: 7, badgeVerticalPadding: 3, progressInset: 8,
            progressBottomPadding: 3, titleFont: .subheadline, metadataFont: .caption, badgeFont: .caption2)
        static let large = CardMetrics(contentPadding: 10, gap: 2, badgeInset: 7,
            badgeHorizontalPadding: 7, badgeVerticalPadding: 3, progressInset: 9,
            progressBottomPadding: 4, titleFont: .headline, metadataFont: .caption, badgeFont: .caption)
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
                LinearGradient(colors: item.artworkColors, startPoint: .topLeading, endPoint: .bottomTrailing)
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
