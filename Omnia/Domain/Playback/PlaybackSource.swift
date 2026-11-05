//
//  PlaybackSource.swift
//  Omnia
//

import Foundation

/// A source returned by an enabled, declarative add-on.
///
/// Omnia keeps this separate from `PlaybackSource`: an add-on may identify a
/// stream with a direct URL, a bounded local torrent descriptor, or an
/// external handoff URL. Only validated playback input reaches libmpv.
struct AddonStreamCandidate: Identifiable, Hashable, Sendable {
    enum NativePlaybackCompatibility: Hashable, Sendable {
        /// HLS and common containers are expected to play directly.
        case likelySupported
        /// Some add-ons expose an opaque HTTPS endpoint. libmpv will inspect
        /// the actual response before deciding whether it is playable.
        case unknown
        /// Retained for malformed or non-web-ready source declarations.
        case unsupportedFormat
    }

    enum Delivery: Hashable, Sendable {
        case nativeHTTPS(URL)
        case localTorrent(LocalTorrentPlaybackDescriptor)
        case externalHandoff(URL)
        case unsupported
    }

    let id: String
    let addonID: String
    let addonName: String
    let streamIdentifier: String
    let displayName: String
    let displayDescription: String?
    let delivery: Delivery
    let filename: String?
    let videoSize: Int64?
    let bingeGroup: String?
    let hasPeerDiscoveryHints: Bool
    let requestHeaders: [String: String]

    init(
        stream: AddonStream,
        addon: InstalledAddon,
        streamIdentifier: String,
        position: Int
    ) {
        let directURL = URL.validHTTPSURL(from: stream.url)
        let externalURL = URL.validWebURL(from: stream.externalURL)
            ?? URL.youtubeWatchURL(for: stream.ytId)
        let torrentHash = stream.infoHash?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? stream.sources?.compactMap(Self.infoHash(in:)).first

        id = "\(addon.id)::\(streamIdentifier)::\(position)::\(stream.url ?? stream.infoHash ?? stream.externalURL ?? stream.ytId ?? "unknown")"
        addonID = addon.id
        addonName = addon.displayName
        self.streamIdentifier = streamIdentifier
        displayName = stream.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? addon.displayName
        displayDescription = (stream.description ?? stream.title)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        filename = stream.behaviorHints?.filename?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        videoSize = stream.behaviorHints?.videoSize
        bingeGroup = stream.behaviorHints?.bingeGroup?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        hasPeerDiscoveryHints = !(stream.sources ?? []).isEmpty
        requestHeaders = stream.behaviorHints?.nativeRequestHeaders ?? [:]

        // libmpv can inspect a direct HTTPS response itself. Add-on web-player
        // hints and filename extensions do not determine native playability.
        if let directURL {
            delivery = .nativeHTTPS(directURL)
        } else if let torrentHash,
                  let descriptor = try? LocalTorrentPlaybackDescriptor(
                    infoHash: torrentHash,
                    fileIndex: stream.fileIdx,
                    displayName: filename ?? displayName,
                    expectedByteCount: videoSize,
                    sources: stream.sources ?? []
                  ) {
            delivery = .localTorrent(descriptor)
        } else if let externalURL {
            delivery = .externalHandoff(externalURL)
        } else {
            delivery = .unsupported
        }
    }

    var nativePlaybackSource: PlaybackSource? {
        guard case let .nativeHTTPS(url) = delivery else { return nil }
        return PlaybackSource(candidate: self, url: url)
    }

    var nativePlaybackCompatibility: NativePlaybackCompatibility {
        guard case .nativeHTTPS = delivery else { return .unsupportedFormat }

        let pathExtension = urlPathExtension

        // A familiar stream declaration is a useful positive signal. Other
        // HTTPS media remains available: libmpv inspects the response and
        // supports containers such as Matroska that AVFoundation rejects.
        if ["m3u8", "mp4", "m4v", "mov", "mkv", "webm"].contains(pathExtension) {
            return .likelySupported
        }
        return .unknown
    }

    var hasDiscImageHint: Bool {
        guard case let .nativeHTTPS(url) = delivery else { return false }
        return url.pathExtension.caseInsensitiveCompare("iso") == .orderedSame
            || filename.map {
                URL(fileURLWithPath: $0).pathExtension
                    .caseInsensitiveCompare("iso") == .orderedSame
            } == true
    }

    var hasExtensionlessHTTPSURL: Bool {
        guard case let .nativeHTTPS(url) = delivery else { return false }
        return url.pathExtension.isEmpty
    }

    private var urlPathExtension: String {
        guard case let .nativeHTTPS(url) = delivery else { return "" }
        return url.pathExtension.lowercased()
    }

    var sourceTypeLabel: String {
        switch delivery {
        case .nativeHTTPS:
            switch nativePlaybackCompatibility {
            case .likelySupported: "Direct HTTPS stream"
            case .unknown: "Direct HTTPS — libmpv will inspect"
            case .unsupportedFormat: "Direct HTTPS — libmpv will inspect"
            }
        case .localTorrent: "Local peer-to-peer source"
        case .externalHandoff: "Opens externally"
        case .unsupported: "Unsupported source"
        }
    }

    var technicalSummary: String? {
        var values: [String] = []
        if let filename { values.append(filename) }
        if let videoSize { values.append(ByteCountFormatter.string(fromByteCount: videoSize, countStyle: .file)) }
        if case let .localTorrent(descriptor) = delivery, let fileIndex = descriptor.fileIndex {
            values.append("File \(fileIndex + 1)")
        }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    var deduplicationKey: String {
        switch delivery {
        case let .nativeHTTPS(url): "url:\(url.absoluteString)"
        case let .localTorrent(descriptor): "hash:\(descriptor.cacheKey)"
        case let .externalHandoff(url): "handoff:\(url.absoluteString)"
        case .unsupported: "unsupported:\(id)"
        }
    }

    private nonisolated static func infoHash(in source: String) -> String? {
        let expression = #"(?i)urn:btih:([a-z0-9]+)"#
        guard let range = source.range(of: expression, options: .regularExpression) else { return nil }
        let match = String(source[range])
        guard let value = match.split(separator: ":").last, !value.isEmpty else { return nil }
        return String(value)
    }
}

/// A validated direct HTTPS stream or completed local cache file. The player
/// never receives a torrent hash, magnet URI, tracker, or webpage handoff.
struct PlaybackSource: Identifiable, Hashable, Sendable {
    let id: String
    let addonID: String
    let addonName: String
    let title: String
    let detail: String?
    let streamIdentifier: String
    let url: URL
    let requestHeaders: [String: String]
    let timelinePreviewDescriptor: PlaybackTimelinePreviewDescriptor?

    init(
        candidate: AddonStreamCandidate,
        url: URL,
        timelinePreviewDescriptor: PlaybackTimelinePreviewDescriptor? = nil
    ) {
        id = candidate.id
        addonID = candidate.addonID
        addonName = candidate.addonName
        title = candidate.displayName
        detail = candidate.displayDescription
        streamIdentifier = candidate.streamIdentifier
        self.url = url
        requestHeaders = candidate.requestHeaders
        self.timelinePreviewDescriptor = timelinePreviewDescriptor
    }

    init(
        localCandidate candidate: AddonStreamCandidate,
        fileURL: URL,
        timelinePreviewDescriptor: PlaybackTimelinePreviewDescriptor? = nil
    ) {
        id = candidate.id
        addonID = candidate.addonID
        addonName = candidate.addonName
        title = candidate.displayName
        detail = candidate.displayDescription
        streamIdentifier = candidate.streamIdentifier
        url = fileURL
        requestHeaders = [:]
        self.timelinePreviewDescriptor = timelinePreviewDescriptor
    }

    /// Titles played from Live TV carry this id prefix, so the player skips
    /// what only applies to movies and episodes, such as Continue Watching.
    nonisolated static let liveTVIDPrefix = "livetv:"

    /// A Live TV channel's stream.
    init(
        liveChannelID: String,
        title: String,
        detail: String?,
        sourceName: String,
        url: URL,
        requestHeaders: [String: String]
    ) {
        id = Self.liveTVIDPrefix + liveChannelID
        addonID = "omnia.livetv"
        addonName = sourceName
        self.title = title
        self.detail = detail
        streamIdentifier = liveChannelID
        self.url = url
        self.requestHeaders = requestHeaders
        timelinePreviewDescriptor = nil
    }
}

nonisolated struct AddonSourceResolution: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable {
        case loaded
        case empty
        case failed
    }

    enum Failure: Equatable, Sendable {
        case credentialRejected
        case endpointNotFound
        case rateLimited
        case serverUnavailable
        case requestTimedOut
        case connectionFailed
        case redirectRejected
        case unsupportedResponse
        case responseTooLarge
        case invalidPayload
        case secureConnectionRequired
        case cancelled
        /// A plugin failed; its message says why.
        case plugin(String)

        init(error: Error) {
            if let transportError = error as? HTTPTransportError {
                self = switch transportError {
                case .httpsRequired, .originRejected:
                    .secureConnectionRequired
                case .redirectRejected:
                    .redirectRejected
                case .invalidResponse:
                    .invalidPayload
                case let .unsuccessfulStatus(status) where [401, 403].contains(status):
                    .credentialRejected
                case .unsuccessfulStatus(404):
                    .endpointNotFound
                case .unsuccessfulStatus(429):
                    .rateLimited
                case let .unsuccessfulStatus(status) where status >= 500:
                    .serverUnavailable
                case .unsuccessfulStatus:
                    .unsupportedResponse
                case .unsupportedContentType:
                    .unsupportedResponse
                case .responseTooLarge:
                    .responseTooLarge
                case .timedOut:
                    .requestTimedOut
                case .cancelled:
                    .cancelled
                case .transportFailure:
                    .connectionFailed
                }
                return
            }

            if let clientError = error as? StremioAddonClient.AddonClientError {
                self = switch clientError {
                case .requiresHTTPS:
                    .secureConnectionRequired
                case .invalidResponse, .invalidManifest, .notAManifest:
                    .invalidPayload
                }
                return
            }

            self = .connectionFailed
        }

        var description: String {
            switch self {
            case .credentialRejected:
                "The add-on rejected its configured credentials."
            case .endpointNotFound:
                "The add-on does not provide this stream endpoint."
            case .rateLimited:
                "The add-on is temporarily rate limiting requests."
            case .serverUnavailable:
                "The add-on server is temporarily unavailable."
            case .requestTimedOut:
                "The add-on took too long to respond."
            case .connectionFailed:
                "Omnia could not reach the add-on server."
            case .redirectRejected:
                "The add-on redirected to an untrusted server."
            case .unsupportedResponse:
                "The add-on returned an unsupported response."
            case .responseTooLarge:
                "The add-on response exceeded Omnia’s safety limit."
            case .invalidPayload:
                "The add-on returned stream data Omnia could not read."
            case .secureConnectionRequired:
                "The add-on request did not meet Omnia’s secure connection policy."
            case .cancelled:
                "The add-on request was cancelled."
            case let .plugin(message):
                message
            }
        }
    }

    let addonID: String
    let addonName: String
    let candidates: [AddonStreamCandidate]
    let state: State
    let failure: Failure?

    init(
        addonID: String,
        addonName: String,
        candidates: [AddonStreamCandidate],
        state: State,
        failure: Failure? = nil
    ) {
        self.addonID = addonID
        self.addonName = addonName
        self.candidates = candidates
        self.state = state
        self.failure = failure
    }

    var id: String { addonID }

    var statusDescription: String {
        if let failure { return failure.description }
        return state == .empty
            ? "The add-on returned no sources for these identifiers."
            : "Sources loaded."
    }
}

struct PlaybackSourceResolution: Sendable {
    let addonResults: [AddonSourceResolution]
    let attemptedIdentifiers: [String]

    var candidates: [AddonStreamCandidate] {
        addonResults.flatMap(\.candidates)
    }

    var enabledAddonCount: Int { addonResults.count }

    var failedAddonResults: [AddonSourceResolution] {
        addonResults.filter { $0.state == .failed }
    }

    func replacingAddonResult(_ replacement: AddonSourceResolution) -> Self {
        var results = addonResults
        if let index = results.firstIndex(where: { $0.addonID == replacement.addonID }) {
            results[index] = replacement
        } else {
            results.append(replacement)
        }
        return Self(addonResults: results, attemptedIdentifiers: attemptedIdentifiers)
    }

    var emptyStateDescription: String {
        guard enabledAddonCount > 0 else {
            return "Enable a trusted add-on that supplies streams, then try again."
        }

        if !failedAddonResults.isEmpty {
            return "Omnia could not read the response from the enabled add-on. Check the add-on connection and try again."
        }

        return "The enabled add-on returned no sources for this title's available identifiers."
    }
}

extension LocalTorrentPlaybackDescriptor {
    init(candidate: AddonStreamCandidate) throws {
        guard case let .localTorrent(descriptor) = candidate.delivery else {
            throw DescriptorError.invalidInfoHash
        }
        self = descriptor
    }
}

enum PlaybackSourceResolver {
    static func resolve(
        addon: InstalledAddon,
        mediaTypes: [String],
        identifiers: [String]
    ) async -> AddonSourceResolution {
        await resolve(
            addon: addon,
            mediaTypes: mediaTypes,
            identifiers: identifiers,
            timeout: .seconds20,
            transport: HTTPTransport()
        )
    }

    static func resolve(
        addon: InstalledAddon,
        mediaTypes: [String],
        identifiers: [String],
        timeout: AddonTimeout,
        transport: any HTTPTransporting
    ) async -> AddonSourceResolution {
        do {
            let candidates = try await StremioAddonClient.fetchStreamCandidates(
                from: addon,
                mediaTypes: mediaTypes,
                identifiers: identifiers,
                timeout: timeout,
                transport: transport
            )
            return AddonSourceResolution(
                addonID: addon.id,
                addonName: addon.displayName,
                candidates: candidates,
                state: candidates.isEmpty ? .empty : .loaded
            )
        } catch {
            return AddonSourceResolution(
                addonID: addon.id,
                addonName: addon.displayName,
                candidates: [],
                state: .failed,
                failure: .init(error: error)
            )
        }
    }

    /// `onUpdate` receives the sources found so far each time an add-on or
    /// the plugins finish, so the list can fill in before the slowest one
    /// answers. The returned value is the complete result.
    static func resolve(
        for item: MediaItem,
        episode: MediaEpisode? = nil,
        addons: [InstalledAddon],
        plugins: PluginStreamPlan = .empty,
        servers: MediaServerStreamPlan = .empty,
        timeout: AddonTimeout = .seconds20,
        onUpdate: ((PlaybackSourceResolution, _ pendingCount: Int) -> Void)? = nil
    ) async -> PlaybackSourceResolution {
        let identifiers = item.streamIdentifierCandidates(for: episode)
        let mediaTypes = item.streamMediaTypes
        let enabledAddons = addons.filter { $0.isEnabled && $0.manifest.supportsStreams }
        let hasPlugins = !plugins.entries.isEmpty

        return await withTaskGroup(
            of: (Int, [AddonSourceResolution]).self,
            returning: PlaybackSourceResolution.self
        ) { group in
            for (position, addon) in enabledAddons.enumerated() {
                group.addTask {
                    guard !identifiers.isEmpty else {
                        return (position, [AddonSourceResolution(
                            addonID: addon.id,
                            addonName: addon.displayName,
                            candidates: [],
                            state: .empty
                        )])
                    }
                    let result = await resolve(
                        addon: addon,
                        mediaTypes: mediaTypes,
                        identifiers: identifiers,
                        timeout: timeout,
                        transport: HTTPTransport()
                    )
                    return (position, [result])
                }
            }
            // Plugins search by TMDB ID, so they run alongside the add-ons and
            // their sources are listed after them.
            // Each plugin is listed as soon as it answers; the TMDB ID they
            // search by is looked up once.
            let tmdbLookup: Task<String?, Never>? = hasPlugins
                ? Task { await PluginStreamResolver.tmdbID(for: item, apiKey: plugins.tmdbAPIKey) }
                : nil
            for (offset, entry) in plugins.entries.enumerated() {
                group.addTask {
                    let tmdbID = await tmdbLookup?.value
                    let result = await PluginStreamResolver.resolve(
                        entry,
                        tmdbID: tmdbID,
                        plan: plugins,
                        item: item,
                        episode: episode
                    )
                    return (enabledAddons.count + offset, [result])
                }
            }

            // Media servers (Jellyfin, Emby) are listed last.
            let serverOffset = enabledAddons.count + plugins.entries.count
            for (offset, entry) in servers.entries.enumerated() {
                group.addTask {
                    let result = await MediaServerStreamResolver.resolve(entry, item: item, episode: episode)
                    return (serverOffset + offset, [result])
                }
            }

            var pending = serverOffset + servers.entries.count
            var batches: [(Int, [AddonSourceResolution])] = []
            func current() -> PlaybackSourceResolution {
                PlaybackSourceResolution(
                    addonResults: batches.sorted { $0.0 < $1.0 }.flatMap(\.1),
                    attemptedIdentifiers: identifiers
                )
            }
            for await batch in group {
                batches.append(batch)
                pending -= 1
                if pending > 0 { onUpdate?(current(), pending) }
            }
            return current()
        }
    }
}

private extension URL {
    static func validHTTPSURL(from text: String?) -> URL? {
        guard let text, let url = URL(string: text), url.scheme?.lowercased() == "https", url.host != nil else {
            return nil
        }
        return url
    }

    static func validWebURL(from text: String?) -> URL? {
        guard let text, let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            return nil
        }
        return url
    }

    static func youtubeWatchURL(for identifier: String?) -> URL? {
        guard let identifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty else {
            return nil
        }
        return URL(string: "https://www.youtube.com/watch?v=\(identifier)")
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

#if DEBUG
private extension AddonStreamCandidate {
    init(previewName: String, previewDetail: String) {
        id = "omnia.debug.apple-hls-sample"
        addonID = "omnia.debug"
        addonName = "Omnia Development"
        streamIdentifier = "debug-sample"
        displayName = previewName
        displayDescription = previewDetail
        delivery = .unsupported
        filename = nil
        videoSize = nil
        bingeGroup = nil
        hasPeerDiscoveryHints = false
        requestHeaders = [:]
    }
}
#endif
