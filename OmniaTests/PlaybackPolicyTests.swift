import XCTest
@testable import Omnia

final class PlaybackPolicyTests: XCTestCase {
    func testAdapterCompatibilityAndExternalHandoffExclusion() {
        let hls = candidate(id: "hls", delivery: .nativeHTTPS(URL(string: "https://media.example/video.m3u8")!))
        let mp4 = candidate(id: "mp4", delivery: .nativeHTTPS(URL(string: "https://media.example/video.mp4")!))
        let mkv = candidate(id: "mkv", delivery: .nativeHTTPS(URL(string: "https://media.example/video.mkv")!))
        let opaque = candidate(id: "opaque", delivery: .nativeHTTPS(URL(string: "https://media.example/play")!))
        let handoff = candidate(id: "handoff", delivery: .externalHandoff(URL(string: "https://player.example/watch")!))

        XCTAssertEqual(PlaybackPolicy.compatibility(of: hls, adapter: .avPlayer), .supported)
        XCTAssertEqual(PlaybackPolicy.compatibility(of: mp4, adapter: .avPlayer), .supported)
        XCTAssertEqual(PlaybackPolicy.compatibility(of: mkv, adapter: .avPlayer), .unsupported)
        XCTAssertEqual(PlaybackPolicy.compatibility(of: mkv, adapter: .libmpv), .supported)
        XCTAssertEqual(PlaybackPolicy.compatibility(of: opaque, adapter: .libmpv), .unknown)
        XCTAssertFalse(PlaybackPolicy.isEligible(handoff, adapter: .libmpv, compatibleOnly: false))
        XCTAssertFalse(PlaybackPolicy.isEligible(opaque, adapter: .avPlayer, compatibleOnly: false))
        XCTAssertTrue(PlaybackPolicy.isEligible(opaque, adapter: .libmpv, compatibleOnly: false))
    }

    func testOpaqueHTTPSRemainsEligibleForLibmpvWhenCompatibilityFilterIsEnabled() {
        let opaque = candidate(
            id: "opaque",
            delivery: .nativeHTTPS(URL(string: "https://media.example/play")!)
        )

        XCTAssertTrue(PlaybackPolicy.isEligible(opaque, adapter: .libmpv, compatibleOnly: true))
    }

    func testRememberedSourceWinsThenAutoplayUsesFirstSafeCandidate() {
        let first = candidate(id: "first", addonID: "one", bingeGroup: "group-a")
        let rememberedCandidate = candidate(id: "remembered", addonID: "two", bingeGroup: "group-b")
        let remembered = RememberedSource(
            mediaKey: MediaPlaybackKey(rawValue: "series:1:2"),
            addonID: "two",
            bingeGroup: "group-b",
            displayNameFingerprint: rememberedCandidate.displayNameFingerprint,
            expiresAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(
            PlaybackPolicy.choose(
                from: [first, rememberedCandidate],
                adapter: .libmpv,
                compatibleOnly: true,
                autoplayFirst: false,
                remembered: remembered,
                now: Date(timeIntervalSince1970: 50)
            ),
            .play(rememberedCandidate)
        )
        XCTAssertEqual(
            PlaybackPolicy.choose(
                from: [first, rememberedCandidate],
                adapter: .libmpv,
                compatibleOnly: true,
                autoplayFirst: true,
                remembered: nil,
                now: .now
            ),
            .play(first)
        )
        XCTAssertEqual(
            PlaybackPolicy.choose(
                from: [first, rememberedCandidate],
                adapter: .libmpv,
                compatibleOnly: true,
                autoplayFirst: false,
                remembered: nil,
                now: .now
            ),
            .requiresSelection([first, rememberedCandidate])
        )
    }

    private func candidate(
        id: String,
        addonID: String = "addon",
        bingeGroup: String? = nil,
        delivery: AddonStreamCandidate.Delivery = .nativeHTTPS(URL(string: "https://media.example/video.mp4")!)
    ) -> AddonStreamCandidate {
        AddonStreamCandidate(
            id: id,
            addonID: addonID,
            addonName: addonID,
            streamIdentifier: "tt123",
            displayName: id,
            displayDescription: nil,
            delivery: delivery,
            filename: nil,
            videoSize: nil,
            bingeGroup: bingeGroup,
            hasPeerDiscoveryHints: false,
            requestHeaders: ["Authorization": "secret"]
        )
    }
}
