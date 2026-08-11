import AppKit
import XCTest
@testable import Omnia

final class MPVPlaybackIntegrationTests: XCTestCase {
    @MainActor
    func testLocalMultiTrackFixtureRendersAndSupportsExplicitTrackSelection() throws {
        let fixtureURL = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "multi-track", withExtension: "mkv")
        )
        let player = OMMpvPlayerController(url: fixtureURL, requestHeaders: [:])
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 270),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = player.videoView
        window.orderFrontRegardless()
        defer {
            player.stop()
            window.close()
        }

        player.startIfNeeded()
        waitUntil {
            player.errorMessage != nil
                || (player.hasRenderedVideoFrame && player.audioTracks.count == 2 && player.subtitleTracks.count == 1)
        }

        XCTAssertNil(player.errorMessage)
        XCTAssertTrue(player.hasRenderedVideoFrame)
        XCTAssertEqual(player.audioTracks.count, 2)
        XCTAssertEqual(player.subtitleTracks.count, 1)

        let secondAudio = try XCTUnwrap(player.audioTracks.last)
        player.selectAudioTrack(id: secondAudio.trackID)
        waitUntil { player.audioTracks.contains { $0.trackID == secondAudio.trackID && $0.isSelected } }
        XCTAssertTrue(player.audioTracks.contains { $0.trackID == secondAudio.trackID && $0.isSelected })

        let subtitle = try XCTUnwrap(player.subtitleTracks.first)
        player.selectSubtitleTrack(id: NSNumber(value: subtitle.trackID))
        waitUntil { player.subtitleTracks.contains { $0.trackID == subtitle.trackID && $0.isSelected } }
        XCTAssertTrue(player.subtitleTracks.contains { $0.trackID == subtitle.trackID && $0.isSelected })

        player.selectSubtitleTrack(id: nil)
        waitUntil { !player.subtitleTracks.contains(where: \.isSelected) }
        XCTAssertFalse(player.subtitleTracks.contains(where: \.isSelected))
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval = 5, condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }
}
