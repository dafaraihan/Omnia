import XCTest
@testable import Omnia

@MainActor
final class PlaybackSourcePresentationTests: XCTestCase {
    func testSourceResolutionKeepsSuccessfulRowsWhenAnotherAddonFails() {
        let direct = fixture("mediafusion", .nativeHTTPS(URL(string: "https://media.example/play")!))
        let torrent = fixture("torrentio", localTorrentDelivery())

        let resolution = PlaybackSourceResolution(
            addonResults: [
                AddonSourceResolution(
                    addonID: "mediafusion",
                    addonName: "MediaFusion",
                    candidates: [direct],
                    state: .loaded
                ),
                AddonSourceResolution(
                    addonID: "broken",
                    addonName: "Unavailable Add-on",
                    candidates: [],
                    state: .failed
                ),
                AddonSourceResolution(
                    addonID: "torrentio",
                    addonName: "Torrentio",
                    candidates: [torrent],
                    state: .loaded
                ),
            ],
            attemptedIdentifiers: ["tt123:1:1"]
        )

        XCTAssertEqual(resolution.candidates.map(\.id), ["mediafusion", "torrentio"])
        XCTAssertEqual(resolution.failedAddonResults.map(\.addonID), ["broken"])
        XCTAssertEqual(resolution.enabledAddonCount, 3)
    }

    func testRetryReplacementPreservesAddonOrderAndOtherCandidates() {
        let torrent = fixture("torrentio", localTorrentDelivery())
        let mediafusion = fixture(
            "mediafusion",
            .nativeHTTPS(URL(string: "https://media.example/retry")!)
        )
        let initial = PlaybackSourceResolution(
            addonResults: [
                AddonSourceResolution(
                    addonID: "mediafusion",
                    addonName: "MediaFusion",
                    candidates: [],
                    state: .failed
                ),
                AddonSourceResolution(
                    addonID: "torrentio",
                    addonName: "Torrentio",
                    candidates: [torrent],
                    state: .loaded
                ),
            ],
            attemptedIdentifiers: ["tt123:1:1"]
        )

        let retried = initial.replacingAddonResult(AddonSourceResolution(
            addonID: "mediafusion",
            addonName: "MediaFusion",
            candidates: [mediafusion],
            state: .loaded
        ))

        XCTAssertEqual(retried.addonResults.map(\.addonID), ["mediafusion", "torrentio"])
        XCTAssertEqual(retried.candidates.map(\.id), ["mediafusion", "torrentio"])
        XCTAssertTrue(retried.failedAddonResults.isEmpty)
    }

    func testEveryCandidateAppearsInExactlyOneSection() {
        let candidates = [
            fixture("direct", .nativeHTTPS(URL(string: "https://media.example/play")!)),
            fixture("torrent", localTorrentDelivery()),
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
            fixture("torrent", localTorrentDelivery()),
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

    func testISOHintsRequireExplicitDiscPreparationIncludingExtensionlessURL() {
        let extensionURL = fixture(
            "url-iso",
            .nativeHTTPS(URL(string: "https://media.example/movie.iso")!)
        )
        let extensionless = fixture(
            "filename-iso",
            .nativeHTTPS(URL(string: "https://media.example/download/opaque")!),
            filename: "Movie.ISO"
        )
        let opaque = fixture(
            "opaque",
            .nativeHTTPS(URL(string: "https://media.example/download/opaque")!)
        )
        let regularStream = fixture(
            "regular-stream",
            .nativeHTTPS(URL(string: "https://media.example/movie.mkv")!)
        )
        let unknownExtension = fixture(
            "unknown-extension",
            .nativeHTTPS(URL(string: "https://media.example/movie.avi")!)
        )

        XCTAssertEqual(PlaybackSourceRowState(candidate: extensionURL).action, .prepareDisc)
        XCTAssertEqual(
            PlaybackSourceRowState(candidate: extensionURL).idleStatus,
            "Prepare Blu-ray Disc · Downloads to local resolver cache"
        )
        XCTAssertEqual(PlaybackSourceRowState(candidate: extensionless).action, .prepareDisc)
        XCTAssertEqual(PlaybackSourceRowState(candidate: opaque).action, .playDirect)
        XCTAssertFalse(PlaybackSourceRowState(candidate: extensionURL).isEligibleForAutoplay)
        XCTAssertTrue(
            PlaybackSourceRowState(candidate: extensionURL)
                .isPrimaryActionDisabled(isLocalPreparationActive: true)
        )
        XCTAssertFalse(PlaybackSourceRowState(candidate: extensionless).isEligibleForAutoplay)
        XCTAssertTrue(PlaybackSourceRowState(candidate: opaque).isEligibleForAutoplay)
        XCTAssertFalse(
            PlaybackSourceRowState(candidate: opaque)
                .isPrimaryActionDisabled(isLocalPreparationActive: true)
        )
        XCTAssertNil(PlaybackSourceRowState(candidate: opaque).idleStatus)
        XCTAssertTrue(PlaybackSourceRowState(candidate: opaque).allowsExplicitDiscPreparation)
        XCTAssertFalse(
            PlaybackSourceRowState(candidate: regularStream).allowsExplicitDiscPreparation
        )
        XCTAssertFalse(
            PlaybackSourceRowState(candidate: unknownExtension).allowsExplicitDiscPreparation
        )
    }

    func testDiscPreparationStatesExposeAccessibleStatus() {
        XCTAssertEqual(
            DiscPreparationPresentation(state: .detecting).status,
            "Checking disc size…"
        )
        XCTAssertEqual(
            DiscPreparationPresentation(
                state: .materializing(completedBytes: 25, totalBytes: 100)
            ).status,
            "Preparing disc locally… 25%"
        )
        XCTAssertEqual(
            DiscPreparationPresentation(state: .failed(.storageFull)).status,
            "Not enough resolver cache space"
        )
        XCTAssertEqual(
            DiscPreparationPresentation(state: .failed(.busy)).status,
            "Another local source is already being prepared"
        )
        XCTAssertEqual(
            DiscPreparationPresentation(state: .failed(.encryptedDisc)).status,
            "Encrypted disc media is not supported"
        )
        XCTAssertEqual(
            DiscPreparationPresentation(state: .ready).status,
            "Disc ready to play"
        )
    }

    private func fixture(
        _ id: String,
        _ delivery: AddonStreamCandidate.Delivery,
        filename: String? = nil
    ) -> AddonStreamCandidate {
        AddonStreamCandidate(
            id: id,
            addonID: "addon",
            addonName: "Addon",
            streamIdentifier: "tt123",
            displayName: id,
            displayDescription: nil,
            delivery: delivery,
            filename: filename,
            videoSize: nil,
            bingeGroup: nil,
            hasPeerDiscoveryHints: false,
            requestHeaders: [:]
        )
    }

    private func localTorrentDelivery() -> AddonStreamCandidate.Delivery {
        .localTorrent(try! LocalTorrentPlaybackDescriptor(
            infoHash: String(repeating: "a", count: 40),
            fileIndex: 2,
            displayName: "Movie.mkv",
            expectedByteCount: nil
        ))
    }
}
