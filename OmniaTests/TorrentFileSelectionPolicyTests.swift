import XCTest
@testable import Omnia

final class TorrentFileSelectionPolicyTests: XCTestCase {
    private let policy = TorrentFileSelectionPolicy()

    func testUsesIndexThenFilenameThenUniqueLargestVideo() {
        let files = [
            TorrentMediaFile(index: 0, relativePath: "sample.mkv", size: 10),
            TorrentMediaFile(index: 1, relativePath: "Feature/Movie.m2ts", size: 1_000),
        ]

        XCTAssertEqual(
            policy.select(files, preferredIndex: 0, preferredFilename: "Movie.m2ts"),
            .selected(files[0])
        )
        XCTAssertEqual(
            policy.select(files, preferredIndex: nil, preferredFilename: "movie.M2TS"),
            .selected(files[1])
        )
        XCTAssertEqual(
            policy.select(files, preferredIndex: nil, preferredFilename: nil),
            .selected(files[1])
        )
    }

    func testSimilarlySizedEpisodesRequireStableBoundedChoice() {
        let files = (0..<250).map { index in
            TorrentMediaFile(
                index: index,
                relativePath: String(format: "Season/Episode-%03d.mkv", 249 - index),
                size: 1_000 - Int64(index % 5)
            )
        }

        guard case let .requiresChoice(choices) = policy.select(
            files,
            preferredIndex: nil,
            preferredFilename: nil
        ) else {
            return XCTFail("Expected a bounded file choice")
        }
        XCTAssertEqual(choices.count, 200)
        XCTAssertEqual(choices.first?.size, 1_000)
        XCTAssertEqual(choices.prefix(2).map(\.relativePath), [
            "Season/Episode-004.mkv",
            "Season/Episode-009.mkv",
        ])
    }

    func testRejectsTraversalAbsoluteAndLinkMetadata() {
        let unsafeFiles = [
            TorrentMediaFile(index: 0, relativePath: "../escape.mkv", size: 100),
            TorrentMediaFile(index: 1, relativePath: "/absolute.mkv", size: 100),
            TorrentMediaFile(index: 2, relativePath: "linked.mkv", size: 100, isSymbolicLink: true),
        ]

        for file in unsafeFiles {
            XCTAssertEqual(
                policy.select([file], preferredIndex: nil, preferredFilename: nil),
                .unavailable(.unsafePath)
            )
        }
    }

    func testRejectsMetadataFloodAndZeroByteOnlyPayload() {
        let excessive = (0...10_000).map {
            TorrentMediaFile(index: $0, relativePath: "\($0).mkv", size: 1)
        }
        XCTAssertEqual(
            policy.select(excessive, preferredIndex: nil, preferredFilename: nil),
            .unavailable(.metadataLimitExceeded)
        )
        XCTAssertEqual(
            policy.select(
                [TorrentMediaFile(index: 0, relativePath: "empty.mkv", size: 0)],
                preferredIndex: nil,
                preferredFilename: nil
            ),
            .unavailable(.noRegularFiles)
        )
    }

    func testExplicitIndexMaySelectUnknownExtensionRegularFile() {
        let file = TorrentMediaFile(index: 4, relativePath: "opaque.media", size: 200)

        XCTAssertEqual(
            policy.select([file], preferredIndex: 4, preferredFilename: nil),
            .selected(file)
        )
    }
}
