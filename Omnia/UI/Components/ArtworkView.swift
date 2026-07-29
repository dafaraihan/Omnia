//
//  ArtworkView.swift
//  Omnia
//

import SwiftUI

struct ArtworkView: View {
    let item: MediaItem
    var showsTitle: Bool = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            fallbackArtwork

            if let artworkURL = item.artworkURL {
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

            if showsTitle {
                LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(12)
            }
        }
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
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
