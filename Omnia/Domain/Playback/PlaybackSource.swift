//
//  PlaybackSource.swift
//  Omnia
//

import Foundation

/// A direct, platform-playable stream offered by an enabled add-on. This is a
/// transport description only; Omnia never resolves torrents, magnets, or
/// third-party handoff links.
struct PlaybackSource: Identifiable, Hashable, Sendable {
    let id: String
    let addonID: String
    let addonName: String
    let title: String
    let detail: String?
    let streamIdentifier: String
    let url: URL

    init?(
        stream: AddonStream,
        addon: InstalledAddon,
        streamIdentifier: String
    ) {
        guard
            stream.behaviorHints?.notWebReady != true,
            let urlText = stream.url,
            let url = URL(string: urlText),
            url.scheme?.lowercased() == "https",
            url.host != nil
        else { return nil }

        self.id = "\(addon.id)::\(streamIdentifier)::\(url.absoluteString)"
        self.addonID = addon.id
        self.addonName = addon.manifest.name
        self.title = stream.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? addon.manifest.name
        self.detail = (stream.title ?? stream.description)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        self.streamIdentifier = streamIdentifier
        self.url = url
    }

    #if DEBUG
    /// Apple's public HLS sample is available exclusively in debug builds for
    /// exercising native player integration. It isn't presented as title media.
    static let integrationSample = PlaybackSource(
        id: "omnia.debug.apple-hls-sample",
        addonID: "omnia.debug",
        addonName: "Omnia Development",
        title: "Apple HLS Sample",
        detail: "Integration test only — not media for this title",
        streamIdentifier: "debug-sample",
        url: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8")!
    )
    #endif

    private init(
        id: String,
        addonID: String,
        addonName: String,
        title: String,
        detail: String?,
        streamIdentifier: String,
        url: URL
    ) {
        self.id = id
        self.addonID = addonID
        self.addonName = addonName
        self.title = title
        self.detail = detail
        self.streamIdentifier = streamIdentifier
        self.url = url
    }
}

enum PlaybackSourceResolver {
    static func sources(for item: MediaItem, addons: [InstalledAddon]) async -> [PlaybackSource] {
        let type = item.kind == .movie ? "movie" : "series"
        let candidates = item.streamIdentifierCandidates
        guard !candidates.isEmpty else { return [] }

        var resolved: [PlaybackSource] = []
        for addon in addons where addon.isEnabled && addon.manifest.supportsStreams {
            do {
                let sources = try await StremioAddonClient.fetchDirectStreams(
                    from: addon,
                    mediaType: type,
                    identifiers: candidates
                )
                resolved.append(contentsOf: sources)
            } catch {
                continue
            }
        }

        var seen = Set<String>()
        return resolved.filter { seen.insert($0.url.absoluteString).inserted }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
