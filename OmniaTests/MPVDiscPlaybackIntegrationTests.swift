import AppKit
import Foundation
import XCTest
@testable import Omnia

final class MPVDiscPlaybackIntegrationTests: XCTestCase {
    func testNativeTorrentAdapterRecognizesOnlyCompleteSingleBluRayTree() {
        XCTAssertTrue(
            OMLocalTorrentEngine.isSupportedBluRayLayout(
                forTesting: [
                    "Movie/bdmv/INDEX.BDMV",
                    "Movie/BDMV/STREAM/00001.m2ts",
                ],
                sizes: [5, 6],
                symbolicLinkIndices: []
            )
        )
        XCTAssertFalse(
            OMLocalTorrentEngine.isSupportedBluRayLayout(
                forTesting: [
                    "Movie/BDMV/index.bdmv",
                    "unrelated.mkv",
                ],
                sizes: [5, 6],
                symbolicLinkIndices: []
            )
        )
        XCTAssertFalse(
            OMLocalTorrentEngine.isSupportedBluRayLayout(
                forTesting: [
                    "Movie/BDMV/index.bdmv",
                    "Movie/bdmv/INDEX.BDMV",
                ],
                sizes: [5, 5],
                symbolicLinkIndices: []
            )
        )
        XCTAssertFalse(
            OMLocalTorrentEngine.isSupportedBluRayLayout(
                forTesting: ["../Movie/BDMV/index.bdmv"],
                sizes: [5],
                symbolicLinkIndices: []
            )
        )
        XCTAssertFalse(
            OMLocalTorrentEngine.isSupportedBluRayLayout(
                forTesting: [
                    "Movie/BDMV/index.bdmv",
                    "Movie/BDMV/STREAM/00001.m2ts",
                ],
                sizes: [5, 6],
                symbolicLinkIndices: [1]
            )
        )
    }

    func testNativeCapacityHelperChargesOnlyMissingConfinedRegularBytes() throws {
        let root = temporaryDirectory(named: "TorrentCapacity")
        let outside = temporaryDirectory(named: "TorrentCapacityOutside")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let partial = root.appendingPathComponent("partial.m2ts")
        let outsideFile = outside.appendingPathComponent("outside.m2ts")
        let link = root.appendingPathComponent("link.m2ts")
        try Data(repeating: 1, count: 4).write(to: partial)
        try Data(repeating: 2, count: 4).write(to: outsideFile)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsideFile)

        let allocated = try XCTUnwrap(
            partial.resourceValues(forKeys: [.fileAllocatedSizeKey]).fileAllocatedSize
        )
        let selectedBytes = Int64(allocated + 10_000)
        XCTAssertEqual(
            OMLocalTorrentEngine.remainingDownloadBytes(
                forTesting: selectedBytes,
                rootURL: root,
                selectedFileURLs: [partial, outsideFile, link]
            ),
            10_000
        )
        try Data(repeating: 1, count: Int(selectedBytes)).write(to: partial)
        let completed = URL(fileURLWithPath: partial.path)
        XCTAssertEqual(
            OMLocalTorrentEngine.remainingDownloadBytes(
                forTesting: selectedBytes,
                rootURL: root,
                selectedFileURLs: [completed]
            ),
            0
        )

        let sparse = root.appendingPathComponent("sparse.m2ts")
        XCTAssertTrue(FileManager.default.createFile(atPath: sparse.path, contents: nil))
        let handle = try FileHandle(forWritingTo: sparse)
        try handle.truncate(atOffset: 1_048_576)
        try handle.close()
        let sparseAllocated = try XCTUnwrap(
            sparse.resourceValues(forKeys: [.fileAllocatedSizeKey]).fileAllocatedSize
        )
        XCTAssertLessThan(sparseAllocated, 1_048_576)
        XCTAssertEqual(
            OMLocalTorrentEngine.remainingDownloadBytes(
                forTesting: 1_048_576,
                rootURL: root,
                selectedFileURLs: [URL(fileURLWithPath: sparse.path)]
            ),
            Int64(1_048_576 - sparseAllocated)
        )
    }

    func testFinalizesCompletedTorrentBluRayTreeInsideCache() throws {
        let cacheRoot = temporaryDirectory(named: "TorrentDiscCache")
        let jobRoot = cacheRoot.appendingPathComponent("job", isDirectory: true)
        let discRoot = jobRoot.appendingPathComponent("Movie", isDirectory: true)
        let marker = discRoot.appendingPathComponent("BDMV/index.bdmv")
        let stream = discRoot.appendingPathComponent("BDMV/STREAM/00001.m2ts")
        defer { try? FileManager.default.removeItem(at: cacheRoot) }
        try FileManager.default.createDirectory(
            at: stream.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("index".utf8).write(to: marker)
        try Data("stream".utf8).write(to: stream)
        let jobID = UUID()

        let disc = try TorrentDiscFinalizer.finalizeBluRayDirectory(
            discRoot,
            declaredBytes: 11,
            cacheRoot: cacheRoot,
            jobID: jobID
        )

        XCTAssertEqual(disc.rootURL, discRoot)
        XCTAssertEqual(disc.kindHint, .bluRayDirectory)
        XCTAssertEqual(disc.bytes, 11)
        let request = try DiscPlaybackRequest(disc: disc, cacheRoot: cacheRoot)
        XCTAssertEqual(request.deviceURL, discRoot)

        let replay = try TorrentDiscFinalizer.finalizeBluRayDirectory(
            discRoot,
            declaredBytes: 11,
            cacheRoot: cacheRoot,
            jobID: UUID()
        )
        XCTAssertEqual(replay, disc)
        XCTAssertNoThrow(try DiscPlaybackRequest(disc: replay, cacheRoot: cacheRoot))
    }

    func testRejectsTorrentBluRayTreeWithSymlinkOrByteMismatch() throws {
        let cacheRoot = temporaryDirectory(named: "TorrentDiscCache")
        let jobRoot = cacheRoot.appendingPathComponent("job", isDirectory: true)
        let discRoot = jobRoot.appendingPathComponent("Movie", isDirectory: true)
        let marker = discRoot.appendingPathComponent("BDMV/index.bdmv")
        let outside = temporaryDirectory(named: "TorrentDiscOutside")
        defer {
            try? FileManager.default.removeItem(at: cacheRoot)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createDirectory(
            at: marker.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("index".utf8).write(to: marker)

        XCTAssertThrowsError(
            try TorrentDiscFinalizer.finalizeBluRayDirectory(
                discRoot,
                declaredBytes: 4,
                cacheRoot: cacheRoot,
                jobID: UUID()
            )
        ) { error in
            XCTAssertEqual(error as? DiscMaterializationError, .byteCountMismatch)
        }

        let link = discRoot.appendingPathComponent("BDMV/STREAM")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertThrowsError(
            try TorrentDiscFinalizer.finalizeBluRayDirectory(
                discRoot,
                declaredBytes: 5,
                cacheRoot: cacheRoot,
                jobID: UUID()
            )
        ) { error in
            XCTAssertEqual(error as? DiscMaterializationError, .unsafeReservation)
        }
    }

    func testCreatesTypedBluRayDirectoryRequestInsideCompletedCacheJob() throws {
        let fixture = try makeFixture(kind: .bluRayDirectory)
        defer { try? FileManager.default.removeItem(at: fixture.cacheRoot) }

        let request = try DiscPlaybackRequest(
            disc: fixture.disc,
            cacheRoot: fixture.cacheRoot
        )

        XCTAssertEqual(request.playbackURL.absoluteString, "bd://longest")
        XCTAssertEqual(request.deviceURL, fixture.disc.rootURL)
        XCTAssertEqual(request.requestHeaders, [:])
    }

    @MainActor
    func testControllerAcceptsTypedDiscRequestWithoutHTTPHeaders() throws {
        let fixture = try makeFixture(kind: .bluRayDirectory)
        defer { try? FileManager.default.removeItem(at: fixture.cacheRoot) }
        let request = try DiscPlaybackRequest(
            disc: fixture.disc,
            cacheRoot: fixture.cacheRoot
        )

        let player = OMMpvPlayerController(
            url: request.playbackURL,
            requestHeaders: request.requestHeaders,
            blurayDeviceURL: request.deviceURL
        )
        defer { player.stop() }

        XCTAssertNotNil(player.videoView)
    }

    func testCreatesTypedISORequestInsideCompletedCacheJob() throws {
        let fixture = try makeFixture(kind: .iso)
        defer { try? FileManager.default.removeItem(at: fixture.cacheRoot) }

        let request = try DiscPlaybackRequest(
            disc: fixture.disc,
            cacheRoot: fixture.cacheRoot
        )

        XCTAssertEqual(request.playbackURL.absoluteString, "bd://longest")
        XCTAssertEqual(request.deviceURL, fixture.disc.rootURL)
    }

    func testRejectsDiscOutsideCacheAndIncompleteJob() throws {
        let fixture = try makeFixture(kind: .iso)
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiscPlaybackOutside.\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: fixture.cacheRoot)
            try? FileManager.default.removeItem(at: outside)
        }
        try Data("iso".utf8).write(to: outside)
        let outsideDisc = MaterializedDisc(
            jobID: UUID(),
            rootURL: outside,
            kindHint: .iso,
            bytes: 3
        )

        XCTAssertThrowsError(
            try DiscPlaybackRequest(disc: outsideDisc, cacheRoot: fixture.cacheRoot)
        ) { error in
            XCTAssertEqual(error as? DiscPlaybackRequestError, .outsideCache)
        }

        try FileManager.default.removeItem(
            at: fixture.jobRoot.appendingPathComponent("complete.plist")
        )
        XCTAssertThrowsError(
            try DiscPlaybackRequest(disc: fixture.disc, cacheRoot: fixture.cacheRoot)
        ) { error in
            XCTAssertEqual(error as? DiscPlaybackRequestError, .incompleteMaterialization)
        }
    }

    func testRejectsSymlinkedDeviceAndMissingBluRayMarker() throws {
        let fixture = try makeFixture(kind: .bluRayDirectory)
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiscPlaybackOutside.\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: fixture.cacheRoot)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: fixture.disc.rootURL)
        try FileManager.default.createSymbolicLink(
            at: fixture.disc.rootURL,
            withDestinationURL: outside
        )

        XCTAssertThrowsError(
            try DiscPlaybackRequest(disc: fixture.disc, cacheRoot: fixture.cacheRoot)
        ) { error in
            XCTAssertEqual(error as? DiscPlaybackRequestError, .unsafeDevice)
        }

        try FileManager.default.removeItem(at: fixture.disc.rootURL)
        try FileManager.default.createDirectory(
            at: fixture.disc.rootURL,
            withIntermediateDirectories: true
        )
        XCTAssertThrowsError(
            try DiscPlaybackRequest(disc: fixture.disc, cacheRoot: fixture.cacheRoot)
        ) { error in
            XCTAssertEqual(error as? DiscPlaybackRequestError, .unsupportedDisc)
        }
    }

    private func makeFixture(
        kind: MaterializedDisc.KindHint
    ) throws -> (cacheRoot: URL, jobRoot: URL, disc: MaterializedDisc) {
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiscPlaybackCache.\(UUID().uuidString)", isDirectory: true)
        let jobRoot = cacheRoot.appendingPathComponent("job", isDirectory: true)
        let mediaRoot = jobRoot.appendingPathComponent("Media", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaRoot, withIntermediateDirectories: true)
        let jobID = UUID()

        let rootURL: URL
        switch kind {
        case .iso:
            rootURL = mediaRoot.appendingPathComponent("Movie.iso")
            try Data("iso".utf8).write(to: rootURL)
        case .bluRayDirectory:
            rootURL = mediaRoot
            let marker = mediaRoot.appendingPathComponent("BDMV/index.bdmv")
            try FileManager.default.createDirectory(
                at: marker.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("index".utf8).write(to: marker)
        }

        let bytes: Int64 = kind == .iso ? 3 : 5
        let manifest = DiscMaterializationManifest(
            version: 1,
            jobID: jobID,
            kind: kind == .iso ? "iso" : "bluRayDirectory",
            bytes: bytes,
            completedAt: Date()
        )
        try PropertyListEncoder().encode(manifest).write(
            to: jobRoot.appendingPathComponent("complete.plist")
        )

        return (
            cacheRoot,
            jobRoot,
            MaterializedDisc(
                jobID: jobID,
                rootURL: rootURL,
                kindHint: kind,
                bytes: bytes
            )
        )
    }

    private func temporaryDirectory(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name).\(UUID().uuidString)", isDirectory: true)
    }
}
