//
//  TitleLogoView.swift
//  Omnia
//

import SwiftUI

/// Displays a provider-supplied transparent title treatment without forcing an
/// icon or a generic wordmark over the featured artwork. A text title remains
/// available to callers when the provider has no usable localized logo.
struct TitleLogoView: View {
    let url: URL
    let title: String
    var maximumWidth: CGFloat = 360
    var maximumHeight: CGFloat = 108
    var alignment: Alignment = .leading

    var body: some View {
        AsyncImage(url: url, transaction: .init(animation: .easeInOut)) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFit()
                    // Reserve the same canvas for every provider logo. The
                    // transparent artwork is therefore centred consistently
                    // above the shared hero action row.
                    .frame(width: maximumWidth, height: maximumHeight, alignment: alignment)
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                    .accessibilityLabel(title)
            } else {
                // Keep the hero's identity column stable while the transparent
                // artwork arrives. Showing a temporary plain-text title makes
                // the transition read like a duplicate logo.
                Color.clear
                    .frame(width: maximumWidth, height: maximumHeight, alignment: alignment)
                    .accessibilityHidden(true)
            }
        }
    }
}
