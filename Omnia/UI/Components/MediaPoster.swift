//
//  MediaPoster.swift
//  Omnia
//

import SwiftUI

struct MediaPoster: View {
    enum Style {
        case poster
        case landscape
    }

    let item: MediaItem
    var style: Style = .poster
    var fillsAvailableWidth = false

    var body: some View {
        NavigationLink(value: item) {
            ArtworkView(item: item)
                .aspectRatio(style == .landscape ? 1.72 : 2 / 3, contentMode: .fit)
                .clipShape(.rect(cornerRadius: style == .landscape ? 16 : 12, style: .continuous))
                .overlay {
                    if style == .landscape {
                        ZStack {
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.5)],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                            Image(systemName: "play.fill")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.black)
                                .frame(width: 42, height: 42)
                                .background(.white, in: Circle())
                        }
                    }
                }
                .overlay(alignment: .bottom) {
                    if let progress = item.progress {
                        ProgressView(value: progress)
                            .controlSize(.mini)
                            .tint(.white)
                            .scaleEffect(y: 0.65)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 8)
                    }
                }
            .frame(maxWidth: fillsAvailableWidth ? .infinity : nil, alignment: .leading)
            .frame(width: fillsAvailableWidth ? nil : cardWidth, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
    }

    private var cardWidth: CGFloat {
        if style == .landscape {
            #if os(iOS)
            return 248
            #else
            return 304
            #endif
        }

        #if os(iOS)
        return 132
        #else
        return 154
        #endif
    }
}

/// Apple TV presents a Top 10 shelf as a numbered poster sequence. The rank
/// belongs to the artwork, not to a separate column, so the horizontal rhythm
/// stays the same as every other cinematic shelf.
struct RankedMediaPoster: View {
    let item: MediaItem
    let rank: Int

    var body: some View {
        NavigationLink(value: item) {
            ArtworkView(item: item)
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    RankBadge(rank: rank)
                        .padding(10)
                }
                .frame(width: cardWidth, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Number \(rank), \(item.title)")
    }

    private var cardWidth: CGFloat {
        #if os(iOS)
        132
        #else
        154
        #endif
    }
}

/// The rank is glyph-only—never a badge or a second piece of chrome. A subtle
/// highlight gradient keeps it legible over changing poster artwork without
/// adding a glass container around the number.
private struct RankBadge: View {
    let rank: Int

    var body: some View {
        Text("\(rank)")
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(
                LinearGradient(
                    colors: [.white, .white.opacity(0.78), .white.opacity(0.92)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            .accessibilityHidden(true)
    }
}
