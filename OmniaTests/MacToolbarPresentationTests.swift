import XCTest
@testable import Omnia

#if os(macOS)
final class MacToolbarPresentationTests: XCTestCase {
    func testHomeAndDetailUseBlankNativeNavigationTitles() {
        XCTAssertEqual(MacToolbarPresentation.navigationTitle("Home", for: .home), "")
        XCTAssertEqual(MacToolbarPresentation.navigationTitle("Movie", for: .mediaDetail), "")
    }

    func testMainDestinationsKeepTheirNativeNavigationTitles() {
        XCTAssertTrue(MacToolbarPresentation.usesVisibleNativeWindowTitle)
        XCTAssertEqual(MacToolbarPresentation.navigationTitle("Library", for: .library), "Library")
        XCTAssertEqual(MacToolbarPresentation.navigationTitle("Discover", for: .discover), "Discover")
        XCTAssertEqual(MacToolbarPresentation.navigationTitle("Search", for: .search), "Search")
        XCTAssertEqual(MacToolbarPresentation.navigationTitle("Settings", for: .settings), "Settings")
    }

    func testDiscoverUsesOneNativeFilterMenu() {
        XCTAssertEqual(MacToolbarPresentation.discoverFilterButtonCount, 1)
    }

    func testDiscoverFilterMenuUsesTheApprovedNestedSections() {
        XCTAssertEqual(
            DiscoverFilterPresentation.menuSections,
            [.catalogs, .genre, .kind, .sort]
        )
    }

    func testPushedPageToolbarSeparatesPlainTitleFromNativeBackButton() {
        XCTAssertEqual(
            MacToolbarPresentation.pushedPageOrder,
            [.back, .fixedSpacer, .title]
        )
        XCTAssertEqual(
            MacToolbarPresentation.addonsPageOrder,
            [.back, .fixedSpacer, .title, .primaryAction]
        )
    }

    func testPlaybackDismissalRestoresTransparentBrowsingToolbar() {
        XCTAssertTrue(WindowChromePresentation.hidesToolbarDuringPlayback)
        XCTAssertTrue(WindowChromePresentation.hidesToolbarBackgroundDuringBrowsing)

        var restoration = WindowChromeRestorationState()
        XCTAssertFalse(restoration.update(isPlaybackPresented: false))
        XCTAssertFalse(restoration.update(isPlaybackPresented: true))
        XCTAssertTrue(restoration.update(isPlaybackPresented: false))
    }
}
#endif
