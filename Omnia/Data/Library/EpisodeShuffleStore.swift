//
//  EpisodeShuffleStore.swift
//  Omnia
//

import Foundation
import Observation

/// One show's shuffle choice (Nuvio's EpisodeShuffleSettings).
nonisolated struct EpisodeShuffleSettings: Codable, Equatable, Sendable {
    var enabled = false
    var includeWatched = false
}

/// Nuvio's Shuffle: per show, whether its episodes play in random order and
/// whether watched episodes are included. Saved on this device. The global
/// switch is Settings › Layout › Detail Page › Shuffle.
@Observable
final class EpisodeShuffleStore {
    static let shared = EpisodeShuffleStore()

    private static let defaultsKey = "episode-shuffle-shows"

    private(set) var shows: [String: EpisodeShuffleSettings]
    /// Episodes already offered this session, so a shuffle goes through
    /// every candidate before repeating one, as Nuvio's picker does.
    @ObservationIgnored private var shownIDs: [String: Set<String>] = [:]
    @ObservationIgnored private var lastPickedID: [String: String] = [:]

    private init() {
        let data = UserDefaults.standard.data(forKey: Self.defaultsKey)
        shows = data.flatMap { try? JSONDecoder().decode([String: EpisodeShuffleSettings].self, from: $0) } ?? [:]
    }

    func settings(for mediaID: String) -> EpisodeShuffleSettings {
        shows[mediaID] ?? EpisodeShuffleSettings()
    }

    /// Whether shuffle is on for a show right now.
    func isActive(for item: MediaItem, display: DisplayPreferences) -> Bool {
        display.episodeShuffleAvailable && item.kind == .series && settings(for: item.id).enabled
    }

    func save(_ settings: EpisodeShuffleSettings, for mediaID: String) {
        shows[mediaID] = settings
        if let data = try? JSONEncoder().encode(shows) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    /// Released, numbered episodes outside specials; watched ones only when
    /// `includeWatched`.
    func candidates(
        episodes: [MediaEpisode],
        watchState: LocalMediaWatchState,
        includeWatched: Bool,
        now: Date = .now
    ) -> [MediaEpisode] {
        var seen = Set<String>()
        return episodes
            .filter { $0.seasonNumber > 0 && $0.episodeNumber > 0 }
            .filter { episode in
                guard let airDate = NextUpEpisode.airDate(episode) else { return true }
                return airDate <= now
            }
            .filter { seen.insert("\($0.seasonNumber):\($0.episodeNumber)").inserted }
            .filter { includeWatched || watchState.isWatched($0) != true }
    }

    /// A random episode, never `current`, avoiding ones offered before until
    /// every candidate has had a turn.
    func pick(
        for mediaID: String,
        episodes: [MediaEpisode],
        watchState: LocalMediaWatchState,
        includeWatched: Bool,
        excluding current: MediaEpisode? = nil
    ) -> MediaEpisode? {
        let candidates = candidates(episodes: episodes, watchState: watchState, includeWatched: includeWatched)
            .filter { episode in
                guard let current else { return true }
                return !(episode.seasonNumber == current.seasonNumber && episode.episodeNumber == current.episodeNumber)
            }
        guard !candidates.isEmpty else { return nil }
        var shown = shownIDs[mediaID] ?? []
        if let current { shown.insert(current.id) }
        var pool = candidates.filter { !shown.contains($0.id) }
        if pool.isEmpty {
            shown.subtract(candidates.map(\.id))
            pool = candidates.filter { $0.id != lastPickedID[mediaID] }
            if pool.isEmpty { pool = candidates }
        }
        guard let picked = pool.randomElement() else { return nil }
        shown.insert(picked.id)
        shownIDs[mediaID] = shown
        lastPickedID[mediaID] = picked.id
        return picked
    }
}
