//
//  MediaBrowseMetrics.swift
//  Omnia
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

/// The shared rhythm for every media browse page. Anime, Search, Discover,
/// Library, and provider catalog pages must always use the same poster width,
/// shelf gap, grid gap, and content inset.
enum MediaBrowseMetrics {
    #if os(iOS)
    static let pageInset: CGFloat = 20
    static let posterWidth: CGFloat = 132
    static let posterMaximumGridWidth: CGFloat = 168
    #else
    static let pageInset: CGFloat = 32
    static let posterWidth: CGFloat = 154
    static let posterMaximumGridWidth: CGFloat = 190
    #endif

    static let shelfSpacing: CGFloat = 16
    static let gridSpacing: CGFloat = 18
    static let gridRowSpacing: CGFloat = 26
    #if os(iOS)
    static let landscapeCardWidth: CGFloat = 248
    static let landscapeCardMaximumGridWidth: CGFloat = 300
    #else
    static let landscapeCardWidth: CGFloat = 304
    static let landscapeCardMaximumGridWidth: CGFloat = 360
    #endif
    static let shelfItemSpan: CGFloat = posterWidth + shelfSpacing
    static let posterHeight: CGFloat = posterWidth * 1.5
    static let posterCornerRadius: CGFloat = 14
    static let landscapeCornerRadius: CGFloat = 16

    /// Poster cards follow Settings › Appearance › Poster Cards. Landscape
    /// posters swap every poster row and grid to backdrop cards.
    static func posterItemSpan(_ display: DisplayPreferences) -> CGFloat {
        (display.landscapePosters ? display.landscapePosterCardWidth : display.posterCardWidth) + shelfSpacing
    }

    static func posterGridLayout(containerWidth: CGFloat, display: DisplayPreferences) -> MediaGridLayout {
        if display.landscapePosters {
            return landscapeGridLayout(containerWidth: containerWidth, display: display)
        }
        return MediaGridLayout.fitting(
            containerWidth: containerWidth,
            horizontalInset: pageInset,
            minimumItemWidth: display.posterCardWidth,
            maximumItemWidth: display.posterCardWidth * posterMaximumGridWidth / posterWidth,
            spacing: gridSpacing
        )
    }

    /// As many columns as fit at the poster width, then stretched so the
    /// grid fills the row instead of leaving a gap on the trailing side.
    /// A row's card width would leave one or two enormous columns on iPhone,
    /// so its grids fit two landscape cards or three posters across.
    private static func gridMinimum(_ display: DisplayPreferences) -> CGFloat {
        let width = display.landscapePosters ? display.landscapePosterCardWidth : display.posterCardWidth
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            return min(width, display.landscapePosters ? 160 : 104)
        }
        #endif
        return width
    }

    static func posterGridColumns(_ display: DisplayPreferences) -> [GridItem] {
        [GridItem(
            .adaptive(
                minimum: gridMinimum(display),
                maximum: .infinity
            ),
            spacing: gridSpacing,
            alignment: .top
        )]
    }

    static func posterGridLayout(containerWidth: CGFloat) -> MediaGridLayout {
        MediaGridLayout.fitting(
            containerWidth: containerWidth,
            horizontalInset: pageInset,
            minimumItemWidth: posterWidth,
            maximumItemWidth: posterMaximumGridWidth,
            spacing: gridSpacing
        )
    }

    static func landscapeGridLayout(containerWidth: CGFloat, display: DisplayPreferences = .default) -> MediaGridLayout {
        MediaGridLayout.fitting(
            containerWidth: containerWidth,
            horizontalInset: pageInset,
            minimumItemWidth: display.landscapePosterCardWidth,
            maximumItemWidth: display.landscapePosterCardWidth * landscapeCardMaximumGridWidth / landscapeCardWidth,
            spacing: gridSpacing
        )
    }
}

struct MediaGridLayout: Equatable {
    let columnCount: Int
    let itemWidth: CGFloat
    let spacing: CGFloat

    var columns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(itemWidth), spacing: spacing, alignment: .top),
            count: columnCount
        )
    }

    static func fitting(
        containerWidth: CGFloat,
        horizontalInset: CGFloat,
        minimumItemWidth: CGFloat,
        maximumItemWidth: CGFloat,
        spacing: CGFloat
    ) -> MediaGridLayout {
        let contentWidth = max(0, containerWidth - horizontalInset * 2)
        let minimumSpan = max(1, minimumItemWidth + spacing)
        let columnCount = max(1, Int((contentWidth + spacing) / minimumSpan))
        let totalSpacing = spacing * CGFloat(max(0, columnCount - 1))
        let uncappedItemWidth = max(0, (contentWidth - totalSpacing) / CGFloat(columnCount))

        return MediaGridLayout(
            columnCount: columnCount,
            itemWidth: min(maximumItemWidth, uncappedItemWidth),
            spacing: spacing
        )
    }
}
