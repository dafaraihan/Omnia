import XCTest
@testable import Omnia

@MainActor
final class MediaPosterLabelTests: XCTestCase {
    func testContentPreservesExactTitleAndFormatsYearWithFirstGenre() {
        let title = "The Full Real Provider Title That Must Never Be Shortened"
        let content = MediaPosterLabelContent(item: item(
            title: title,
            year: "2026",
            genres: ["Drama", "Mystery"]
        ))

        XCTAssertEqual(content.title, title)
        XCTAssertEqual(content.metadata, "2026 · Drama")
    }

    func testMetadataOmitsUnavailableValuesWithoutInventingPlaceholders() {
        let yearOnly = MediaPosterLabelContent(item: item(year: "2026", genres: []))
        let genreOnly = MediaPosterLabelContent(item: item(year: "", genres: ["Drama"]))
        let neither = MediaPosterLabelContent(item: item(year: "  ", genres: [" "]))
        let placeholderYear = MediaPosterLabelContent(item: item(year: "—", genres: []))

        XCTAssertEqual(yearOnly.metadata, "2026")
        XCTAssertEqual(genreOnly.metadata, "Drama")
        XCTAssertNil(neither.metadata)
        XCTAssertNil(placeholderYear.metadata)
    }

    private func item(
        title: String = "Title",
        year: String,
        genres: [String]
    ) -> MediaItem {
        MediaItem(
            id: UUID().uuidString,
            title: title,
            year: year,
            kind: .movie,
            overview: "",
            genres: genres,
            symbol: "film",
            artworkColors: [.blue, .black],
            progress: nil
        )
    }
}
