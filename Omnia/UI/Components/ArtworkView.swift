//
//  ArtworkView.swift
//  Omnia
//

import SwiftUI

struct ArtworkView: View {
    let item: MediaItem
    var showsTitle: Bool = false
    /// Landscape poster cards draw the backdrop with the title logo over it.
    var prefersBackdrop = false
    @Environment(\.displayPreferences) private var display

    private var imageURL: URL? {
        prefersBackdrop ? item.backdropURL ?? item.artworkURL : item.artworkURL
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            fallbackArtwork

            if let artworkURL = imageURL {
                AsyncImage(url: artworkURL, transaction: .init(animation: .easeInOut)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if prefersBackdrop, let logoURL = item.logoURL {
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                TitleLogoView(url: logoURL, title: item.title, maximumWidth: 150, maximumHeight: 44, alignment: .bottomLeading)
                    .padding(12)
            } else if prefersBackdrop {
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(12)
            }

            if showsTitle {
                LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(12)
            }
        }
        .clipShape(.rect(cornerRadius: display.posterCornerRadius, style: .continuous))
        .accessibilityLabel("Artwork for \(item.title)")
    }

    private var fallbackArtwork: some View {
        ZStack {
            LinearGradient(colors: item.artworkColors, startPoint: .topLeading, endPoint: .bottomTrailing)

            Image(systemName: item.symbol)
                .font(.system(size: 44, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
