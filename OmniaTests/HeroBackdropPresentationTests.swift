import XCTest
@testable import Omnia

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
        var state = HeroBackdropState()

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
        var state = HeroBackdropState()

        state.report(initial, frame: CGRect(x: 220, y: 0, width: 1_580, height: 820), from: .detail)
        state.report(resolved, frame: CGRect(x: 220, y: 0, width: 1_580, height: 820), from: .detail)

        XCTAssertEqual(state.presentation?.item.backdropURL, initial.backdropURL)
        XCTAssertEqual(state.presentation?.frame.height, 820)
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
