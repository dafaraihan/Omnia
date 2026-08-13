import Foundation
import XCTest
@testable import Omnia

final class LocalTorrentPlaybackTests: XCTestCase {
    func testHexDescriptorNormalizesHashAndPreservesValidatedFileIndex() throws {
        let descriptor = try LocalTorrentPlaybackDescriptor(
            infoHash: String(repeating: "A", count: 40),
            fileIndex: 2,
            displayName: "Movie Remux",
            expectedByteCount: 12_000
        )

        XCTAssertEqual(descriptor.infoHash, String(repeating: "a", count: 40))
        XCTAssertEqual(descriptor.fileIndex, 2)
        XCTAssertEqual(descriptor.cacheKey, "\(String(repeating: "a", count: 40))-2")
        XCTAssertEqual(
            descriptor.magnetURL.absoluteString,
            "magnet:?xt=urn:btih:\(String(repeating: "a", count: 40))&dn=Movie%20Remux"
        )
    }

    func testBase32DescriptorNormalizesToUppercase() throws {
        let descriptor = try LocalTorrentPlaybackDescriptor(
            infoHash: String(repeating: "b", count: 32),
            fileIndex: nil,
            displayName: "Series",
            expectedByteCount: nil
        )

        XCTAssertEqual(descriptor.infoHash, String(repeating: "B", count: 32))
        XCTAssertEqual(descriptor.cacheKey, "\(String(repeating: "B", count: 32))-auto")
    }

    func testV2DescriptorAcceptsHexAndBoundsTrackerHints() throws {
        let descriptor = try LocalTorrentPlaybackDescriptor(
            infoHash: String(repeating: "A", count: 64),
            fileIndex: 100_000,
            displayName: "Movie.mkv",
            expectedByteCount: nil,
            sources: [
                "tracker:https://tracker.example/announce",
                "tracker:udp://tracker.example:6969/announce",
                "tracker:http://insecure.example/announce",
                "tracker:https://user:password@tracker.example/private",
                "tracker:https://tracker.example/fragment#unsafe",
                "tracker:https://tracker.example/announce",
            ]
        )

        XCTAssertEqual(descriptor.infoHash, String(repeating: "a", count: 64))
        XCTAssertEqual(
            descriptor.trackers.map(\.absoluteString),
            [
                "https://tracker.example/announce",
                "udp://tracker.example:6969/announce",
            ]
        )
        XCTAssertTrue(
            descriptor.magnetURL.absoluteString.contains(
                "tr=https://tracker.example/announce"
            )
        )
    }

    func testDescriptorRejectsExcessiveIndexAndUTF8Filename() {
        XCTAssertThrowsError(
            try LocalTorrentPlaybackDescriptor(
                infoHash: String(repeating: "a", count: 40),
                fileIndex: 100_001,
                displayName: "Movie",
                expectedByteCount: nil
            )
        )
        XCTAssertThrowsError(
            try LocalTorrentPlaybackDescriptor(
                infoHash: String(repeating: "a", count: 40),
                fileIndex: nil,
                displayName: String(repeating: "é", count: 257),
                expectedByteCount: nil
            )
        )
    }

    func testDescriptorKeepsAtMostSixteenUniqueBoundedTrackers() throws {
        let sources = (0..<18).map { "tracker:https://tracker\($0).example/announce" }
            + ["tracker:https://tracker.example/\(String(repeating: "a", count: 2_050))"]
        let descriptor = try LocalTorrentPlaybackDescriptor(
            infoHash: String(repeating: "a", count: 40),
            fileIndex: nil,
            displayName: "Movie",
            expectedByteCount: nil,
            sources: sources
        )

        XCTAssertEqual(descriptor.trackers.count, 16)
        XCTAssertEqual(descriptor.trackers.first?.host, "tracker0.example")
        XCTAssertEqual(descriptor.trackers.last?.host, "tracker15.example")
    }

    func testDescriptorRejectsMalformedHashNegativeIndexAndSize() {
        XCTAssertThrowsError(try descriptor(hash: "not-a-hash"))
        XCTAssertThrowsError(try descriptor(hash: String(repeating: "a", count: 40), fileIndex: -1))
        XCTAssertThrowsError(try descriptor(hash: String(repeating: "a", count: 40), size: -1))
    }

    func testStoragePlanRejectsOversizedItemAndReservesFreeSpace() throws {
        let policy = LocalTorrentStoragePolicy(
            maximumCacheBytes: 20_000,
            minimumFreeBytes: 5_000,
            maximumItemBytes: 12_000
        )

        XCTAssertThrowsError(
            try policy.plan(
                expectedItemBytes: 13_000,
                currentCacheBytes: 0,
                availableVolumeBytes: 30_000
            )
        )

        let plan = try policy.plan(
            expectedItemBytes: 8_000,
            currentCacheBytes: 18_000,
            availableVolumeBytes: 20_000
        )
        XCTAssertEqual(plan.requiredEvictionBytes, 6_000)
        XCTAssertEqual(plan.requiredAvailableBytes, 13_000)
    }

    func testConsentTextDisclosesPeerIPUploadAndLocalStorage() {
        XCTAssertTrue(LocalTorrentConsent.disclosure.contains("IP address"))
        XCTAssertTrue(LocalTorrentConsent.disclosure.contains("upload"))
        XCTAssertTrue(LocalTorrentConsent.disclosure.contains("local cache"))
    }

    func testCachePreparationEvictsOldestInactiveEntry() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalTorrentCacheTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("old", isDirectory: true)
        let recent = root.appendingPathComponent("recent", isDirectory: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: recent, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4_096).write(to: old.appendingPathComponent("media.bin"))
        try Data(repeating: 2, count: 4_096).write(to: recent.appendingPathComponent("media.bin"))
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)],
            ofItemAtPath: old.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 2)],
            ofItemAtPath: recent.path
        )

        let descriptor = try descriptor(hash: String(repeating: "c", count: 40), size: 4_096)
        let directory = try LocalTorrentCacheManager.prepare(
            descriptor: descriptor,
            policy: .init(
                maximumCacheBytes: 8_192,
                minimumFreeBytes: 0,
                maximumItemBytes: 8_192
            ),
            root: root,
            availableVolumeBytes: 1_000_000
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recent.path))
        XCTAssertEqual(directory.lastPathComponent, descriptor.cacheKey)
    }

    func testCachePreparationRejectsSymbolicLinkEntry() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalTorrentCacheTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("unsafe"),
            withDestinationURL: FileManager.default.temporaryDirectory
        )
        let descriptor = try descriptor(hash: String(repeating: "d", count: 40), size: 1)

        XCTAssertThrowsError(
            try LocalTorrentCacheManager.prepare(
                descriptor: descriptor,
                policy: .init(
                    maximumCacheBytes: 1_024,
                    minimumFreeBytes: 0,
                    maximumItemBytes: 1_024
                ),
                root: root,
                availableVolumeBytes: 1_000_000
            )
        )
    }

    private func descriptor(
        hash: String,
        fileIndex: Int? = nil,
        size: Int64? = nil
    ) throws -> LocalTorrentPlaybackDescriptor {
        try LocalTorrentPlaybackDescriptor(
            infoHash: hash,
            fileIndex: fileIndex,
            displayName: "Fixture",
            expectedByteCount: size
        )
    }
}
