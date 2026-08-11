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
}
