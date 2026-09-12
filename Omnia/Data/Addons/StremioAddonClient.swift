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
            data = try await transport.data(for: HTTPRequestPolicy(
                url: url,
                allowedOrigin: origin,
                timeout: TimeInterval(timeout.rawValue),
                maximumResponseBytes: 1_048_576,
                acceptedContentTypes: ["application/json"]
            ))
        } catch let error as AddonClientError {
            throw error
        } catch {
            throw AddonClientError.invalidResponse
        }

        guard let manifest = try? JSONDecoder().decode(StremioAddonManifest.self, from: data),
              manifest.hasValidBounds else {
            throw AddonClientError.invalidManifest
        }
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
            for mediaType in mediaTypes where addon.manifest.supports(resource: "stream", type: mediaType, identifier: identifier) {
                try Task.checkCancellation()
                let endpoint = resourceURL(addon: addon, resource: "stream", type: mediaType, id: identifier)
                do {
                    guard let origin = NormalizedOrigin(url: endpoint) else { continue }
                    let data = try await transport.data(for: HTTPRequestPolicy(
                        url: endpoint,
                        allowedOrigin: origin,
                        timeout: TimeInterval(timeout.rawValue),
                        // Aggregator add-ons can legitimately return several
                        // hundred richly-described streams. Keep the response
                        // bounded, but allow the payload size observed from
                        // compatible Stremio clients and AIOStreams.
                        maximumResponseBytes: 8_388_608,
                        acceptedContentTypes: ["application/json"]
                    ))
                    try Task.checkCancellation()
                    guard let result = try? JSONDecoder().decode(AddonStreamResponse.self, from: data),
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
        if candidates.isEmpty, !receivedValidResponse, let mostRecentError { throw mostRecentError }
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.deduplicationKey).inserted }
    }

    static func fetchCatalog(
        from addon: InstalledAddon,
        catalog: AddonCatalog,
        extra: [String: String] = [:]
    ) async throws -> [AddonMetaPreview] {
        guard addon.isEnabled,
              addon.manifest.supports(resource: "catalog", type: catalog.type),
              extra.keys.allSatisfy({ key in catalog.extra?.contains(where: { $0.name == key }) == true }),
              !(catalog.extra ?? []).contains(where: { $0.isRequired == true && extra[$0.name] == nil })
        else { return [] }

        let endpoint = resourceURL(
            addon: addon,
            resource: "catalog",
            type: catalog.type,
            id: catalog.id,
            extra: extra
        )
        let response: AddonCatalogResponse = try await fetch(endpoint)
        return response.metas
    }

    static func searchCatalogs(
        addons: [InstalledAddon],
        query: String
    ) async -> [AddonCatalogItem] {
        let enabledCatalogs = addons.flatMap { addon in
            addon.isEnabled ? addon.manifest.catalogs
                .filter { $0.supportsSearch && ["movie", "series"].contains($0.type) }
                .map { (addon, $0) } : []
        }

        return await withTaskGroup(of: [AddonCatalogItem].self, returning: [AddonCatalogItem].self) { group in
            for (addon, catalog) in enabledCatalogs {
                group.addTask {
                    guard let metas = try? await fetchCatalog(from: addon, catalog: catalog, extra: ["search": query]) else { return [] }
                    return await MainActor.run {
                        metas.compactMap { preview in
                            preview.mediaItem(addon: addon).map { .init(item: $0, addon: addon, catalog: catalog) }
                        }
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
        for identifier in identifiers {
            guard addon.manifest.supports(resource: "meta", type: mediaType, identifier: identifier) else { continue }
            let endpoint = resourceURL(addon: addon, resource: "meta", type: mediaType, id: identifier)
            if let response: AddonMetaResponse = try? await fetch(endpoint) {
                return response.meta
            }
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
                    let item = await MainActor.run { meta?.mediaItem(addon: addon) }
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

        var extra: [String: String] = ["videoID": videoID]
        if let videoHash { extra["videoHash"] = videoHash }
        if let videoSize { extra["videoSize"] = String(videoSize) }
        let endpoint = resourceURL(addon: addon, resource: "subtitles", type: mediaType, id: "", extra: extra)
        let response: AddonSubtitlesResponse = try await fetch(endpoint)
        return response.subtitles
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

    private static func fetch<Response: Decodable>(_ url: URL) async throws -> Response {
        guard let origin = NormalizedOrigin(url: url) else {
            throw AddonClientError.invalidResponse
        }
        let data: Data
        do {
            data = try await HTTPTransport().data(for: HTTPRequestPolicy(
                url: url,
                allowedOrigin: origin,
                timeout: 20,
                maximumResponseBytes: 2_097_152,
                acceptedContentTypes: ["application/json"]
            ))
        } catch {
            throw AddonClientError.invalidResponse
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw AddonClientError.invalidResponse
        }
    }

    private static func resourceURL(
        addon: InstalledAddon,
        resource: String,
        type: String,
        id: String,
        extra: [String: String] = [:]
    ) -> URL {
        var url = addon.manifestURL.deletingLastPathComponent()
            .appending(path: resource)
            .appending(path: type)
        if !id.isEmpty { url.append(path: id) }
        if !extra.isEmpty {
            let serialized = extra.sorted { $0.key < $1.key }.map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? value)"
            }.joined(separator: "&")
            // Extras are a query-string-shaped *path segment* in the Stremio
            // protocol. `URL.append(path:)` would encode `%` again and turn a
            // search term such as `the%20matrix` into `the%2520matrix`.
            return URL(string: "\(url.absoluteString)/\(serialized).json")!
        }
        return url.appendingPathExtension("json")
    }

    enum AddonClientError: LocalizedError, Equatable {
        case requiresHTTPS
        case invalidResponse
        case invalidManifest

        var errorDescription: String? {
            switch self {
            case .requiresHTTPS: "Omnia accepts HTTPS add-on manifests only."
            case .invalidResponse: "The add-on server returned an invalid response."
            case .invalidManifest: "This manifest is missing required identity information."
            }
        }
    }
}

private extension StremioAddonManifest {
    var hasValidBounds: Bool {
        let identityIsValid = !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && id.count <= 256
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && name.count <= 256
            && version.count <= 64
            && description.count <= 4_096
        let collectionsAreBounded = resources.count <= 64
            && types.count <= 64
            && catalogs.count <= 256
            && (addonCatalogs?.count ?? 0) <= 256
            && (idPrefixes?.count ?? 0) <= 128
        let stringsAreBounded = resources.allSatisfy { $0.name.count <= 64 }
            && types.allSatisfy { !$0.isEmpty && $0.count <= 64 }
            && catalogs.allSatisfy { !$0.id.isEmpty && $0.id.count <= 256 && $0.type.count <= 64 }
        return identityIsValid && collectionsAreBounded && stringsAreBounded
    }
}

struct AddonStreamResponse: Decodable {
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

struct AddonCatalogResponse: Decodable {
    let metas: [AddonMetaPreview]
}

struct AddonMetaResponse: Decodable {
    let meta: AddonMeta
}

struct AddonSubtitlesResponse: Decodable {
    let subtitles: [AddonSubtitle]
}

struct AddonCatalogAddonsResponse: Decodable {
    let addons: [AddonCatalogAddon]
}

struct AddonCatalogAddon: Decodable, Identifiable, Sendable {
    let transportURL: URL?
    let manifest: StremioAddonManifest?

    var id: String { transportURL?.absoluteString ?? manifest?.id ?? "unidentified-addon" }

    enum CodingKeys: String, CodingKey {
        case transportURL = "transportUrl"
        case manifest
    }
}

struct AddonSubtitle: Decodable, Identifiable, Hashable, Sendable {
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

struct AddonStream: Decodable {
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

struct AddonStreamBehaviorHints: Decodable {
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

struct AddonProxyHeaders: Decodable {
    let request: [String: String]?
    let response: [String: String]?

    private enum CodingKeys: String, CodingKey { case request, response }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        request = container.decodeLossy([String: String].self, forKey: .request)
        response = container.decodeLossy([String: String].self, forKey: .response)
    }
}

private struct LossyDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

private extension KeyedDecodingContainer {
    func decodeLossy<Value: Decodable>(_ type: Value.Type, forKey key: Key) -> Value? {
        try? decodeIfPresent(type, forKey: key)
    }
}

private extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+#?")
        return set
    }()
}
