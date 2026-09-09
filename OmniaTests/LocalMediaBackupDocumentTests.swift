import XCTest
@testable import Omnia

@MainActor
final class LocalMediaBackupDocumentTests: XCTestCase {
    func testExportIsVersionedDeterministicAndContainsNoCredentialURLs() throws {
        let later = LocalMediaSnapshot(
            item: makeItem(id: "b"),
            isInWatchlist: true,
            savedAt: Date(timeIntervalSince1970: 20),
            lastPlayedAt: nil
        )
        let earlier = LocalMediaSnapshot(
            item: makeItem(id: "a"),
            isInWatchlist: true,
            savedAt: nil,
            lastPlayedAt: Date(timeIntervalSince1970: 10)
        )

        let document = try LocalMediaBackupDocument(
            snapshots: [later, earlier],
            exportedAt: Date(timeIntervalSince1970: 30)
        )
        let encoded = try document.encoded()
        let decoded = try LocalMediaBackupDocument.decode(encoded)

        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.records.map(\.media.id), ["a", "b"])
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("Authorization"))
    }

    func testDecodeRejectsCorruptOversizedAndExcessiveInput() throws {
        XCTAssertThrowsError(try LocalMediaBackupDocument.decode(Data("bad".utf8)))
        XCTAssertThrowsError(
            try LocalMediaBackupDocument.decode(Data(repeating: 0, count: LocalMediaBackupDocument.maximumByteCount + 1))
        )

        let record = try LocalMediaBackupRecord(snapshot: .init(
            item: makeItem(id: "a"),
            isInWatchlist: true,
            savedAt: nil,
            lastPlayedAt: nil
        ))
        let document = LocalMediaBackupDocument(
            version: 1,
            exportedAt: .now,
            records: Array(repeating: record, count: LocalMediaBackupDocument.maximumRecordCount + 1)
        )
        XCTAssertThrowsError(try LocalMediaBackupDocument.decode(JSONEncoder().encode(document)))
    }

    func testCredentialBearingArtworkURLIsRejected() {
        let item = MediaItem(
            id: "secret",
            title: "Secret",
            year: "2026",
            kind: .movie,
            overview: "",
            genres: [],
            symbol: "film",
            artworkColors: [.blue],
            artworkURL: URL(string: "https://user:password@example.com/poster.jpg"),
            progress: nil
        )
        XCTAssertThrowsError(
            try LocalMediaBackupDocument(snapshots: [
                .init(item: item, isInWatchlist: true, savedAt: nil, lastPlayedAt: nil)
            ])
        )
    }

    func testWatchStateSurvivesBackupRoundTrip() throws {
        let episode = MediaEpisode(
            id: "s1e1",
            seasonNumber: 1,
            episodeNumber: 1,
            title: "Pilot",
            overview: "",
            runtimeMinutes: 42,
            stillURL: nil,
            airDate: nil
        )
        var watchState = LocalMediaWatchState(movieWatched: nil)
        watchState.setWatched(true, for: episode)
        let snapshot = LocalMediaSnapshot(
            item: makeItem(id: "series"),
            isInWatchlist: true,
            savedAt: nil,
            lastPlayedAt: nil,
            watchState: watchState
        )

        let encoded = try LocalMediaBackupDocument(snapshots: [snapshot]).encoded()
        let decoded = try LocalMediaBackupDocument.decode(encoded)

        XCTAssertEqual(decoded.records.first?.snapshot.watchState.isWatched(episode), true)
    }

    private func makeItem(id: String) -> MediaItem {
        MediaItem(
            id: id,
            title: id.uppercased(),
            year: "2026",
            kind: .movie,
            overview: "Overview",
            genres: ["Drama"],
            symbol: "film",
            artworkColors: [.blue],
            externalIDs: ["imdb": "tt123"],
            progress: nil
        )
    }
}
