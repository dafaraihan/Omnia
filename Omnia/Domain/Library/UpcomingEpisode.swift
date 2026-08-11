import Foundation

struct UpcomingEpisode: Identifiable, Hashable, Sendable {
    let series: MediaItem
    let episode: MediaEpisode
    let airDate: Date

    var id: String {
        "\(series.id):\(episode.seasonNumber):\(episode.episodeNumber)"
    }
}

struct UpcomingResult: Equatable, Sendable {
    let items: [UpcomingEpisode]
    let failures: [String]
    let isStale: Bool
    let lastUpdated: Date
}
