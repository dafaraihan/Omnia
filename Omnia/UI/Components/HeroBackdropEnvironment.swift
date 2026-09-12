//
//  HeroBackdropEnvironment.swift
//  Omnia
//

import SwiftUI

enum HeroArtworkPlacement: Equatable {
    case windowTracked
    case local
}

enum HeroBackdropSource: Equatable {
    case home
    case detail
}

struct WindowHeroPresentation {
    let item: MediaItem
    let frame: CGRect
}

@Observable
@MainActor
final class HeroBackdropState {
    private var homePresentation: WindowHeroPresentation?
    private var detailPresentation: WindowHeroPresentation?
    @ObservationIgnored private var homeOwner: UUID?
    @ObservationIgnored private var detailOwner: UUID?

    var presentation: WindowHeroPresentation? {
        detailPresentation ?? homePresentation
    }

    func report(_ item: MediaItem, frame: CGRect, from source: HeroBackdropSource, owner: UUID? = nil) {
        switch source {
        case .home:
            homeOwner = owner
            homePresentation = updatedPresentation(homePresentation, item: item, frame: frame)
        case .detail:
            // A detail request replaces its lightweight catalog model with
            // richer metadata while the page is already visible. Keep the
            // first artwork resource for that title so the full-window image
            // does not visibly recrop during the async handoff; only its
            // scrolling frame is allowed to change.
            detailOwner = owner
            detailPresentation = updatedPresentation(detailPresentation, item: item, frame: frame)
        }
    }

    private func updatedPresentation(
        _ current: WindowHeroPresentation?, item: MediaItem, frame: CGRect
    ) -> WindowHeroPresentation {
        // Metadata enrichment must not discard or replace artwork that is
        // already visible. A missing initial backdrop can still be filled in.
        let artworkItem: MediaItem
        if let current, current.item.backdropURL != nil, representsSameDetail(current.item, item) {
            artworkItem = current.item
        } else {
            artworkItem = item
        }
        return WindowHeroPresentation(item: artworkItem, frame: frame)
    }

    private func representsSameDetail(_ current: MediaItem, _ incoming: MediaItem) -> Bool {
        if current.id == incoming.id { return true }

        if let currentRecordID = current.metadataRecordID,
           currentRecordID == incoming.metadataRecordID {
            return true
        }

        if current.metadataProvider == incoming.metadataProvider,
           let currentProviderID = current.metadataProviderID,
           currentProviderID == incoming.metadataProviderID {
            return true
        }

        let sharesExternalID = current.externalIDs.contains { key, value in
            incoming.externalIDs[key] == value
        }
        if sharesExternalID {
            return true
        }

        return current.kind == incoming.kind
            && current.title.compare(
                incoming.title,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame
            && (current.year == incoming.year || current.year == "—" || incoming.year == "—")
    }

    func clear(_ source: HeroBackdropSource, owner: UUID? = nil) {
        switch source {
        case .home:
            guard owner == nil || owner == homeOwner else { return }
            homePresentation = nil
            homeOwner = nil
        case .detail:
            guard owner == nil || owner == detailOwner else { return }
            detailPresentation = nil
            detailOwner = nil
        }
    }
}

enum HeroBackdropPresentation {
    #if os(macOS)
    static let artworkPlacement: HeroArtworkPlacement = .windowTracked
    #else
    static let artworkPlacement: HeroArtworkPlacement = .local
    #endif

    static let windowCoordinateSpace = "OmniaWindowHero"

    static var drawsLocalHeroArtwork: Bool {
        artworkPlacement == .local
    }

    static let usesArtworkAccentBelowHero = true
}

private struct HeroBackdropReporterKey: EnvironmentKey {
    static let defaultValue: (HeroBackdropSource, UUID, MediaItem?, CGRect) -> Void = { _, _, _, _ in }
}

extension EnvironmentValues {
    var reportWindowHeroBackdrop: (HeroBackdropSource, UUID, MediaItem?, CGRect) -> Void {
        get { self[HeroBackdropReporterKey.self] }
        set { self[HeroBackdropReporterKey.self] = newValue }
    }
}

struct HeroAccentBackground: View {
    let item: MediaItem

    var body: some View {
        ZStack {
            LinearGradient(
                colors: item.artworkColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let url = item.backdropURL ?? item.artworkURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 72)
                            .scaleEffect(1.18)
                    }
                }
            }

            Color.black.opacity(0.64)
            LinearGradient(
                colors: [.black.opacity(0.20), .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct HeroArtworkCanvas: View {
    let item: MediaItem
    var source: HeroBackdropSource?
    var artworkAlignment: Alignment = .topTrailing
    @Environment(\.reportWindowHeroBackdrop) private var reportWindowHeroBackdrop
    @State private var measuredFrame = CGRect.zero
    @State private var owner = UUID()

    var body: some View {
        Group {
            if HeroBackdropPresentation.drawsLocalHeroArtwork {
                FeaturedBackdrop(item: item, artworkAlignment: artworkAlignment)
            } else {
                Color.clear
            }
        }
        #if os(macOS)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(HeroBackdropPresentation.windowCoordinateSpace))
        } action: { frame in
            measuredFrame = frame
            report(item: item, frame: frame)
        }
        .onChange(of: artworkKey) { _, _ in
            report(item: item, frame: measuredFrame)
        }
        .onAppear {
            report(item: item, frame: measuredFrame)
        }
        .onDisappear {
            guard let source else { return }
            reportWindowHeroBackdrop(source, owner, nil, measuredFrame)
        }
        #endif
    }

    #if os(macOS)
    private var artworkKey: String {
        "\(item.id)|\(item.backdropURL?.absoluteString ?? "")"
    }

    private func report(item: MediaItem, frame: CGRect) {
        guard let source, frame.width > 0, frame.height > 0 else { return }
        reportWindowHeroBackdrop(source, owner, item, frame)
    }
    #endif
}

#if os(macOS)
enum WindowHeroBackdropLayout {
    static func artworkFrame(windowWidth: CGFloat, measuredHeroFrame: CGRect) -> CGRect {
        CGRect(
            x: 0,
            y: measuredHeroFrame.minY,
            width: windowWidth,
            height: measuredHeroFrame.height
        )
    }

    static func accentFrame(windowSize: CGSize, measuredHeroFrame: CGRect) -> CGRect {
        let originY = measuredHeroFrame.maxY
        return CGRect(
            x: 0,
            y: originY,
            width: windowSize.width,
            height: max(0, windowSize.height - originY)
        )
    }
}

struct WindowHeroBackdrop: View {
    let state: HeroBackdropState

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color(nsColor: .windowBackgroundColor)

                if let presentation = state.presentation {
                    let artworkFrame = WindowHeroBackdropLayout.artworkFrame(
                        windowWidth: proxy.size.width,
                        measuredHeroFrame: presentation.frame
                    )
                    let accentFrame = WindowHeroBackdropLayout.accentFrame(
                        windowSize: proxy.size,
                        measuredHeroFrame: presentation.frame
                    )

                    HeroAccentBackground(item: presentation.item)
                        .frame(width: accentFrame.width, height: accentFrame.height)
                        .offset(x: accentFrame.minX, y: accentFrame.minY)

                    ZStack {
                        LinearGradient(
                            colors: presentation.item.artworkColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )

                        FeaturedBackdrop(
                            item: presentation.item,
                            artworkAlignment: .topTrailing
                        )

                        LinearGradient(
                            colors: [.clear, .black.opacity(0.22), .black.opacity(0.68)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .frame(width: artworkFrame.width, height: artworkFrame.height)
                    .clipped()
                    .offset(x: artworkFrame.minX, y: artworkFrame.minY)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
