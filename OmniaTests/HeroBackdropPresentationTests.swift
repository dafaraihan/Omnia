import XCTest
@testable import Omnia

@MainActor
final class HeroBackdropPresentationTests: XCTestCase {
    func testMacOSUsesOneWindowOwnedHeroArtworkLayerThatTracksTheScrollHero() {
        XCTAssertEqual(HeroBackdropPresentation.artworkPlacement, .windowTracked)
        XCTAssertFalse(HeroBackdropPresentation.drawsLocalHeroArtwork)
    }

    #if os(macOS)
    func testWindowHeroExtendsBehindSidebarWithoutChangingMeasuredScrollGeometry() {
        let measuredHeroFrame = CGRect(x: 220, y: -96, width: 1_580, height: 820)

        let frame = WindowHeroBackdropLayout.artworkFrame(
            windowWidth: 1_800,
            measuredHeroFrame: measuredHeroFrame
        )

        XCTAssertEqual(frame, CGRect(x: 0, y: -96, width: 1_800, height: 820))
    }

    func testWindowAccentBeginsAtTrackedHeroBottom() {
        let measuredHeroFrame = CGRect(x: 220, y: -96, width: 1_580, height: 820)

        let frame = WindowHeroBackdropLayout.accentFrame(
            windowSize: CGSize(width: 1_800, height: 1_100),
            measuredHeroFrame: measuredHeroFrame
        )

        XCTAssertEqual(frame, CGRect(x: 0, y: 724, width: 1_800, height: 376))
    }

    #endif

    func testContentBelowHeroUsesArtworkAccent() {
        XCTAssertTrue(HeroBackdropPresentation.usesArtworkAccentBelowHero)
    }

    func testDetailBackdropRetainsPriorityOverHomeCarouselUpdates() {
        let home = item(id: "home", title: "Home")
        let nextHome = item(id: "next-home", title: "Next Home")
        let detail = item(id: "detail", title: "Detail")
        let state = HeroBackdropState()

        state.report(home, frame: .zero, from: .home)
        state.report(detail, frame: .zero, from: .detail)
        state.report(nextHome, frame: .zero, from: .home)

        XCTAssertEqual(state.presentation?.item.id, detail.id)

        state.clear(.detail)

        XCTAssertEqual(state.presentation?.item.id, nextHome.id)
    }

    func testDetailHeroKeepsOneArtworkResourceWhileMetadataLoads() {
        let initial = item(
            id: "catalog:detail",
            title: "Detail",
            backdropURL: URL(string: "https://example.com/catalog-backdrop.jpg")
        )
        let resolved = item(
            id: "provider:resolved-detail",
            title: "Detail",
            backdropURL: URL(string: "https://example.com/resolved-backdrop.jpg")
        )
        let state = HeroBackdropState()

        state.report(initial, frame: CGRect(x: 220, y: 0, width: 1_580, height: 820), from: .detail)
        state.report(resolved, frame: CGRect(x: 220, y: 0, width: 1_580, height: 820), from: .detail)

        XCTAssertEqual(state.presentation?.item.backdropURL, initial.backdropURL)
        XCTAssertEqual(state.presentation?.frame.height, 820)
    }

    func testHomeHeroDoesNotDiscardVisibleArtworkWhenMetadataOmitsBackdrop() {
        let initial = item(
            id: "catalog:home",
            title: "Home",
            backdropURL: URL(string: "https://example.com/catalog-backdrop.jpg")
        )
        let resolvedWithoutBackdrop = item(
            id: "catalog:home",
            title: "Home"
        )
        let state = HeroBackdropState()

        state.report(initial, frame: CGRect(x: 220, y: 0, width: 1_580, height: 820), from: .home)
        state.report(
            resolvedWithoutBackdrop,
            frame: CGRect(x: 220, y: 0, width: 1_580, height: 820),
            from: .home
        )

        XCTAssertEqual(state.presentation?.item.backdropURL, initial.backdropURL)
    }

    func testOutgoingCarouselViewCannotClearTheIncomingArtwork() {
        let state = HeroBackdropState()
        let outgoing = UUID()
        let incoming = UUID()
        state.report(item(id: "old", title: "Old"), frame: .zero, from: .home, owner: outgoing)
        state.report(item(id: "new", title: "New"), frame: .zero, from: .home, owner: incoming)

        state.clear(.home, owner: outgoing)

        XCTAssertEqual(state.presentation?.item.id, "new")
        state.clear(.home, owner: incoming)
        XCTAssertNil(state.presentation)
    }

    func testHomeSelectionHandlesRepeatedCatalogItemsAndKeepsSixUniqueTitles() {
        let items = (1...8).map { item(id: "\($0)", title: "Title \($0)") }
        let selection = HomeView.selectHeroCandidates(from: items + items)
        XCTAssertEqual(selection.map(\.id), ["1", "2", "3", "4", "5", "6"])
        XCTAssertTrue(HomeView.selectHeroCandidates(from: []).isEmpty)
    }

    func testMissingInitialArtworkCanBeFilledByMetadata() {
        let state = HeroBackdropState()
        let url = URL(string: "https://example.com/resolved.jpg")!
        for source in [HeroBackdropSource.home, .detail] {
            state.report(item(id: "same", title: "Same"), frame: .zero, from: source)
            state.report(item(id: "same", title: "Same", backdropURL: url), frame: .zero, from: source)
            XCTAssertEqual(state.presentation?.item.backdropURL, url)
            state.clear(source)
        }
    }

    private func item(id: String, title: String, backdropURL: URL? = nil) -> MediaItem {
        MediaItem(
            id: id,
            title: title,
            year: "2026",
            kind: .movie,
            overview: "",
            genres: [],
            symbol: "film",
            artworkColors: [.black],
            backdropURL: backdropURL,
            progress: nil
        )
    }
}
