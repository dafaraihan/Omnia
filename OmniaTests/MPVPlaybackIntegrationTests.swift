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
        let graph = makeStartedPlayer(url: fixtureURL)
        defer { retainAndStop(graph) }
        let player = graph.player

        var snapshots: [OMMpvPlaybackSnapshot] = []
        player.stateChangeHandler = { snapshot in
            snapshots.append(snapshot)
        }
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
        waitUntil { player.position > 0.15 }
        let positionBeforeSelection = player.position
        XCTAssertFalse(player.isPaused)

        let secondAudio = try XCTUnwrap(player.audioTracks.last)
        var audioReplies: [(UInt64, Bool, String?)] = []
        let audioRequestID = player.selectAudioTrack(id: secondAudio.trackID) { id, succeeded, message in
            audioReplies.append((id, succeeded, message))
        }
        waitUntil {
            audioReplies.contains { $0.0 == audioRequestID }
                && player.audioTracks.contains { $0.trackID == secondAudio.trackID && $0.isSelected }
                && player.position > positionBeforeSelection
        }
        XCTAssertEqual(audioReplies.last?.0, audioRequestID)
        XCTAssertEqual(audioReplies.last?.1, true)
        XCTAssertNil(audioReplies.last?.2)
        XCTAssertFalse(player.isPaused)
        XCTAssertTrue(player.audioTracks.contains { $0.trackID == secondAudio.trackID && $0.isSelected })

        let subtitle = try XCTUnwrap(player.subtitleTracks.first)
        var subtitleReplies: [(UInt64, Bool, String?)] = []
        let subtitleRequestID = player.selectSubtitleTrack(id: NSNumber(value: subtitle.trackID)) {
            id,
            succeeded,
            message in
            subtitleReplies.append((id, succeeded, message))
        }
        waitUntil {
            subtitleReplies.contains { $0.0 == subtitleRequestID }
                && player.subtitleTracks.contains { $0.trackID == subtitle.trackID && $0.isSelected }
        }
        XCTAssertEqual(subtitleReplies.last?.1, true)
        XCTAssertNil(subtitleReplies.last?.2)
        XCTAssertFalse(player.isPaused)
        XCTAssertTrue(player.subtitleTracks.contains { $0.trackID == subtitle.trackID && $0.isSelected })

        let disableRequestID = player.selectSubtitleTrack(id: nil) { id, succeeded, message in
            subtitleReplies.append((id, succeeded, message))
        }
        waitUntil {
            subtitleReplies.contains { $0.0 == disableRequestID && $0.1 }
                && !player.subtitleTracks.contains(where: \.isSelected)
        }
        XCTAssertFalse(player.isPaused)
        XCTAssertFalse(player.subtitleTracks.contains(where: \.isSelected))
    }

    @MainActor
    func testLatestAsynchronousAudioSelectionWins() throws {
        let fixtureURL = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "multi-track", withExtension: "mkv")
        )
        let graph = makeStartedPlayer(url: fixtureURL)
        defer { retainAndStop(graph) }
        let player = graph.player
        waitUntil { player.audioTracks.count == 2 && player.position > 0.1 }

        let first = try XCTUnwrap(player.audioTracks.first)
        let second = try XCTUnwrap(player.audioTracks.last)
        var latestReply: (UInt64, Bool)?
        _ = player.selectAudioTrack(id: second.trackID) { _, _, _ in }
        let latestID = player.selectAudioTrack(id: first.trackID) { id, succeeded, _ in
            latestReply = (id, succeeded)
        }

        waitUntil {
            latestReply?.0 == latestID
                && latestReply?.1 == true
                && player.audioTracks.contains { $0.trackID == first.trackID && $0.isSelected }
        }
        XCTAssertFalse(player.isPaused)
    }

    @MainActor
    func testThumbnailGeneratorReturnsBoundedFrameWithoutPlayerView() throws {
        let fixtureURL = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "multi-track", withExtension: "mkv")
        )
        let generator = OMMpvThumbnailGenerator(url: fixtureURL, requestHeaders: [:])
        defer { generator.stop() }
        var result: Result<NSImage, Error>?

        generator.requestFrame(at: 0.5, maximumSize: NSSize(width: 320, height: 180)) { image, error in
            if let image {
                result = .success(image)
            } else {
                result = .failure(error ?? NSError(domain: "OmniaTests", code: 1))
            }
        }
        waitUntil { result != nil }

        let image = try XCTUnwrap(try result?.get())
        XCTAssertLessThanOrEqual(image.size.width, 320)
        XCTAssertLessThanOrEqual(image.size.height, 180)
    }

    @MainActor
    func testThumbnailGeneratorCancelsSupersededRequest() throws {
        let fixtureURL = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "multi-track", withExtension: "mkv")
        )
        let generator = OMMpvThumbnailGenerator(url: fixtureURL, requestHeaders: [:])
        defer { generator.stop() }
        var firstError: Error?
        var secondImage: NSImage?

        _ = generator.requestFrame(at: 0.1, maximumSize: NSSize(width: 320, height: 180)) { _, error in
            firstError = error
        }
        _ = generator.requestFrame(at: 0.8, maximumSize: NSSize(width: 320, height: 180)) { image, _ in
            secondImage = image
        }
        waitUntil { firstError != nil && secondImage != nil }

        XCTAssertEqual((firstError as NSError?)?.domain, "OMMpvThumbnailErrorDomain")
        XCTAssertNotNil(secondImage)
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

    @MainActor
    private func makeStartedPlayer(url: URL) -> PlayerGraph {
        let player = OMMpvPlayerController(url: url, requestHeaders: [:])
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 270),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0
        window.contentView = player.videoView
        window.orderFrontRegardless()
        player.startIfNeeded()
        player.play()
        return PlayerGraph(player: player, window: window)
    }

    @MainActor
    private func retainAndStop(_ graph: PlayerGraph) {
        graph.player.stateChangeHandler = nil
        graph.player.stop()
        Self.retainedPlayers.append(graph.player)
        Self.retainedWindows.append(graph.window)
    }
}

private struct PlayerGraph {
    let player: OMMpvPlayerController
    let window: NSWindow
}
