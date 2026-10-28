//
//  CinematicHeroColumn.swift
//  Omnia
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

/// A single coordinate system for the identity portion of every cinematic
/// hero. Home and title detail intentionally share these measurements so the
/// logo, synopsis, and action row never drift independently.
enum CinematicHeroLayout {
    #if os(iOS)
    // iPad takes the Mac's column, which its screen has room for; the
    // iPhone's was too narrow there for the logo, synopsis and buttons.
    private static let isPad: Bool = {
        guard Thread.isMainThread else { return false }
        return MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
    }()
    static let horizontalInset: CGFloat = isPad ? 40 : 20
    static let contentWidth: CGFloat = isPad ? 620 : 360
    static let logoWidth: CGFloat = isPad ? 340 : 236
    static let logoHeight: CGFloat = isPad ? 98 : 74
    // Identity text shares the logo's exact column, rather than extending
    // wider into the backdrop. This keeps the transparent mark, synopsis,
    // and action row on one clean visual axis.
    static let synopsisWidth: CGFloat = logoWidth
    static let synopsisFontSize: CGFloat = isPad ? 14 : 13
    #else
    static let horizontalInset: CGFloat = 48
    static let contentWidth: CGFloat = 620
    static let logoWidth: CGFloat = 340
    static let logoHeight: CGFloat = 98
    static let synopsisWidth: CGFloat = logoWidth
    static let synopsisFontSize: CGFloat = 13
    #endif
}

/// Places hero identity content in a fixed, shared column. The caller owns
/// vertical placement; this view owns the horizontal geometry.
struct CinematicHeroColumn<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .frame(width: CinematicHeroLayout.contentWidth, alignment: .leading)
    }
}

/// The concise, provider-backed identity line shared by the Home and title
/// detail heroes. It deliberately uses the exact logo column so the mark,
/// metadata, synopsis, and actions form one visual axis.
struct HeroMetadataLine: View {
    let item: MediaItem

    private var values: [String] {
        var values = [item.year, item.kind == .series ? "TV Show" : item.kind.rawValue]
        if !item.genres.isEmpty {
            values.append(item.genres.prefix(2).joined(separator: ", "))
        }
        if let ageRating = item.details?.ageRating, !ageRating.isEmpty {
            values.append(ageRating)
        }
        return values
    }

    var body: some View {
        Text(values.joined(separator: " · "))
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.82))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: CinematicHeroLayout.logoWidth, alignment: .leading)
            .accessibilityLabel(values.joined(separator: ", "))
    }
}
