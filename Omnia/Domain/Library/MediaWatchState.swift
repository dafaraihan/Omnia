import Foundation

struct MediaEpisodeKey: Codable, Hashable, Sendable {
    let id: String
    let seasonNumber: Int
    let episodeNumber: Int

    init(_ episode: MediaEpisode) {
        id = episode.id
        seasonNumber = episode.seasonNumber
        episodeNumber = episode.episodeNumber
    }
}

struct LocalMediaWatchState: Codable, Equatable, Sendable {
    var movieWatched: Bool?
    var episodeStates: [MediaEpisodeKey: Bool]

    init(
        movieWatched: Bool? = nil,
        episodeStates: [MediaEpisodeKey: Bool] = [:]
    ) {
        self.movieWatched = movieWatched
        self.episodeStates = episodeStates
    }

    static let empty = Self()

    func isWatched(_ episode: MediaEpisode) -> Bool? {
        episodeStates[MediaEpisodeKey(episode)]
    }

    mutating func setWatched(_ watched: Bool, for episode: MediaEpisode) {
        episodeStates[MediaEpisodeKey(episode)] = watched
    }

    var isEmpty: Bool {
        movieWatched == nil && episodeStates.isEmpty
    }
}

enum LocalMediaWatchCommand: Equatable, Sendable {
    case markMovie(watched: Bool)
    case markEpisode(MediaEpisode, watched: Bool)
    case markSeason(containing: MediaEpisode, watched: Bool)
    case markThrough(MediaEpisode, watched: Bool)
    case revertToPrevious(MediaEpisode)
}
