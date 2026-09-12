#if os(macOS)
import AppKit
import Foundation

nonisolated protocol PlaybackStoryboardLoading: Sendable {
    func hlsStoryboard(for source: PlaybackSource) async throws -> PlaybackStoryboardDescriptor?
    func image(
        at timestamp: Double,
        descriptor: PlaybackStoryboardDescriptor,
        source: PlaybackSource
    ) async throws -> PlaybackTimelinePreviewImage
}

nonisolated protocol PlaybackLocalFrameGenerating: Sendable {
    func image(at timestamp: Double, source: PlaybackSource) async throws -> PlaybackTimelinePreviewImage
    func stop() async
}

nonisolated struct PlaybackTimelinePreviewFrame: @unchecked Sendable {
    let sourceID: String
    let timestamp: Double
    let image: NSImage
    let byteCount: Int
}

nonisolated struct PlaybackTimelinePreviewCacheKey: Hashable, Sendable {
    enum Storage: Hashable, Sendable {
        case storyboard
        case local
    }

    let sourceID: String
    let timestampBucket: Int
    let storage: Storage

    init(
        sourceID: String,
        timestampBucket: Int,
        storage: Storage = .local
    ) {
        self.sourceID = sourceID
        self.timestampBucket = timestampBucket
        self.storage = storage
    }
}

nonisolated struct DefaultPlaybackStoryboardLoader: PlaybackStoryboardLoading {
    private static let playlistContentTypes: Set<String> = [
        "application/vnd.apple.mpegurl",
        "application/x-mpegurl",
        "audio/mpegurl",
    ]

    private let transport: any HTTPTransporting

    init(transport: any HTTPTransporting = HTTPTransport()) {
        self.transport = transport
    }

    func hlsStoryboard(for source: PlaybackSource) async throws -> PlaybackStoryboardDescriptor? {
        guard source.url.pathExtension.caseInsensitiveCompare("m3u8") == .orderedSame,
              source.url.scheme?.lowercased() == "https",
              let allowedOrigin = NormalizedOrigin(url: source.url) else {
            return nil
        }

        let masterData = try await playlistData(
            at: source.url,
            allowedOrigin: allowedOrigin,
            requestHeaders: source.requestHeaders
        )
        try Task.checkCancellation()
        let imagePlaylistURL: URL
        do {
            imagePlaylistURL = try HLSImagePlaylistParser.imagePlaylistURL(
                data: masterData,
                baseURL: source.url
            )
        } catch HLSImagePlaylistError.missingImagePlaylist {
            return nil
        }
        let imagePlaylistData = try await playlistData(
            at: imagePlaylistURL,
            allowedOrigin: allowedOrigin,
            requestHeaders: source.requestHeaders
        )
        try Task.checkCancellation()
        return try HLSImagePlaylistParser.storyboard(
            data: imagePlaylistData,
            playlistURL: imagePlaylistURL,
            allowedOriginURL: source.url
        )
    }

    func image(
        at timestamp: Double,
        descriptor: PlaybackStoryboardDescriptor,
        source: PlaybackSource
    ) async throws -> PlaybackTimelinePreviewImage {
        try await StoryboardFrameLoader.image(
            for: timestamp,
            descriptor: descriptor,
            transport: transport,
            requestHeaders: source.requestHeaders
        )
    }

    private func playlistData(
        at url: URL,
        allowedOrigin: NormalizedOrigin,
        requestHeaders: [String: String]
    ) async throws -> Data {
        try await transport.data(
            for: HTTPRequestPolicy(
                url: url,
                allowedOrigin: allowedOrigin,
                timeout: 8,
                maximumResponseBytes: HLSImagePlaylistParser.maximumManifestBytes,
                acceptedContentTypes: Self.playlistContentTypes,
                requestHeaders: requestHeaders
            )
        )
    }
}

actor MPVLocalFrameGenerator: PlaybackLocalFrameGenerating {
    private var generator: OMMpvThumbnailGenerator?
    private var sourceID: String?

    func image(at timestamp: Double, source: PlaybackSource) async throws -> PlaybackTimelinePreviewImage {
        try Task.checkCancellation()
        if sourceID != source.id {
            generator?.stop()
            generator = OMMpvThumbnailGenerator(
                url: source.url,
                requestHeaders: source.requestHeaders
            )
            sourceID = source.id
        }
        guard let generator else {
            throw PlaybackTimelinePreviewServiceError.unavailable
        }

        let image = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                generator.requestFrame(
                    at: timestamp,
                    maximumSize: NSSize(width: 320, height: 180)
                ) { image, error in
                    if let image {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(
                            throwing: error ?? PlaybackTimelinePreviewServiceError.unavailable
                        )
                    }
                }
            }
        } onCancel: {
            generator.cancelPendingRequest()
        }
        try Task.checkCancellation()
        return PlaybackTimelinePreviewImage(
            image: image,
            byteCount: 320 * 180 * 4
        )
    }

    func stop() async {
        generator?.stop()
        generator = nil
        sourceID = nil
    }
}

private nonisolated enum PlaybackTimelinePreviewServiceError: Error {
    case unavailable
}

actor PlaybackTimelinePreviewService {
    private struct GeneratedFrame: @unchecked Sendable {
        let frame: PlaybackTimelinePreviewFrame
        let cacheKey: PlaybackTimelinePreviewCacheKey
    }

    private struct GenerationOutcome: @unchecked Sendable {
        let generatedFrame: GeneratedFrame?
        let resolvedHLSStoryboard: PlaybackStoryboardDescriptor?
        let didResolveHLSStoryboard: Bool
    }

    private let source: PlaybackSource
    private let storyboardLoader: any PlaybackStoryboardLoading
    private let localGenerator: any PlaybackLocalFrameGenerating
    private var cache: PlaybackTimelinePreviewCache<PlaybackTimelinePreviewCacheKey, PlaybackTimelinePreviewFrame>
    private var inFlight: Task<GenerationOutcome?, Never>?
    private var requestGeneration: UInt64 = 0
    private var didResolveHLSStoryboard = false
    private var resolvedHLSStoryboard: PlaybackStoryboardDescriptor?
    private var stopped = false

    init(
        source: PlaybackSource,
        configuration: PlaybackTimelinePreviewConfiguration,
        storyboardLoader: any PlaybackStoryboardLoading = DefaultPlaybackStoryboardLoader(),
        localGenerator: any PlaybackLocalFrameGenerating = MPVLocalFrameGenerator()
    ) {
        self.source = source
        self.storyboardLoader = storyboardLoader
        self.localGenerator = localGenerator
        cache = .init(
            maximumCount: configuration.maximumFrameCount,
            maximumBytes: configuration.maximumBytes
        )
    }

    func frame(at timestamp: Double) async -> PlaybackTimelinePreviewFrame? {
        guard !stopped, timestamp.isFinite, timestamp >= 0 else { return nil }

        requestGeneration &+= 1
        let generation = requestGeneration
        inFlight?.cancel()
        inFlight = nil

        let explicitStoryboard = Self.explicitStoryboard(for: source)
        let cacheKey = Self.storyboardCacheKey(
            sourceID: source.id,
            timestamp: timestamp,
            descriptor: explicitStoryboard ?? resolvedHLSStoryboard
        ) ?? Self.localCacheKey(sourceID: source.id, timestamp: timestamp)
        if let cached = cache.value(for: cacheKey) {
            return cached
        }

        let hlsWasResolved = didResolveHLSStoryboard
        let knownHLSStoryboard = resolvedHLSStoryboard
        let task = Task<GenerationOutcome?, Never> { [source, storyboardLoader, localGenerator] in
            if let explicitStoryboard,
               let loaded = await Self.storyboardImage(
                   at: timestamp,
                   descriptor: explicitStoryboard,
                   source: source,
                   loader: storyboardLoader
               ) {
                return Self.generationOutcome(
                    source: source,
                    timestamp: timestamp,
                    loaded: loaded,
                    cacheKey: Self.storyboardCacheKey(
                        sourceID: source.id,
                        timestamp: timestamp,
                        descriptor: explicitStoryboard
                    ) ?? Self.localCacheKey(sourceID: source.id, timestamp: timestamp),
                    resolvedHLSStoryboard: knownHLSStoryboard,
                    didResolveHLSStoryboard: hlsWasResolved
                )
            }
            guard !Task.isCancelled else { return nil }

            var hlsStoryboard = knownHLSStoryboard
            var didResolveHLS = hlsWasResolved
            if !didResolveHLS {
                do {
                    hlsStoryboard = try await storyboardLoader.hlsStoryboard(for: source)
                    didResolveHLS = true
                } catch {
                    guard !Task.isCancelled else { return nil }
                    hlsStoryboard = nil
                }
            }
            guard !Task.isCancelled else { return nil }
            if let hlsStoryboard,
               let loaded = await Self.storyboardImage(
                   at: timestamp,
                   descriptor: hlsStoryboard,
                   source: source,
                   loader: storyboardLoader
               ) {
                return Self.generationOutcome(
                    source: source,
                    timestamp: timestamp,
                    loaded: loaded,
                    cacheKey: Self.storyboardCacheKey(
                        sourceID: source.id,
                        timestamp: timestamp,
                        descriptor: hlsStoryboard
                    ) ?? Self.localCacheKey(sourceID: source.id, timestamp: timestamp),
                    resolvedHLSStoryboard: hlsStoryboard,
                    didResolveHLSStoryboard: didResolveHLS
                )
            }
            guard !Task.isCancelled else { return nil }

            do {
                let loaded = try await localGenerator.image(at: timestamp, source: source)
                guard !Task.isCancelled else { return nil }
                return Self.generationOutcome(
                    source: source,
                    timestamp: timestamp,
                    loaded: loaded,
                    cacheKey: Self.localCacheKey(sourceID: source.id, timestamp: timestamp),
                    resolvedHLSStoryboard: hlsStoryboard,
                    didResolveHLSStoryboard: didResolveHLS
                )
            } catch {
                guard !Task.isCancelled else { return nil }
                return GenerationOutcome(
                    generatedFrame: nil,
                    resolvedHLSStoryboard: hlsStoryboard,
                    didResolveHLSStoryboard: didResolveHLS
                )
            }
        }
        inFlight = task

        guard let outcome = await task.value,
              !Task.isCancelled,
              !stopped,
              generation == requestGeneration else {
            return nil
        }
        inFlight = nil
        if outcome.didResolveHLSStoryboard {
            didResolveHLSStoryboard = true
            resolvedHLSStoryboard = outcome.resolvedHLSStoryboard
        }
        guard let generated = outcome.generatedFrame else { return nil }
        cache.insert(
            generated.frame,
            for: generated.cacheKey,
            byteCount: generated.frame.byteCount
        )
        return generated.frame
    }

    func stop() async {
        guard !stopped else { return }
        stopped = true
        requestGeneration &+= 1
        inFlight?.cancel()
        inFlight = nil
        cache.removeAll()
        didResolveHLSStoryboard = false
        resolvedHLSStoryboard = nil
        await localGenerator.stop()
    }

    private nonisolated static func explicitStoryboard(
        for source: PlaybackSource
    ) -> PlaybackStoryboardDescriptor? {
        guard case let .storyboard(storyboard)? = source.timelinePreviewDescriptor else {
            return nil
        }
        return storyboard
    }

    private nonisolated static func storyboardCacheKey(
        sourceID: String,
        timestamp: Double,
        descriptor: PlaybackStoryboardDescriptor?
    ) -> PlaybackTimelinePreviewCacheKey? {
        guard let tile = descriptor?.tiles.first(where: { $0.contains(timestamp) })
            ?? descriptor?.tiles.last.flatMap({ timestamp == $0.endTime ? $0 : nil }) else {
            return nil
        }
        return PlaybackTimelinePreviewCacheKey(
            sourceID: sourceID,
            timestampBucket: Int((tile.startTime * 1_000).rounded(.down)),
            storage: .storyboard
        )
    }

    private nonisolated static func localCacheKey(
        sourceID: String,
        timestamp: Double
    ) -> PlaybackTimelinePreviewCacheKey {
        PlaybackTimelinePreviewCacheKey(
            sourceID: sourceID,
            timestampBucket: Int(timestamp.rounded(.down))
        )
    }

    private nonisolated static func storyboardImage(
        at timestamp: Double,
        descriptor: PlaybackStoryboardDescriptor,
        source: PlaybackSource,
        loader: any PlaybackStoryboardLoading
    ) async -> PlaybackTimelinePreviewImage? {
        do {
            let image = try await loader.image(
                at: timestamp,
                descriptor: descriptor,
                source: source
            )
            return Task.isCancelled ? nil : image
        } catch {
            return nil
        }
    }

    private nonisolated static func generationOutcome(
        source: PlaybackSource,
        timestamp: Double,
        loaded: PlaybackTimelinePreviewImage,
        cacheKey: PlaybackTimelinePreviewCacheKey,
        resolvedHLSStoryboard: PlaybackStoryboardDescriptor?,
        didResolveHLSStoryboard: Bool
    ) -> GenerationOutcome {
        GenerationOutcome(
            generatedFrame: GeneratedFrame(
                frame: PlaybackTimelinePreviewFrame(
                    sourceID: source.id,
                    timestamp: timestamp,
                    image: loaded.image,
                    byteCount: loaded.byteCount
                ),
                cacheKey: cacheKey
            ),
            resolvedHLSStoryboard: resolvedHLSStoryboard,
            didResolveHLSStoryboard: didResolveHLSStoryboard
        )
    }
}
#endif
