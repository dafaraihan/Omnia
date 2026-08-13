import Foundation
import XCTest
@testable import Omnia

final class DiscMaterializerTests: XCTestCase {
    func testWritesVerifiedDirectoryTreeInsideReservation() async throws {
        let reservation = temporaryReservation()
        defer { try? FileManager.default.removeItem(at: reservation) }
        let files = [
            file("Movie/BDMV/index.bdmv", index: 0, size: 3),
            file("Movie/BDMV/STREAM/00001.m2ts", index: 1, size: 4),
        ]
        let materializer = DiscMaterializer(
            reservationRoot: reservation,
            reservedBytes: 7
        )

        let events = try await collect(
            await materializer.materialize(
                .bluRayDirectory(root: "Movie", files: files),
                source: FixtureDiscByteSource(contents: [
                    0: [Data("idx".utf8)],
                    1: [Data("data".utf8)],
                ])
            )
        )

        guard case let .ready(result) = events.last else {
            return XCTFail("Expected a completed disc")
        }
        XCTAssertTrue(result.rootURL.path.hasPrefix(reservation.path + "/"))
        XCTAssertEqual(result.kindHint, .bluRayDirectory)
        XCTAssertEqual(result.bytes, 7)
        XCTAssertEqual(
            try Data(contentsOf: result.rootURL.appendingPathComponent("BDMV/index.bdmv")),
            Data("idx".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: result.rootURL.appendingPathComponent("BDMV/STREAM/00001.m2ts")),
            Data("data".utf8)
        )
    }

    func testMaterializesDetectedBluRayRootCaseInsensitively() async throws {
        let reservation = temporaryReservation()
        defer { try? FileManager.default.removeItem(at: reservation) }
        let files = [file("movie/BDMV/index.bdmv", index: 0, size: 3)]
        let materializer = DiscMaterializer(
            reservationRoot: reservation,
            reservedBytes: 3
        )

        let events = try await collect(
            await materializer.materialize(
                .bluRayDirectory(root: "Movie", files: files),
                source: FixtureDiscByteSource(contents: [0: [Data("idx".utf8)]])
            )
        )

        guard case let .ready(result) = events.last else {
            return XCTFail("Expected a completed disc")
        }
        XCTAssertEqual(
            try Data(contentsOf: result.rootURL.appendingPathComponent("BDMV/index.bdmv")),
            Data("idx".utf8)
        )
    }

    func testRejectsInsufficientReservationBeforeReadingSource() async throws {
        let reservation = temporaryReservation()
        defer { try? FileManager.default.removeItem(at: reservation) }
        let source = CountingDiscByteSource(contents: [0: [Data("image".utf8)]])
        let materializer = DiscMaterializer(
            reservationRoot: reservation,
            reservedBytes: 4
        )

        do {
            _ = try await collect(
                await materializer.materialize(
                    .iso(file("Movie.iso", index: 0, size: 5)),
                    source: source
                )
            )
            XCTFail("Expected the reservation to be rejected")
        } catch {
            XCTAssertEqual(error as? DiscMaterializationError, .insufficientReservation)
        }
        let readCount = await source.readCount
        XCTAssertEqual(readCount, 0)
    }

    func testByteCountMismatchRemovesPartialOutput() async throws {
        let reservation = temporaryReservation()
        defer { try? FileManager.default.removeItem(at: reservation) }
        let materializer = DiscMaterializer(
            reservationRoot: reservation,
            reservedBytes: 5
        )

        do {
            _ = try await collect(
                await materializer.materialize(
                    .iso(file("Movie.iso", index: 0, size: 5)),
                    source: FixtureDiscByteSource(contents: [0: [Data("four".utf8)]])
                )
            )
            XCTFail("Expected exact byte-count enforcement")
        } catch {
            XCTAssertEqual(error as? DiscMaterializationError, .byteCountMismatch)
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: reservation.appendingPathComponent("Media/Movie.iso.partial").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: reservation.appendingPathComponent("complete.plist").path
            )
        )
    }

    func testRejectsPreexistingSymlinkWithoutWritingThroughIt() async throws {
        let reservation = temporaryReservation()
        let outside = temporaryReservation()
        defer {
            try? FileManager.default.removeItem(at: reservation)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createDirectory(at: reservation, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: reservation.appendingPathComponent("Media"),
            withDestinationURL: outside
        )
        let materializer = DiscMaterializer(
            reservationRoot: reservation,
            reservedBytes: 5,
            retainsIncompleteJobs: true
        )

        do {
            _ = try await collect(
                await materializer.materialize(
                    .iso(file("Movie.iso", index: 0, size: 5)),
                    source: FixtureDiscByteSource(contents: [0: [Data("image".utf8)]])
                )
            )
            XCTFail("Expected the symlink to be rejected")
        } catch {
            XCTAssertEqual(error as? DiscMaterializationError, .unsafeReservation)
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: outside.appendingPathComponent("Movie.iso").path)
        )
    }

    func testCompletionMarkerIsLastAndProgressNeverExceedsTotal() async throws {
        let reservation = temporaryReservation()
        defer { try? FileManager.default.removeItem(at: reservation) }
        let materializer = DiscMaterializer(
            reservationRoot: reservation,
            reservedBytes: 5
        )

        let events = try await collect(
            await materializer.materialize(
                .iso(file("Movie.iso", index: 0, size: 5)),
                source: FixtureDiscByteSource(contents: [
                    0: [Data("im".utf8), Data("age".utf8)],
                ])
            )
        )

        let progress = events.compactMap { event -> (Int64, Int64)? in
            guard case let .progress(completedBytes, totalBytes) = event else { return nil }
            return (completedBytes, totalBytes)
        }
        XCTAssertEqual(progress.map(\.0), [2, 5])
        XCTAssertTrue(progress.allSatisfy { $0.0 <= $0.1 && $0.1 == 5 })
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: reservation.appendingPathComponent("complete.plist").path
            )
        )
        guard case .ready = events.last else {
            return XCTFail("Ready must be the final event")
        }
    }

    func testSourceFailureRemovesIncompleteJobAndDoesNotWriteCompletionMarker() async throws {
        let reservation = temporaryReservation()
        defer { try? FileManager.default.removeItem(at: reservation) }
        let materializer = DiscMaterializer(
            reservationRoot: reservation,
            reservedBytes: 5
        )

        do {
            _ = try await collect(
                await materializer.materialize(
                    .iso(file("Movie.iso", index: 0, size: 5)),
                    source: FailingDiscByteSource()
                )
            )
            XCTFail("Expected the source error")
        } catch {
            XCTAssertEqual(error as? FixtureSourceError, .unavailable)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: reservation.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: reservation.appendingPathComponent("complete.plist").path
            )
        )
    }

    func testCancellationDuringSecondFileRemovesIncompleteJob() async throws {
        let reservation = temporaryReservation()
        defer { try? FileManager.default.removeItem(at: reservation) }
        let source = BlockingSecondFileDiscByteSource()
        let materializer = DiscMaterializer(
            reservationRoot: reservation,
            reservedBytes: 2
        )
        let stream = await materializer.materialize(
            .bluRayDirectory(
                root: "Movie",
                files: [
                    file("Movie/BDMV/index.bdmv", index: 0, size: 1),
                    file("Movie/BDMV/STREAM/00001.m2ts", index: 1, size: 1),
                ]
            ),
            source: source
        )
        let collection = Task { try await collect(stream) }

        for _ in 0..<10_000 {
            if await source.hasRequestedSecondFile { break }
            await Task.yield()
        }
        let requestedSecondFile = await source.hasRequestedSecondFile
        XCTAssertTrue(requestedSecondFile)
        await materializer.cancel()

        do {
            _ = try await collection.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: reservation.path))
    }

    private func collect(
        _ stream: AsyncThrowingStream<DiscMaterializationEvent, Error>
    ) async throws -> [DiscMaterializationEvent] {
        var events: [DiscMaterializationEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    private func temporaryReservation() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DiscMaterializerTests.\(UUID().uuidString)", isDirectory: true)
    }

    private func file(_ path: String, index: Int, size: Int64) -> TorrentMediaFile {
        TorrentMediaFile(index: index, relativePath: path, size: size)
    }
}

private struct FixtureDiscByteSource: DiscByteSource {
    let contents: [Int: [Data]]

    func bytes(for file: TorrentMediaFile) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            for chunk in contents[file.index, default: []] {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}

private actor CountingDiscByteSource: DiscByteSource {
    let contents: [Int: [Data]]
    private(set) var readCount = 0

    init(contents: [Int: [Data]]) {
        self.contents = contents
    }

    nonisolated func bytes(for file: TorrentMediaFile) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let chunks = await read(file.index)
                for chunk in chunks {
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }

    private func read(_ index: Int) -> [Data] {
        readCount += 1
        return contents[index, default: []]
    }
}

private enum FixtureSourceError: Error, Equatable {
    case unavailable
}

private struct FailingDiscByteSource: DiscByteSource {
    func bytes(for file: TorrentMediaFile) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(Data("pa".utf8))
            continuation.finish(throwing: FixtureSourceError.unavailable)
        }
    }
}

private actor BlockingSecondFileDiscByteSource: DiscByteSource {
    private(set) var hasRequestedSecondFile = false

    nonisolated func bytes(for file: TorrentMediaFile) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let producer = Task {
                if file.index == 0 {
                    continuation.yield(Data("a".utf8))
                    continuation.finish()
                    return
                }

                await markSecondFileRequested()
                do {
                    try await Task.sleep(for: .seconds(30))
                    continuation.yield(Data("b".utf8))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                producer.cancel()
            }
        }
    }

    private func markSecondFileRequested() {
        hasRequestedSecondFile = true
    }
}
