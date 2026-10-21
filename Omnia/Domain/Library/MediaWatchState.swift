import Foundation

nonisolated struct MediaEpisodeKey: Codable, Hashable, Sendable {
    let id: String
    let seasonNumber: Int
    let episodeNumber: Int

    init(_ episode: MediaEpisode) {
        id = episode.id
        seasonNumber = episode.seasonNumber
        episodeNumber = episode.episodeNumber
    }
}

nonisolated struct LocalMediaWatchState: Codable, Equatable, Sendable {
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

nonisolated enum LocalMediaWatchCommand: Equatable, Sendable {
    case markMovie(watched: Bool)
    case markEpisode(MediaEpisode, watched: Bool)
    case markSeason(containing: MediaEpisode, watched: Bool)
    case markThrough(MediaEpisode, watched: Bool)
    case revertToPrevious(MediaEpisode)
    /// Playback reached the end of an episode: it is marked watched and
    /// `nextUp` becomes the title's Continue Watching entry, or none.
    case finishEpisode(MediaEpisode, nextUp: MediaEpisode?)
}

/// Nuvio's Next Up: which episode Continue Watching offers after one ends.
nonisolated enum NextUpEpisode {
    static func after(
        _ finished: MediaEpisode,
        episodes: [MediaEpisode],
        watchState: LocalMediaWatchState,
        fromFurthest: Bool,
        includesUnaired: Bool,
        now: Date = .now
    ) -> MediaEpisode? {
        // Specials are skipped unless the finished episode is one.
        let ordered = episodes
            .filter { $0.seasonNumber > 0 || finished.seasonNumber == 0 }
            .sorted { ($0.seasonNumber, $0.episodeNumber) < ($1.seasonNumber, $1.episodeNumber) }
        func position(_ episode: MediaEpisode) -> Int? {
            ordered.firstIndex {
                $0.id == episode.id || ($0.seasonNumber == episode.seasonNumber && $0.episodeNumber == episode.episodeNumber)
            }
        }
        guard var base = position(finished) else { return nil }
        if fromFurthest {
            for (key, watched) in watchState.episodeStates where watched {
                if let index = ordered.firstIndex(where: {
                    $0.id == key.id || ($0.seasonNumber == key.seasonNumber && $0.episodeNumber == key.episodeNumber)
                }) {
                    base = max(base, index)
                }
            }
        }
        guard ordered.indices.contains(base + 1) else { return nil }
        let next = ordered[base + 1]
        if !includesUnaired, let airDate = airDate(next), airDate > now {
            return nil
        }
        return next
    }

    /// TMDB and add-ons give `yyyy-MM-dd` or a full ISO date.
    static func airDate(_ episode: MediaEpisode) -> Date? {
        guard let text = episode.airDate?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if let date = try? Date(text, strategy: .iso8601) { return date }
        return try? Date(String(text.prefix(10)), strategy: Date.ISO8601FormatStyle().year().month().day().dateSeparator(.dash))
    }
}
