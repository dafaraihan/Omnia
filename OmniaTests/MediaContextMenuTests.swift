import XCTest
@testable import Omnia

final class MediaContextMenuTests: XCTestCase {
    func testContextMenuUsesWhiteSymbolsWithNativeBlueSelection() {
        XCTAssertEqual(MediaContextMenuPresentation.symbolTreatment, .white)
        XCTAssertEqual(MediaContextMenuPresentation.selectionTreatment, .nativeBlue)
    }

    func testContinueWatchingMovieCommandsMatchAppleTVOrder() {
        XCTAssertEqual(
            MediaContextMenuPresentation.commands(kind: .movie, placement: .continueWatching),
            [
                .goToMovie,
                .separator,
                .markWatched,
                .markUnwatched,
                .removeWatchProgress,
            ]
        )
    }

    func testContinueWatchingSeriesCommandsMatchAppleTVOrder() {
        XCTAssertEqual(
            MediaContextMenuPresentation.commands(kind: .series, placement: .continueWatching),
            [
                .goToShow,
                .separator,
                .markWatched,
                .markUnwatched,
                .seasonWatched,
                .seasonUnwatched,
                .revertToPreviousEpisode,
                .episodesThroughHereWatched,
                .episodesThroughHereUnwatched,
            ]
        )
    }

    func testBrowseMovieShowsBothLibraryCommands() {
        XCTAssertEqual(
            MediaContextMenuPresentation.commands(kind: .movie, placement: .browse),
            [.goToMovie, .addToWatchlist, .removeFromWatchlist]
        )
    }

    func testBrowseSeriesShowsBothLibraryCommands() {
        XCTAssertEqual(
            MediaContextMenuPresentation.commands(kind: .series, placement: .browse),
            [.goToShow, .addToWatchlist, .removeFromWatchlist]
        )
    }

    @MainActor
    func testLibraryMenuActionsAreIdempotent() {
        let item = MediaItem.previewLibrary[0]
        let store = OmniaStore(library: [], installedAddons: [])

        store.setSaved(item, isIncluded: true)
        store.setSaved(item, isIncluded: true)
        XCTAssertTrue(store.isSaved(item))
        XCTAssertEqual(store.library.filter { $0.id == item.id }.count, 1)

        store.setSaved(item, isIncluded: false)
        store.setSaved(item, isIncluded: false)
        XCTAssertFalse(store.isSaved(item))
    }

    @MainActor
    func testInMemoryWatchMenuActionsUpdateObservableState() {
        let item = MediaItem.previewLibrary[0]
        let store = OmniaStore(library: [item], installedAddons: [])

        store.applyWatchCommand(.markMovie(watched: true), to: item, episodes: [])

        XCTAssertEqual(store.watchState(for: item).movieWatched, true)
        XCTAssertNil(store.library.first(where: { $0.id == item.id })?.progress)
    }

    func testDetailWatchActionUsesEyeToMarkUnwatchedTitlesWatched() {
        let episode = MediaEpisode(
            id: "series:1:2",
            seasonNumber: 1,
            episodeNumber: 2,
            title: "Two",
            overview: "",
            runtimeMinutes: 42,
            stillURL: nil,
            airDate: nil
        )

        let movieAction = MediaDetailWatchActionPresentation.action(
            kind: .movie,
            currentEpisode: nil,
            watchState: .empty
        )
        XCTAssertEqual(movieAction?.systemImage, "eye")
        XCTAssertEqual(movieAction?.accessibilityLabel, "Mark as Watched")
        XCTAssertEqual(movieAction?.command, .markMovie(watched: true))

        let episodeAction = MediaDetailWatchActionPresentation.action(
            kind: .series,
            currentEpisode: episode,
            watchState: .empty
        )
        XCTAssertEqual(episodeAction?.systemImage, "eye")
        XCTAssertEqual(episodeAction?.command, .markEpisode(episode, watched: true))
        XCTAssertNil(
            MediaDetailWatchActionPresentation.action(
                kind: .series,
                currentEpisode: nil,
                watchState: .empty
            )
        )
    }

    func testDetailWatchActionUsesEyeSlashToMarkWatchedTitlesUnwatched() {
        let episode = MediaEpisode(
            id: "series:1:2",
            seasonNumber: 1,
            episodeNumber: 2,
            title: "Two",
            overview: "",
            runtimeMinutes: 42,
            stillURL: nil,
            airDate: nil
        )
        var watchState = LocalMediaWatchState(movieWatched: true)
        watchState.setWatched(true, for: episode)

        let movieAction = MediaDetailWatchActionPresentation.action(
            kind: .movie,
            currentEpisode: nil,
            watchState: watchState
        )
        XCTAssertEqual(movieAction?.systemImage, "eye.slash")
        XCTAssertEqual(movieAction?.accessibilityLabel, "Mark as Unwatched")
        XCTAssertEqual(movieAction?.command, .markMovie(watched: false))

        let episodeAction = MediaDetailWatchActionPresentation.action(
            kind: .series,
            currentEpisode: episode,
            watchState: watchState
        )
        XCTAssertEqual(episodeAction?.systemImage, "eye.slash")
        XCTAssertEqual(episodeAction?.command, .markEpisode(episode, watched: false))
    }

    @MainActor
    func testRemovingProgressPreservesUnsavedWatchHistory() {
        var item = MediaItem.previewLibrary[0]
        item.progress = nil
        let store = OmniaStore(library: [item], installedAddons: [])
        store.applyWatchCommand(.markMovie(watched: true), to: item, episodes: [])
        store.setSaved(item, isIncluded: false)
        store.recordPlayback(
            for: item,
            positionSeconds: 120,
            durationSeconds: 1_200
        )
        XCTAssertEqual(
            store.localMediaSnapshots.first(where: { $0.mediaID == item.id })?.progress,
            0.1
        )

        store.removeFromContinueWatching(item)

        XCTAssertFalse(store.isSaved(item))
        XCTAssertEqual(store.watchState(for: item).movieWatched, true)
        XCTAssertNil(store.localMediaSnapshots.first(where: { $0.mediaID == item.id })?.progress)
    }
}
