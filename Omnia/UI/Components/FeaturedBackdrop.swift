//
//  FeaturedBackdrop.swift
//  Omnia
//

import SwiftUI

/// The content-led canvas shared by Home and title details. The artwork is the
/// visual anchor; an SF Symbol is only a small, intentional fallback.
struct FeaturedBackdrop: View {
    let item: MediaItem
    var artworkAlignment: Alignment = .center

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Let the owning page's semantic surface fill any transient
                // image-loading area. A hard-coded black base becomes a
                // visible bar when the user selects Light appearance.
                Color.clear

                if let backdropURL = item.backdropURL {
                    AsyncImage(url: backdropURL, transaction: .init(animation: .easeInOut)) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFill()
                                .transition(.opacity)
                        } else if phase.error != nil {
                            fallbackArtwork
                        } else {
                            fallbackArtwork
                                .redacted(reason: .placeholder)
                        }
                    }
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height,
                        alignment: artworkAlignment
                    )
                    .clipped()
                } else {
                    fallbackArtwork
                }

            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var fallbackArtwork: some View {
        ZStack {
            LinearGradient(
                colors: item.artworkColors + [.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: item.symbol)
                .font(.system(size: 80, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.28))
        }
    }
}
