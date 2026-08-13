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
