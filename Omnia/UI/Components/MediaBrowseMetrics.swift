//
//  MediaBrowseMetrics.swift
//  Omnia
//

import SwiftUI

/// The shared rhythm for every media browse page. Anime, Search, Discover,
/// Library, and provider catalog pages must always use the same poster width,
/// shelf gap, grid gap, and content inset.
enum MediaBrowseMetrics {
    #if os(iOS)
    static let pageInset: CGFloat = 20
    static let posterWidth: CGFloat = 132
    static let posterMaximumGridWidth: CGFloat = 168
    static let genreCardWidth: CGFloat = 164
    static let genreCardHeight: CGFloat = 246
    static let genreMaximumGridWidth: CGFloat = 220
    #else
    static let pageInset: CGFloat = 32
    static let posterWidth: CGFloat = 154
    static let posterMaximumGridWidth: CGFloat = 190
    static let genreCardWidth: CGFloat = 220
    static let genreCardHeight: CGFloat = 330
    static let genreMaximumGridWidth: CGFloat = 280
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
    static let genreCornerRadius: CGFloat = 16
    static let genreGridSpacing: CGFloat = 14

    static func posterGridLayout(containerWidth: CGFloat) -> MediaGridLayout {
        MediaGridLayout.fitting(
            containerWidth: containerWidth,
            horizontalInset: pageInset,
            minimumItemWidth: posterWidth,
            maximumItemWidth: posterMaximumGridWidth,
            spacing: gridSpacing
        )
    }

    static func genreGridLayout(containerWidth: CGFloat) -> MediaGridLayout {
        MediaGridLayout.fitting(
            containerWidth: containerWidth,
            horizontalInset: pageInset,
            minimumItemWidth: genreCardWidth,
            maximumItemWidth: genreMaximumGridWidth,
            spacing: genreGridSpacing
        )
    }

    static func landscapeGridLayout(containerWidth: CGFloat) -> MediaGridLayout {
        MediaGridLayout.fitting(
            containerWidth: containerWidth,
            horizontalInset: pageInset,
            minimumItemWidth: landscapeCardWidth,
            maximumItemWidth: landscapeCardMaximumGridWidth,
            spacing: gridSpacing
        )
    }

    static var posterGridColumns: [GridItem] {
        [GridItem(
            .adaptive(minimum: posterWidth, maximum: posterWidth),
            spacing: gridSpacing,
            alignment: .top
        )]
    }

    static var genreGridColumns: [GridItem] {
        [GridItem(
            .adaptive(minimum: genreCardWidth, maximum: genreCardWidth),
            spacing: genreGridSpacing,
            alignment: .top
        )]
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

    var usedWidth: CGFloat {
        itemWidth * CGFloat(columnCount) + spacing * CGFloat(max(0, columnCount - 1))
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
