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
        // Scrolled past: nothing to move, so the rest of the page's scrolling
        // doesn't redraw the window backdrop on every tick.
        let current = source == .home ? homePresentation : detailPresentation
        if let current, current.item.id == item.id, current.frame.maxY <= 0, frame.maxY <= 0 { return }
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

/// Home alone uses a solid artwork wash; detail and stream surfaces keep
/// their existing cinematic gradients.
struct HomeArtworkBackground: View {
    let item: MediaItem?
    var isEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var tint: ArtworkTint?

    private var artworkURL: URL? {
        guard isEnabled, !reduceTransparency, contrast != .increased else { return nil }
        return item?.backdropURL ?? item?.artworkURL
    }

    /// A colour already worked out shows at once. Starting blank and fading in
    /// made the page flash each time a new copy of this view appeared.
    private var shownTint: ArtworkTint? {
        tint ?? artworkURL.flatMap { ArtworkTintMemory.colors[$0] }
    }

    var body: some View {
        OmniaPageBackground()
            .overlay {
                if artworkURL != nil, let tint = shownTint {
                    Color(red: tint.red, green: tint.green, blue: tint.blue).opacity(0.42)
                }
            }
            .animation(reduceMotion ? nil : .timingCurve(0, 0, 0.2, 1, duration: 0.6), value: tint)
            .task(id: artworkURL) {
                guard let url = artworkURL else { tint = nil; return }
                // Keep the preceding tint while the next artwork is loading.
                let next = await ArtworkTintCache.shared.tint(for: url)
                guard !Task.isCancelled else { return }
                if let next { ArtworkTintMemory.colors[url] = next }
                tint = next
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A vertical fade in the page's colour. It draws one plain gradient: masking
/// a full copy of the page over a moving trailer costs an extra GPU pass every
/// frame.
private struct HeroWashFade: View {
    @Environment(\.displayPreferences) private var display
    @Environment(\.self) private var environment
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var tint: ArtworkTint?

    let item: MediaItem
    let stops: [(location: Double, opacity: Double)]

    private var artworkURL: URL? {
        guard !reduceTransparency, contrast != .increased else { return nil }
        return item.backdropURL ?? item.artworkURL
    }

    /// The same colour as `HomeArtworkBackground` in dark: the tint at 42%
    /// over the page, worked out once.
    private var color: Color {
        var dark = environment
        dark.colorScheme = .dark
        #if os(iOS)
        let system = Color(uiColor: .systemBackground)
        #else
        let system = Color(nsColor: .windowBackgroundColor)
        #endif
        let page = (display.amoledBlack ? Color.black : system).resolve(in: dark)
        guard let tint = tint ?? artworkURL.flatMap({ ArtworkTintMemory.colors[$0] }) else {
            return Color(page)
        }
        return Color(
            red: Double(page.red) * 0.58 + tint.red * 0.42,
            green: Double(page.green) * 0.58 + tint.green * 0.42,
            blue: Double(page.blue) * 0.58 + tint.blue * 0.42
        )
    }

    var body: some View {
        let color = color
        LinearGradient(
            stops: stops.map { .init(color: color.opacity($0.opacity), location: $0.location) },
            startPoint: .top,
            endPoint: .bottom
        )
        .task(id: artworkURL) {
            guard let url = artworkURL else { tint = nil; return }
            let next = await ArtworkTintCache.shared.tint(for: url)
            guard !Task.isCancelled else { return }
            if let next { ArtworkTintMemory.colors[url] = next }
            tint = next
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Melts a hero's lower part into the artwork wash under it, so the hero and
/// the rows below read as one surface. Set in Settings › Layout.
struct HeroBottomBlend: View {
    @Environment(\.displayPreferences) private var display

    let item: MediaItem

    var body: some View {
        let blend = display.heroBlend
        let top = 1 - blend.height
        HeroWashFade(item: item, stops: [
            (top, 0),
            (top + blend.height * 0.41, 0.55 * blend.strength),
            (top + blend.height * 0.72, 0.92 * blend.strength),
            (top + blend.height * 0.9, blend.strength)
        ])
    }
}

/// Under a playing trailer on iPad and Mac: a short fade, so the video doesn't
/// end in a hard edge, without covering the picture as the full overlay does.
struct HeroTrailerBottomFade: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: MediaItem
    var usesWash: Bool

    var body: some View {
        // Without the wash, fading into a light page would hide the hero's text.
        if usesWash || colorScheme == .dark {
            HeroWashFade(item: item, stops: [(0.78, 0), (0.92, 0.6), (1, 1)])
        }
    }
}

/// Over a playing trailer: covers the black bar some trailers have at the top.
struct HeroTrailerTopFade: View {
    let item: MediaItem
    var usesWash: Bool

    var body: some View {
        if usesWash {
            HeroWashFade(item: item, stops: [(0, 1), (0.1, 0.8), (0.3, 0)])
        } else {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.8), location: 0.1),
                    .init(color: .clear, location: 0.3)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Colours already worked out, readable while a view draws.
@MainActor
private enum ArtworkTintMemory {
    static var colors: [URL: ArtworkTint] = [:]
}

private nonisolated struct ArtworkTint: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
}

/// Shares the existing bounded HTTPS artwork loader, then samples at most
/// 96 × 96 pixels. The small color cache has no image or credential payloads.
private actor ArtworkTintCache {
    static let shared = ArtworkTintCache()
    private var colors: [URL: ArtworkTint] = [:]
    private var order: [URL] = []

    func tint(for url: URL) async -> ArtworkTint? {
        if let color = colors[url] {
            order.removeAll { $0 == url }
            order.append(url)
            return color
        }
        guard !Task.isCancelled,
              let image = await RemoteArtworkCache.shared.image(
                for: url, target: RemoteArtworkTarget(width: 96, height: 96, fills: false)
              ), !Task.isCancelled else { return nil }
        guard let color = Self.extract(image), !Task.isCancelled else { return nil }
        colors[url] = color
        order.removeAll { $0 == url }
        order.append(url)
        while order.count > 256 { colors.removeValue(forKey: order.removeFirst()) }
        return color
    }

    private nonisolated static func extract(_ image: CGImage) -> ArtworkTint? {
        let side = 96
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        var swatches: [Int: (count: Int, red: Double, green: Double, blue: Double)] = [:]
        for index in stride(from: 0, to: pixels.count, by: 4) {
            guard pixels[index + 3] >= 240 else { continue }
            let r = Double(pixels[index]) / 255
            let g = Double(pixels[index + 1]) / 255
            let b = Double(pixels[index + 2]) / 255
            let high = max(r, g, b), low = min(r, g, b)
            let lightness = (high + low) / 2
            let saturation = high == low ? 0 : (high - low) / (1 - abs(2 * lightness - 1))
            guard (0.22...0.92).contains(lightness), saturation >= 0.08 else { continue }
            let key = (Int(pixels[index]) >> 4) << 8 | (Int(pixels[index + 1]) >> 4) << 4 | Int(pixels[index + 2]) >> 4
            var swatch = swatches[key] ?? (0, 0, 0, 0)
            swatch.count += 1
            swatch.red += r; swatch.green += g; swatch.blue += b
            swatches[key] = swatch
        }
        guard let swatch = swatches.values.max(by: { $0.count < $1.count }) else { return nil }
        let count = Double(swatch.count)
        let r = swatch.red / count, g = swatch.green / count, b = swatch.blue / count
        let high = max(r, g, b), low = min(r, g, b)
        let lightness = (high + low) / 2
        let desired = min(0.8, max(0.45, lightness))
        // Preserve hue and saturation while lifting the selected HSL swatch.
        let factor = (1 - abs(2 * desired - 1)) / max(0.001, 1 - abs(2 * lightness - 1))
        return ArtworkTint(
            red: min(1, max(0, desired + (r - lightness) * factor)),
            green: min(1, max(0, desired + (g - lightness) * factor)),
            blue: min(1, max(0, desired + (b - lightness) * factor))
        )
    }
}

struct HeroAccentBackground: View {
    let item: MediaItem

    fileprivate static let downscale: CGFloat = 8

    var body: some View {
        ZStack {
            MediaItem.placeholderArtworkColor

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

}

/// Only the artwork changing redraws it; scrolling just moves it.
private struct WindowHeroArtwork: View, Equatable {
    let item: MediaItem

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item.id == rhs.item.id && lhs.item.backdropURL == rhs.item.backdropURL
    }

    var body: some View {
        FeaturedBackdrop(item: item, artworkAlignment: .topTrailing)
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
                    HomeArtworkBackground(item: accentItem)
                        .environment(\.colorScheme, .dark)
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
                            MediaItem.placeholderArtworkColor

                            WindowHeroArtwork(item: presentation.item)
                                .equatable()

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
