import XCTest
@testable import Omnia

final class PlaybackMediaSelectionPolicyTests: XCTestCase {
    func testFollowSystemLeavesSelectionToPlatformDefaults() {
        let policy = PlaybackMediaSelectionPolicy.resolve(
            preferences: .default,
            isAnime: false,
            systemLanguages: ["id-ID", "en-US"]
        )

        XCTAssertNil(policy.audioLanguages)
        XCTAssertNil(policy.subtitleLanguages)
        XCTAssertFalse(policy.disablesSubtitles)
        XCTAssertFalse(policy.prefersSDH)
    }

    func testExplicitLanguagesPreservePreferredThenFallbackOrder() {
        var preferences = SettingsPreferences.default
        preferences.preferredAudioLanguage = .language("id")
        preferences.audioFallbackLanguage = .language("en")
        preferences.preferredSubtitleLanguage = .language("en")
        preferences.subtitleFallbackLanguage = .language("id")
        preferences.sdhPreference = .prefer

        let policy = PlaybackMediaSelectionPolicy.resolve(
            preferences: preferences,
            isAnime: false,
            systemLanguages: ["ja-JP"]
        )

        XCTAssertEqual(policy.audioLanguages, ["id", "en"])
        XCTAssertEqual(policy.subtitleLanguages, ["en", "id"])
        XCTAssertTrue(policy.prefersSDH)
    }

    func testSubtitleOffProducesAnExplicitDisableDecision() {
        var preferences = SettingsPreferences.default
        preferences.preferredSubtitleLanguage = .none

        let policy = PlaybackMediaSelectionPolicy.resolve(
            preferences: preferences,
            isAnime: false,
            systemLanguages: ["en-US"]
        )

        XCTAssertTrue(policy.disablesSubtitles)
        XCTAssertEqual(policy.subtitleLanguages, [])
    }

    func testAnimeSubAndDubPoliciesAreDeterministic() {
        var preferences = SettingsPreferences.default
        preferences.preferredAudioLanguage = .language("id")
        preferences.preferredSubtitleLanguage = .language("en")
        preferences.animeAudioPreference = .sub

        let sub = PlaybackMediaSelectionPolicy.resolve(
            preferences: preferences,
            isAnime: true,
            systemLanguages: ["id-ID"]
        )
        XCTAssertEqual(sub.audioLanguages, ["ja", "id"])
        XCTAssertEqual(sub.subtitleLanguages, ["en"])
        XCTAssertFalse(sub.disablesSubtitles)

        preferences.animeAudioPreference = .dub
        let dub = PlaybackMediaSelectionPolicy.resolve(
            preferences: preferences,
            isAnime: true,
            systemLanguages: ["id-ID"]
        )
        XCTAssertEqual(dub.audioLanguages, ["id"])
        XCTAssertTrue(dub.disablesSubtitles)
    }

    func testResumeEpisodeUsesPersistedContextWhenDetailsAreUnavailable() throws {
        let item = MediaItem(
            id: "series",
            title: "Series",
            year: "2026",
            kind: .series,
            overview: "",
            genres: [],
            symbol: "tv",
            artworkColors: [],
            progress: 0.4,
            resumeEpisodeID: "episode-7",
            resumeSeasonNumber: 2,
            resumeEpisodeNumber: 7
        )

        let episode = try XCTUnwrap(item.resumeEpisode)
        XCTAssertEqual(episode.id, "episode-7")
        XCTAssertEqual(episode.seasonNumber, 2)
        XCTAssertEqual(episode.episodeNumber, 7)
    }
}
