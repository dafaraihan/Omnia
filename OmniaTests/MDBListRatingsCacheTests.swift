import XCTest
@testable import Omnia

final class MDBListRatingsCacheTests: XCTestCase {
    func testSuccessfulAndAggregateOnlyResultsRemainFreshUntilThirtyMinutes() async throws {
        let clock = MDBListMutableClock(now: Date(timeIntervalSince1970: 1_000))
        let cache = MDBListRatingsCache(clock: clock)
        let counter = MDBListCallCounter()
        let aggregateOnly = MDBListTitleRatings(score: 8.4)

        let first = try await cache.value(for: .movieFixture) {
            await counter.increment()
            return aggregateOnly
        }
        clock.advance(by: 30 * 60 - 1)
        let second = try await cache.value(for: .movieFixture) {
            await counter.increment()
            return MDBListTitleRatings(score: 1)
        }

        XCTAssertEqual(first, aggregateOnly)
        XCTAssertEqual(second, aggregateOnly)
        let callCount = await counter.currentValue()
        XCTAssertEqual(callCount, 1)
    }

    func testEntryExpiresAtThirtyMinutes() async throws {
        let clock = MDBListMutableClock(now: Date(timeIntervalSince1970: 1_000))
        let cache = MDBListRatingsCache(clock: clock)
        let counter = MDBListCallCounter()

        _ = try await cache.value(for: .movieFixture) {
            let call = await counter.increment()
            return MDBListTitleRatings(score: Double(call))
        }
        clock.advance(by: 30 * 60)
        let refreshed = try await cache.value(for: .movieFixture) {
            let call = await counter.increment()
            return MDBListTitleRatings(score: Double(call))
        }

        XCTAssertEqual(refreshed?.score, 2)
        let callCount = await counter.currentValue()
        XCTAssertEqual(callCount, 2)
    }

    func testFailureIsNotCached() async throws {
        let cache = MDBListRatingsCache()
        let counter = MDBListCallCounter()

        do {
            _ = try await cache.value(for: .movieFixture) {
                await counter.increment()
                throw MDBListMetadataError.temporarilyUnavailable
            }
            XCTFail("Expected failure")
        } catch let error as MDBListMetadataError {
            XCTAssertEqual(error, .temporarilyUnavailable)
        }

        let recovered = try await cache.value(for: .movieFixture) {
            await counter.increment()
            return MDBListTitleRatings(score: 7.5)
        }
        XCTAssertEqual(recovered?.score, 7.5)
        let callCount = await counter.currentValue()
        XCTAssertEqual(callCount, 2)
    }

    func testBypassRefreshesAndReplacesFreshEntry() async throws {
        let cache = MDBListRatingsCache()
        _ = try await cache.value(for: .movieFixture) { MDBListTitleRatings(score: 4) }

        let refreshed = try await cache.value(for: .movieFixture, bypassCache: true) {
            MDBListTitleRatings(score: 9)
        }
        let cached = try await cache.value(for: .movieFixture) {
            MDBListTitleRatings(score: 1)
        }

        XCTAssertEqual(refreshed?.score, 9)
        XCTAssertEqual(cached?.score, 9)
    }

    func testConcurrentCallsForSameRouteCoalesce() async throws {
        let cache = MDBListRatingsCache()
        let gate = MDBListLoaderGate(result: MDBListTitleRatings(score: 8.8))

        async let first = cache.value(for: .movieFixture) { try await gate.load() }
        async let second = cache.value(for: .movieFixture) { try await gate.load() }
        await gate.waitForCalls(1)
        var callCount = await gate.currentCallCount()
        XCTAssertEqual(callCount, 1)
        await gate.releaseAll()

        let values = try await [first, second]
        XCTAssertEqual(values, [MDBListTitleRatings(score: 8.8), MDBListTitleRatings(score: 8.8)])
        callCount = await gate.currentCallCount()
        XCTAssertEqual(callCount, 1)
    }

    func testDifferentRoutesDoNotCoalesce() async throws {
        let cache = MDBListRatingsCache()
        let gate = MDBListLoaderGate(result: MDBListTitleRatings(score: 6))

        async let movie = cache.value(for: .movieFixture) { try await gate.load() }
        async let show = cache.value(for: .showFixture) { try await gate.load() }
        await gate.waitForCalls(2)
        let callCount = await gate.currentCallCount()
        XCTAssertEqual(callCount, 2)
        await gate.releaseAll()

        _ = try await [movie, show]
    }

    func testCancellingOneRouteCannotPublishIntoAnotherRoute() async throws {
        let cache = MDBListRatingsCache()
        let gate = MDBListLoaderGate(result: MDBListTitleRatings(score: 2))
        let cancelled = Task {
            try await cache.value(for: .movieFixture) { try await gate.load() }
        }
        await gate.waitForCalls(1)
        cancelled.cancel()

        let show = try await cache.value(for: .showFixture) {
            MDBListTitleRatings(score: 9)
        }
        await gate.releaseAll()
        _ = try? await cancelled.value
        let cachedShow = try await cache.value(for: .showFixture) {
            MDBListTitleRatings(score: 1)
        }

        XCTAssertEqual(show?.score, 9)
        XCTAssertEqual(cachedShow?.score, 9)
    }

    func testCacheKeyDescriptionCannotContainCredentialMaterial() {
        let description = String(reflecting: MDBListLookupRoute.movieFixture)

        XCTAssertTrue(description.contains("tmdb"))
        XCTAssertTrue(description.contains("movie"))
        XCTAssertTrue(description.contains("550"))
        XCTAssertFalse(description.contains("secret-api-key"))
    }
}

private extension MDBListLookupRoute {
    static let movieFixture = MDBListLookupRoute(
        provider: .tmdb,
        mediaType: .movie,
        identifier: "550"
    )
    static let showFixture = MDBListLookupRoute(
        provider: .tvdb,
        mediaType: .show,
        identifier: "81189"
    )
}

private final class MDBListMutableClock: ClockProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var storedNow: Date

    init(now: Date) {
        storedNow = now
    }

    var now: Date {
        lock.withLock { storedNow }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { storedNow.addTimeInterval(interval) }
    }
}

private actor MDBListCallCounter {
    private(set) var value = 0

    @discardableResult
    func increment() -> Int {
        value += 1
        return value
    }

    func currentValue() -> Int {
        value
    }
}

private actor MDBListLoaderGate {
    private(set) var callCount = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private let result: MDBListTitleRatings

    init(result: MDBListTitleRatings) {
        self.result = result
    }

    func load() async throws -> MDBListTitleRatings {
        callCount += 1
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
        try Task.checkCancellation()
        return result
    }

    func waitForCalls(_ expected: Int) async {
        while callCount < expected {
            await Task.yield()
        }
    }

    func currentCallCount() -> Int {
        callCount
    }

    func releaseAll() {
        let waiting = continuations
        continuations.removeAll()
        waiting.forEach { $0.resume() }
    }
}
