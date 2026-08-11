import XCTest
@testable import Omnia

final class SettingsPresentationTests: XCTestCase {
    func testFilteringPreservesApprovedSectionAndRouteOrder() {
        let groups = SettingsRoute.filteredRootGroups(query: "video")

        XCTAssertEqual(groups.map(\.section), [.playback])
        XCTAssertEqual(groups.flatMap(\.routes), [.videoPlayer])
    }

    func testAccountProvidersRemainAppleGoogleFacebook() {
        XCTAssertEqual(OmniaAccount.Provider.allCases, [.apple, .google, .facebook])
    }

    func testAppearanceChoicesRemainSystemLightDark() {
        XCTAssertEqual(AppAppearance.allCases, [.system, .light, .dark])
    }

    func testVideoPlayerNestedRoutesRemainDiscoverable() {
        XCTAssertEqual(SettingsRoute.subtitle.title, "Subtitle")
        XCTAssertEqual(SettingsRoute.playbackResolver.title, "Playback Resolver")
        XCTAssertTrue(SettingsRoute.playbackResolver.matches("approved HTTPS hosts"))
    }

    func testSearchMetadataDescribesOnlyApprovedSettings() {
        let terms = SettingsRoute.allVerificationRoutes
            .flatMap { [$0.title] + $0.searchTerms }
            .joined(separator: " ")
            .lowercased()

        XCTAssertTrue(terms.contains("skip intro"))
        XCTAssertTrue(terms.contains("subtitles"))
        XCTAssertTrue(terms.contains("up next"))
        XCTAssertTrue(terms.contains("local progress"))
        XCTAssertTrue(terms.contains("add-ons"))
        XCTAssertTrue(terms.contains("upcoming"))
        XCTAssertFalse(terms.contains("trakt"))
        XCTAssertFalse(terms.contains("publicmetadb"))
        XCTAssertFalse(terms.contains("external player"))
        XCTAssertFalse(terms.contains("translation"))
        XCTAssertFalse(terms.contains("cache mode"))
    }

    func testDependentVideoRowsExplainWhyTheyAreDisabled() {
        var preferences = SettingsPreferences.default
        preferences.showSkipIntro = false
        preferences.rememberLastSelection = false

        let model = VideoPlayerSettingsModel(preferences: preferences)

        XCTAssertFalse(model.isAutoSkipEnabled)
        XCTAssertNotNil(model.autoSkipDisabledExplanation)
        XCTAssertFalse(model.isRetentionEnabled)
        XCTAssertNotNil(model.retentionDisabledExplanation)
    }

    func testExcludedMetadataProvidersAreNotRegistered() {
        let providerIDs = Set(MetadataProvider.supported.map(\.id))
        XCTAssertFalse(providerIDs.contains("publicmetadb"))
    }

    #if os(macOS)
    func testMacSettingsLayoutCapsWideContentAtReadableWidth() {
        XCTAssertEqual(MacSettingsLayout.contentWidth(for: 1_800), 680)
    }

    func testMacSettingsLayoutPreservesMarginsInNarrowWindow() {
        XCTAssertEqual(MacSettingsLayout.contentWidth(for: 600), 552)
        XCTAssertEqual(MacSettingsLayout.contentWidth(for: 40), 0)
    }
    #endif
}
