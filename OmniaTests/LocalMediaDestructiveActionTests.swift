import XCTest
@testable import Omnia

@MainActor
final class LocalMediaDestructiveActionTests: XCTestCase {
    func testImportReviewReportsConflictAndReplaceRequiresMatchingConfirmation() async throws {
        let store = try LocalMediaStore.inMemory()
        let existing = makeItem(id: "existing", title: "Old")
        try await store.setWatchlist(existing, isIncluded: true, at: .distantPast)

        let replacement = LocalMediaSnapshot(
            item: makeItem(id: "existing", title: "New"),
            isInWatchlist: true,
            savedAt: .now,
            lastPlayedAt: nil
        )
        let added = LocalMediaSnapshot(
            item: makeItem(id: "added", title: "Added"),
            isInWatchlist: true,
            savedAt: .now,
            lastPlayedAt: nil
        )
        let data = try LocalMediaBackupDocument(snapshots: [replacement, added]).encoded()
        let review = try await store.reviewImport(data)

        XCTAssertEqual(review.conflictingMediaIDs, ["existing"])
        await XCTAssertThrowsErrorAsync {
            try await store.applyImport(review, mode: .replace(.init(rawValue: UUID())))
        }

        try await store.applyImport(review, mode: .replace(review.confirmation))
        let snapshots = try await store.snapshot()
        XCTAssertEqual(Set(snapshots.map(\.mediaID)), ["existing", "added"])
        XCTAssertEqual(snapshots.first { $0.mediaID == "existing" }?.item.title, "New")
    }

    func testClearActionsPreserveIndependentStateAndRejectWrongToken() async throws {
        let store = try LocalMediaStore.inMemory()
        let watchlist = makeItem(id: "watchlist", title: "Watchlist")
        let progress = makeItem(id: "progress", title: "Progress")
        try await store.setWatchlist(watchlist, isIncluded: true, at: .now)
        try await store.recordPlayback(
            for: progress,
            episode: nil,
            positionSeconds: 10,
            durationSeconds: 100,
            completionThreshold: 0.95,
            at: .now
        )

        let progressConfirmation = await store.confirmation(for: .clearProgress)
        await XCTAssertThrowsErrorAsync {
            try await store.perform(.clearWatchlist, confirmation: progressConfirmation)
        }
        try await store.perform(.clearProgress, confirmation: progressConfirmation)
        var snapshots = try await store.snapshot()
        XCTAssertEqual(snapshots.map(\.mediaID), ["watchlist"])

        try await store.recordPlayback(
            for: progress,
            episode: nil,
            positionSeconds: 10,
            durationSeconds: 100,
            completionThreshold: 0.95,
            at: .now
        )
        let watchlistConfirmation = await store.confirmation(for: .clearWatchlist)
        try await store.perform(.clearWatchlist, confirmation: watchlistConfirmation)
        snapshots = try await store.snapshot()
        XCTAssertEqual(snapshots.map(\.mediaID), ["progress"])
        XCTAssertFalse(snapshots[0].isInWatchlist)
        XCTAssertNotNil(snapshots[0].progress)
    }

    private func makeItem(id: String, title: String) -> MediaItem {
        MediaItem(
            id: id,
            title: title,
            year: "2026",
            kind: .movie,
            overview: "",
            genres: [],
            symbol: "film",
            artworkColors: [.blue],
            progress: nil
        )
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {}
}
