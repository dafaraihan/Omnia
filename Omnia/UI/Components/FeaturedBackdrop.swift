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
