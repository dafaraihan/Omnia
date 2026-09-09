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

    func testHomeShelfPreferencesPersistIndividualBuiltInCatalogChoices() {
        var preferences = HomeShelfPreferences(rawValue: "")
        preferences.setEnabled(false, for: .popularMovies)
        preferences.setEnabled(false, for: .airingToday)

        let restored = HomeShelfPreferences(rawValue: preferences.rawValue)

        XCTAssertFalse(restored.isEnabled(.popularMovies))
        XCTAssertFalse(restored.isEnabled(.airingToday))
        XCTAssertTrue(restored.isEnabled(.trendingMovies))
        XCTAssertEqual(BuiltInHomeShelf.allCases.count, 8)
    }

    func testHomeShelfPreferencesIgnoreUnknownPersistedIdentifiers() {
        let preferences = HomeShelfPreferences(rawValue: "popular-movies\nunknown-future-row")

        XCTAssertFalse(preferences.isEnabled(.popularMovies))
        XCTAssertEqual(preferences.rawValue, "popular-movies")
    }

    #if os(macOS)
    @MainActor
    func testMacSettingsLayoutExpandsRowsAcrossTheUsableDetailWidth() {
        let layout = MacSettingsLayout.presentation(for: 1_800)

        XCTAssertEqual(layout.leadingOffset, 24)
        XCTAssertEqual(layout.contentWidth, 1_752)
        XCTAssertEqual(layout.rowWidth, 1_752)
    }

    func testMacSettingsLayoutPreservesMarginsInNarrowWindow() {
        XCTAssertEqual(MacSettingsLayout.presentation(for: 600).rowWidth, 552)
        XCTAssertEqual(MacSettingsLayout.presentation(for: 40).rowWidth, 0)
    }

    @MainActor
    func testMacSettingsUsesWideGroupedCardsAndNativeInteractionColors() {
        XCTAssertEqual(MacSettingsPresentation.containerStyle, .groupedCards)
        XCTAssertEqual(
            MacSettingsPresentation.symbolTreatment(isHovered: false, isPressed: false),
            .whiteMonochrome
        )
        XCTAssertEqual(
            MacSettingsPresentation.symbolTreatment(isHovered: true, isPressed: false),
            .blueMonochrome
        )
        XCTAssertEqual(
            MacSettingsPresentation.symbolTreatment(isHovered: false, isPressed: true),
            .blueMonochrome
        )
        XCTAssertEqual(MacSettingsPresentation.hoverTreatment, .neutralGray)
        XCTAssertEqual(MacSettingsPresentation.pressedTreatment, .neutralGray)
    }
    #endif
}
