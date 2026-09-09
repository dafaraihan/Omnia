import XCTest
@testable import Omnia

final class ResumeProgressPresentationTests: XCTestCase {
    func testSeriesPlayTargetsFirstEpisodeFromBeginning() throws {
        let episodes = [episode(season: 2, number: 1), episode(season: 1, number: 1)]

        let intent = MediaDetailPlaybackIntent(
            displayItem: item(id: "series", kind: .series),
            persistedItem: nil,
            episodes: episodes
        )

        XCTAssertEqual(intent.title, "Play")
        XCTAssertEqual(intent.episode, episode(season: 1, number: 1))
        XCTAssertNil(intent.resumeAt)
    }

    func testSeriesPlayStillTargetsS1E1BeforeDetailEpisodesFinishLoading() throws {
        let intent = MediaDetailPlaybackIntent(
            displayItem: item(id: "series", kind: .series),
            persistedItem: nil,
            episodes: []
        )

        XCTAssertEqual(intent.episode?.seasonNumber, 1)
        XCTAssertEqual(intent.episode?.episodeNumber, 1)
        XCTAssertNil(intent.resumeAt)
    }

    func testSeriesRewatchTargetsFirstEpisodeFromBeginning() throws {
        let episodes = [episode(season: 2, number: 1), episode(season: 1, number: 1)]
        let completed = item(
            id: "series",
            kind: .series,
            progress: nil,
            positionSeconds: 2_400,
            durationSeconds: 2_400,
            resumeSeasonNumber: 2,
            resumeEpisodeNumber: 4
        )

        let intent = MediaDetailPlaybackIntent(
            displayItem: item(id: "series", kind: .series),
            persistedItem: completed,
            episodes: episodes
        )

        XCTAssertEqual(intent.title, "Rewatch")
        XCTAssertEqual(intent.episode, episode(season: 1, number: 1))
        XCTAssertNil(intent.resumeAt)
    }

    func testSeriesResumeTargetsSavedEpisodeAndTimestamp() throws {
        let savedEpisode = episode(season: 3, number: 7)
        let partial = item(
            id: "series",
            kind: .series,
            progress: 0.5,
            positionSeconds: 1_200,
            durationSeconds: 2_400,
            resumeEpisodeID: savedEpisode.id,
            resumeSeasonNumber: 3,
            resumeEpisodeNumber: 7
        )

        let intent = MediaDetailPlaybackIntent(
            displayItem: item(id: "series", kind: .series),
            persistedItem: partial,
            episodes: [episode(season: 1, number: 1), savedEpisode]
        )

        XCTAssertEqual(intent.title, "Resume")
        XCTAssertEqual(intent.episode, savedEpisode)
        XCTAssertEqual(intent.resumeAt, 1_200)
    }

    func testMoviePlayAndRewatchStartFromBeginningWhileResumeUsesSavedTimestamp() {
        let display = item(id: "movie", kind: .movie)
        let play = MediaDetailPlaybackIntent(displayItem: display, persistedItem: nil, episodes: [])
        let rewatch = MediaDetailPlaybackIntent(
            displayItem: display,
            persistedItem: item(
                id: "movie",
                kind: .movie,
                progress: nil,
                positionSeconds: 7_200,
                durationSeconds: 7_200
            ),
            episodes: []
        )
        let resume = MediaDetailPlaybackIntent(
            displayItem: display,
            persistedItem: item(
                id: "movie",
                kind: .movie,
                progress: 0.5,
                positionSeconds: 3_600,
                durationSeconds: 7_200
            ),
            episodes: []
        )

        XCTAssertEqual(play.title, "Play")
        XCTAssertNil(play.episode)
        XCTAssertNil(play.resumeAt)
        XCTAssertEqual(rewatch.title, "Rewatch")
        XCTAssertNil(rewatch.episode)
        XCTAssertNil(rewatch.resumeAt)
        XCTAssertEqual(resume.title, "Resume")
        XCTAssertNil(resume.episode)
        XCTAssertEqual(resume.resumeAt, 3_600)
    }

    func testSeriesResumeUsesEpisodeIdentifierInsteadOfRemainingTime() throws {
        let item = MediaItem(
            id: "series",
            title: "Series",
            year: "2026",
            kind: .series,
            overview: "",
            genres: [],
            symbol: "tv",
            artworkColors: [.black],
            progress: 0.25,
            positionSeconds: 900,
            durationSeconds: 3_600,
            resumeEpisodeID: "series:2:4",
            resumeSeasonNumber: 2,
            resumeEpisodeNumber: 4
        )

        let presentation = try XCTUnwrap(ResumeProgressPresentation(item: item))

        XCTAssertEqual(presentation.progress, 0.25)
        XCTAssertEqual(presentation.heroMetadataText, "S2E4")
        XCTAssertEqual(presentation.continueWatchingMetadataText, "S2E4  •  45m left")
    }

    func testMovieResumeUsesRemainingTimeInsteadOfEpisodeIdentifier() throws {
        let item = MediaItem(
            id: "movie",
            title: "Movie",
            year: "2026",
            kind: .movie,
            overview: "",
            genres: [],
            symbol: "film",
            artworkColors: [.black],
            progress: 0.5,
            positionSeconds: 3_600,
            durationSeconds: 7_200
        )

        let presentation = try XCTUnwrap(ResumeProgressPresentation(item: item))

        XCTAssertEqual(presentation.heroMetadataText, "1h left")
        XCTAssertEqual(presentation.continueWatchingMetadataText, "1h left")
    }

    func testEpisodeProgressAppearsOnlyOnThePersistedResumeEpisode() throws {
        let item = MediaItem(
            id: "series",
            title: "Series",
            year: "2026",
            kind: .series,
            overview: "",
            genres: [],
            symbol: "tv",
            artworkColors: [.black],
            progress: 0.5,
            positionSeconds: 1_200,
            durationSeconds: 2_400,
            resumeEpisodeID: "series:3:7",
            resumeSeasonNumber: 3,
            resumeEpisodeNumber: 7
        )
        let matchingEpisode = MediaEpisode(
            id: "series:3:7",
            seasonNumber: 3,
            episodeNumber: 7,
            title: "Seven",
            overview: "",
            runtimeMinutes: 40,
            stillURL: nil,
            airDate: nil
        )
        let otherEpisode = MediaEpisode(
            id: "series:3:8",
            seasonNumber: 3,
            episodeNumber: 8,
            title: "Eight",
            overview: "",
            runtimeMinutes: 40,
            stillURL: nil,
            airDate: nil
        )
        let presentation = try XCTUnwrap(ResumeProgressPresentation(item: item))

        XCTAssertTrue(presentation.matches(matchingEpisode))
        XCTAssertFalse(presentation.matches(otherEpisode))
        XCTAssertEqual(presentation.remainingText, "20m left")
    }

    func testPlayAndRewatchStatesDoNotProduceResumeProgress() {
        let playItem = MediaItem(
            id: "play",
            title: "Play",
            year: "2026",
            kind: .movie,
            overview: "",
            genres: [],
            symbol: "film",
            artworkColors: [.black],
            progress: nil
        )
        let rewatchItem = MediaItem(
            id: "rewatch",
            title: "Rewatch",
            year: "2026",
            kind: .movie,
            overview: "",
            genres: [],
            symbol: "film",
            artworkColors: [.black],
            progress: nil,
            positionSeconds: 7_200,
            durationSeconds: 7_200
        )

        XCTAssertNil(ResumeProgressPresentation(item: playItem))
        XCTAssertNil(ResumeProgressPresentation(item: rewatchItem))
    }

    private func item(
        id: String,
        kind: MediaItem.Kind,
        progress: Double? = nil,
        positionSeconds: Double? = nil,
        durationSeconds: Double? = nil,
        resumeEpisodeID: String? = nil,
        resumeSeasonNumber: Int? = nil,
        resumeEpisodeNumber: Int? = nil
    ) -> MediaItem {
        MediaItem(
            id: id,
            title: "Title",
            year: "2026",
            kind: kind,
            overview: "",
            genres: [],
            symbol: kind == .movie ? "film" : "tv",
            artworkColors: [.black],
            progress: progress,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds,
            resumeEpisodeID: resumeEpisodeID,
            resumeSeasonNumber: resumeSeasonNumber,
            resumeEpisodeNumber: resumeEpisodeNumber
        )
    }

    private func episode(season: Int, number: Int) -> MediaEpisode {
        MediaEpisode(
            id: "series:\(season):\(number)",
            seasonNumber: season,
            episodeNumber: number,
            title: "Episode \(number)",
            overview: "",
            runtimeMinutes: 40,
            stillURL: nil,
            airDate: nil
        )
    }
}
