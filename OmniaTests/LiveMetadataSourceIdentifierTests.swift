import Foundation
import XCTest
@testable import Omnia

@MainActor
final class LiveMetadataSourceIdentifierTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(MetadataSourceURLProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(MetadataSourceURLProtocol.self)
        MetadataSourceURLProtocol.handler = nil
        super.tearDown()
    }

    func testDetailsAddsIMDbFromExactTMDBFallbackWhenTVDBHasNoCrossID() async throws {
        MetadataSourceURLProtocol.handler = { request in
            let payload = try Self.payload(from: request)

            switch (payload["action"] as? String, payload["provider"] as? String) {
            case ("details", "tvdb"):
                return Self.response(
                    for: request,
                    json: #"{"item":{"canonicalKey":"tvdb:series:121361","provider":"tvdb","providerID":"121361","type":"series","title":"Game of Thrones","releaseDate":"2011-04-17","externalIDs":{"tvdb":"121361"}},"cached":true}"#
                )
            case ("search", _):
                return Self.response(
                    for: request,
                    json: #"{"results":[{"canonicalKey":"tmdb:series:1399","provider":"tmdb","providerID":"1399","type":"series","title":"Game of Thrones","releaseDate":"2011-04-17","externalIDs":{"tmdb":"1399"}}],"providers":["tmdb"]}"#
                )
            case ("details", "tmdb"):
                return Self.response(
                    for: request,
                    json: #"{"item":{"canonicalKey":"tmdb:series:1399","provider":"tmdb","providerID":"1399","type":"series","title":"Game of Thrones","releaseDate":"2011-04-17","externalIDs":{"tmdb":"1399","imdb":"tt0944947"}},"cached":false}"#
                )
            default:
                throw URLError(.badServerResponse)
            }
        }
        let store = LiveMetadataStore(
            configuration: .init(
                projectURL: URL(string: "https://metadata.example")!,
                publishableKey: "publishable-test-key"
            ),
            loadsBundleConfiguration: false
        )
        var routing = MetadataRoutingPreferences()
        routing.series.fallbackEnabled = false
        store.configure(metadataRouting: routing)
        let item = MediaItem(
            id: "tvdb:series:121361",
            title: "Game of Thrones",
            year: "2011",
            kind: .series,
            overview: "",
            genres: [],
            symbol: "tv",
            artworkColors: [],
            metadataProvider: .tvdb,
            metadataProviderID: "121361",
            externalIDs: ["tvdb": "121361"],
            progress: nil
        )

        let result = await store.details(for: item)

        XCTAssertEqual(result.externalIDs["imdb"], "tt0944947")
        XCTAssertEqual(
            result.streamIdentifierCandidates,
            ["tt0944947", "tmdb:1399", "tvdb:121361", "tvdb:series:121361"]
        )
    }

    func testDetailsDoesNotMergeTMDBIdentifierFromDifferentReleaseYear() async throws {
        MetadataSourceURLProtocol.handler = { request in
            let payload = try Self.payload(from: request)

            switch (payload["action"] as? String, payload["provider"] as? String) {
            case ("details", "tvdb"):
                return Self.response(
                    for: request,
                    json: #"{"item":{"canonicalKey":"tvdb:series:121361","provider":"tvdb","providerID":"121361","type":"series","title":"Game of Thrones","releaseDate":"2011-04-17","externalIDs":{"tvdb":"121361"}},"cached":true}"#
                )
            case ("search", _):
                return Self.response(
                    for: request,
                    json: #"{"results":[{"canonicalKey":"tmdb:series:9999","provider":"tmdb","providerID":"9999","type":"series","title":"Game of Thrones","releaseDate":"2017-01-01","externalIDs":{"tmdb":"9999"}}],"providers":["tmdb"]}"#
                )
            default:
                XCTFail("A mismatched search result must not trigger TMDB details")
                throw URLError(.badServerResponse)
            }
        }
        let store = LiveMetadataStore(
            configuration: .init(
                projectURL: URL(string: "https://metadata.example")!,
                publishableKey: "publishable-test-key"
            ),
            loadsBundleConfiguration: false
        )
        let item = MediaItem(
            id: "tvdb:series:121361",
            title: "Game of Thrones",
            year: "2011",
            kind: .series,
            overview: "",
            genres: [],
            symbol: "tv",
            artworkColors: [],
            metadataProvider: .tvdb,
            metadataProviderID: "121361",
            externalIDs: ["tvdb": "121361"],
            progress: nil
        )

        let result = await store.details(for: item)

        XCTAssertNil(result.externalIDs["imdb"])
        XCTAssertEqual(result.externalIDs["tvdb"], "121361")
    }

    private static func response(
        for request: URLRequest,
        json: String
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            Data(json.utf8)
        )
    }

    private static func bodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private static func payload(from request: URLRequest) throws -> [String: Any] {
        let body = try bodyData(from: request)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }
}

private final class MetadataSourceURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "metadata.example"
    }

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
