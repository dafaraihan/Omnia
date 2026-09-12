import XCTest
@testable import Omnia
#if os(macOS)
import AppKit
#endif

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
    func testMacSettingsUsesWideGroupedCardsAndNeutralInteractionColors() {
        XCTAssertEqual(MacSettingsPresentation.containerStyle, .groupedCards)
        XCTAssertEqual(
            MacSettingsPresentation.symbolTreatment(isHovered: false, isPressed: false),
            .whiteMonochrome
        )
        XCTAssertEqual(
            MacSettingsPresentation.symbolTreatment(isHovered: true, isPressed: false),
            .whiteMonochrome
        )
        XCTAssertEqual(
            MacSettingsPresentation.symbolTreatment(isHovered: false, isPressed: true),
            .whiteMonochrome
        )
        XCTAssertEqual(MacSettingsPresentation.hoverTreatment, .neutralGray)
        XCTAssertEqual(MacSettingsPresentation.pressedTreatment, .neutralGray)
    }

    @MainActor
    func testMacSettingsUsesTheSameNativeToolbarSearchInBothNavigationStyles() {
        XCTAssertEqual(
            MacSettingsPresentation.searchPlacement(for: .sidebar),
            .toolbar
        )
        XCTAssertEqual(
            MacSettingsPresentation.searchPlacement(for: .topBar),
            .toolbar
        )
    }

    @MainActor
    func testMacSettingsToolbarSearchBoundsUnexpectedExpansion() {
        XCTAssertEqual(MacSettingsPresentation.searchWidth(proposedWidth: 240), 240)
        XCTAssertEqual(MacSettingsPresentation.searchWidth(proposedWidth: 900), 320)
    }

    @MainActor
    func testMacSettingsLimitsTheNativeSearchItemWithoutReplacingIt() {
        let searchItem = NSSearchToolbarItem(
            itemIdentifier: NSToolbarItem.Identifier("settings-search")
        )
        let nativeSearchField = searchItem.searchField

        MacSettingsPresentation.limitWidth(of: searchItem, to: 320)

        XCTAssertTrue(searchItem.searchField === nativeSearchField)
        XCTAssertEqual(searchItem.preferredWidthForSearchField, 320)
        let widthConstraint = searchItem.searchField.constraints.first(where: {
            $0.identifier == "Omnia.SettingsSearch.MaximumWidth"
        })
        XCTAssertEqual(widthConstraint?.relation, .lessThanOrEqual)
        XCTAssertEqual(widthConstraint?.constant, 320)
    }
    #endif
}
