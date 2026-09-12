#if os(macOS)
import AppKit
import Foundation
import XCTest
@testable import Omnia

@MainActor
final class PlaybackTimelinePreviewServiceTests: XCTestCase {
    func testExplicitStoryboardWinsWithoutStartingHLSOrLocalGenerator() async throws {
        let descriptor = makeStoryboard(sourceID: "explicit")
        let source = makeSource(id: "explicit", descriptor: .storyboard(descriptor))
        let storyboard = PreviewStoryboardLoaderStub(hlsDescriptor: makeStoryboard(sourceID: "hls"))
        let local = PreviewLocalGeneratorStub()
        let service = PlaybackTimelinePreviewService(
            source: source,
            configuration: .init(isLowPowerModeEnabled: false),
            storyboardLoader: storyboard,
            localGenerator: local
        )

        let frame = await service.frame(at: 1)

        let hlsRequestCount = await storyboard.hlsRequestCount
        let imageRequestCount = await storyboard.imageRequestCount
        let localRequestCount = await local.imageRequestCount
        XCTAssertEqual(frame?.sourceID, "explicit")
        XCTAssertEqual(hlsRequestCount, 0)
        XCTAssertEqual(imageRequestCount, 1)
        XCTAssertEqual(localRequestCount, 0)
    }

    func testHLSStoryboardWinsWhenExplicitDescriptorIsAbsent() async throws {
        let source = makeSource(id: "hls", descriptor: nil)
        let storyboard = PreviewStoryboardLoaderStub(hlsDescriptor: makeStoryboard(sourceID: "hls"))
        let local = PreviewLocalGeneratorStub()
        let service = PlaybackTimelinePreviewService(
            source: source,
            configuration: .init(isLowPowerModeEnabled: false),
            storyboardLoader: storyboard,
            localGenerator: local
        )

        let frame = await service.frame(at: 2)

        let hlsRequestCount = await storyboard.hlsRequestCount
        let imageRequestCount = await storyboard.imageRequestCount
        let localRequestCount = await local.imageRequestCount
        XCTAssertNotNil(frame)
        XCTAssertEqual(hlsRequestCount, 1)
        XCTAssertEqual(imageRequestCount, 1)
        XCTAssertEqual(localRequestCount, 0)
    }

    func testLocalGeneratorRunsWhenStoryboardSourcesAreUnavailable() async throws {
        let source = makeSource(id: "local", descriptor: nil)
        let storyboard = PreviewStoryboardLoaderStub(hlsDescriptor: nil)
        let local = PreviewLocalGeneratorStub()
        let service = PlaybackTimelinePreviewService(
            source: source,
            configuration: .init(isLowPowerModeEnabled: false),
            storyboardLoader: storyboard,
            localGenerator: local
        )

        let frame = await service.frame(at: 3)

        let localRequestCount = await local.imageRequestCount
        XCTAssertNotNil(frame)
        XCTAssertEqual(localRequestCount, 1)
    }

    func testRepeatedTimestampUsesCachedFrame() async throws {
        let source = makeSource(id: "cache", descriptor: nil)
        let local = PreviewLocalGeneratorStub()
        let service = PlaybackTimelinePreviewService(
            source: source,
            configuration: .init(isLowPowerModeEnabled: false),
            storyboardLoader: PreviewStoryboardLoaderStub(hlsDescriptor: nil),
            localGenerator: local
        )

        _ = await service.frame(at: 120.2)
        _ = await service.frame(at: 120.8)

        let localRequestCount = await local.imageRequestCount
        XCTAssertEqual(localRequestCount, 1)
    }

    func testStoryboardTimestampsInOneTileUseCachedFrame() async throws {
        let descriptor = makeStoryboard(sourceID: "tile")
        let storyboard = PreviewStoryboardLoaderStub(hlsDescriptor: nil)
        let service = PlaybackTimelinePreviewService(
            source: makeSource(id: "tile", descriptor: .storyboard(descriptor)),
            configuration: .init(isLowPowerModeEnabled: false),
            storyboardLoader: storyboard,
            localGenerator: PreviewLocalGeneratorStub()
        )

        _ = await service.frame(at: 1)
        _ = await service.frame(at: 59)

        let imageRequestCount = await storyboard.imageRequestCount
        XCTAssertEqual(imageRequestCount, 1)
    }

    func testLocalFallbackDoesNotCollideWithStoryboardCacheKey() async throws {
        let descriptor = makeStoryboard(sourceID: "fallback")
        let storyboard = PreviewStoryboardLoaderStub(
            hlsDescriptor: nil,
            imageFailureCount: 1
        )
        let local = PreviewLocalGeneratorStub()
        let service = PlaybackTimelinePreviewService(
            source: makeSource(id: "fallback", descriptor: .storyboard(descriptor)),
            configuration: .init(isLowPowerModeEnabled: false),
            storyboardLoader: storyboard,
            localGenerator: local
        )

        _ = await service.frame(at: 0.5)
        _ = await service.frame(at: 0.5)

        let storyboardRequestCount = await storyboard.imageRequestCount
        let localRequestCount = await local.imageRequestCount
        XCTAssertEqual(storyboardRequestCount, 2)
        XCTAssertEqual(localRequestCount, 1)
    }

    func testUnavailableHLSDescriptorIsResolvedOnlyOnce() async throws {
        let storyboard = PreviewStoryboardLoaderStub(hlsDescriptor: nil)
        let local = PreviewLocalGeneratorStub()
        let service = PlaybackTimelinePreviewService(
            source: makeSource(id: "no-hls", descriptor: nil),
            configuration: .init(isLowPowerModeEnabled: false),
            storyboardLoader: storyboard,
            localGenerator: local
        )

        _ = await service.frame(at: 1)
        _ = await service.frame(at: 2)

        let hlsRequestCount = await storyboard.hlsRequestCount
        let localRequestCount = await local.imageRequestCount
        XCTAssertEqual(hlsRequestCount, 1)
        XCTAssertEqual(localRequestCount, 2)
    }

    func testUnavailableHLSDescriptorRemainsResolvedWhenLocalGenerationFails() async throws {
        let storyboard = PreviewStoryboardLoaderStub(hlsDescriptor: nil)
        let local = PreviewLocalGeneratorStub(imageFailureCount: 2)
        let service = PlaybackTimelinePreviewService(
            source: makeSource(id: "no-preview", descriptor: nil),
            configuration: .init(isLowPowerModeEnabled: false),
            storyboardLoader: storyboard,
            localGenerator: local
        )

        let firstFrame = await service.frame(at: 1)
        let secondFrame = await service.frame(at: 2)

        let hlsRequestCount = await storyboard.hlsRequestCount
        let localRequestCount = await local.imageRequestCount
        XCTAssertNil(firstFrame)
        XCTAssertNil(secondFrame)
        XCTAssertEqual(hlsRequestCount, 1)
        XCTAssertEqual(localRequestCount, 2)
    }

    func testCacheKeyIncludesSourceIdentity() {
        XCTAssertNotEqual(
            PlaybackTimelinePreviewCacheKey(sourceID: "a", timestampBucket: 10),
            PlaybackTimelinePreviewCacheKey(sourceID: "b", timestampBucket: 10)
        )
    }

    func testCancelledRequestDoesNotReturnAFrame() async throws {
        let gate = PreviewGenerationGate()
        let local = PreviewLocalGeneratorStub(gate: gate)
        let service = PlaybackTimelinePreviewService(
            source: makeSource(id: "cancel", descriptor: nil),
            configuration: .init(isLowPowerModeEnabled: false),
            storyboardLoader: PreviewStoryboardLoaderStub(hlsDescriptor: nil),
            localGenerator: local
        )
        let first = Task { await service.frame(at: 10) }
        await gate.waitUntilRequested()
        let second = Task { await service.frame(at: 20) }
        await gate.release()

        let firstValue = await first.value
        let secondValue = await second.value
        XCTAssertNil(firstValue)
        XCTAssertNotNil(secondValue)
    }

    func testStopClearsCacheAndStopsLocalGenerator() async throws {
        let local = PreviewLocalGeneratorStub()
        let service = PlaybackTimelinePreviewService(
            source: makeSource(id: "stop", descriptor: nil),
            configuration: .init(isLowPowerModeEnabled: false),
            storyboardLoader: PreviewStoryboardLoaderStub(hlsDescriptor: nil),
            localGenerator: local
        )
        _ = await service.frame(at: 1)
        await service.stop()

        let stopCount = await local.stopCount
        let frameAfterStop = await service.frame(at: 1)
        XCTAssertEqual(stopCount, 1)
        XCTAssertNil(frameAfterStop)
    }
}

private actor PreviewGenerationGate {
    private var requested = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        requested = true
        requestWaiters.forEach { $0.resume() }
        requestWaiters.removeAll()
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilRequested() async {
        if requested { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func release() {
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private actor PreviewStoryboardLoaderStub: PlaybackStoryboardLoading {
    let hlsDescriptor: PlaybackStoryboardDescriptor?
    private var imageFailureCount: Int
    private(set) var hlsRequestCount = 0
    private(set) var imageRequestCount = 0

    init(
        hlsDescriptor: PlaybackStoryboardDescriptor?,
        imageFailureCount: Int = 0
    ) {
        self.hlsDescriptor = hlsDescriptor
        self.imageFailureCount = imageFailureCount
    }

    func hlsStoryboard(for source: PlaybackSource) async throws -> PlaybackStoryboardDescriptor? {
        hlsRequestCount += 1
        return hlsDescriptor
    }

    func image(
        at timestamp: Double,
        descriptor: PlaybackStoryboardDescriptor,
        source: PlaybackSource
    ) async throws -> PlaybackTimelinePreviewImage {
        imageRequestCount += 1
        if imageFailureCount > 0 {
            imageFailureCount -= 1
            throw PreviewStoryboardLoaderError.injectedFailure
        }
        return makePreviewImage()
    }
}

private enum PreviewStoryboardLoaderError: Error {
    case injectedFailure
}

private actor PreviewLocalGeneratorStub: PlaybackLocalFrameGenerating {
    private let gate: PreviewGenerationGate?
    private var imageFailureCount: Int
    private(set) var imageRequestCount = 0
    private(set) var stopCount = 0

    init(
        gate: PreviewGenerationGate? = nil,
        imageFailureCount: Int = 0
    ) {
        self.gate = gate
        self.imageFailureCount = imageFailureCount
    }

    func image(at timestamp: Double, source: PlaybackSource) async throws -> PlaybackTimelinePreviewImage {
        imageRequestCount += 1
        if imageRequestCount == 1, let gate {
            await gate.suspend()
        }
        try Task.checkCancellation()
        if imageFailureCount > 0 {
            imageFailureCount -= 1
            throw PreviewStoryboardLoaderError.injectedFailure
        }
        return makePreviewImage()
    }

    func stop() async {
        stopCount += 1
    }
}

nonisolated private func makePreviewImage() -> PlaybackTimelinePreviewImage {
    PlaybackTimelinePreviewImage(
        image: NSImage(size: NSSize(width: 320, height: 180)),
        byteCount: 320 * 180 * 4
    )
}

nonisolated private func makeStoryboard(sourceID: String) -> PlaybackStoryboardDescriptor {
    let url = URL(string: "https://media.example/\(sourceID).jpg")!
    return PlaybackStoryboardDescriptor(
        allowedOriginURL: url,
        tiles: [.init(startTime: 0, endTime: 60, imageURL: url, crop: nil)]
    )
}

private func makeSource(
    id: String,
    descriptor: PlaybackTimelinePreviewDescriptor?
) -> PlaybackSource {
    PlaybackSource(
        previewID: id,
        url: URL(string: "https://media.example/video.m3u8")!,
        timelinePreviewDescriptor: descriptor
    )
}
#endif
