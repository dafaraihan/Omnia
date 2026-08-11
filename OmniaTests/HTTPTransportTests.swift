import Foundation
import XCTest
@testable import Omnia

final class HTTPTransportTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testReturnsBoundedJSONFromAllowedHTTPSOrigin() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://introdb.app/segments")
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json; charset=utf-8"]
                )!,
                Data("{\"segments\":[]}".utf8)
            )
        }
        let transport = makeTransport()

        let data = try await transport.data(for: makePolicy())

        XCTAssertEqual(String(decoding: data, as: UTF8.self), "{\"segments\":[]}")
    }

    func testRejectsNonHTTPSRequestBeforeLoading() async {
        let transport = makeTransport()
        let policy = HTTPRequestPolicy(
            url: URL(string: "http://introdb.app/segments")!,
            allowedOrigin: NormalizedOrigin(scheme: "https", host: "introdb.app", port: nil),
            timeout: 20,
            maximumResponseBytes: 256_000,
            acceptedContentTypes: ["application/json"]
        )

        await assertThrows(.httpsRequired) {
            try await transport.data(for: policy)
        }
    }

    func testRejectsRequestOutsideAllowedOrigin() async {
        let transport = makeTransport()
        let policy = HTTPRequestPolicy(
            url: URL(string: "https://example.test/segments")!,
            allowedOrigin: NormalizedOrigin(scheme: "https", host: "introdb.app", port: nil),
            timeout: 20,
            maximumResponseBytes: 256_000,
            acceptedContentTypes: ["application/json"]
        )

        await assertThrows(.originRejected) {
            try await transport.data(for: policy)
        }
    }

    func testRejectsCrossOriginRedirectPolicy() {
        let origin = NormalizedOrigin(scheme: "https", host: "introdb.app", port: nil)

        XCTAssertTrue(origin.permits(URL(string: "https://introdb.app/other")!))
        XCTAssertFalse(origin.permits(URL(string: "https://example.test/other")!))
        XCTAssertFalse(origin.permits(URL(string: "http://introdb.app/other")!))
    }

    func testRejectsUnexpectedContentType() async {
        StubURLProtocol.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/html"]
                )!,
                Data("<html></html>".utf8)
            )
        }

        await assertThrows(.unsupportedContentType) {
            try await makeTransport().data(for: makePolicy())
        }
    }

    func testRejectsResponseOverByteLimit() async {
        StubURLProtocol.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(repeating: 0x41, count: 9)
            )
        }
        var policy = makePolicy()
        policy.maximumResponseBytes = 8

        await assertThrows(.responseTooLarge) {
            try await makeTransport().data(for: policy)
        }
    }

    func testLocalizedErrorDoesNotRevealRequestURL() {
        let message = HTTPTransportError.originRejected.errorDescription ?? ""

        XCTAssertFalse(message.contains("http"))
        XCTAssertFalse(message.contains("introdb"))
    }

    private func makeTransport() -> HTTPTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return HTTPTransport(configuration: configuration)
    }

    private func makePolicy() -> HTTPRequestPolicy {
        HTTPRequestPolicy(
            url: URL(string: "https://introdb.app/segments")!,
            allowedOrigin: NormalizedOrigin(scheme: "https", host: "introdb.app", port: nil),
            timeout: 20,
            maximumResponseBytes: 256_000,
            acceptedContentTypes: ["application/json"]
        )
    }

    private func assertThrows(
        _ expected: HTTPTransportError,
        operation: () async throws -> Data,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? HTTPTransportError, expected, file: file, line: line)
        }
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
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
