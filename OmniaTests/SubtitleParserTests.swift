import XCTest
@testable import Omnia

final class SubtitleParserTests: XCTestCase {
    func testParsesSRTAndWebVTTWithStableOrdering() throws {
        let srt = try SubtitleParser.parse(try fixture("omnia-sample.srt"), format: .srt)
        XCTAssertEqual(srt.map(\.text), ["Hello world", "Second line"])
        XCTAssertEqual(srt[0].startSeconds, 1)
        XCTAssertEqual(srt[1].startSeconds, 2.5)

        let vtt = try SubtitleParser.parse(try fixture("omnia-sample.vtt"), format: .webVTT)
        XCTAssertEqual(vtt.map(\.text), ["Hello VTT", "Next cue"])
    }

    func testRejectsMalformedOversizedAndStyledASSInput() throws {
        XCTAssertThrowsError(try SubtitleParser.parse(try fixture("omnia-malformed.srt"), format: .srt))
        XCTAssertThrowsError(try SubtitleParser.parse(Data(repeating: 0, count: SubtitleParser.maximumByteCount + 1), format: .srt))
        XCTAssertThrowsError(try SubtitleParser.parse(Data("{\\an8}styled".utf8), format: .srt))
    }

    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "Fixtures/Subtitles/\(name)")
        return try Data(contentsOf: url)
    }
}
