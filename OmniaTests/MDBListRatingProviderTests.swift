import XCTest
@testable import Omnia

final class MDBListRatingProviderTests: XCTestCase {
    func testKnownAliasesNormalizeToCanonicalProviderIDs() {
        XCTAssertEqual(MDBListRatingProviderID("IMDb"), .imdb)
        XCTAssertEqual(MDBListRatingProviderID("the-movie-database"), .tmdb)
        XCTAssertEqual(MDBListRatingProviderID("Rotten Tomatoes"), .rottenTomatoes)
        XCTAssertEqual(MDBListRatingProviderID("tomatoes-audience"), .rottenTomatoesAudience)
        XCTAssertEqual(MDBListRatingProviderID("tomatoesaudience"), .rottenTomatoesAudience)
        XCTAssertEqual(MDBListRatingProviderID("popcorn"), .rottenTomatoesAudience)
        XCTAssertEqual(MDBListRatingProviderID("mal"), .myAnimeList)
        XCTAssertEqual(MDBListRatingProviderID("Roger Ebert"), .rogerEbert)
    }

    func testUnknownProviderUsesBoundedNormalizedIDAndReadableLabel() throws {
        let provider = try XCTUnwrap(MDBListRatingProviderID("Future_Source.2"))

        XCTAssertEqual(provider.rawValue, "future_source.2")
        XCTAssertEqual(
            MDBListRatingProviderRegistry.descriptor(for: provider).displayName,
            "Future Source 2"
        )
    }

    func testInvalidProviderIDsAreRejected() {
        XCTAssertNil(MDBListRatingProviderID(""))
        XCTAssertNil(MDBListRatingProviderID("contains/slash"))
        XCTAssertNil(MDBListRatingProviderID(String(repeating: "a", count: 65)))
        XCTAssertNil(MDBListRatingProviderID("café"))
    }

    func testSettingsDescriptorsKeepKnownOrderThenUnknownLexicalOrder() {
        let descriptors = MDBListRatingProviderRegistry.settingsDescriptors(
            discovered: ["zeta", "future_source", "imdb", "alpha"]
        )

        XCTAssertEqual(
            descriptors.map(\.id),
            [
                .imdb,
                .tmdb,
                .rottenTomatoes,
                .metacritic,
                .trakt,
                .letterboxd,
                .rottenTomatoesAudience,
                .myAnimeList,
                .rogerEbert,
                MDBListRatingProviderID("alpha"),
                MDBListRatingProviderID("future_source"),
                MDBListRatingProviderID("zeta")
            ]
        )
    }

    func testFormattingPreservesReturnedScaleAndAddsPercentOnlyWhereDefined() {
        XCTAssertEqual(MDBListRatingProviderRegistry.formattedValue(7.2, for: .imdb), "7.2")
        XCTAssertEqual(MDBListRatingProviderRegistry.formattedValue(76, for: .tmdb), "76")
        XCTAssertEqual(
            MDBListRatingProviderRegistry.formattedValue(65, for: .rottenTomatoes),
            "65%"
        )
        XCTAssertEqual(
            MDBListRatingProviderRegistry.formattedValue(90, for: .rottenTomatoesAudience),
            "90%"
        )
        XCTAssertEqual(MDBListRatingProviderRegistry.formattedAggregate(8.0), "8")
        XCTAssertEqual(MDBListRatingProviderRegistry.formattedAggregate(8.1), "8.1")
    }

    func testFormattingRejectsInvalidValuesInsteadOfClampingOrDisplayingThem() {
        XCTAssertNil(MDBListRatingProviderRegistry.formattedValue(-0.1, for: .imdb))
        XCTAssertNil(MDBListRatingProviderRegistry.formattedValue(100.1, for: .imdb))
        XCTAssertNil(MDBListRatingProviderRegistry.formattedValue(.infinity, for: .imdb))
        XCTAssertNil(MDBListRatingProviderRegistry.formattedAggregate(.nan))
    }

    func testCodableProviderIDUsesCanonicalSingleStringRepresentation() throws {
        let encoded = try JSONEncoder().encode(MDBListRatingProviderID("IMDb"))
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), "\"imdb\"")

        let decoded = try JSONDecoder().decode(MDBListRatingProviderID.self, from: encoded)
        XCTAssertEqual(decoded, .imdb)
    }
}
