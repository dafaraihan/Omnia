import XCTest
@testable import Omnia

@MainActor
final class LibraryCollectionPresentationTests: XCTestCase {
    func testSectionsAreMutuallyExclusive() {
        let saved = snapshot(id: "saved", isSaved: true)
        let unfinished = snapshot(id: "unfinished", isSaved: true, progress: 0.4)
        let watched = snapshot(id: "watched", isSaved: true, watched: true)

        let sections = LibraryCollectionPresentation.sections(
            snapshots: [saved, unfinished, watched],
            kind: nil,
            sort: .recentAdded
        )

        XCTAssertEqual(sections.first(where: { $0.kind == .myList })?.items.map(\.id), ["saved"])
        XCTAssertEqual(sections.first(where: { $0.kind == .continueWatching })?.items.map(\.id), ["unfinished"])
        XCTAssertEqual(sections.first(where: { $0.kind == .rewatch })?.items.map(\.id), ["watched"])
    }

    func testUnfinishedTitlesAppearOnlyInContinueWatchingEvenWhenSaved() {
        let result = LibraryCollectionPresentation.sections(
            snapshots: [snapshot(id: "both", isSaved: true, progress: 0.25)],
            kind: nil,
            sort: .recentAdded
        )

        XCTAssertEqual(result.first(where: { $0.kind == .continueWatching })?.items.map(\.id), ["both"])
        XCTAssertTrue(result.first(where: { $0.kind == .myList })?.items.isEmpty == true)
    }

    func testKindFilterAppliesToEverySection() {
        let movie = snapshot(id: "movie", kind: .movie, isSaved: true)
        let series = snapshot(id: "series", kind: .series, isSaved: true, progress: 0.2)

        let result = LibraryCollectionPresentation.sections(
            snapshots: [movie, series],
            kind: .movie,
            sort: .title
        )

        XCTAssertEqual(result.flatMap(\.items).map(\.id), ["movie"])
    }

    func testTitleSortAppliesToEverySection() {
        let zebra = snapshot(id: "zebra", title: "Zebra", isSaved: true)
        let apple = snapshot(id: "apple", title: "Apple", isSaved: true)

        let result = LibraryCollectionPresentation.sections(
            snapshots: [zebra, apple],
            kind: nil,
            sort: .title
        )

        XCTAssertEqual(result.first(where: { $0.kind == .myList })?.items.map(\.title), ["Apple", "Zebra"])
    }

    private func snapshot(
        id: String,
        title: String? = nil,
        kind: MediaItem.Kind = .movie,
        isSaved: Bool,
        progress: Double? = nil,
        watched: Bool = false
    ) -> LocalMediaSnapshot {
        let item = MediaItem(
            id: id,
            title: title ?? id,
            year: "2026",
            kind: kind,
            overview: "",
            genres: [],
            symbol: "film",
            artworkColors: [.black],
            progress: progress,
            positionSeconds: progress.map { $0 * 100 },
            durationSeconds: progress == nil ? nil : 100
        )
        return LocalMediaSnapshot(
            item: item,
            isInWatchlist: isSaved,
            savedAt: Date(timeIntervalSince1970: 10),
            lastPlayedAt: progress == nil ? nil : Date(timeIntervalSince1970: 20),
            watchState: LocalMediaWatchState(movieWatched: watched ? true : nil)
        )
    }
}
