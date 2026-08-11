import XCTest
@testable import Omnia

@MainActor
final class MDBListRatingsPresentationTests: XCTestCase {
    func testPresentationDeduplicatesFiltersOrdersAndKeepsAggregateLast() throws {
        let futureB = try XCTUnwrap(MDBListRatingProviderID("zeta_score"))
        let futureA = try XCTUnwrap(MDBListRatingProviderID("alpha_score"))
        let tomatoAlias = try XCTUnwrap(MDBListRatingProviderID("Rotten Tomatoes Critics"))
        let response = MDBListTitleRatings(
            score: 8.6,
            ratings: [
                MDBListRating(providerID: futureB, value: 9),
                MDBListRating(providerID: .imdb, value: 7.2),
                MDBListRating(providerID: tomatoAlias, value: 65),
                MDBListRating(providerID: .rottenTomatoes, value: 99, votes: 1_000_000),
                MDBListRating(providerID: .trakt, value: 78),
                MDBListRating(providerID: futureA, value: 4)
            ]
        )
        let preferences = MDBListRatingPreferences(disabledProviderIDs: ["trakt"])

        let presentation = MDBListRatingsPresentation(
            response: response,
            preferences: preferences
        )

        XCTAssertEqual(
            presentation.items.map(\.id),
            ["imdb", "tomatoes", "alpha_score", "zeta_score", "mdblist"]
        )
        XCTAssertEqual(presentation.items.map(\.formattedValue), ["7.2", "65%", "4", "9", "8.6"])
        XCTAssertEqual(
            presentation.discoveredProviderIDs,
            [.imdb, .rottenTomatoes, .trakt, futureA, futureB]
        )
    }

    func testDisabledExternalProvidersNeverHideAggregate() {
        let response = MDBListTitleRatings(
            score: 8,
            ratings: [MDBListRating(providerID: .imdb, value: 7)]
        )
        let preferences = MDBListRatingPreferences(disabledProviderIDs: ["imdb"])

        let presentation = MDBListRatingsPresentation(
            response: response,
            preferences: preferences
        )

        XCTAssertEqual(presentation.items.map(\.id), ["mdblist"])
        XCTAssertEqual(presentation.items.first?.accessibilityLabel, "MDBList, 8")
    }

    func testAggregateOnlyIsVisibleAndNoValuesIsEmpty() {
        let aggregateOnly = MDBListRatingsPresentation(
            response: MDBListTitleRatings(score: 7.4),
            preferences: .default
        )
        let empty = MDBListRatingsPresentation(
            response: MDBListTitleRatings(),
            preferences: .default
        )

        XCTAssertEqual(aggregateOnly.items.map(\.id), ["mdblist"])
        XCTAssertTrue(empty.items.isEmpty)
    }

    func testAccessibilityUsesFullProviderNameAndFormattedScale() {
        let presentation = MDBListRatingsPresentation(
            response: MDBListTitleRatings(ratings: [
                MDBListRating(providerID: .rottenTomatoesAudience, value: 91),
                MDBListRating(providerID: .myAnimeList, value: 8.2)
            ]),
            preferences: .default
        )

        XCTAssertEqual(
            presentation.items.map(\.accessibilityLabel),
            ["Rotten Tomatoes Audience, 91%", "MyAnimeList, 8.2"]
        )
    }

    func testPresentationSelectsValueDependentAndAggregateArtwork() {
        let presentation = MDBListRatingsPresentation(
            response: MDBListTitleRatings(
                score: 8.2,
                ratings: [
                    MDBListRating(providerID: .imdb, value: 7.4),
                    MDBListRating(providerID: .rottenTomatoes, value: 59),
                    MDBListRating(providerID: .rottenTomatoesAudience, value: 60)
                ]
            ),
            preferences: .default
        )

        XCTAssertEqual(
            presentation.items.map(\.assetName),
            [
                "RatingIMDbMark",
                "RatingRottenTomatoesRottenMark",
                "RatingRottenTomatoesAudienceHotMark",
                "RatingMDBListMark"
            ]
        )
    }

    func testUnknownProviderKeepsTextFallback() throws {
        let unknown = try XCTUnwrap(MDBListRatingProviderID("future_source"))
        let presentation = MDBListRatingsPresentation(
            response: MDBListTitleRatings(ratings: [
                MDBListRating(providerID: unknown, value: 8)
            ]),
            preferences: .default
        )

        XCTAssertNil(presentation.items.first?.assetName)
        XCTAssertEqual(presentation.items.first?.displayName, "Future Source")
    }

    func testSettingsUseDefaultArtworkForEveryKnownSourceAndAggregate() {
        let rows = MDBListRatingSettingsModel.rows(preferences: .default)

        XCTAssertEqual(
            rows.first { $0.id == "tomatoes" }?.assetName,
            "RatingRottenTomatoesFreshMark"
        )
        XCTAssertEqual(
            rows.first { $0.id == "popcorn" }?.assetName,
            "RatingRottenTomatoesAudienceHotMark"
        )
        XCTAssertEqual(rows.last?.assetName, "RatingMDBListMark")
    }

    func testMissingProvidersAreNotSynthesizedAsZero() {
        let presentation = MDBListRatingsPresentation(
            response: MDBListTitleRatings(ratings: [
                MDBListRating(providerID: .imdb, value: 6.8)
            ]),
            preferences: .default
        )

        XCTAssertEqual(presentation.items.map(\.id), ["imdb"])
        XCTAssertFalse(presentation.items.contains { $0.formattedValue == "0" })
    }

    func testSettingsRowsAlwaysIncludeKnownDiscoveredAndAggregateSources() throws {
        let preferences = MDBListRatingPreferences(
            discoveredProviderIDs: ["zeta_score", "alpha_score"],
            disabledProviderIDs: ["tmdb", "zeta_score"]
        )

        let rows = MDBListRatingSettingsModel.rows(preferences: preferences)

        XCTAssertEqual(
            rows.map(\.id),
            [
                "imdb", "tmdb", "tomatoes", "metacritic", "trakt", "letterboxd",
                "popcorn", "myanimelist", "rogerebert", "alpha_score", "zeta_score",
                "mdblist"
            ]
        )
        XCTAssertEqual(rows.first(where: { $0.id == "imdb" })?.isEnabled, true)
        XCTAssertEqual(rows.first(where: { $0.id == "tmdb" })?.isEnabled, false)
        XCTAssertEqual(rows.first(where: { $0.id == "zeta_score" })?.isEnabled, false)
        XCTAssertNil(rows.last?.isEnabled)
        XCTAssertEqual(rows.last?.detail, "Always shown")
    }

    func testLoaderTransitionsThroughLoadingToLoadedAndReportsDiscovery() async {
        let service = ControllableMDBListRatingService()
        let loader = MDBListRatingsLoader(service: service)
        let task = Task {
            await loader.load(for: Self.item(id: "a"), preferences: .default)
        }
        await service.waitForCallCount(1)
        XCTAssertEqual(loader.state, .loading)

        service.complete(
            id: "a",
            with: .success(MDBListTitleRatings(
                score: 8,
                ratings: [MDBListRating(providerID: .imdb, value: 7)]
            ))
        )
        await task.value

        guard case let .loaded(presentation) = loader.state else {
            return XCTFail("Expected loaded state")
        }
        XCTAssertEqual(presentation.items.map(\.id), ["imdb", "mdblist"])
        XCTAssertEqual(presentation.discoveredProviderIDs, [.imdb])
    }

    func testNotConfiguredNoIdentifierAndNotFoundBecomeEmpty() async {
        for result in [
            Result<MDBListTitleRatings?, Error>.success(nil),
            .failure(MDBListMetadataError.noSupportedIdentifier),
            .failure(MDBListMetadataError.notFound)
        ] {
            let service = ImmediateMDBListRatingService(result: result)
            let loader = MDBListRatingsLoader(service: service)
            await loader.load(for: Self.item(), preferences: .default)
            XCTAssertEqual(loader.state, .empty)
        }
    }

    func testFailuresExposeOnlyTheirSupportedRecoveryAction() async {
        let cases: [(MDBListMetadataError, MDBListRatingsRecoveryAction?)] = [
            (.authenticationRequired, .openSettings),
            (.rateLimited, nil),
            (.temporarilyUnavailable, .retry),
            (.malformedResponse, .retry),
            (.responseTooLarge, .retry)
        ]

        for (error, recovery) in cases {
            let loader = MDBListRatingsLoader(
                service: ImmediateMDBListRatingService(result: .failure(error))
            )
            await loader.load(for: Self.item(), preferences: .default)
            XCTAssertEqual(loader.state, .failed(error, recovery: recovery))
        }
    }

    func testRetryBypassesCacheAndIsIgnoredWhileLoading() async {
        let service = ControllableMDBListRatingService()
        let loader = MDBListRatingsLoader(service: service)
        let initial = Task {
            await loader.load(for: Self.item(id: "a"), preferences: .default)
        }
        await service.waitForCallCount(1)

        await loader.retry(for: Self.item(id: "a"), preferences: .default)
        XCTAssertEqual(service.calls.count, 1)
        service.complete(id: "a", with: .failure(MDBListMetadataError.temporarilyUnavailable))
        await initial.value

        let retry = Task {
            await loader.retry(for: Self.item(id: "a"), preferences: .default)
        }
        await service.waitForCallCount(2)
        XCTAssertEqual(service.calls.last?.bypassCache, true)
        service.complete(id: "a", with: .success(MDBListTitleRatings(score: 7)))
        await retry.value
        XCTAssertEqual(loader.state, .loaded(MDBListRatingsPresentation(
            response: MDBListTitleRatings(score: 7),
            preferences: .default
        )))
    }

    func testCancellationIsSilentAndLateTitleCannotReplaceNewerState() async {
        let service = ControllableMDBListRatingService()
        let loader = MDBListRatingsLoader(service: service)
        let first = Task {
            await loader.load(for: Self.item(id: "a"), preferences: .default)
        }
        await service.waitForCallCount(1)
        let second = Task {
            await loader.load(for: Self.item(id: "b"), preferences: .default)
        }
        await service.waitForCallCount(2)

        service.complete(id: "b", with: .success(MDBListTitleRatings(score: 9)))
        await second.value
        service.complete(id: "a", with: .success(MDBListTitleRatings(score: 1)))
        await first.value

        XCTAssertEqual(loader.state, .loaded(MDBListRatingsPresentation(
            response: MDBListTitleRatings(score: 9),
            preferences: .default
        )))

        let cancellation = Task {
            await loader.load(for: Self.item(id: "c"), preferences: .default)
        }
        await service.waitForCallCount(3)
        loader.cancel()
        service.complete(id: "c", with: .failure(CancellationError()))
        await cancellation.value
        XCTAssertNotEqual(loader.state, .failed(.temporarilyUnavailable, recovery: .retry))
    }

    private static func item(id: String = "fixture") -> MediaItem {
        MediaItem(
            id: id,
            title: "Fixture",
            year: "2026",
            kind: .movie,
            overview: "",
            genres: [],
            symbol: "film",
            artworkColors: [.clear],
            externalIDs: ["tmdb": "550"],
            progress: nil
        )
    }
}

@MainActor
private final class ImmediateMDBListRatingService: MDBListRatingServing {
    private let result: Result<MDBListTitleRatings?, Error>

    init(result: Result<MDBListTitleRatings?, Error>) {
        self.result = result
    }

    func titleRatings(
        for item: MediaItem,
        bypassCache: Bool
    ) async throws -> MDBListTitleRatings? {
        try result.get()
    }
}

@MainActor
private final class ControllableMDBListRatingService: MDBListRatingServing {
    struct Call: Equatable {
        let id: String
        let bypassCache: Bool
    }

    private(set) var calls: [Call] = []
    private var continuations: [String: CheckedContinuation<MDBListTitleRatings?, Error>] = [:]

    func titleRatings(
        for item: MediaItem,
        bypassCache: Bool
    ) async throws -> MDBListTitleRatings? {
        calls.append(Call(id: item.id, bypassCache: bypassCache))
        return try await withCheckedThrowingContinuation { continuation in
            continuations[item.id] = continuation
        }
    }

    func waitForCallCount(_ expected: Int) async {
        while calls.count < expected {
            await Task.yield()
        }
    }

    func complete(
        id: String,
        with result: Result<MDBListTitleRatings?, Error>
    ) {
        continuations.removeValue(forKey: id)?.resume(with: result)
    }
}
