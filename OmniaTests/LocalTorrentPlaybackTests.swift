import Foundation
import XCTest
@testable import Omnia

final class LocalTorrentPlaybackTests: XCTestCase {
    func testLocalPlaybackCoordinatorAllowsOnlyOnePreparationUntilRelease() async throws {
        let coordinator = LocalPlaybackJobCoordinator()
        let firstLease = try await coordinator.acquire()

        do {
            _ = try await coordinator.acquire()
            XCTFail("A second local preparation must not acquire the shared cache")
        } catch {
            XCTAssertEqual(error as? LocalPlaybackJobCoordinator.JobError, .busy)
        }

        await coordinator.release(firstLease)
        let secondLease = try await coordinator.acquire()
        await coordinator.release(secondLease)
    }

    func testCoordinatorReleaseRollsBackUncommittedReservation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalPlaybackCoordinatorTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = LocalPlaybackJobCoordinator(
            root: root,
            availableVolumeBytes: 1_000_000
        )
        let descriptor = try descriptor(hash: String(repeating: "2", count: 40), size: 1)
        let lease = try await coordinator.acquire()
        let reservation = try await coordinator.prepare(
            descriptor: descriptor,
            policy: .init(
                maximumCacheBytes: 1_024,
                minimumFreeBytes: 0,
                maximumItemBytes: 1_024
            ),
            lease: lease
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: reservation.itemDirectory.path))
        await coordinator.release(lease)
        XCTAssertFalse(FileManager.default.fileExists(atPath: reservation.itemDirectory.path))
    }

    func testCoordinatorProtectsActivePlaybackFromEviction() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalPlaybackCoordinatorTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = LocalPlaybackJobCoordinator(
            root: root,
            availableVolumeBytes: 1_000_000
        )
        let policy = LocalTorrentStoragePolicy(
            maximumCacheBytes: 4_096,
            minimumFreeBytes: 0,
            maximumItemBytes: 4_096
        )
        let activeDescriptor = try descriptor(
            hash: String(repeating: "3", count: 40),
            size: 4_096
        )
        let activeLease = try await coordinator.acquire()
        let activeReservation = try await coordinator.prepare(
            descriptor: activeDescriptor,
            policy: policy,
            lease: activeLease
        )
        try Data(repeating: 1, count: 4_096).write(
            to: activeReservation.itemDirectory.appendingPathComponent("movie.mkv")
        )
        try await coordinator.commitPreparation(activeLease)
        let protection = try await coordinator.protectForPlayback(activeLease)

        let nextDescriptor = try descriptor(
            hash: String(repeating: "4", count: 40),
            size: 4_096
        )
        let nextLease = try await coordinator.acquire()
        do {
            _ = try await coordinator.prepare(
                descriptor: nextDescriptor,
                policy: policy,
                lease: nextLease
            )
            XCTFail("Active playback must not be evicted")
        } catch {
            XCTAssertEqual(error as? LocalTorrentCacheManager.CacheError, .evictionFailed)
        }
        await coordinator.release(nextLease)
        XCTAssertTrue(FileManager.default.fileExists(atPath: activeReservation.itemDirectory.path))

        await coordinator.unprotect(protection)
        let retryLease = try await coordinator.acquire()
        let nextReservation = try await coordinator.prepare(
            descriptor: nextDescriptor,
            policy: policy,
            lease: retryLease
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: activeReservation.itemDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: nextReservation.itemDirectory.path))
        await coordinator.release(retryLease)
    }

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

    func testCancelledCachePreparationDoesNotEvictOrCreateItem() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalTorrentCacheTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = root.appendingPathComponent("existing", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4_096).write(
            to: existing.appendingPathComponent("media.bin")
        )
        let descriptor = try descriptor(hash: String(repeating: "f", count: 40), size: 4_096)

        XCTAssertThrowsError(
            try LocalTorrentCacheManager.prepare(
                descriptor: descriptor,
                policy: .init(
                    maximumCacheBytes: 4_096,
                    minimumFreeBytes: 0,
                    maximumItemBytes: 4_096
                ),
                root: root,
                availableVolumeBytes: 1_000_000,
                cancellationCheck: { throw CancellationError() }
            )
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: existing.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(descriptor.cacheKey).path
            )
        )
    }

    func testCancellationAfterReservationCreationRemovesNewItem() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalTorrentCacheTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let descriptor = try descriptor(hash: String(repeating: "1", count: 40), size: 1)
        var cancellationChecks = 0

        XCTAssertThrowsError(
            try LocalTorrentCacheManager.prepare(
                descriptor: descriptor,
                policy: .init(
                    maximumCacheBytes: 1_024,
                    minimumFreeBytes: 0,
                    maximumItemBytes: 1_024
                ),
                root: root,
                availableVolumeBytes: 1_000_000,
                cancellationCheck: {
                    cancellationChecks += 1
                    if cancellationChecks == 5 { throw CancellationError() }
                }
            )
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(descriptor.cacheKey).path
            )
        )
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

    func testCachePreparationExcludesRootAndItemFromBackup() throws {
        let root = try XCTUnwrap(
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        )
            .appendingPathComponent("LocalTorrentCacheTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let descriptor = try descriptor(hash: String(repeating: "e", count: 40), size: 1)

        let item = try LocalTorrentCacheManager.prepare(
            descriptor: descriptor,
            policy: .init(
                maximumCacheBytes: 1_024,
                minimumFreeBytes: 0,
                maximumItemBytes: 1_024
            ),
            root: root,
            availableVolumeBytes: 1_000_000
        )

        XCTAssertEqual(
            try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup,
            true
        )
        XCTAssertEqual(
            try item.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup,
            true
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
