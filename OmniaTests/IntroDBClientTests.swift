import XCTest
@testable import Omnia

final class IntroDBClientTests: XCTestCase {
    func testBuildsDocumentedReadOnlyRequestAndDecodesSegments() async throws {
        let transport = IntroDBTransportStub(data: try fixture("segments-valid.json"))
        let client = IntroDBClient(transport: transport)

        let segments = try await client.segments(imdbID: "tt0903747", season: 1, episode: 1)
        let policy = await transport.lastPolicy

        XCTAssertEqual(policy?.url.absoluteString, "https://api.introdb.app/segments?imdb_id=tt0903747&season=1&episode=1")
        XCTAssertEqual(policy?.allowedOrigin, NormalizedOrigin(scheme: "https", host: "api.introdb.app", port: nil))
        XCTAssertEqual(policy?.maximumResponseBytes, 256 * 1_024)
        XCTAssertEqual(segments.map(\.kind), [.intro, .outro])
        XCTAssertEqual(segments[0].startSeconds, 2)
        XCTAssertEqual(segments[0].endSeconds, 58)
    }

    func testRejectsInvalidIdentifiersMalformedAndOversizedPayloads() async throws {
        let malformed = IntroDBClient(transport: IntroDBTransportStub(data: try fixture("segments-malformed.json")))
        await XCTAssertThrowsErrorAsync { try await malformed.segments(imdbID: "tt0903747", season: 1, episode: 1) }
        await XCTAssertThrowsErrorAsync { try await malformed.segments(imdbID: "not-imdb", season: 1, episode: 1) }

        let oversized = IntroDBClient(
            transport: IntroDBTransportStub(data: Data(repeating: 0, count: 256 * 1_024 + 1))
        )
        await XCTAssertThrowsErrorAsync { try await oversized.segments(imdbID: "tt0903747", season: 1, episode: 1) }
    }

    func testCancellationIsPreserved() async {
        let client = IntroDBClient(transport: CancellingIntroDBTransport())
        await XCTAssertThrowsErrorAsync {
            try await client.segments(imdbID: "tt0903747", season: 1, episode: 1)
        }
    }

    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/IntroDB/\(name)")
        return try Data(contentsOf: url)
    }
}

private actor IntroDBTransportStub: HTTPTransporting {
    let data: Data
    private(set) var lastPolicy: HTTPRequestPolicy?

    init(data: Data) { self.data = data }

    func data(for policy: HTTPRequestPolicy) async throws -> Data {
        lastPolicy = policy
        guard data.count <= policy.maximumResponseBytes else { throw HTTPTransportError.responseTooLarge }
        return data
    }
}

private struct CancellingIntroDBTransport: HTTPTransporting {
    func data(for policy: HTTPRequestPolicy) async throws -> Data {
        throw CancellationError()
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {}
}
