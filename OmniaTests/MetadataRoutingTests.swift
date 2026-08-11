import XCTest
@testable import Omnia

final class MetadataRoutingTests: XCTestCase {
    func testMoveFallbackEarlierMovesOnePosition() {
        var route = MetadataRoute(primary: .anilist, fallbackOrder: [.tvdb, .tmdb])

        XCTAssertTrue(route.moveFallback(.tmdb, direction: .earlier))
        XCTAssertEqual(route.fallbackOrder, [.tmdb, .tvdb])
    }

    func testMoveFallbackLaterMovesOnePosition() {
        var route = MetadataRoute(primary: .anilist, fallbackOrder: [.tvdb, .tmdb])

        XCTAssertTrue(route.moveFallback(.tvdb, direction: .later))
        XCTAssertEqual(route.fallbackOrder, [.tmdb, .tvdb])
    }

    func testMoveFallbackRejectsBoundaryAndUnknownProvider() {
        var route = MetadataRoute(primary: .anilist, fallbackOrder: [.tvdb, .tmdb])

        XCTAssertFalse(route.moveFallback(.tvdb, direction: .earlier))
        XCTAssertFalse(route.moveFallback(.anilist, direction: .later))
        XCTAssertEqual(route.fallbackOrder, [.tvdb, .tmdb])
    }
}
