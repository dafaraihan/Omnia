import XCTest
@testable import Omnia

final class DiscDetectionPolicyTests: XCTestCase {
    private let policy = DiscDetectionPolicy(maximumBytes: 10_000)

    func testDetectsBluRayAndDVDDirectoryRootsCaseInsensitively() {
        let bluRay = [
            file("Movie/bdmv/INDEX.BDMV", size: 10),
            file("Movie/BDMV/STREAM/00001.m2ts", index: 1, size: 100),
        ]
        XCTAssertEqual(
            policy.detect(files: bluRay),
            .supported(.bluRayDirectory(root: "Movie", files: bluRay))
        )

        XCTAssertEqual(
            policy.detect(files: [
                file("Disc/VIDEO_TS/VIDEO_TS.IFO", size: 10),
                file("Disc/VIDEO_TS/VTS_01_1.VOB", index: 1, size: 100),
            ]),
            .unsupportedDVDDirectory(root: "Disc")
        )
    }

    func testDetectsOneISOAndRejectsAmbiguousDiscObjects() {
        let iso = file("Movie.iso", size: 1_000)
        XCTAssertEqual(policy.detect(files: [iso]), .supported(.iso(iso)))
        XCTAssertEqual(
            policy.detect(files: [iso, file("Bonus.iso", index: 1, size: 500)]),
            .rejected(.ambiguousLayout)
        )
        XCTAssertEqual(
            policy.detect(files: [
                file("Movie/BDMV/index.bdmv", size: 10),
                file("Other/readme.txt", index: 1, size: 1),
            ]),
            .rejected(.ambiguousLayout)
        )
    }

    func testRejectsUnsafePathsMetadataFloodAndTotalOverflow() {
        XCTAssertEqual(
            policy.detect(files: [file("../Movie.iso", size: 10)]),
            .rejected(.unsafePath)
        )
        XCTAssertEqual(
            policy.detect(files: [
                TorrentMediaFile(
                    index: 0,
                    relativePath: "Movie.iso",
                    size: 10,
                    isSymbolicLink: true
                ),
            ]),
            .rejected(.unsafePath)
        )
        let excessive = (0...10_000).map {
            file("Movie/BDMV/STREAM/\($0).m2ts", index: $0, size: 1)
        }
        XCTAssertEqual(
            policy.detect(files: excessive),
            .rejected(.metadataLimitExceeded)
        )
        XCTAssertEqual(
            policy.detect(files: [file("Movie.iso", size: 10_001)]),
            .rejected(.totalSizeExceeded)
        )
        XCTAssertEqual(
            policy.detect(files: [
                file("Movie.iso", size: Int64.max),
                file("Other.bin", index: 1, size: Int64.max),
            ]),
            .rejected(.totalSizeExceeded)
        )
    }

    func testOrdinaryMediaIsNotDisc() {
        XCTAssertEqual(
            policy.detect(files: [file("Movie.mkv", size: 1_000)]),
            .notDisc
        )
    }

    private func file(
        _ path: String,
        index: Int = 0,
        size: Int64 = 1
    ) -> TorrentMediaFile {
        TorrentMediaFile(index: index, relativePath: path, size: size)
    }
}
