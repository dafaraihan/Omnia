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
    @Environment(\.showsMediaCardLabels) private var showsMediaCardLabels

    var body: some View {
        NavigationLink(value: item) {
            VStack(alignment: .leading, spacing: 8) {
                ArtworkView(item: item)
                    .aspectRatio(style == .landscape ? 1.72 : 2 / 3, contentMode: .fit)
                    .frame(maxWidth: fillsAvailableWidth ? .infinity : nil)
                    .frame(width: fillsAvailableWidth ? nil : cardWidth)
                    .clipShape(.rect(
                        cornerRadius: style == .landscape
                            ? MediaBrowseMetrics.landscapeCornerRadius
                            : MediaBrowseMetrics.posterCornerRadius,
                        style: .continuous
                    ))
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

                if showsMediaCardLabels {
                    MediaPosterLabel(item: item)
                }
            }
            .frame(width: fillsAvailableWidth ? nil : cardWidth, alignment: .leading)
            .frame(maxWidth: fillsAvailableWidth ? .infinity : nil, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .mediaContextMenu(for: item, placement: .browse)
    }

    private var cardWidth: CGFloat {
        if style == .landscape {
            #if os(iOS)
            return 248
            #else
            return 304
            #endif
        }

        return MediaBrowseMetrics.posterWidth
    }
}

/// Apple TV presents a Top 10 shelf as a numbered poster sequence. The rank
/// belongs to the artwork, not to a separate column, so the horizontal rhythm
/// stays the same as every other cinematic shelf.
struct RankedMediaPoster: View {
    let item: MediaItem
    let rank: Int
    @Environment(\.showsMediaCardLabels) private var showsMediaCardLabels

    var body: some View {
        NavigationLink(value: item) {
            VStack(alignment: .leading, spacing: 8) {
                ArtworkView(item: item)
                    .frame(width: cardWidth, height: MediaBrowseMetrics.posterHeight)
                    .overlay(alignment: .topLeading) {
                        RankBadge(rank: rank)
                            .padding(10)
                    }

                if showsMediaCardLabels {
                    MediaPosterLabel(item: item)
                }
            }
            .frame(width: cardWidth, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Number \(rank), \(item.title)")
        .mediaContextMenu(for: item, placement: .browse)
    }

    private var cardWidth: CGFloat {
        return MediaBrowseMetrics.posterWidth
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
