import Foundation

struct EpisodeRelease: Identifiable, Hashable, Sendable {
    let series: MediaItem
    let episode: MediaEpisode
    let airDate: Date

    var id: String {
        "\(series.id):\(episode.seasonNumber):\(episode.episodeNumber)"
    }
}

struct EpisodeReleaseResult: Equatable, Sendable {
    let items: [EpisodeRelease]
    let failures: [String]
    let isStale: Bool
    let lastUpdated: Date
}
