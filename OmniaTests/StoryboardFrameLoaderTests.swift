import AppKit
import Foundation
import XCTest
@testable import Omnia

final class StoryboardFrameLoaderTests: XCTestCase {
    private let twoPixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAFElEQVR42mP4z8DwH4QZGBgYGJgAAAwBAf8CBTYAAAAASUVORK5CYII="
    )!

    func testLoadsSameOriginTileWithBoundedPolicyAndOutput() async throws {
        let url = try XCTUnwrap(URL(string: "https://media.example/sheet.png"))
        let descriptor = PlaybackStoryboardDescriptor(
            allowedOriginURL: url,
            tiles: [
                .init(
                    startTime: 0,
                    endTime: 10,
                    imageURL: url,
                    crop: PlaybackStoryboardCrop(x: 0, y: 0, width: 1, height: 1)
                ),
            ]
        )
        let transport = RecordingStoryboardTransport(data: twoPixelPNG)

        let result = try await StoryboardFrameLoader.image(
            for: 1,
            descriptor: descriptor,
            transport: transport,
            requestHeaders: ["Authorization": "Bearer test"]
        )

        XCTAssertLessThanOrEqual(result.image.size.width, 320)
        XCTAssertLessThanOrEqual(result.image.size.height, 180)
        XCTAssertEqual(result.byteCount, 320 * 180 * 4)
        let recordedPolicy = await transport.lastPolicy()
        let policy = try XCTUnwrap(recordedPolicy)
        XCTAssertLessThanOrEqual(policy.maximumResponseBytes, 4 * 1_024 * 1_024)
        XCTAssertEqual(policy.acceptedContentTypes, ["image/jpeg", "image/png"])
        XCTAssertEqual(policy.requestHeaders["Authorization"], "Bearer test")
    }

    func testRejectsUnsafeDescriptorBeforeTransport() async throws {
        let safe = try XCTUnwrap(URL(string: "https://media.example/sheet.png"))
        let unsafeURLs = [
            try XCTUnwrap(URL(string: "http://media.example/sheet.png")),
            try XCTUnwrap(URL(string: "https://other.example/sheet.png")),
        ]

        for imageURL in unsafeURLs {
            let descriptor = PlaybackStoryboardDescriptor(
                allowedOriginURL: safe,
                tiles: [.init(startTime: 0, endTime: 10, imageURL: imageURL, crop: nil)]
            )
            let transport = RecordingStoryboardTransport(data: twoPixelPNG)
            do {
                _ = try await StoryboardFrameLoader.image(
                    for: 1,
                    descriptor: descriptor,
                    transport: transport,
                    requestHeaders: [:]
                )
                XCTFail("Expected unsafe descriptor rejection")
            } catch {}
            let requestCount = await transport.requestCount()
            XCTAssertEqual(requestCount, 0)
        }
    }

    func testInvalidImageBytesAreRejected() async throws {
        let url = try XCTUnwrap(URL(string: "https://media.example/sheet.png"))
        let descriptor = PlaybackStoryboardDescriptor(
            allowedOriginURL: url,
            tiles: [.init(startTime: 0, endTime: 10, imageURL: url, crop: nil)]
        )

        do {
            _ = try await StoryboardFrameLoader.image(
                for: 1,
                descriptor: descriptor,
                transport: RecordingStoryboardTransport(data: Data("not image".utf8)),
                requestHeaders: [:]
            )
            XCTFail("Expected invalid image")
        } catch {
            XCTAssertEqual(error as? StoryboardFrameLoaderError, .invalidImage)
        }
    }

    func testRedirectRejectedStoryboardImageIsRejected() async throws {
        let url = try XCTUnwrap(URL(string: "https://media.example/sheet.jpg"))
        let descriptor = PlaybackStoryboardDescriptor(
            allowedOriginURL: url,
            tiles: [.init(startTime: 0, endTime: 10, imageURL: url, crop: nil)]
        )
        let transport = FailingStoryboardTransport(error: .redirectRejected)

        do {
            _ = try await StoryboardFrameLoader.image(
                for: 1,
                descriptor: descriptor,
                transport: transport,
                requestHeaders: [:]
            )
            XCTFail("Expected redirect rejection")
        } catch {
            XCTAssertEqual(error as? HTTPTransportError, .redirectRejected)
        }
    }
}

private actor RecordingStoryboardTransport: HTTPTransporting {
    private let data: Data
    private var policies: [HTTPRequestPolicy] = []

    init(data: Data) {
        self.data = data
    }

    func data(for policy: HTTPRequestPolicy) async throws -> Data {
        policies.append(policy)
        return data
    }

    func lastPolicy() -> HTTPRequestPolicy? { policies.last }
    func requestCount() -> Int { policies.count }
}

private actor FailingStoryboardTransport: HTTPTransporting {
    let error: HTTPTransportError

    init(error: HTTPTransportError) {
        self.error = error
    }

    func data(for policy: HTTPRequestPolicy) async throws -> Data {
        throw error
    }
}
