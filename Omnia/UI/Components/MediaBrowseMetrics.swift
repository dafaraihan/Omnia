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
    #else
    static let pageInset: CGFloat = 32
    static let posterWidth: CGFloat = 154
    #endif

    static let shelfSpacing: CGFloat = 16
    static let gridSpacing: CGFloat = 18
    static let gridRowSpacing: CGFloat = 26
    static let shelfItemSpan: CGFloat = posterWidth + shelfSpacing
}
