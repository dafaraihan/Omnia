import XCTest
@testable import Omnia

final class PlaybackTrackTests: XCTestCase {
    func testTrackAvailabilityDistinguishesLoadingEmptyAndAvailable() {
        XCTAssertEqual(PlaybackTrackAvailability(isLoading: true, tracks: []), .loading)
        XCTAssertEqual(PlaybackTrackAvailability(isLoading: false, tracks: []), .empty)
        XCTAssertEqual(
            PlaybackTrackAvailability(isLoading: false, tracks: [
                PlaybackTrack(id: 1, title: nil, language: nil, codec: "aac", isSelected: true)
            ]),
            .available
        )
    }

    func testTrackDisplayNamePrefersTitleAndKeepsLanguageVisible() {
        let track = PlaybackTrack(
            id: 3,
            title: "Director Commentary",
            language: "eng",
            codec: "aac",
            isSelected: true
        )

        XCTAssertEqual(track.displayName, "Director Commentary · English")
    }

    func testTrackDisplayNameFallsBackToLanguageThenStableTrackNumber() {
        XCTAssertEqual(
            PlaybackTrack(id: 2, title: nil, language: "jpn", codec: nil, isSelected: false).displayName,
            "Japanese"
        )
        XCTAssertEqual(
            PlaybackTrack(id: 7, title: nil, language: nil, codec: nil, isSelected: false).displayName,
            "Track 7"
        )
    }
}
