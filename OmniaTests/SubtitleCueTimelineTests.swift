import XCTest
@testable import Omnia

final class SubtitleCueTimelineTests: XCTestCase {
    func testReturnsOverlappingCuesInStableOrder() {
        let cues = [
            SubtitleCue(startSeconds: 2.5, endSeconds: 4, text: "Second"),
            SubtitleCue(startSeconds: 1, endSeconds: 3, text: "First")
        ]
        let timeline = SubtitleCueTimeline(cues: cues)
        XCTAssertEqual(timeline.cues(at: 2.75).map(\.text), ["First", "Second"])
        XCTAssertTrue(timeline.cues(at: 5).isEmpty)
    }
}
