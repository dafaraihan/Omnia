import XCTest
@testable import Omnia

@MainActor
final class LegacyLibraryMigrationTests: XCTestCase {
    func testLegacyKeyIsRemovedOnlyAfterVerifiedRoundTripAndMigrationIsIdempotent() async throws {
        let defaults = try makeDefaults()
        let store = try LocalMediaStore.inMemory()
        defaults.set(try JSONEncoder().encode(LegacyLibraryFixture.validItems), forKey: "saved-library")

        let migration = LegacyLibraryMigration(defaults: defaults, store: store)
        try await migration.runIfNeeded()
        let firstSnapshot = try await store.snapshot()
        try await migration.runIfNeeded()
        let secondSnapshot = try await store.snapshot()

        XCTAssertEqual(firstSnapshot, secondSnapshot)
        XCTAssertEqual(firstSnapshot.map(\.mediaID), ["episode", "movie"])
        XCTAssertTrue(firstSnapshot.allSatisfy(\.isInWatchlist))
        XCTAssertNil(defaults.data(forKey: "saved-library"))
        XCTAssertTrue(defaults.bool(forKey: LegacyLibraryMigration.markerKey))
    }

    func testCorruptLegacyDataIsRetainedForRecovery() async throws {
        let defaults = try makeDefaults()
        let store = try LocalMediaStore.inMemory()
        let corrupt = Data("not-json".utf8)
        defaults.set(corrupt, forKey: "saved-library")

        do {
            try await LegacyLibraryMigration(defaults: defaults, store: store).runIfNeeded()
            XCTFail("Expected corrupt legacy data to fail migration")
        } catch {
            let snapshot = try await store.snapshot()
            XCTAssertEqual(defaults.data(forKey: "saved-library"), corrupt)
            XCTAssertFalse(defaults.bool(forKey: LegacyLibraryMigration.markerKey))
            XCTAssertTrue(snapshot.isEmpty)
        }
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "LegacyLibraryMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

private enum LegacyLibraryFixture {
    static let validItems = [
        SavedMediaItem(
            MediaItem(
                id: "movie",
                title: "Movie",
                year: "2026",
                kind: .movie,
                overview: "",
                genres: [],
                symbol: "film",
                artworkColors: [.blue],
                progress: nil
            )
        ),
        SavedMediaItem(
            MediaItem(
                id: "episode",
                title: "Series",
                year: "2026",
                kind: .series,
                overview: "",
                genres: [],
                symbol: "tv",
                artworkColors: [.cyan],
                progress: 0.5,
                positionSeconds: 100,
                durationSeconds: 200,
                resumeEpisodeID: "s1e2",
                resumeSeasonNumber: 1,
                resumeEpisodeNumber: 2
            )
        )
    ]
}
