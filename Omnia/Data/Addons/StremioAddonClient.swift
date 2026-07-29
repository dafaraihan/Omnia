//
//  StremioAddonClient.swift
//  Omnia
//

import Foundation

enum StremioAddonClient {
    static func fetchManifest(from url: URL) async throws -> StremioAddonManifest {
        guard url.scheme?.lowercased() == "https" else { throw AddonClientError.requiresHTTPS }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse, 200 ..< 300 ~= response.statusCode else {
            throw AddonClientError.invalidResponse
        }

        let manifest = try JSONDecoder().decode(StremioAddonManifest.self, from: data)
        guard !manifest.id.isEmpty, !manifest.name.isEmpty else { throw AddonClientError.invalidManifest }
        return manifest
    }

    /// Resolves only direct HTTPS media URLs. Omnia deliberately doesn't
    /// process torrent identifiers, magnets, or third-party handoff links.
    static func fetchDirectStreams(
        from addon: InstalledAddon,
        mediaType: String,
        identifiers: [String]
    ) async throws -> [PlaybackSource] {
        guard addon.isEnabled, addon.manifest.supportsStreams else { return [] }

        let streamBaseURL = addon.manifestURL.deletingLastPathComponent()
        for identifier in identifiers {
            let endpoint = streamBaseURL
                .appending(path: "stream")
                .appending(path: mediaType)
                .appending(path: identifier)
                .appendingPathExtension("json")

            let (data, response) = try await URLSession.shared.data(from: endpoint)
            guard let response = response as? HTTPURLResponse else { continue }
            guard response.statusCode != 404 else { continue }
            guard 200 ..< 300 ~= response.statusCode else { throw AddonClientError.invalidResponse }

            let result = try JSONDecoder().decode(AddonStreamResponse.self, from: data)
            let sources = result.streams.compactMap {
                PlaybackSource(stream: $0, addon: addon, streamIdentifier: identifier)
            }
            if !sources.isEmpty { return sources }
        }
        return []
    }

    enum AddonClientError: LocalizedError {
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

struct AddonStreamResponse: Decodable {
    let streams: [AddonStream]
}

struct AddonStream: Decodable {
    let name: String?
    let title: String?
    let description: String?
    let url: String?
    let behaviorHints: AddonStreamBehaviorHints?
}

struct AddonStreamBehaviorHints: Decodable {
    let notWebReady: Bool?
}
