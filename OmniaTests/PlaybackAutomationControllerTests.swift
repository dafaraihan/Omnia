import XCTest
@testable import Omnia

final class PlaybackAutomationControllerTests: XCTestCase {
    func testSkipButtonTracksEntryExitAndDisabledPolicy() {
        let intro = SkipSegment(kind: .intro, startSeconds: 10, endSeconds: 70, confidence: 1)
        var controller = PlaybackAutomationController(policy: .init(
            showSkipIntro: true,
            autoSkipIntro: false,
            autoplayNextEpisode: false,
            upNextLeadSeconds: 30
        ))

        XCTAssertEqual(controller.update(position: 9, duration: 1_800, segments: [intro]), .none)
        XCTAssertEqual(controller.update(position: 10, duration: 1_800, segments: [intro]), .presentSkip(intro))
        XCTAssertEqual(controller.update(position: 20, duration: 1_800, segments: [intro]), .none)
        XCTAssertEqual(controller.update(position: 71, duration: 1_800, segments: [intro]), .dismissSkip)

        var disabled = PlaybackAutomationController(policy: .init(
            showSkipIntro: false,
            autoSkipIntro: false,
            autoplayNextEpisode: false,
            upNextLeadSeconds: 30
        ))
        XCTAssertEqual(disabled.update(position: 10, duration: 1_800, segments: [intro]), .none)
    }

    func testAutoSkipSeeksOncePerSegmentEvenAfterSeekingBack() {
        let intro = SkipSegment(kind: .intro, startSeconds: 10, endSeconds: 70, confidence: 1)
        var controller = PlaybackAutomationController(policy: .init(
            showSkipIntro: true,
            autoSkipIntro: true,
            autoplayNextEpisode: false,
            upNextLeadSeconds: 30
        ))

        XCTAssertEqual(controller.update(position: 10, duration: 1_800, segments: [intro]), .seek(to: 70))
        XCTAssertEqual(controller.update(position: 71, duration: 1_800, segments: [intro]), .none)
        XCTAssertEqual(controller.update(position: 11, duration: 1_800, segments: [intro]), .none)
    }

    func testUpNextRequiresKnownDurationAndNextEpisode() {
        var controller = PlaybackAutomationController(policy: .init(
            showSkipIntro: true,
            autoSkipIntro: false,
            autoplayNextEpisode: true,
            upNextLeadSeconds: 30
        ))

        XCTAssertEqual(controller.update(position: 100, duration: nil, segments: [], hasNextEpisode: true), .none)
        XCTAssertEqual(controller.update(position: 1_769, duration: 1_800, segments: [], hasNextEpisode: true), .none)
        XCTAssertEqual(controller.update(position: 1_770, duration: 1_800, segments: [], hasNextEpisode: false), .none)
        XCTAssertEqual(controller.update(position: 1_770, duration: 1_800, segments: [], hasNextEpisode: true), .presentUpNext)
        XCTAssertEqual(controller.update(position: 1_775, duration: 1_800, segments: [], hasNextEpisode: true), .none)
        XCTAssertEqual(controller.playbackEnded(hasNextEpisode: true), .resolveNextEpisode)
    }

    func testCompletionAndCancellationStopWhenAutoplayCannotContinue() {
        var noNext = PlaybackAutomationController(policy: .init(
            showSkipIntro: true,
            autoSkipIntro: false,
            autoplayNextEpisode: true,
            upNextLeadSeconds: 30
        ))
        XCTAssertEqual(noNext.playbackEnded(hasNextEpisode: false), .stopAtEnd)

        var disabled = PlaybackAutomationController(policy: .init(
            showSkipIntro: true,
            autoSkipIntro: false,
            autoplayNextEpisode: false,
            upNextLeadSeconds: 30
        ))
        XCTAssertEqual(disabled.playbackEnded(hasNextEpisode: true), .stopAtEnd)
        XCTAssertEqual(disabled.cancel(), .stopAtEnd)
    }
}
