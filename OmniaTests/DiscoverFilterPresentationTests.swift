import XCTest
@testable import Omnia

@MainActor
final class DiscoverFilterPresentationTests: XCTestCase {
    func testKindGenreAndReleasePeriodFilterItemsFunctionally() {
        let state = DiscoverFilterState(
            genre: "Drama",
            kind: .series,
            releasePeriod: .thisYear,
            sort: .catalogOrder
        )

        let result = DiscoverFilterPresentation.apply(
            state,
            to: [
                item("matching", year: "2026", kind: .series, genres: ["Drama"]),
                item("movie", year: "2026", kind: .movie, genres: ["Drama"]),
                item("old", year: "2020", kind: .series, genres: ["Drama"]),
                item("comedy", year: "2026", kind: .series, genres: ["Comedy"])
            ],
            currentYear: 2026
        )

        XCTAssertEqual(result.map(\.id), ["matching"])
    }

    func testChooseYearAndDateSortingAreApplied() {
        let values = [
            item("older", year: "2024"),
            item("newer", year: "2026"),
            item("middle", year: "2025")
        ]
        let newest = DiscoverFilterPresentation.apply(
            DiscoverFilterState(sort: .newestFirst),
            to: values,
            currentYear: 2026
        )
        let chosen = DiscoverFilterPresentation.apply(
            DiscoverFilterState(releasePeriod: .chooseYear, selectedYear: 2025),
            to: values,
            currentYear: 2026
        )

        XCTAssertEqual(newest.map(\.id), ["newer", "middle", "older"])
        XCTAssertEqual(chosen.map(\.id), ["middle"])
    }

    func testCatalogSelectionAndSettingsPreferencesControlShelfVisibility() {
        var preferences = HomeShelfPreferences(rawValue: "")
        preferences.setEnabled(false, for: .popularMovies)
        let state = DiscoverFilterState(selectedCatalogIDs: [BuiltInHomeShelf.trendingMovies.id])

        XCTAssertTrue(
            DiscoverFilterPresentation.showsCatalog(
                id: BuiltInHomeShelf.trendingMovies.id,
                kind: .movie,
                state: state,
                builtInShelf: .trendingMovies,
                preferences: preferences
            )
        )
        XCTAssertFalse(
            DiscoverFilterPresentation.showsCatalog(
                id: BuiltInHomeShelf.popularMovies.id,
                kind: .movie,
                state: DiscoverFilterState(),
                builtInShelf: .popularMovies,
                preferences: preferences
            )
        )
    }

    private func item(
        _ id: String,
        year: String,
        kind: MediaItem.Kind = .movie,
        genres: [String] = []
    ) -> MediaItem {
        MediaItem(
            id: id,
            title: id,
            year: year,
            kind: kind,
            overview: "",
            genres: genres,
            symbol: "film",
            artworkColors: [.black],
            progress: nil
        )
    }
}
