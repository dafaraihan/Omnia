//
//  PortraitHeroArtwork.swift
//  Omnia
//

import SwiftUI

#if os(iOS)
/// The iPhone's portrait hero art: the title's textless poster fills the
/// hero, and the logo sits over a fade at the bottom. Without one (no TMDB
/// key, or TMDB has none) the backdrop is cropped to the middle, and
/// without a backdrop the poster is used under a heavier fade, since it
/// carries its own title.
struct PortraitHeroArtwork: View {
    let item: MediaItem
    /// The page's colour fades in over the art instead of the dark floor.
    var blendsIntoPage = false
    @State private var textlessPoster: (itemID: String, url: URL)?

    var body: some View {
        ZStack {
            if let textlessPoster, textlessPoster.itemID == item.id {
                artwork(textlessPoster.url)
                fade(darkness: blendsIntoPage ? 0.3 : 0.78)
            } else if item.backdropURL != nil {
                FeaturedBackdrop(item: item, artworkAlignment: .center)
                fade(darkness: blendsIntoPage ? 0.3 : 0.78)
            } else if let poster = item.artworkURL {
                artwork(poster)
                fade(darkness: blendsIntoPage ? 0.3 : 0.92)
            }
        }
        .task(id: item.id) {
            guard let url = await PortraitArtworkResolver.shared.textlessPoster(for: item),
                  !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                textlessPoster = (item.id, url)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func artwork(_ url: URL) -> some View {
        GeometryReader { proxy in
            CachedArtworkImage(url: url, size: proxy.size, transaction: .init(animation: .easeInOut)) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    Color.clear
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .clipped()
        }
    }

    /// Keeps the status bar legible at the top and gives the logo, synopsis
    /// and buttons a dark floor at the bottom.
    private func fade(darkness: Double) -> some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.35), location: 0),
                .init(color: .clear, location: 0.18),
                .init(color: .clear, location: 0.42),
                .init(color: .black.opacity(darkness * 0.7), location: 0.7),
                .init(color: .black.opacity(darkness), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// The iPhone's portrait hero identity, centred under the art as in Nuvio:
/// the logo (or the title), one metadata line, a short synopsis and the
/// actions in one row.
struct PortraitHeroIdentity<Primary: View, Ratings: View>: View {
    let item: MediaItem
    /// Draw the title when the details have loaded without a logo.
    let showsTitleWithoutLogo: Bool
    let isSaved: Bool
    let libraryAction: () -> Void
    let watchAction: HeroWatchAction?
    var shuffleAction: HeroWatchAction?
    @ViewBuilder let ratings: () -> Ratings
    @ViewBuilder let primary: () -> Primary

    private var metadata: String {
        var values = [item.year, item.kind == .series ? "TV Show" : item.kind.rawValue]
        if !item.genres.isEmpty { values.append(item.genres.prefix(2).joined(separator: ", ")) }
        if let ageRating = item.details?.ageRating, !ageRating.isEmpty { values.append(ageRating) }
        return values.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let logoURL = item.logoURL {
                    TitleLogoView(url: logoURL, title: item.title, maximumWidth: 220, maximumHeight: 72, alignment: .center)
                } else if showsTitleWithoutLogo {
                    Text(item.title)
                        .font(.system(size: 28, weight: .bold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                } else {
                    // The logo is still on its way: keep its room so the
                    // text below doesn't jump.
                    Color.clear.accessibilityHidden(true)
                }
            }
            .frame(maxWidth: 220, minHeight: 56, maxHeight: 72)

            Text(metadata)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)

            ratings()

            if !item.overview.isEmpty {
                Text(item.overview)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 20)
            }

            // The shared buttons at a smaller size, so the identity keeps to
            // the lower part of the art.
            HeroActionRow(
                width: 340,
                isSaved: isSaved,
                libraryAction: libraryAction,
                watchAction: watchAction,
                shuffleAction: shuffleAction,
                primary: primary
            )
            .scaleEffect(0.85)
            .frame(height: 46 * 0.85)
            .padding(.top, 2)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
}

extension AnyTransition {
    /// The outgoing title's text leaves at once and the next one fades in
    /// after, so two titles' text never show on top of each other.
    static var heroIdentity: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(.easeOut(duration: 0.25).delay(0.12)),
            removal: .opacity.animation(.easeIn(duration: 0.08))
        )
    }
}
#endif

/// A hero's height: fixed, or a poster's 2:3 shape on an upright iPhone.
struct HeroFrame: ViewModifier {
    let height: CGFloat
    let followsPosterShape: Bool

    func body(content: Content) -> some View {
        if followsPosterShape {
            content.aspectRatio(2.0 / 3.0, contentMode: .fit)
        } else {
            content.frame(height: height)
        }
    }
}
