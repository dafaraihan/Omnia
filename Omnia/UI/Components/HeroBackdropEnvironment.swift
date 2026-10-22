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
    let source: HeroBackdropSource
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

    func activate(_ source: HeroBackdropSource, owner: UUID) {
        switch source {
        case .home:
            homeOwner = owner
        case .detail:
            detailOwner = owner
        }
    }

    func report(_ item: MediaItem, frame: CGRect, from source: HeroBackdropSource, owner: UUID? = nil) {
        switch source {
        case .home:
            if let owner {
                guard owner == homeOwner else { return }
            }
            homePresentation = updatedPresentation(homePresentation, item: item, frame: frame, source: .home)
        case .detail:
            if let owner {
                guard owner == detailOwner else { return }
            }
            // A detail request replaces its lightweight catalog model with
            // richer metadata while the page is already visible. Keep the
            // first artwork resource for that title so the full-window image
            // does not visibly recrop during the async handoff; only its
            // scrolling frame is allowed to change.
            detailPresentation = updatedPresentation(detailPresentation, item: item, frame: frame, source: .detail)
        }
    }

    private func updatedPresentation(
        _ current: WindowHeroPresentation?, item: MediaItem, frame: CGRect, source: HeroBackdropSource
    ) -> WindowHeroPresentation {
        // Metadata enrichment must not discard or replace artwork that is
        // already visible. A missing initial backdrop can still be filled in.
        if let current, current.item.backdropURL != nil, representsSameDetail(current.item, item) {
            return WindowHeroPresentation(item: current.item, frame: frame, source: source)
        }
        return WindowHeroPresentation(item: item, frame: frame, source: source)
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

private struct HeroBackdropActivationKey: EnvironmentKey {
    static let defaultValue: (HeroBackdropSource, UUID) -> Void = { _, _ in }
}

private struct ActiveDestinationKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Production screens rendered as a passive onboarding demonstration.
    @Entry var isOnboardingPreview = false

    var reportWindowHeroBackdrop: (HeroBackdropSource, UUID, MediaItem?, CGRect) -> Void {
        get { self[HeroBackdropReporterKey.self] }
        set { self[HeroBackdropReporterKey.self] = newValue }
    }

    var activateWindowHeroBackdrop: (HeroBackdropSource, UUID) -> Void {
        get { self[HeroBackdropActivationKey.self] }
        set { self[HeroBackdropActivationKey.self] = newValue }
    }

    /// False while a destination's stack is kept alive in a hidden tab. Its
    /// hero must not drive the shared window backdrop, and its timers pause.
    var isActiveDestination: Bool {
        get { self[ActiveDestinationKey.self] }
        set { self[ActiveDestinationKey.self] = newValue }
    }
}

struct HeroAccentBackground: View {
    let item: MediaItem

    fileprivate static let downscale: CGFloat = 8

    var body: some View {
        ZStack {
            LinearGradient(
                colors: item.artworkColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let url = item.backdropURL ?? item.artworkURL {
                // The fill image is laid out as an overlay so its aspect-fill size
                // never feeds back into the ZStack. Otherwise the stack grows past
                // the frame it was given and spills up over the hero above it.
                Color.clear
                    .overlay {
                        GeometryReader { proxy in
                            // Blurring at full window size is costly and was
                            // redone while scrolling. Blur a copy an eighth of
                            // the size instead and scale it up: a heavy blur
                            // looks the same either way. It is decoded at that
                            // size too, unless a sharper copy is already kept.
                            let scale = HeroAccentBackground.downscale
                            CachedArtworkImage(
                                url: url,
                                size: CGSize(width: proxy.size.width / scale, height: proxy.size.height / scale)
                            ) { phase in
                                if let image = phase.image {
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: proxy.size.width / scale, height: proxy.size.height / scale)
                                        .clipped()
                                        .blur(radius: 72 / scale)
                                        .drawingGroup()
                                        .scaleEffect(scale * 1.18)
                                        .frame(width: proxy.size.width, height: proxy.size.height)
                                }
                            }
                        }
                    }
                    .clipped()
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

extension HeroAccentBackground: Equatable {
    /// Only the artwork matters; richer metadata for the same title must not
    /// re-render the blur.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item.backdropURL == rhs.item.backdropURL
            && lhs.item.artworkURL == rhs.item.artworkURL
            && lhs.item.artworkColors == rhs.item.artworkColors
    }
}

struct HeroArtworkCanvas: View {
    let item: MediaItem
    var source: HeroBackdropSource?
    var artworkAlignment: Alignment = .topTrailing
    /// Draws the artwork in place even on macOS, for Home's Card hero. The
    /// window then draws only the accent behind it.
    var drawsArtworkLocally = false
    @Environment(\.activateWindowHeroBackdrop) private var activateWindowHeroBackdrop
    @Environment(\.reportWindowHeroBackdrop) private var reportWindowHeroBackdrop
    @Environment(\.isActiveDestination) private var isActiveDestination
    @State private var measuredFrame = CGRect.zero
    @State private var owner = UUID()

    var body: some View {
        Group {
            if HeroBackdropPresentation.drawsLocalHeroArtwork || drawsArtworkLocally {
                FeaturedBackdrop(item: item, artworkAlignment: artworkAlignment)
            } else {
                Color.clear
            }
        }
        #if os(macOS)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            measuredFrame = frame
            report(item: item, frame: frame)
        }
        .onChange(of: artworkKey) { _, _ in
            report(item: item, frame: measuredFrame)
        }
        .onAppear {
            guard let source, isActiveDestination else { return }
            activateWindowHeroBackdrop(source, owner)
            report(item: item, frame: measuredFrame)
        }
        // A hero in a hidden tab (the Home carousel keeps rotating there)
        // claims the window backdrop again only when its tab is shown.
        .onChange(of: isActiveDestination) { _, isActive in
            guard let source, isActive else { return }
            activateWindowHeroBackdrop(source, owner)
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
        guard let source, isActiveDestination, frame.width > 0, frame.height > 0 else { return }
        reportWindowHeroBackdrop(source, owner, item, frame)
    }
    #endif
}

#if os(macOS)
enum WindowHeroBackdropLayout {
    static func artworkFrame(windowWidth: CGFloat, measuredHeroFrame: CGRect, backdropGlobalFrame: CGRect) -> CGRect {
        CGRect(
            x: 0,
            y: measuredHeroFrame.minY - backdropGlobalFrame.minY,
            width: windowWidth,
            height: measuredHeroFrame.height
        )
    }

    static func accentFrame(windowSize: CGSize, measuredHeroFrame: CGRect, backdropGlobalFrame: CGRect) -> CGRect {
        let originY = measuredHeroFrame.maxY - backdropGlobalFrame.minY
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
    @Environment(HomeLayoutStore.self) private var homeLayout
    /// The accent fades out when the hero scrolls away instead of cutting
    /// to black, then is dropped so nothing is drawn behind the shelves.
    @State private var accentItem: MediaItem?
    @State private var accentVisible = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                OmniaPageBackground()

                if let accentItem {
                    HeroAccentBackground(item: accentItem)
                        .equatable()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .opacity(accentVisible ? 1 : 0)
                }

                if let presentation = state.presentation {
                    let globalFrame = proxy.frame(in: .global)
                    let artworkFrame = WindowHeroBackdropLayout.artworkFrame(
                        windowWidth: proxy.size.width,
                        measuredHeroFrame: presentation.frame,
                        backdropGlobalFrame: globalFrame
                    )

                    // The accent (drawn above) covers the whole window and
                    // depends only on the item, so scrolling, which moves the
                    // hero frame, never re-renders the blur.
                    let isHome = presentation.source == .home

                    // Home's Card hero draws its own artwork inside the card.
                    if !isHome || homeLayout.preferences.heroStyle == .fullBleed {
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
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: updateAccent)
        .onChange(of: accentKey) { updateAccent() }
    }

    private var wantedAccent: MediaItem? {
        guard let presentation = state.presentation else { return nil }
        guard presentation.source != .home || homeLayout.preferences.dynamicBackground else { return nil }
        return presentation.item
    }

    private var accentKey: String {
        guard let item = wantedAccent else { return "" }
        return "\(item.id)|\(item.backdropURL?.absoluteString ?? item.artworkURL?.absoluteString ?? "")"
    }

    private func updateAccent() {
        if let item = wantedAccent {
            accentItem = item
            withAnimation(.easeOut(duration: 0.35)) { accentVisible = true }
        } else if accentItem != nil {
            withAnimation(.easeInOut(duration: 0.55)) {
                accentVisible = false
            } completion: {
                if !accentVisible { accentItem = nil }
            }
        }
    }
}
#endif
