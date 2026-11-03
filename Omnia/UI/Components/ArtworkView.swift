//
//  ArtworkView.swift
//  Omnia
//

import ImageIO
import SwiftUI

struct ArtworkView: View {
    let item: MediaItem
    var showsTitle: Bool = false
    /// Landscape poster cards draw the backdrop with the title logo over it.
    var prefersBackdrop = false
    @Environment(\.displayPreferences) private var display

    private var imageURL: URL? {
        prefersBackdrop ? item.backdropURL ?? item.artworkURL : item.artworkURL
    }

    /// Settings › Layout › Poster Cards › Custom Poster Source. Backdrop
    /// cards use it only when the pattern can ask for a landscape image.
    private var customURL: URL? {
        let pattern = display.customPosterURLPattern
        guard !pattern.isEmpty else { return nil }
        if prefersBackdrop {
            guard pattern.contains("{shape}") else { return nil }
            return CustomPosterURLResolver.url(for: item, pattern: pattern, shape: "landscape")
        }
        return CustomPosterURLResolver.url(for: item, pattern: pattern)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            fallbackArtwork

            if let customURL {
                // A failed custom poster falls back to the title's own.
                RemoteArtworkImage(url: customURL, fallbackURL: imageURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let artworkURL = imageURL {
                RemoteArtworkImage(url: artworkURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if prefersBackdrop, let logoURL = item.logoURL {
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                TitleLogoView(url: logoURL, title: item.title, maximumWidth: 150, maximumHeight: 44, alignment: .bottomLeading)
                    .padding(12)
            } else if prefersBackdrop {
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(12)
            }

            if showsTitle {
                LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(12)
            }
        }
        .clipShape(.rect(cornerRadius: display.posterCornerRadius, style: .continuous))
        .accessibilityLabel("Artwork for \(item.title)")
    }

    private var fallbackArtwork: some View {
        ZStack {
            LinearGradient(colors: item.artworkColors, startPoint: .topLeading, endPoint: .bottomTrailing)

            Image(systemName: item.symbol)
                .font(.system(size: 44, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A card's poster or backdrop. AsyncImage gave up for good on the first
/// failure, and a row scrolled past cancelled its loads, so add-on posters
/// that are drawn on request (Xperience's badges) often stayed blank. Here
/// a load keeps going when the card scrolls away, is retried, and the
/// result is kept in memory for every card that shows the same image.
/// It fills its frame, and is decoded at the size it is drawn.
struct RemoteArtworkImage: View {
    let url: URL
    /// Shown instead when `url` fails, such as a custom poster service that
    /// has no image for the title.
    var fallbackURL: URL? = nil
    @State private var size = CGSize.zero

    var body: some View {
        Color.clear
            .onGeometryChange(for: CGSize.self) { $0.size } action: { newValue in
                // Grow only: a smaller frame can keep the sharper copy.
                let grown = CGSize(width: max(size.width, newValue.width), height: max(size.height, newValue.height))
                if grown != size { size = grown }
            }
            .overlay {
                CachedArtworkImage(url: url, size: size, transaction: .init(animation: .easeInOut)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    } else if case .failure = phase, let fallbackURL, fallbackURL != url {
                        CachedArtworkImage(url: fallbackURL, size: size, transaction: .init(animation: .easeInOut)) { fallback in
                            if let image = fallback.image {
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .transition(.opacity)
                            }
                        }
                    }
                }
            }
            .clipped()
    }
}

/// What `CachedArtworkImage` has to show, like AsyncImagePhase.
enum RemoteArtworkPhase {
    case empty
    case success(Image)
    case failure

    var image: Image? {
        if case let .success(image) = self { return image }
        return nil
    }
}

/// How much of an image a frame needs, in pixels: the frame's size and
/// whether the image fills it (cropping) or fits inside it.
nonisolated struct RemoteArtworkTarget: Hashable, Sendable {
    let width: Int
    let height: Int
    let fills: Bool

    var isEmpty: Bool { width == 0 || height == 0 }

    /// The longest side the image needs, given its own aspect ratio.
    func longestSide(sourceWidth: Int, sourceHeight: Int) -> Int {
        guard sourceWidth > 0, sourceHeight > 0 else { return max(width, height) }
        let scaleX = Double(width) / Double(sourceWidth)
        let scaleY = Double(height) / Double(sourceHeight)
        let scale = fills ? max(scaleX, scaleY) : min(scaleX, scaleY)
        return Int((Double(max(sourceWidth, sourceHeight)) * scale).rounded(.up))
    }

    /// True when `image` is sharp enough for this frame. A pixel or two
    /// short is decoder rounding.
    func isCovered(by image: CGImage) -> Bool {
        let imageWidth = image.width + 2, imageHeight = image.height + 2
        return fills
            ? imageWidth >= width && imageHeight >= height
            : imageWidth >= width || imageHeight >= height
    }
}

/// AsyncImage's replacement: the same phases, but loads go through
/// `RemoteArtworkCache` and are decoded at the pixel size the image is drawn
/// at on this display, never smaller. A 4K backdrop drawn 1440 points wide
/// keeps 2880 pixels instead of 3840: it looks the same and holds about
/// half the memory.
///
/// `size` is the frame the image is drawn in, in points, and `contentMode`
/// how it is drawn there. Nothing loads while the size is zero.
struct CachedArtworkImage<Content: View>: View {
    let url: URL?
    let size: CGSize
    var contentMode: ContentMode = .fill
    var transaction = Transaction()
    @ViewBuilder let content: (RemoteArtworkPhase) -> Content
    @Environment(\.displayScale) private var displayScale
    @State private var loaded: (url: URL, image: CGImage)?
    @State private var failedURL: URL?

    init(
        url: URL?,
        size: CGSize,
        contentMode: ContentMode = .fill,
        transaction: Transaction = Transaction(),
        @ViewBuilder content: @escaping (RemoteArtworkPhase) -> Content
    ) {
        self.url = url
        self.size = size
        self.contentMode = contentMode
        self.transaction = transaction
        self.content = content
    }

    /// Rounded up to steps of 64 pixels, so a window resize doesn't decode
    /// again for every point, with room for the cards' hover lift.
    private var target: RemoteArtworkTarget {
        let scale = max(displayScale, 1) * 1.05
        return RemoteArtworkTarget(
            width: RemoteArtworkCache.bucket(size.width * scale),
            height: RemoteArtworkCache.bucket(size.height * scale),
            fills: contentMode == .fill
        )
    }

    private var image: CGImage? {
        guard let url else { return nil }
        if let cached = RemoteArtworkCache.shared.cachedImage(for: url, target: target) { return cached }
        // While a sharper copy loads, keep showing the one already here,
        // or a smaller one another view loaded.
        if let loaded, loaded.url == url { return loaded.image }
        return RemoteArtworkCache.shared.anyImage(for: url)
    }

    private var phase: RemoteArtworkPhase {
        if let image { return .success(Image(decorative: image, scale: max(displayScale, 1))) }
        if url == nil || failedURL == url { return .failure }
        return .empty
    }

    var body: some View {
        // The empty point keeps the view (and its load) alive while `content`
        // draws nothing; it doesn't change the content's size or place.
        ZStack {
            Color.clear.frame(width: 0, height: 0)
            content(phase)
        }
        .task(id: LoadKey(url: url, target: target)) {
            let target = target
            guard let url, !target.isEmpty else { return }
            let cache = RemoteArtworkCache.shared
            if let cached = cache.cachedImage(for: url, target: target) {
                // Another card may have loaded it after this one was drawn.
                if loaded?.url != url || loaded?.image !== cached { loaded = (url, cached) }
                return
            }
            guard let fetched = await cache.image(for: url, target: target), !Task.isCancelled else {
                if !Task.isCancelled, loaded?.url != url { failedURL = url }
                return
            }
            failedURL = nil
            withTransaction(transaction) { loaded = (url, fetched) }
        }
    }

    private nonisolated struct LoadKey: Equatable {
        let url: URL?
        let target: RemoteArtworkTarget
    }
}

@MainActor
final class RemoteArtworkCache {
    static let shared = RemoteArtworkCache()

    private let memory = NSCache<NSURL, CGImageBox>()
    private var inFlight: [InFlightKey: Task<RemoteArtworkImageData?, Never>] = [:]

    private init() {
        // Images are decoded at the size they are drawn, so this holds a few
        // hundred cards; NSCache also gives memory back when the Mac needs it.
        memory.totalCostLimit = 192 * 1_024 * 1_024
    }

    /// Rounds a pixel length up to the next step of 64.
    nonisolated static func bucket(_ pixels: CGFloat) -> Int {
        guard pixels > 0 else { return 0 }
        let step = 64
        return Int((pixels / CGFloat(step)).rounded(.up)) * step
    }

    /// The kept copy, when it is sharp enough for `target` or is already
    /// the full image.
    func cachedImage(for url: URL, target: RemoteArtworkTarget) -> CGImage? {
        guard let box = memory.object(forKey: url as NSURL) else { return nil }
        return box.isFullSize || target.isCovered(by: box.image) ? box.image : nil
    }

    /// Whatever copy is kept, however small.
    func anyImage(for url: URL) -> CGImage? {
        memory.object(forKey: url as NSURL)?.image
    }

    func image(for url: URL, target: RemoteArtworkTarget) async -> CGImage? {
        if let cached = cachedImage(for: url, target: target) { return cached }
        let key = InFlightKey(url: url, target: target)
        if let running = inFlight[key] { return await running.value?.image }
        // Detached, so the download outlives the card that asked for it.
        let task = Task.detached(priority: .utility) {
            await RemoteArtworkFetcher.image(at: url, target: target)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        guard let result else { return nil }
        // Keep the largest copy decoded so far.
        if let current = memory.object(forKey: url as NSURL),
           current.image.width * current.image.height > result.image.width * result.image.height {
            return current.image
        }
        memory.setObject(
            CGImageBox(result.image, isFullSize: result.isFullSize),
            forKey: url as NSURL,
            cost: result.image.bytesPerRow * result.image.height
        )
        return result.image
    }

    private nonisolated struct InFlightKey: Hashable {
        let url: URL
        let target: RemoteArtworkTarget
    }
}

private final class CGImageBox {
    let image: CGImage
    /// The source was no bigger than asked for, so no sharper copy exists.
    let isFullSize: Bool
    init(_ image: CGImage, isFullSize: Bool) {
        self.image = image
        self.isFullSize = isFullSize
    }
}

/// A decoded image handed from the download back to the main actor; it is
/// never changed after decoding.
nonisolated struct RemoteArtworkImageData: @unchecked Sendable {
    let image: CGImage
    let isFullSize: Bool
}

nonisolated enum RemoteArtworkFetcher {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = .shared
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        // Add-ons that draw posters on request can take a while per image.
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 90
        configuration.httpMaximumConnectionsPerHost = 6
        // Posters need no cookies or saved logins, and only modern TLS.
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        return URLSession(configuration: configuration)
    }()

    private static let gate = RemoteArtworkGate(limit: 8)

    /// Up to three tries, waiting longer after each failure or rate limit.
    static func image(at url: URL, target: RemoteArtworkTarget) async -> RemoteArtworkImageData? {
        let requestURL = decodable(secured(url))
        for attempt in 0 ..< 3 {
            if attempt > 0 {
                try? await Task.sleep(for: .seconds(Double(attempt * attempt) * 1.5))
            }
            await gate.acquire()
            let result = try? await session.data(from: requestURL)
            await gate.release()
            guard let (data, response) = result else { continue }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            if status == 404 || status == 410 { return nil }
            guard (200 ..< 300).contains(status), let decoded = decoded(data, target: target) else { continue }
            return decoded
        }
        return nil
    }

    /// Plain http:// artwork is blocked by App Transport Security outside the
    /// local network; image hosts answer the same address over https.
    private static func secured(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http",
              let host = url.host?.lowercased(),
              !host.hasSuffix(".local"), host != "localhost",
              !host.hasPrefix("192.168."), !host.hasPrefix("10."), !host.hasPrefix("127."),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        components.scheme = "https"
        return components.url ?? url
    }

    /// TMDB keeps some logos as SVG, which ImageIO can't decode, so those
    /// title logos never appeared. TMDB serves the same logo as PNG when the
    /// extension is swapped.
    private static func decodable(_ url: URL) -> URL {
        guard url.host?.lowercased() == "image.tmdb.org",
              url.pathExtension.lowercased() == "svg" else { return url }
        return url.deletingPathExtension().appendingPathExtension("png")
    }

    /// Decoded at the size it is drawn, so a large poster doesn't hold
    /// pixels the screen never shows. Never scaled up past the source.
    private static func decoded(_ data: Data, target: RemoteArtworkTarget) -> RemoteArtworkImageData? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let sourceWidth = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let sourceHeight = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let sourceSize = max(sourceWidth, sourceHeight)
        let maxPixelSize = target.longestSide(sourceWidth: sourceWidth, sourceHeight: sourceHeight)
        let isFullSize = sourceSize > 0 && sourceSize <= maxPixelSize
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: isFullSize ? sourceSize : maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return RemoteArtworkImageData(image: image, isFullSize: isFullSize)
    }
}

/// Caps how many artwork downloads run at once, so a Home full of rows
/// doesn't fire hundreds of requests at one add-on.
private actor RemoteArtworkGate {
    private let limit: Int
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        if waiting.isEmpty {
            running -= 1
        } else {
            waiting.removeFirst().resume()
        }
    }
}
