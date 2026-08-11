import XCTest
@testable import Omnia

@MainActor
final class UpcomingServiceTests: XCTestCase {
    func testFiltersToInclusiveWindowDeduplicatesAndOrders() async {
        let now = ISO8601DateFormatter().date(from: "2026-08-11T04:00:00Z")!
        let item = series(
            episodes: [
                episode(id: "late", number: 3, airDate: "2026-08-20"),
                episode(id: "today", number: 1, airDate: "2026-08-11"),
                episode(id: "duplicate", number: 1, airDate: "2026-08-11"),
                episode(id: "outside", number: 4, airDate: "2026-09-20"),
                episode(id: "bad", number: 5, airDate: "soon")
            ]
        )
        let service = UpcomingService(now: { now }, calendar: jakartaCalendar)

        let result = await service.load(savedItems: [item], lookAheadDays: 30, itemLimit: nil)

        XCTAssertEqual(result.items.map(\.episode.id), ["today", "late"])
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertFalse(result.isStale)
    }

    func testUsesResolverForMissingDetailsAndReportsPartialFailure() async {
        let now = ISO8601DateFormatter().date(from: "2026-08-11T04:00:00Z")!
        let cached = series(id: "cached", episodes: [episode(id: "cached-1", number: 1, airDate: "2026-08-12")])
        let missing = series(id: "missing", episodes: [])
        let service = UpcomingService(now: { now }, calendar: jakartaCalendar) { item in
            if item.id == "missing" { throw UpcomingServiceError.metadataUnavailable }
            return item
        }

        let result = await service.load(savedItems: [cached, missing], lookAheadDays: 7, itemLimit: 1)

        XCTAssertEqual(result.items.map(\.episode.id), ["cached-1"])
        XCTAssertEqual(result.failures, ["missing"])
    }

    private var jakartaCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return calendar
    }

    private func series(id: String = "series", episodes: [MediaEpisode]) -> MediaItem {
        MediaItem(
            id: id,
            title: id.capitalized,
            year: "2026",
            kind: .series,
            overview: "",
            genres: [],
            symbol: "tv",
            artworkColors: [],
            details: MediaTitleDetails(
                ageRating: nil, runtimeMinutes: nil, status: nil, budget: nil, revenue: nil,
                studios: [], cast: [], crew: [], studioTitles: [], collection: nil,
                recommendations: [],
                seasons: [MediaSeason(id: "s1", seasonNumber: 1, title: "Season 1", overview: nil, posterURL: nil, episodes: episodes)],
                trailers: [], bonusContent: []
            ),
            progress: nil
        )
    }

    private func episode(id: String, number: Int, airDate: String) -> MediaEpisode {
        MediaEpisode(
            id: id,
            seasonNumber: 1,
            episodeNumber: number,
            title: "Episode \(number)",
            overview: "",
            runtimeMinutes: nil,
            stillURL: nil,
            airDate: airDate
        )
    }
}
