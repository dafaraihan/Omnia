//
//  StremioAddonClient.swift
//  Omnia
//

import Foundation

enum StremioAddonClient {
    static func fetchManifest(from url: URL) async throws -> StremioAddonManifest {
        try await fetchManifest(
            from: url,
            timeout: .seconds20,
            transport: HTTPTransport()
        )
    }

    static func fetchManifest(
        from url: URL,
        timeout: AddonTimeout,
        transport: any HTTPTransporting
    ) async throws -> StremioAddonManifest {
        guard url.scheme?.lowercased() == "https" else { throw AddonClientError.requiresHTTPS }
        guard let origin = NormalizedOrigin(url: url) else { throw AddonClientError.requiresHTTPS }

        let data: Data
        do {
            // Catalog add-ons such as Xperience and AIOMetadata generate large
            // manifests (hundreds of catalogs with long genre lists) on demand,
            // so they get more time and room than the user's stream timeout.
            data = try await transport.data(for: Self.addonPolicy(HTTPRequestPolicy(
                url: url,
                allowedOrigin: origin,
                timeout: TimeInterval(max(timeout.rawValue, 60)),
                maximumResponseBytes: 10 * 1_048_576,
                acceptedContentTypes: Self.jsonContentTypes,
                requestHeaders: ["Accept": "application/json"]
            )))
        } catch let error as AddonClientError {
            throw error
        } catch let error as HTTPTransportError {
            throw error
        } catch {
            throw AddonClientError.invalidResponse
        }

        let manifest: StremioAddonManifest
        do {
            manifest = try await decodeJSON(StremioAddonManifest.self, from: data)
        } catch {
            throw AddonClientError.notAManifest
        }
        guard manifest.hasValidBounds else { throw AddonClientError.invalidManifest }
        return manifest
    }

    /// Fetches the documented stream response without discarding non-direct
    /// candidates. Playback capability is decided later by the platform-safe
    /// resolver boundary.
    static func fetchStreamCandidates(
        from addon: InstalledAddon,
        mediaTypes: [String],
        identifiers: [String]
    ) async throws -> [AddonStreamCandidate] {
        try await fetchStreamCandidates(
            from: addon,
            mediaTypes: mediaTypes,
            identifiers: identifiers,
            timeout: .seconds20,
            transport: HTTPTransport()
        )
    }

    static func fetchStreamCandidates(
        from addon: InstalledAddon,
        mediaTypes: [String],
        identifiers: [String],
        timeout: AddonTimeout,
        transport: any HTTPTransporting
    ) async throws -> [AddonStreamCandidate] {
        guard addon.isEnabled, addon.manifest.supportsStreams else { return [] }

        var candidates: [AddonStreamCandidate] = []
        var mostRecentError: Error?
        var receivedValidResponse = false

        for identifier in identifiers {
            try Task.checkCancellation()
            // Nuvio and Stremio ask an add-on once, with the first ID it
            // accepts. Later IDs are only a fallback for add-ons that found
            // nothing, so one slow add-on isn't asked again and again.
            if !candidates.isEmpty { break }
            for mediaType in mediaTypes where addon.manifest.supports(resource: "stream", type: mediaType, identifier: identifier) {
                try Task.checkCancellation()
                if !candidates.isEmpty { break }
                let endpoint = resourceURL(addon: addon, resource: "stream", type: mediaType, id: identifier)
                do {
                    guard let origin = NormalizedOrigin(url: endpoint) else { continue }
                    let data = try await transport.data(for: Self.addonPolicy(HTTPRequestPolicy(
                        url: endpoint,
                        allowedOrigin: origin,
                        timeout: TimeInterval(timeout.rawValue),
                        // Aggregator add-ons can legitimately return several
                        // hundred richly-described streams. Keep the response
                        // bounded, but allow the payload size observed from
                        // compatible Stremio clients and AIOStreams.
                        maximumResponseBytes: 8_388_608,
                        acceptedContentTypes: Self.jsonContentTypes,
                        requestHeaders: ["Accept": "application/json"]
                    )))
                    try Task.checkCancellation()
                    guard let result = try? await decodeJSON(AddonStreamResponse.self, from: data),
                          !result.streams.isEmpty || result.discardedEntryCount == 0 else {
                        mostRecentError = AddonClientError.invalidResponse
                        continue
                    }
                    receivedValidResponse = true
                    candidates += result.streams.enumerated().map { position, stream in
                        AddonStreamCandidate(
                            stream: stream,
                            addon: addon,
                            streamIdentifier: identifier,
                            position: position
                        )
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch HTTPTransportError.cancelled {
                    throw CancellationError()
                } catch {
                    try Task.checkCancellation()
                    // One unsupported or temporarily unavailable identifier
                    // must not suppress an add-on's valid later ID formats.
                    mostRecentError = error
                }
            }
        }

        try Task.checkCancellation()
        if receivedValidResponse {
            AddonDiagnostics.shared.recordSuccess(.stream, addon: addon)
        } else if let mostRecentError {
            AddonDiagnostics.shared.recordFailure(.stream, addon: addon, error: mostRecentError)
        }
        if candidates.isEmpty, !receivedValidResponse, let mostRecentError { throw mostRecentError }
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.deduplicationKey).inserted }
    }

    static func fetchCatalog(
        from addon: InstalledAddon,
        catalog: AddonCatalog,
        extra: [String: String] = [:],
        allowsMissingRequiredExtras: Bool = false
    ) async throws -> [AddonMetaPreview] {
        // Collection folders open catalogs that AIOMetadata and Xperience
        // keep off Home by marking `genre` required; Nuvio requests them
        // without it, and so does Omnia when `allowsMissingRequiredExtras`.
        // Everywhere else a missing required value takes its first option,
        // as in Stremio. Types and extras aren't checked against the
        // manifest: a listed catalog is enough, and Stremio sends them as is.
        guard addon.isEnabled else { return [] }
        var extra = extra.filter { !$0.value.isEmpty && !($0.key == "skip" && $0.value == "0") }
        if !allowsMissingRequiredExtras {
            // A search-only catalog with nothing to search for.
            guard let resolved = catalog.resolvingExtras(extra) else { return [] }
            extra = resolved
        }

        let endpoint = resourceURL(
            addon: addon,
            resource: "catalog",
            type: catalog.type,
            id: catalog.id,
            extra: extra
        )
        do {
            let response: AddonCatalogResponse = try await fetch(endpoint)
            AddonDiagnostics.shared.recordSuccess(.catalog, addon: addon, catalog: catalog)
            return response.metas
        } catch {
            AddonDiagnostics.shared.recordFailure(.catalog, addon: addon, catalog: catalog, error: error)
            throw error
        }
    }

    static func searchCatalogs(
        addons: [InstalledAddon],
        query: String
    ) async -> [AddonCatalogItem] {
        let enabledCatalogs = addons.flatMap { addon in
            addon.isEnabled ? addon.manifest.catalogs
                .filter(\.supportsSearch)
                .map { (addon, $0) } : []
        }

        return await withTaskGroup(of: [AddonCatalogItem].self, returning: [AddonCatalogItem].self) { group in
            for (addon, catalog) in enabledCatalogs {
                group.addTask {
                    guard let metas = try? await fetchCatalog(from: addon, catalog: catalog, extra: ["search": query]) else { return [] }
                    // Building titles is nonisolated, so it stays off the main actor.
                    return metas.compactMap { preview in
                        preview.mediaItem(addon: addon).map { .init(item: $0, addon: addon, catalog: catalog) }
                    }
                }
            }

            var values: [AddonCatalogItem] = []
            for await result in group { values.append(contentsOf: result) }
            return values
        }
    }

    static func fetchMeta(
        from addon: InstalledAddon,
        mediaType: String,
        identifiers: [String]
    ) async throws -> AddonMeta? {
        guard addon.isEnabled else { return nil }
        var lastError: Error?
        for identifier in identifiers {
            guard addon.manifest.supports(resource: "meta", type: mediaType, identifier: identifier) else { continue }
            let endpoint = resourceURL(addon: addon, resource: "meta", type: mediaType, id: identifier)
            do {
                // Details back the Home hero, which moves on after a few
                // seconds; a stalled add-on must not hold it for a minute.
                let response: AddonMetaResponse = try await fetch(endpoint, timeout: 15)
                AddonDiagnostics.shared.recordSuccess(.meta, addon: addon)
                return response.meta
            } catch {
                lastError = error
            }
        }
        // A 404 only means this add-on doesn't know the title.
        if let lastError, lastError as? HTTPTransportError != .unsuccessfulStatus(404) {
            AddonDiagnostics.shared.recordFailure(.meta, addon: addon, error: lastError)
        }
        return nil
    }

    static func fetchMetadata(
        for item: MediaItem,
        addons: [InstalledAddon]
    ) async -> [MediaItem] {
        let mediaType = item.kind == .movie ? "movie" : "series"
        let identifiers = item.streamIdentifierCandidates

        return await withTaskGroup(of: (Int, MediaItem?).self, returning: [MediaItem].self) { group in
            for (index, addon) in addons.enumerated() where addon.isEnabled && addon.manifest.supportsMeta {
                group.addTask {
                    let meta = (try? await fetchMeta(from: addon, mediaType: mediaType, identifiers: identifiers)) ?? nil
                    let item = meta?.mediaItem(addon: addon)
                    return (index, item)
                }
            }

            var ordered: [(Int, MediaItem)] = []
            for await indexAndItem in group {
                if let item = indexAndItem.1 { ordered.append((indexAndItem.0, item)) }
            }
            return ordered.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    static func fetchSubtitles(
        from addon: InstalledAddon,
        mediaType: String,
        videoID: String,
        videoHash: String? = nil,
        videoSize: Int64? = nil
    ) async throws -> [AddonSubtitle] {
        guard addon.isEnabled,
              addon.manifest.supports(resource: "subtitles", type: mediaType, identifier: videoID)
        else { return [] }

        // Stremio protocol: /subtitles/{type}/{videoID}/videoHash=…&videoSize=….json
        var extra: [String: String] = [:]
        if let videoHash { extra["videoHash"] = videoHash }
        if let videoSize { extra["videoSize"] = String(videoSize) }
        let endpoint = resourceURL(addon: addon, resource: "subtitles", type: mediaType, id: videoID, extra: extra)
        do {
            let response: AddonSubtitlesResponse = try await fetch(endpoint)
            AddonDiagnostics.shared.recordSuccess(.subtitles, addon: addon)
            return response.subtitles
        } catch {
            AddonDiagnostics.shared.recordFailure(.subtitles, addon: addon, error: error)
            throw error
        }
    }

    static func fetchAddonCatalog(
        from addon: InstalledAddon,
        catalog: AddonCatalog
    ) async throws -> [AddonCatalogAddon] {
        guard addon.isEnabled,
              addon.manifest.supportsAddonCatalogs,
              addon.manifest.addonCatalogs?.contains(catalog) == true
        else { return [] }
        let endpoint = resourceURL(addon: addon, resource: "addon_catalog", type: catalog.type, id: catalog.id)
        let response: AddonCatalogAddonsResponse = try await fetch(endpoint)
        return response.addons
    }

    private static func fetch<Response: Decodable & Sendable>(_ url: URL, timeout: TimeInterval = 60) async throws -> Response {
        guard let origin = NormalizedOrigin(url: url) else {
            throw AddonClientError.invalidResponse
        }
        let data: Data
        do {
            data = try await HTTPTransport().data(for: Self.addonPolicy(HTTPRequestPolicy(
                url: url,
                allowedOrigin: origin,
                timeout: timeout,
                maximumResponseBytes: 10 * 1_048_576,
                acceptedContentTypes: Self.jsonContentTypes,
                requestHeaders: ["Accept": "application/json"]
            )))
        } catch let error as HTTPTransportError {
            // Kept as is, so callers can tell a timeout or a 404 from bad JSON.
            throw error
        } catch {
            throw AddonClientError.invalidResponse
        }
        do {
            return try await decodeJSON(Response.self, from: data)
        } catch {
            throw AddonClientError.invalidResponse
        }
    }

    /// Add-on responses can be megabytes of JSON (a manifest with hundreds of
    /// catalogs, a catalog page, hundreds of streams). Decoding them on the
    /// main actor stalled scrolling and typing, so it runs on the cooperative
    /// pool instead. The response types are `nonisolated` for this reason.
    @concurrent
    nonisolated private static func decodeJSON<Value: Decodable & Sendable>(
        _ type: Value.Type,
        from data: Data
    ) async throws -> Value {
        try JSONDecoder().decode(type, from: data)
    }

    private static func resourceURL(
        addon: InstalledAddon,
        resource: String,
        type: String,
        id: String,
        extra: [String: String] = [:]
    ) -> URL {
        // Some add-ons keep their configuration in the manifest's query
        // string; it is sent again with every resource request, as Nuvio does.
        var components = URLComponents(url: addon.manifestURL, resolvingAgainstBaseURL: false)
        let query = components?.percentEncodedQuery
        components?.percentEncodedQuery = nil
        components?.fragment = nil
        let manifestWithoutQuery = components?.url ?? addon.manifestURL

        // Every segment is encoded like Stremio's `encodeURIComponent`, so
        // ids such as `kitsu:1` and genres such as `Action/Adventure` stay
        // one segment instead of splitting the path.
        var path = manifestWithoutQuery.deletingLastPathComponent().absoluteString
        if !path.hasSuffix("/") { path += "/" }
        path += [resource, type].map(Self.encodeComponent).joined(separator: "/")
        if !id.isEmpty { path += "/" + Self.encodeComponent(id) }
        if !extra.isEmpty {
            // Extras are a query-string-shaped path segment, ordered the
            // way Stremio and Nuvio send them.
            let order = ["search", "genre", "skip"]
            let keys = extra.keys.sorted { lhs, rhs in
                let left = order.firstIndex(of: lhs) ?? order.count
                let right = order.firstIndex(of: rhs) ?? order.count
                return left == right ? lhs < rhs : left < right
            }
            path += "/" + keys.map { "\(Self.encodeComponent($0))=\(Self.encodeComponent(extra[$0] ?? ""))" }
                .joined(separator: "&")
        }
        let suffix = query.map { "?\($0)" } ?? ""
        return URL(string: path + ".json" + suffix) ?? manifestWithoutQuery
    }

    /// Percent-encodes everything but RFC 3986 unreserved characters.
    private static func encodeComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .addonUnreserved) ?? value
    }

    /// Add-on requests behave like Stremio's: redirects to another HTTPS
    /// host are followed and the body is judged by decoding it, not by its
    /// Content-Type label.
    private static func addonPolicy(_ policy: HTTPRequestPolicy) -> HTTPRequestPolicy {
        var policy = policy
        policy.allowsCrossOriginRedirects = true
        policy.acceptsAnyContentType = true
        return policy
    }

    /// Add-on servers label JSON in several ways; the body is still decoded
    /// and validated as JSON whatever the label says.
    static let jsonContentTypes: Set<String> = [
        "application/json", "text/json", "text/plain", "application/javascript", "text/javascript"
    ]

    enum AddonClientError: LocalizedError, Equatable {
        case requiresHTTPS
        case invalidResponse
        case invalidManifest
        case notAManifest

        var errorDescription: String? {
            switch self {
            case .requiresHTTPS: "Omnia accepts HTTPS add-on manifests only."
            case .invalidResponse: "The add-on server returned an invalid response."
            case .invalidManifest: "This manifest is missing required identity information."
            case .notAManifest: "This address didn't return an add-on manifest. Use the add-on's install link, which usually ends in manifest.json."
            }
        }
    }
}

private nonisolated extension StremioAddonManifest {
    var hasValidBounds: Bool {
        let identityIsValid = !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && id.count <= 256
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && name.count <= 256
            && version.count <= 64
            && description.count <= 32_768
        let collectionsAreBounded = resources.count <= 64
            && types.count <= 256
            && catalogs.count <= 4_096
            && (addonCatalogs?.count ?? 0) <= 1_024
            && (idPrefixes?.count ?? 0) <= 1_024
        let stringsAreBounded = resources.allSatisfy { $0.name.count <= 64 }
            && types.allSatisfy { $0.count <= 64 }
            && catalogs.allSatisfy { !$0.id.isEmpty && $0.id.count <= 256 && $0.type.count <= 64 }
        return identityIsValid && collectionsAreBounded && stringsAreBounded
    }
}

nonisolated struct AddonStreamResponse: Decodable, Sendable {
    let streams: [AddonStream]
    let discardedEntryCount: Int

    private enum CodingKeys: String, CodingKey { case streams }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decode([LossyDecodable<AddonStream>].self, forKey: .streams)
        streams = decoded.compactMap(\.value)
        discardedEntryCount = decoded.count - streams.count
    }
}

nonisolated struct AddonCatalogResponse: Decodable, Sendable {
    let metas: [AddonMetaPreview]

    private enum CodingKeys: String, CodingKey {
        case metas
    }

    // One malformed card (for example a broken poster URL) must not empty the
    // whole row, so entries decode independently.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decodeIfPresent([LossyDecodable<AddonMetaPreview>].self, forKey: .metas) ?? []
        metas = decoded.compactMap(\.value)
    }
}

nonisolated struct AddonMetaResponse: Decodable, Sendable {
    let meta: AddonMeta
}

nonisolated struct AddonSubtitlesResponse: Decodable, Sendable {
    let subtitles: [AddonSubtitle]
}

nonisolated struct AddonCatalogAddonsResponse: Decodable, Sendable {
    let addons: [AddonCatalogAddon]
}

nonisolated struct AddonCatalogAddon: Decodable, Identifiable, Sendable {
    let transportURL: URL?
    let manifest: StremioAddonManifest?

    var id: String { transportURL?.absoluteString ?? manifest?.id ?? "unidentified-addon" }

    enum CodingKeys: String, CodingKey {
        case transportURL = "transportUrl"
        case manifest
    }
}

nonisolated struct AddonSubtitle: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let url: URL?
    let lang: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let urlText = try container.decodeIfPresent(String.self, forKey: .url)
        url = urlText.flatMap(URL.init(string:))
        lang = try container.decodeIfPresent(String.self, forKey: .lang)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? "\(urlText ?? "subtitle")::\(lang ?? "und")"
    }

    private enum CodingKeys: String, CodingKey { case id, url, lang }
}

nonisolated struct AddonStream: Decodable, Sendable {
    let name: String?
    let title: String?
    let description: String?
    let url: String?
    let ytId: String?
    let infoHash: String?
    let fileIdx: Int?
    let externalURL: String?
    let sources: [String]?
    let behaviorHints: AddonStreamBehaviorHints?

    enum CodingKeys: String, CodingKey {
        case name, title, description, url, ytId, infoHash, fileIdx, mapIdx, sources, behaviorHints
        case externalURL = "externalUrl"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = container.decodeLossy(String.self, forKey: .name)
        title = container.decodeLossy(String.self, forKey: .title)
        description = container.decodeLossy(String.self, forKey: .description)
        url = container.decodeLossy(String.self, forKey: .url)
        ytId = container.decodeLossy(String.self, forKey: .ytId)
        infoHash = container.decodeLossy(String.self, forKey: .infoHash)
        fileIdx = container.decodeLossy(Int.self, forKey: .fileIdx)
            ?? container.decodeLossy(Int.self, forKey: .mapIdx)
        externalURL = container.decodeLossy(String.self, forKey: .externalURL)
        sources = container.decodeLossy([String].self, forKey: .sources)
        behaviorHints = container.decodeLossy(AddonStreamBehaviorHints.self, forKey: .behaviorHints)
    }
}

nonisolated struct AddonStreamBehaviorHints: Decodable, Sendable {
    let notWebReady: Bool?
    let bingeGroup: String?
    let filename: String?
    let videoSize: Int64?
    let proxyHeaders: AddonProxyHeaders?

    private enum CodingKeys: String, CodingKey {
        case notWebReady, bingeGroup, filename, videoSize, proxyHeaders
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notWebReady = container.decodeLossy(Bool.self, forKey: .notWebReady)
        bingeGroup = container.decodeLossy(String.self, forKey: .bingeGroup)
        filename = container.decodeLossy(String.self, forKey: .filename)
        videoSize = container.decodeLossy(Int64.self, forKey: .videoSize)
        proxyHeaders = container.decodeLossy(AddonProxyHeaders.self, forKey: .proxyHeaders)
    }

    var requiresProxyHeaders: Bool { proxyHeaders != nil }

    /// Stremio add-ons may declare request headers that accompany a direct
    /// media URL. Omnia preserves them as transport metadata, but only the
    /// documented AVFoundation request options (currently User-Agent) are
    /// applied by `PlaybackSession`; response headers are web-player/CORS
    /// metadata and are intentionally not forwarded.
    var nativeRequestHeaders: [String: String] {
        guard let request = proxyHeaders?.request else { return [:] }
        return request.reduce(into: [:]) { headers, entry in
            let name = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !value.isEmpty,
                  !["host", "connection", "content-length", "range"].contains(name.lowercased())
            else { return }
            headers[name] = value
        }
    }
}

nonisolated struct AddonProxyHeaders: Decodable, Sendable {
    let request: [String: String]?
    let response: [String: String]?

    private enum CodingKeys: String, CodingKey { case request, response }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        request = container.decodeLossy([String: String].self, forKey: .request)
        response = container.decodeLossy([String: String].self, forKey: .response)
    }
}

private nonisolated struct LossyDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

private nonisolated extension KeyedDecodingContainer {
    func decodeLossy<Value: Decodable>(_ type: Value.Type, forKey key: Key) -> Value? {
        try? decodeIfPresent(type, forKey: key)
    }
}

private nonisolated extension CharacterSet {
    static let addonUnreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )
}
