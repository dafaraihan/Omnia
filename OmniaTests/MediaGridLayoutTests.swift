import XCTest
@testable import Omnia

@MainActor
final class MediaGridLayoutTests: XCTestCase {
    func testWidePosterGridUsesTheEntireContentWidth() {
        let layout = MediaGridLayout.fitting(
            containerWidth: 1_559,
            horizontalInset: 32,
            minimumItemWidth: 154,
            maximumItemWidth: 190,
            spacing: 18
        )

        XCTAssertEqual(layout.columnCount, 8)
        XCTAssertEqual(layout.itemWidth, 171.125, accuracy: 0.001)
        XCTAssertEqual(layout.usedWidth, 1_495, accuracy: 0.001)
    }

    func testWideGenreGridUsesTheEntireContentWidth() {
        let layout = MediaGridLayout.fitting(
            containerWidth: 1_559,
            horizontalInset: 32,
            minimumItemWidth: 220,
            maximumItemWidth: 280,
            spacing: 14
        )

        XCTAssertEqual(layout.columnCount, 6)
        XCTAssertEqual(layout.itemWidth, 237.5, accuracy: 0.001)
        XCTAssertEqual(layout.usedWidth, 1_495, accuracy: 0.001)
    }

    func testContinueWatchingGridUsesLandscapeCardColumns() {
        let layout = MediaBrowseMetrics.landscapeGridLayout(containerWidth: 1_559)

        XCTAssertEqual(layout.columnCount, 4)
        XCTAssertGreaterThanOrEqual(layout.itemWidth, 304)
        XCTAssertLessThanOrEqual(layout.itemWidth, 360)
        XCTAssertLessThanOrEqual(layout.usedWidth, 1_495)
    }
}
