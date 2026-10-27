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
    @State private var textlessPoster: (itemID: String, url: URL)?

    var body: some View {
        ZStack {
            if let textlessPoster, textlessPoster.itemID == item.id {
                artwork(textlessPoster.url)
                fade(darkness: 0.78)
            } else if item.backdropURL != nil {
                FeaturedBackdrop(item: item, artworkAlignment: .center)
                fade(darkness: 0.78)
            } else if let poster = item.artworkURL {
                artwork(poster)
                fade(darkness: 0.92)
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
#endif
