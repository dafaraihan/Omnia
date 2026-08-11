import XCTest
@testable import Omnia

final class SettingsRouteTests: XCTestCase {
    func testRootGroupsFollowApprovedOrder() {
        XCTAssertEqual(
            SettingsRoute.rootGroups.map(\.section),
            [.account, .media, .playback, .app, .about]
        )
        XCTAssertEqual(
            SettingsRoute.rootGroups.flatMap(\.routes),
            [
                .account,
                .addons,
                .catalogs,
                .metadata,
                .progress,
                .upcoming,
                .videoPlayer,
                .subtitle,
                .appearance,
                .about
            ]
        )
    }

    func testEveryVerificationRouteHasNavigationMetadata() {
        for route in SettingsRoute.allVerificationRoutes {
            XCTAssertFalse(route.title.isEmpty, "Missing title for \(route)")
            XCTAssertFalse(route.systemImage.isEmpty, "Missing symbol for \(route)")
        }
    }

    func testSearchFindsEveryRootCategoryByApprovedTerms() {
        let expectations: [(String, SettingsRoute)] = [
            ("Apple", .account),
            ("sources", .addons),
            ("catalog", .catalogs),
            ("TMDB", .metadata),
            ("watchlist", .progress),
            ("episodes", .upcoming),
            ("skip intro", .videoPlayer),
            ("captions", .subtitle),
            ("theme", .appearance),
            ("libmpv", .about)
        ]

        for (query, expectedRoute) in expectations {
            XCTAssertTrue(expectedRoute.matches(query), "\(query) must find \(expectedRoute)")
        }
    }

    func testBlankSearchMatchesEveryRootRoute() {
        XCTAssertTrue(
            SettingsRoute.rootGroups
                .flatMap(\.routes)
                .allSatisfy { $0.matches("  ") }
        )
    }
}
