import XCTest
@testable import Omnia

@MainActor
final class PlaybackSourcePresentationTests: XCTestCase {
    func testEveryCandidateAppearsInExactlyOneSection() {
        let candidates = [
            fixture("direct", .nativeHTTPS(URL(string: "https://media.example/play")!)),
            fixture(
                "torrent",
                .resolverRequired(infoHash: String(repeating: "a", count: 40), fileIndex: 2)
            ),
            fixture("external", .externalHandoff(URL(string: "https://player.example/watch")!)),
            fixture("bad", .unsupported),
        ]

        let sections = PlaybackSourceSections(candidates: candidates)

        XCTAssertEqual(sections.direct.map(\.id), ["direct"])
        XCTAssertEqual(sections.resolverRequired.map(\.id), ["torrent"])
        XCTAssertEqual(sections.external.map(\.id), ["external"])
        XCTAssertEqual(sections.unavailable.map(\.id), ["bad"])
        XCTAssertEqual(sections.all.map(\.id), candidates.map(\.id))
    }

    func testDeliveryKindsExposeOnlySafeLocalActions() {
        let candidates = [
            fixture("direct", .nativeHTTPS(URL(string: "https://media.example/play")!)),
            fixture(
                "torrent",
                .resolverRequired(infoHash: String(repeating: "a", count: 40), fileIndex: 2)
            ),
            fixture("external", .externalHandoff(URL(string: "https://player.example/watch")!)),
            fixture("bad", .unsupported),
        ]

        XCTAssertEqual(PlaybackSourceRowState(candidate: candidates[0]).action, .playDirect)
        XCTAssertEqual(PlaybackSourceRowState(candidate: candidates[1]).action, .resolve)
        XCTAssertEqual(
            PlaybackSourceRowState(candidate: candidates[2]).action,
            .unavailable("External page—not locally resolved")
        )
        XCTAssertEqual(
            PlaybackSourceRowState(candidate: candidates[3]).action,
            .unavailable("Malformed or unsupported source")
        )
    }

    private func fixture(
        _ id: String,
        _ delivery: AddonStreamCandidate.Delivery
    ) -> AddonStreamCandidate {
        AddonStreamCandidate(
            id: id,
            addonID: "addon",
            addonName: "Addon",
            streamIdentifier: "tt123",
            displayName: id,
            displayDescription: nil,
            delivery: delivery,
            filename: nil,
            videoSize: nil,
            bingeGroup: nil,
            hasPeerDiscoveryHints: false,
            requestHeaders: [:]
        )
    }
}
