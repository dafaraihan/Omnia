import Foundation

/// Captures one user action. The episode must not be recomputed from mutable
/// resume progress or the player's next episode while source lookup awaits.
nonisolated struct PlaybackRequest: Identifiable {
    let id = UUID()
    let item: MediaItem
    let episode: MediaEpisode?
    let resumeAt: Double?
}

struct MediaPlaybackKey: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String
}

extension AddonStreamCandidate {
    init(
        id: String,
        addonID: String,
        addonName: String,
        streamIdentifier: String,
        displayName: String,
        displayDescription: String?,
        delivery: Delivery,
        filename: String?,
        videoSize: Int64?,
        bingeGroup: String?,
        hasPeerDiscoveryHints: Bool,
        requestHeaders: [String: String]
    ) {
        self.id = id
        self.addonID = addonID
        self.addonName = addonName
        self.streamIdentifier = streamIdentifier
        self.displayName = displayName
        self.displayDescription = displayDescription
        self.delivery = delivery
        self.filename = filename
        self.videoSize = videoSize
        self.bingeGroup = bingeGroup
        self.hasPeerDiscoveryHints = hasPeerDiscoveryHints
        self.requestHeaders = requestHeaders
    }
}
