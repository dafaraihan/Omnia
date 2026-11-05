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
    /// Library: only the title under the art. Custom posters such as
    /// Xperience's carry their own details, so Omnia draws nothing over them.
    var showsTitleOnly = false
    @Environment(\.showsMediaCardLabels) private var showsMediaCardLabels
    @Environment(\.displayPreferences) private var display

    /// Landscape Posters (Settings › Appearance › Poster Cards) turns a
    /// standard poster into a backdrop card with the title logo.
    private var usesBackdropCard: Bool {
        style == .poster && display.landscapePosters
    }

    private var isLandscape: Bool { style == .landscape || usesBackdropCard }

    private var cornerRadius: CGFloat {
        isLandscape ? display.landscapeCornerRadius : display.posterCornerRadius
    }

    var body: some View {
        MediaDetailLink(item: item) {
            VStack(alignment: .leading, spacing: 8) {
                ArtworkView(item: item, prefersBackdrop: usesBackdropCard)
                    .aspectRatio(isLandscape ? 16 / 9 : 2 / 3, contentMode: .fit)
                    .frame(maxWidth: fillsAvailableWidth ? .infinity : nil)
                    // A set height too, or a two-line title shrinks the art in a shelf.
                    .frame(
                        width: fillsAvailableWidth ? nil : cardWidth,
                        height: fillsAvailableWidth ? nil : cardWidth / (isLandscape ? 16 / 9 : 2 / 3)
                    )
                    .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
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
                    .cardDepth(.posters, cornerRadius: cornerRadius)
                    .mediaHoverPreview(item)
                    .posterTransitionSource(item, prefersBackdrop: usesBackdropCard, cornerRadius: cornerRadius)

                if showsMediaCardLabels {
                    if showsTitleOnly {
                        Text(item.title)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    } else {
                        MediaPosterLabel(item: item)
                    }
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
        isLandscape ? display.landscapePosterCardWidth : display.posterCardWidth
    }
}

/// Apple TV presents a Top 10 shelf as a numbered poster sequence. The rank
/// belongs to the artwork, not to a separate column, so the horizontal rhythm
/// stays the same as every other cinematic shelf.
struct RankedMediaPoster: View {
    let item: MediaItem
    let rank: Int
    @Environment(\.showsMediaCardLabels) private var showsMediaCardLabels
    @Environment(\.displayPreferences) private var display

    var body: some View {
        MediaDetailLink(item: item) {
            VStack(alignment: .leading, spacing: 8) {
                ArtworkView(item: item, prefersBackdrop: display.landscapePosters)
                    .frame(width: cardWidth, height: cardHeight)
                    .overlay(alignment: .topLeading) {
                        RankBadge(rank: rank)
                            .padding(10)
                    }
                    .cardDepth(
                        .posters,
                        cornerRadius: display.landscapePosters ? display.landscapeCornerRadius : display.posterCornerRadius
                    )
                    .mediaHoverPreview(item)

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
        display.landscapePosters ? display.landscapePosterCardWidth : display.posterCardWidth
    }

    private var cardHeight: CGFloat {
        display.landscapePosters ? display.landscapeCardHeight : display.posterCardHeight
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
