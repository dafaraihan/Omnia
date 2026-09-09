import SwiftData
import XCTest
@testable import Omnia

@MainActor
final class LocalMediaStoreTests: XCTestCase {
    func testWatchlistAndProgressRemainIndependentAndStable() async throws {
        let store = try LocalMediaStore.inMemory()
        let first = makeItem(id: "first", title: "First")
        let second = makeItem(id: "second", title: "Second")

        try await store.setWatchlist(first, isIncluded: true, at: Date(timeIntervalSince1970: 10))
        try await store.recordPlayback(
            for: second,
            episode: nil,
            positionSeconds: 30,
            durationSeconds: 100,
            completionThreshold: 0.95,
            at: Date(timeIntervalSince1970: 20)
        )
        try await store.setWatchlist(first, isIncluded: false, at: Date(timeIntervalSince1970: 30))

        let snapshots = try await store.snapshot()
        XCTAssertEqual(snapshots.map(\.mediaID), ["second"])
        XCTAssertFalse(snapshots[0].isInWatchlist)
        XCTAssertEqual(try XCTUnwrap(snapshots[0].progress), 0.3, accuracy: 0.001)

        try await store.setWatchlist(second, isIncluded: true, at: Date(timeIntervalSince1970: 40))
        try await store.clearProgress()

        let cleared = try await store.snapshot()
        XCTAssertEqual(cleared.map(\.mediaID), ["second"])
        XCTAssertTrue(cleared[0].isInWatchlist)
        XCTAssertNil(cleared[0].progress)
    }

    func testCompletionRemovesResumeStateButPreservesWatchlist() async throws {
        let store = try LocalMediaStore.inMemory()
        let item = makeItem(id: "movie", title: "Movie")
        try await store.setWatchlist(item, isIncluded: true, at: .distantPast)

        try await store.recordPlayback(
            for: item,
            episode: nil,
            positionSeconds: 95,
            durationSeconds: 100,
            completionThreshold: 0.95,
            at: .now
        )

        let snapshots = try await store.snapshot()
        let snapshot = try XCTUnwrap(snapshots.first)
        XCTAssertTrue(snapshot.isInWatchlist)
        XCTAssertNil(snapshot.progress)
        XCTAssertNil(snapshot.positionSeconds)
        XCTAssertNil(snapshot.durationSeconds)
    }

    func testRemovingOneContinueWatchingItemPreservesSavedTitle() async throws {
        let store = try LocalMediaStore.inMemory()
        let saved = makeItem(id: "saved", title: "Saved")
        let transient = makeItem(id: "transient", title: "Transient")
        try await store.setWatchlist(saved, isIncluded: true, at: .distantPast)

        for item in [saved, transient] {
            try await store.recordPlayback(
                for: item,
                episode: nil,
                positionSeconds: 30,
                durationSeconds: 100,
                completionThreshold: 0.95,
                at: .now
            )
        }

        try await store.clearProgress(for: saved.id)
        var snapshots = try await store.snapshot()
        let savedSnapshot = try XCTUnwrap(snapshots.first { $0.mediaID == saved.id })
        let continuingAfterSavedRemoval = try await store.continueWatching(limit: nil)
        XCTAssertTrue(savedSnapshot.isInWatchlist)
        XCTAssertNil(savedSnapshot.progress)
        XCTAssertFalse(continuingAfterSavedRemoval.contains { $0.mediaID == saved.id })

        try await store.clearProgress(for: transient.id)
        snapshots = try await store.snapshot()
        XCTAssertFalse(snapshots.contains { $0.mediaID == transient.id })
    }

    func testEpisodeResumeContextAndContinueLimitUseLastPlayedOrder() async throws {
        let store = try LocalMediaStore.inMemory()
        let series = makeItem(id: "series", title: "Series", kind: .series)
        let movie = makeItem(id: "movie", title: "Movie")
        let episode = MediaEpisode(
            id: "episode-2",
            seasonNumber: 1,
            episodeNumber: 2,
            title: "Second",
            overview: "",
            runtimeMinutes: 42,
            stillURL: URL(string: "https://images.example/second.jpg"),
            airDate: nil
        )

        try await store.recordPlayback(
            for: series,
            episode: episode,
            positionSeconds: 40,
            durationSeconds: 100,
            completionThreshold: 0.95,
            at: Date(timeIntervalSince1970: 10)
        )
        try await store.recordPlayback(
            for: movie,
            episode: nil,
            positionSeconds: 20,
            durationSeconds: 100,
            completionThreshold: 0.95,
            at: Date(timeIntervalSince1970: 20)
        )

        let continuing = try await store.continueWatching(limit: 1)
        XCTAssertEqual(continuing.map(\.mediaID), ["movie"])

        let snapshots = try await store.snapshot()
        let seriesSnapshot = try XCTUnwrap(snapshots.first { $0.mediaID == "series" })
        XCTAssertEqual(seriesSnapshot.item.resumeEpisodeID, "episode-2")
        XCTAssertEqual(seriesSnapshot.item.resumeSeasonNumber, 1)
        XCTAssertEqual(seriesSnapshot.item.resumeEpisodeNumber, 2)
    }

    func testInvalidWriteRollsBackExistingRecord() async throws {
        let store = try LocalMediaStore.inMemory()
        let item = makeItem(id: "stable", title: "Stable")
        try await store.setWatchlist(item, isIncluded: true, at: .now)

        do {
            try await store.recordPlayback(
                for: item,
                episode: nil,
                positionSeconds: .infinity,
                durationSeconds: 100,
                completionThreshold: 0.95,
                at: .now
            )
            XCTFail("Expected validation to reject non-finite playback state")
        } catch {
            let snapshots = try await store.snapshot()
            let snapshot = try XCTUnwrap(snapshots.first)
            XCTAssertTrue(snapshot.isInWatchlist)
            XCTAssertNil(snapshot.progress)
        }
    }

    func testMovieWatchCommandsPersistStatusAndPreserveLibraryMembership() async throws {
        let store = try LocalMediaStore.inMemory()
        let movie = makeItem(id: "movie-watch-state", title: "Movie")
        try await store.setWatchlist(movie, isIncluded: true, at: Date(timeIntervalSince1970: 1))
        try await store.recordPlayback(
            for: movie,
            episode: nil,
            positionSeconds: 25,
            durationSeconds: 100,
            completionThreshold: 0.95,
            at: Date(timeIntervalSince1970: 2)
        )

        try await store.applyWatchCommand(
            .markMovie(watched: true),
            to: movie,
            episodes: [],
            at: Date(timeIntervalSince1970: 3)
        )

        var snapshots = try await store.snapshot()
        var snapshot = try XCTUnwrap(snapshots.first)
        XCTAssertTrue(snapshot.isInWatchlist)
        XCTAssertEqual(snapshot.watchState.movieWatched, true)
        XCTAssertNil(snapshot.progress)

        try await store.applyWatchCommand(
            .markMovie(watched: false),
            to: movie,
            episodes: [],
            at: Date(timeIntervalSince1970: 4)
        )

        snapshots = try await store.snapshot()
        snapshot = try XCTUnwrap(snapshots.first)
        XCTAssertTrue(snapshot.isInWatchlist)
        XCTAssertEqual(snapshot.watchState.movieWatched, false)
        XCTAssertNil(snapshot.progress)
    }

    func testMarkCurrentEpisodeWatchedAdvancesToNextEpisode() async throws {
        let store = try LocalMediaStore.inMemory()
        let series = makeItem(id: "series-advance", title: "Series", kind: .series)
        let episodes = makeEpisodes()
        let current = episodes[1]

        try await store.recordPlayback(
            for: series,
            episode: current,
            positionSeconds: 20,
            durationSeconds: 100,
            completionThreshold: 0.95,
            at: Date(timeIntervalSince1970: 1)
        )
        try await store.applyWatchCommand(
            .markEpisode(current, watched: true),
            to: series,
            episodes: episodes,
            at: Date(timeIntervalSince1970: 2)
        )

        let snapshots = try await store.snapshot()
        let snapshot = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snapshot.watchState.isWatched(current), true)
        XCTAssertEqual(snapshot.item.resumeEpisodeID, episodes[2].id)
        XCTAssertEqual(snapshot.item.resumeSeasonNumber, 2)
        XCTAssertEqual(snapshot.item.resumeEpisodeNumber, 1)
        XCTAssertEqual(snapshot.progress, 0)
        XCTAssertEqual(snapshot.positionSeconds, 0)
    }

    func testMarkCurrentEpisodeUnwatchedMakesItResumeTarget() async throws {
        let store = try LocalMediaStore.inMemory()
        let series = makeItem(id: "series-unwatched", title: "Series", kind: .series)
        let episodes = makeEpisodes()
        let current = episodes[1]

        try await store.applyWatchCommand(
            .markEpisode(current, watched: false),
            to: series,
            episodes: episodes,
            at: Date(timeIntervalSince1970: 2)
        )

        let snapshots = try await store.snapshot()
        let snapshot = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snapshot.watchState.isWatched(current), false)
        XCTAssertEqual(snapshot.item.resumeEpisodeID, current.id)
        XCTAssertEqual(snapshot.progress, 0)
    }

    func testSeasonWatchCommandsAffectOnlyCurrentSeason() async throws {
        let store = try LocalMediaStore.inMemory()
        let series = makeItem(id: "series-season", title: "Series", kind: .series)
        let episodes = makeEpisodes()

        try await store.applyWatchCommand(
            .markSeason(containing: episodes[1], watched: true),
            to: series,
            episodes: episodes,
            at: Date(timeIntervalSince1970: 2)
        )

        var snapshots = try await store.snapshot()
        var snapshot = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snapshot.watchState.isWatched(episodes[0]), true)
        XCTAssertEqual(snapshot.watchState.isWatched(episodes[1]), true)
        XCTAssertNil(snapshot.watchState.isWatched(episodes[2]))
        XCTAssertEqual(snapshot.item.resumeEpisodeID, episodes[2].id)

        try await store.applyWatchCommand(
            .markSeason(containing: episodes[1], watched: false),
            to: series,
            episodes: episodes,
            at: Date(timeIntervalSince1970: 3)
        )

        snapshots = try await store.snapshot()
        snapshot = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snapshot.watchState.isWatched(episodes[0]), false)
        XCTAssertEqual(snapshot.watchState.isWatched(episodes[1]), false)
        XCTAssertNil(snapshot.watchState.isWatched(episodes[2]))
        XCTAssertEqual(snapshot.item.resumeEpisodeID, episodes[0].id)
    }

    func testThroughHereAndRevertUseSeasonEpisodeOrder() async throws {
        let store = try LocalMediaStore.inMemory()
        let series = makeItem(id: "series-through", title: "Series", kind: .series)
        let episodes = makeEpisodes()

        try await store.applyWatchCommand(
            .markThrough(episodes[1], watched: true),
            to: series,
            episodes: episodes,
            at: Date(timeIntervalSince1970: 1)
        )

        var snapshots = try await store.snapshot()
        var snapshot = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snapshot.watchState.isWatched(episodes[0]), true)
        XCTAssertEqual(snapshot.watchState.isWatched(episodes[1]), true)
        XCTAssertNil(snapshot.watchState.isWatched(episodes[2]))
        XCTAssertEqual(snapshot.item.resumeEpisodeID, episodes[2].id)

        try await store.applyWatchCommand(
            .revertToPrevious(episodes[2]),
            to: series,
            episodes: episodes,
            at: Date(timeIntervalSince1970: 2)
        )

        snapshots = try await store.snapshot()
        snapshot = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snapshot.watchState.isWatched(episodes[1]), false)
        XCTAssertEqual(snapshot.item.resumeEpisodeID, episodes[1].id)

        try await store.applyWatchCommand(
            .markThrough(episodes[1], watched: false),
            to: series,
            episodes: episodes,
            at: Date(timeIntervalSince1970: 3)
        )

        snapshots = try await store.snapshot()
        snapshot = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snapshot.watchState.isWatched(episodes[0]), false)
        XCTAssertEqual(snapshot.watchState.isWatched(episodes[1]), false)
        XCTAssertEqual(snapshot.item.resumeEpisodeID, episodes[0].id)
    }

    func testRemoveWatchProgressPreservesWatchedHistory() async throws {
        let store = try LocalMediaStore.inMemory()
        let series = makeItem(id: "series-clear", title: "Series", kind: .series)
        let episodes = makeEpisodes()
        try await store.setWatchlist(series, isIncluded: true, at: Date(timeIntervalSince1970: 1))
        try await store.applyWatchCommand(
            .markEpisode(episodes[0], watched: true),
            to: series,
            episodes: episodes,
            at: Date(timeIntervalSince1970: 2)
        )

        try await store.clearProgress(for: series.id)

        let snapshots = try await store.snapshot()
        let snapshot = try XCTUnwrap(snapshots.first)
        XCTAssertTrue(snapshot.isInWatchlist)
        XCTAssertEqual(snapshot.watchState.isWatched(episodes[0]), true)
        XCTAssertNil(snapshot.progress)
        XCTAssertNil(snapshot.item.resumeEpisodeID)
    }

    private func makeItem(
        id: String,
        title: String,
        kind: MediaItem.Kind = .movie
    ) -> MediaItem {
        MediaItem(
            id: id,
            title: title,
            year: "2026",
            kind: kind,
            overview: "Overview",
            genres: ["Drama"],
            symbol: "film",
            artworkColors: [.blue, .black],
            progress: nil
        )
    }

    private func makeEpisodes() -> [MediaEpisode] {
        [
            makeEpisode(id: "s1e1", season: 1, episode: 1),
            makeEpisode(id: "s1e2", season: 1, episode: 2),
            makeEpisode(id: "s2e1", season: 2, episode: 1),
        ]
    }

    private func makeEpisode(id: String, season: Int, episode: Int) -> MediaEpisode {
        MediaEpisode(
            id: id,
            seasonNumber: season,
            episodeNumber: episode,
            title: "Episode \(episode)",
            overview: "",
            runtimeMinutes: 42,
            stillURL: URL(string: "https://images.example/\(id).jpg"),
            airDate: nil
        )
    }
}
