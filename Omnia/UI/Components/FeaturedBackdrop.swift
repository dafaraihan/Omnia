//
//  FeaturedBackdrop.swift
//  Omnia
//

import SwiftUI

/// The content-led canvas shared by Home and title details. The artwork is the
/// visual anchor. Until real backdrop artwork is available, the owning page's
/// surface remains visible instead of inventing a generic image treatment.
struct FeaturedBackdrop: View {
    let item: MediaItem
    var artworkAlignment: Alignment = .center
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Let the owning page's semantic surface fill any transient
                // image-loading area. A hard-coded black base becomes a
                // visible bar when the user selects Light appearance.
                Color.clear

                if let backdropURL = MediaArtworkResolution.backdropURL(
                    item.backdropURL,
                    pixelWidth: proxy.size.width * displayScale
                ) {
                    AsyncImage(url: backdropURL, transaction: .init(animation: .easeInOut)) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFill()
                                .transition(.opacity)
                        } else {
                            emptyArtwork
                        }
                    }
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height,
                        alignment: artworkAlignment
                    )
                    .clipped()
                } else {
                    emptyArtwork
                }

            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var emptyArtwork: some View {
        Color.clear
    }
}

enum MediaArtworkResolution {
    /// TMDB serves backdrops at w300, w780, w1280 and original. Catalog records
    /// ask for w1280, which a full-width hero on a Retina display stretches
    /// two to three times, so it looks soft. Ask for the original only when the
    /// hero is wider than w1280 in pixels; cards keep the lighter size.
    static func backdropURL(_ url: URL?, pixelWidth: CGFloat) -> URL? {
        guard let url, pixelWidth > 1280, url.host() == "image.tmdb.org" else { return url }
        let path = url.path()
        guard let range = path.range(of: "/t/p/w1280/") else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = path.replacingCharacters(in: range, with: "/t/p/original/")
        return components?.url ?? url
    }
}
