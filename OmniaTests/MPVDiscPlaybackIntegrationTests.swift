import AppKit
import Foundation
import XCTest
@testable import Omnia

final class MPVDiscPlaybackIntegrationTests: XCTestCase {
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
}
