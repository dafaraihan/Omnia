import XCTest
@testable import Omnia

final class IntroSegmentCacheTests: XCTestCase {
    func testPositiveAndNegativeEntriesUseDifferentExpiry() async throws {
        let clock = MutableDateClock(now: Date(timeIntervalSince1970: 1_000))
        let cache = IntroSegmentCache(clock: clock)
        let key = IntroSegmentKey(imdbID: "tt0903747", season: 1, episode: 1)
        let segment = SkipSegment(kind: .intro, startSeconds: 2, endSeconds: 58, confidence: 1)

        await cache.store([segment], for: key)
        clock.advance(by: 7 * 24 * 60 * 60 - 1)
        var value = await cache.value(for: key)
        XCTAssertNotNil(value)
        clock.advance(by: 2)
        value = await cache.value(for: key)
        XCTAssertNil(value)

        await cache.store([], for: key)
        clock.advance(by: 24 * 60 * 60 - 1)
        value = await cache.value(for: key)
        XCTAssertEqual(value, [])
        clock.advance(by: 2)
        value = await cache.value(for: key)
        XCTAssertNil(value)
    }

    func testOfflineFailureReturnsStaleCachedValueButCancellationDoesNot() async throws {
        let clock = MutableDateClock(now: Date(timeIntervalSince1970: 1_000))
        let cache = IntroSegmentCache(clock: clock)
        let key = IntroSegmentKey(imdbID: "tt0903747", season: 1, episode: 1)
        let segment = SkipSegment(kind: .intro, startSeconds: 2, endSeconds: 58, confidence: 1)
        await cache.store([segment], for: key)
        clock.advance(by: 8 * 24 * 60 * 60)

        let fallback = try await cache.segments(for: key) { throw URLError(.notConnectedToInternet) }
        XCTAssertEqual(fallback, [segment])
        await XCTAssertThrowsErrorAsync {
            _ = try await cache.segments(for: key) { throw CancellationError() }
        }
    }
}

private final class MutableDateClock: ClockProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var storedNow: Date

    init(now: Date) { storedNow = now }

    var now: Date {
        lock.withLock { storedNow }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { storedNow.addTimeInterval(interval) }
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {}
}
