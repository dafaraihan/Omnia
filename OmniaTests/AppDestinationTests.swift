import XCTest
@testable import Omnia

final class AppDestinationTests: XCTestCase {
    func testMacPrimaryNavigationMovesAnimeUnderSearch() {
        XCTAssertEqual(
            AppDestination.visibleDestinations(for: .mac),
            [.home, .library, .discover, .search, .settings]
        )
    }

    func testMobilePrimaryNavigationMovesAnimeUnderSearch() {
        XCTAssertEqual(
            AppDestination.visibleDestinations(for: .mobile),
            [.home, .library, .discover, .search, .settings]
        )
    }

    func testMacTopBarKeepsSearchInTheDedicatedTrailingPosition() {
        XCTAssertEqual(
            AppDestination.macTopBarDestinations,
            [.home, .library, .discover, .settings, .search]
        )
    }

    #if os(macOS)
    @MainActor
    func testMacTopBarSearchPresentsWithoutReplacingTheCurrentDestination() {
        let navigation = MacPrimaryNavigationState(selection: .home)

        navigation.selectFromTopBar(.search)

        XCTAssertEqual(navigation.selection, .home)
        XCTAssertTrue(navigation.isSearchPresented)
    }

    @MainActor
    func testMacTopBarDestinationSelectionDismissesSearch() {
        let navigation = MacPrimaryNavigationState(selection: .home)
        navigation.selectFromTopBar(.search)

        navigation.selectFromTopBar(.library)

        XCTAssertEqual(navigation.selection, .library)
        XCTAssertFalse(navigation.isSearchPresented)
    }

    @MainActor
    func testSwitchingToTopBarTurnsAFullPageSearchIntoThePopover() {
        let navigation = MacPrimaryNavigationState(selection: .library)
        navigation.select(.search)

        navigation.activateTopBar()

        XCTAssertEqual(navigation.selection, .library)
        XCTAssertTrue(navigation.isSearchPresented)
    }
    #endif

    func testSearchAndSettingsSuppressTheWindowHeroBackdrop() {
        XCTAssertTrue(AppDestination.home.allowsWindowHeroBackdrop)
        XCTAssertTrue(AppDestination.library.allowsWindowHeroBackdrop)
        XCTAssertTrue(AppDestination.discover.allowsWindowHeroBackdrop)
        XCTAssertFalse(AppDestination.search.allowsWindowHeroBackdrop)
        XCTAssertFalse(AppDestination.settings.allowsWindowHeroBackdrop)
    }

    func testSidebarUsesOutlinedSFSymbols() {
        XCTAssertEqual(AppDestination.home.symbolName, "house")
        XCTAssertEqual(AppDestination.library.symbolName, "rectangle.stack")
        XCTAssertEqual(AppDestination.discover.symbolName, "bag")
        XCTAssertEqual(AppDestination.search.symbolName, "magnifyingglass")
        XCTAssertEqual(AppDestination.settings.symbolName, "gearshape")
    }

    func testMacSidebarSeparatesNeutralSelectionFromAppleBlueSymbol() {
        XCTAssertEqual(MacSidebarPresentation.selectionTint, .neutralGray)
        XCTAssertEqual(
            MacSidebarPresentation.rowTreatment(
                for: .home,
                selection: .home,
                isHovered: false
            ),
            .neutralGray
        )
        XCTAssertEqual(
            MacSidebarPresentation.rowTreatment(
                for: .library,
                selection: .home,
                isHovered: true
            ),
            .neutralGray
        )
        XCTAssertEqual(
            MacSidebarPresentation.rowTreatment(
                for: .library,
                selection: .home,
                isHovered: false
            ),
            .clear
        )
        XCTAssertEqual(
            MacSidebarPresentation.symbolTreatment(for: .home, selection: .home),
            .appleBlue
        )
        XCTAssertEqual(
            MacSidebarPresentation.symbolTreatment(for: .library, selection: .home),
            .secondary
        )
    }

    func testMacSidebarHoverAndSelectionUseTheSameBackgroundBounds() {
        let selected = MacSidebarPresentation.backgroundOutset(
            for: .home,
            selection: .home,
            isHovered: false
        )
        let hovered = MacSidebarPresentation.backgroundOutset(
            for: .library,
            selection: .home,
            isHovered: true
        )

        XCTAssertEqual(selected, hovered)
        XCTAssertEqual(selected, CGSize(width: 7, height: 4))
    }

    #if os(macOS)
    @MainActor
    func testChangingPrimaryDestinationRebuildsItsNavigationStack() {
        let navigation = MacPrimaryNavigationState(selection: .library)

        navigation.select(.discover)

        XCTAssertEqual(navigation.selection, .discover)
        XCTAssertEqual(navigation.stackIdentity, .discover)
    }

    @MainActor
    func testSelectingCurrentPrimaryDestinationDoesNotRebuildItsNavigationStack() {
        let navigation = MacPrimaryNavigationState(selection: .library)

        navigation.select(.library)

        XCTAssertEqual(navigation.stackIdentity, .library)
    }
    #endif
}
