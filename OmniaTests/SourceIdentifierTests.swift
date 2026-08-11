import XCTest
@testable import Omnia

final class SourceIdentifierTests: XCTestCase {
    func testMergingProviderDetailsAddsIMDbBeforeProviderIdentifiers() {
        let catalogItem = makeItem(
            id: "tvdb-series-121361",
            externalIDs: ["tvdb": "121361"]
        )
        let enrichedItem = makeItem(
            id: "tvdb-series-121361",
            externalIDs: ["tvdb": "121361", "imdb": "tt0944947", "tmdb": "1399"]
        )

        let lookupItem = catalogItem.mergingSourceIdentifiers(from: enrichedItem)

        XCTAssertEqual(
            lookupItem.streamIdentifierCandidates,
            ["tt0944947", "tmdb:1399", "tvdb:121361", "tvdb-series-121361"]
        )
    }

    func testEpisodeLookupAddsSeasonAndEpisodeToEveryMergedIdentifier() {
        let item = makeItem(
            id: "tvdb-series-121361",
            externalIDs: ["tvdb": "121361"]
        ).mergingSourceIdentifiers(from: makeItem(
            id: "tvdb-series-121361",
            externalIDs: ["imdb": "tt0944947"]
        ))
        let episode = MediaEpisode(
            id: "episode-2",
            seasonNumber: 1,
            episodeNumber: 2,
            title: "Episode 2",
            overview: "",
            runtimeMinutes: nil,
            stillURL: nil,
            airDate: nil
        )

        XCTAssertEqual(
            item.streamIdentifierCandidates(for: episode),
            ["tt0944947:1:2", "tvdb:121361:1:2", "tvdb-series-121361:1:2"]
        )
    }

    private func makeItem(id: String, externalIDs: [String: String]) -> MediaItem {
        MediaItem(
            id: id,
            title: "Game of Thrones",
            year: "2011",
            kind: .series,
            overview: "",
            genres: [],
            symbol: "tv",
            artworkColors: [],
            metadataProvider: .tvdb,
            metadataProviderID: "121361",
            externalIDs: externalIDs,
            progress: nil
        )
    }
}
