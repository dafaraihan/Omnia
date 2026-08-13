import Foundation
import XCTest
@testable import Omnia

final class HTTPSDiscByteSourceTests: XCTestCase {
    override func tearDown() {
        DiscURLProtocol.handler = nil
        super.tearDown()
    }

    func testProbesExactSizeAndStreamsExtensionlessHTTPSMedia() async throws {
        let payload = Data("disc-image".utf8)
        DiscURLProtocol.handler = { request in
            switch request.httpMethod {
            case "HEAD":
                return response(for: request, length: payload.count, data: Data())
            case "GET":
                XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Omnia Test")
                XCTAssertNil(request.value(forHTTPHeaderField: "Range"))
                XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
                return response(for: request, length: payload.count, data: payload)
            default:
                throw URLError(.badServerResponse)
            }
        }

        let source = try await HTTPSDiscByteSource.prepare(
            url: URL(string: "https://media.example/download/opaque")!,
            maximumBytes: 32,
            requestHeaders: [
                "User-Agent": "Omnia Test",
                "Range": "bytes=0-9",
                "Cookie": "private=value",
            ],
            configuration: configuration()
        )
        let file = TorrentMediaFile(index: 0, relativePath: "Movie.iso", size: 10)
        var received = Data()
        for try await chunk in source.bytes(for: file) {
            received.append(chunk)
        }

        XCTAssertEqual(source.expectedByteCount, 10)
        XCTAssertEqual(received, payload)
    }

    func testRejectsMissingLengthAndOverQuotaBeforeGET() async {
        var methods: [String] = []
        DiscURLProtocol.handler = { request in
            methods.append(request.httpMethod ?? "")
            return response(for: request, length: nil, data: Data())
        }

        await assertPrepareThrows(.invalidContentLength) {
            try await HTTPSDiscByteSource.prepare(
                url: URL(string: "https://media.example/movie.iso")!,
                maximumBytes: 32,
                configuration: configuration()
            )
        }
        XCTAssertEqual(methods, ["HEAD"])

        methods = []
        DiscURLProtocol.handler = { request in
            methods.append(request.httpMethod ?? "")
            return response(for: request, length: 33, data: Data())
        }
        await assertPrepareThrows(.sourceTooLarge) {
            try await HTTPSDiscByteSource.prepare(
                url: URL(string: "https://media.example/movie.iso")!,
                maximumBytes: 32,
                configuration: configuration()
            )
        }
        XCTAssertEqual(methods, ["HEAD"])
    }

    func testRejectsInsecureCredentialedAndMismatchedFileRequests() async throws {
        await assertPrepareThrows(.httpsRequired) {
            try await HTTPSDiscByteSource.prepare(
                url: URL(string: "http://media.example/movie.iso")!,
                maximumBytes: 32,
                configuration: configuration()
            )
        }
        await assertPrepareThrows(.credentialedURL) {
            try await HTTPSDiscByteSource.prepare(
                url: URL(string: "https://user:secret@media.example/movie.iso")!,
                maximumBytes: 32,
                configuration: configuration()
            )
        }

        DiscURLProtocol.handler = { request in
            response(for: request, length: 10, data: Data("disc-image".utf8))
        }
        let source = try await HTTPSDiscByteSource.prepare(
            url: URL(string: "https://media.example/movie.iso")!,
            maximumBytes: 32,
            configuration: configuration()
        )
        do {
            for try await _ in source.bytes(
                for: TorrentMediaFile(index: 1, relativePath: "Other.iso", size: 9)
            ) {}
            XCTFail("Expected the declared file size to be rejected")
        } catch {
            XCTAssertEqual(error as? HTTPSDiscByteSourceError, .fileSizeMismatch)
        }
    }

    private func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DiscURLProtocol.self]
        return configuration
    }

    private func assertPrepareThrows(
        _ expected: HTTPSDiscByteSourceError,
        operation: () async throws -> HTTPSDiscByteSource,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? HTTPSDiscByteSourceError, expected, file: file, line: line)
        }
    }
}

private func response(
    for request: URLRequest,
    length: Int?,
    data: Data
) -> (HTTPURLResponse, Data) {
    var headers = ["Content-Type": "application/octet-stream"]
    if let length { headers["Content-Length"] = String(length) }
    return (
        HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: headers
        )!,
        data
    )
}

private final class DiscURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
