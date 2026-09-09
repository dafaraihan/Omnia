import AppKit
import XCTest
@testable import Omnia

final class MPVPlaybackIntegrationTests: XCTestCase {
    // AppKit and NSOpenGLView enqueue teardown work beyond `NSWindow.close()`.
    // XCTest's per-repetition memory scope can release those objects while
    // the queued work still refers to them, crashing before the next repeat.
    // Keep this test-only native graph alive until the test host exits.
    private static var retainedPlayers: [OMMpvPlayerController] = []
    private static var retainedWindows: [NSWindow] = []

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
        window.alphaValue = 0
        window.contentView = player.videoView
        window.orderFrontRegardless()
        defer {
            player.stateChangeHandler = nil
            player.stop()
            Self.retainedPlayers.append(player)
            Self.retainedWindows.append(window)
        }

        var snapshots: [OMMpvPlaybackSnapshot] = []
        player.stateChangeHandler = { snapshot in
            snapshots.append(snapshot)
        }
        player.startIfNeeded()
        waitUntil {
            player.errorMessage != nil
                || (
                    player.hasRenderedVideoFrame
                        && snapshots.contains {
                            !$0.tracksLoading && $0.audioTracks.count == 2 && $0.subtitleTracks.count == 1
                        }
                )
        }

        XCTAssertNil(player.errorMessage)
        XCTAssertTrue(player.hasRenderedVideoFrame)
        XCTAssertEqual(player.audioTracks.count, 2)
        XCTAssertEqual(player.subtitleTracks.count, 1)
        XCTAssertTrue(snapshots.contains { $0.audioTracks.count == 2 })

        let secondAudio = try XCTUnwrap(player.audioTracks.last)
        player.selectAudioTrack(id: secondAudio.trackID)
        waitUntil {
            snapshots.contains {
                $0.audioTracks.contains { $0.trackID == secondAudio.trackID && $0.isSelected }
            }
        }
        XCTAssertTrue(player.audioTracks.contains { $0.trackID == secondAudio.trackID && $0.isSelected })

        let subtitle = try XCTUnwrap(player.subtitleTracks.first)
        player.selectSubtitleTrack(id: NSNumber(value: subtitle.trackID))
        waitUntil {
            snapshots.contains {
                $0.subtitleTracks.contains { $0.trackID == subtitle.trackID && $0.isSelected }
            }
        }
        XCTAssertTrue(player.subtitleTracks.contains { $0.trackID == subtitle.trackID && $0.isSelected })

        player.selectSubtitleTrack(id: nil)
        waitUntil {
            snapshots.last.map { !$0.subtitleTracks.contains(where: \.isSelected) } == true
        }
        XCTAssertFalse(player.subtitleTracks.contains(where: \.isSelected))
    }

    @MainActor
    func testSeekRequestedBeforePlayerReadinessIsAppliedAfterFileLoads() throws {
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
        window.alphaValue = 0
        window.contentView = player.videoView
        window.orderFrontRegardless()
        defer {
            player.stateChangeHandler = nil
            player.stop()
            Self.retainedPlayers.append(player)
            Self.retainedWindows.append(window)
        }

        player.seek(to: 0.75)
        player.startIfNeeded()
        waitUntil { player.errorMessage != nil || player.position >= 0.6 }

        XCTAssertNil(player.errorMessage)
        XCTAssertGreaterThanOrEqual(player.position, 0.6)
    }

    @MainActor
    func testPictureInPictureMovesVideoSurfaceAndRestoresInlineHost() {
        let player = OMMpvPlayerController(
            url: URL(fileURLWithPath: "/tmp/omnia-pip-contract.mkv"),
            requestHeaders: [:]
        )
        let hostView = NSView(frame: NSRect(x: 0, y: 0, width: 960, height: 540))
        let window = NSWindow(
            contentRect: hostView.bounds,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0
        window.contentView = hostView
        window.orderFrontRegardless()
        defer {
            player.stop()
            Self.retainedPlayers.append(player)
            Self.retainedWindows.append(window)
        }

        let attachSelector = NSSelectorFromString("attachVideoViewToHost:")
        let enterSelector = NSSelectorFromString("enterPictureInPicture")
        let exitSelector = NSSelectorFromString("exitPictureInPicture")
        let activeSelector = NSSelectorFromString("pictureInPictureActive")
        let possibleSelector = NSSelectorFromString("pictureInPicturePossible")
        let selectors = [
            attachSelector,
            enterSelector,
            exitSelector,
            activeSelector,
            possibleSelector,
        ]

        XCTAssertTrue(selectors.allSatisfy(player.responds(to:)))
        guard selectors.allSatisfy(player.responds(to:)) else { return }

        player.perform(attachSelector, with: hostView)
        XCTAssertTrue(player.videoView.superview === hostView)
        XCTAssertEqual(player.value(forKey: "pictureInPicturePossible") as? Bool, true)

        player.perform(enterSelector)
        XCTAssertEqual(player.value(forKey: "pictureInPictureActive") as? Bool, true)
        XCTAssertFalse(player.videoView.superview === hostView)

        player.perform(exitSelector)
        XCTAssertEqual(player.value(forKey: "pictureInPictureActive") as? Bool, false)
        XCTAssertTrue(player.videoView.superview === hostView)
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval = 5, condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }
}
