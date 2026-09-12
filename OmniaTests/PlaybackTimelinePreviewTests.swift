import XCTest
@testable import Omnia

final class PlaybackTimelinePreviewTests: XCTestCase {
    func testHoverTimestampClampsToTimelineBounds() {
        XCTAssertEqual(
            PlaybackTimelinePreviewPosition.timestamp(x: -20, width: 200, duration: 1_000),
            0
        )
        XCTAssertEqual(
            PlaybackTimelinePreviewPosition.timestamp(x: 50, width: 200, duration: 1_000),
            250
        )
        XCTAssertEqual(
            PlaybackTimelinePreviewPosition.timestamp(x: 240, width: 200, duration: 1_000),
            1_000
        )
        XCTAssertNil(
            PlaybackTimelinePreviewPosition.timestamp(x: 50, width: 0, duration: 1_000)
        )
    }

    func testCacheEvictsLeastRecentlyUsedByCount() {
        var cache = PlaybackTimelinePreviewCache<Int, String>(maximumCount: 2, maximumBytes: 100)
        cache.insert("one", for: 1, byteCount: 10)
        cache.insert("two", for: 2, byteCount: 10)
        XCTAssertEqual(cache.value(for: 1), "one")
        cache.insert("three", for: 3, byteCount: 10)

        XCTAssertEqual(cache.value(for: 1), "one")
        XCTAssertNil(cache.value(for: 2))
        XCTAssertEqual(cache.value(for: 3), "three")
    }

    func testCacheEvictsUntilByteLimitAndRejectsOversizedEntry() {
        var cache = PlaybackTimelinePreviewCache<Int, String>(maximumCount: 24, maximumBytes: 20)
        cache.insert("one", for: 1, byteCount: 12)
        cache.insert("two", for: 2, byteCount: 12)
        XCTAssertNil(cache.value(for: 1))
        XCTAssertEqual(cache.value(for: 2), "two")

        cache.insert("oversized", for: 3, byteCount: 21)
        XCTAssertNil(cache.value(for: 3))
    }

    func testLowPowerConfigurationUsesLongerDebounceAndEightFrames() {
        XCTAssertEqual(
            PlaybackTimelinePreviewConfiguration(isLowPowerModeEnabled: false).debounce,
            .milliseconds(250)
        )
        XCTAssertEqual(
            PlaybackTimelinePreviewConfiguration(isLowPowerModeEnabled: false).maximumFrameCount,
            24
        )
        XCTAssertEqual(
            PlaybackTimelinePreviewConfiguration(isLowPowerModeEnabled: true).debounce,
            .milliseconds(500)
        )
        XCTAssertEqual(
            PlaybackTimelinePreviewConfiguration(isLowPowerModeEnabled: true).maximumFrameCount,
            8
        )
    }
}
