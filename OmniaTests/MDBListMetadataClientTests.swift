import XCTest
@testable import Omnia

@MainActor
final class MDBListMetadataClientTests: XCTestCase {
    func testBuildsBoundedTMDBRequestAndDecodesNumberOrStringValues() async throws {
        let transport = MDBListTransportStub(data: Data(Self.validResponse.utf8))
        let client = MDBListMetadataClient(
            transport: transport,
            credentialReader: { "test-key-not-secret" }
        )

        let result = try await client.titleRatings(for: item(externalIDs: ["tmdb": "550"]))
        let policies = await transport.recordedPolicies()
        let policy = try XCTUnwrap(policies.first)
        let components = try XCTUnwrap(URLComponents(url: policy.url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(result?.score, 8.1)
        XCTAssertEqual(
            result?.ratings.map { $0.providerID.rawValue },
            ["imdb", "trakt", "tomatoes", "future_source"]
        )
        XCTAssertEqual(result?.ratings.map(\.value), [7.2, 78, 65, 9.4])
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "api.mdblist.com")
        XCTAssertEqual(components.path, "/tmdb/movie/550")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "apikey", value: "test-key-not-secret")])
        XCTAssertEqual(policy.allowedOrigin, NormalizedOrigin(scheme: "https", host: "api.mdblist.com", port: nil))
        XCTAssertEqual(policy.timeout, 15)
        XCTAssertEqual(policy.maximumResponseBytes, 512 * 1_024)
        XCTAssertEqual(policy.acceptedContentTypes, ["application/json"])
    }

    func testMalformedProviderEntriesDoNotEraseValidSiblingsOrAggregate() async throws {
        let response = #"{"score":8.1,"ratings":[{"source":"imdb","value":7.2},{"source":"trakt","value":"not-a-number"},{"source":"contains/slash","value":80},{"source":"tmdb","value":101},null,{"source":"popcorn","value":"90"}]}"#
        let client = client(data: Data(response.utf8))

        let result = try await client.titleRatings(for: item(externalIDs: ["tmdb": "550"]))

        XCTAssertEqual(result?.score, 8.1)
        XCTAssertEqual(result?.ratings.map(\.providerID), [.imdb, .rottenTomatoesAudience])
        XCTAssertEqual(result?.ratings.map(\.value), [7.2, 90])
    }

    func testResponseAcceptsAtMostFirst64ProviderEntries() async throws {
        let entries: [[String: Any]] = (0..<70).map { index in
            ["source": "future_\(index)", "value": index]
        }
        let data = try JSONSerialization.data(withJSONObject: ["score": 8.0, "ratings": entries])

        let result = try await client(data: data).titleRatings(for: item(externalIDs: ["tmdb": "550"]))

        XCTAssertEqual(result?.ratings.count, 64)
        XCTAssertEqual(result?.ratings.first?.providerID.rawValue, "future_0")
        XCTAssertEqual(result?.ratings.last?.providerID.rawValue, "future_63")
    }

    func testMissingCredentialReturnsNilWithoutTransportRequest() async throws {
        let transport = MDBListTransportStub(data: Data(Self.validResponse.utf8))
        let client = MDBListMetadataClient(transport: transport, credentialReader: { "  " })

        let result = try await client.titleRatings(for: item(externalIDs: ["tmdb": "550"]))

        XCTAssertNil(result)
        let policies = await transport.recordedPolicies()
        XCTAssertEqual(policies.count, 0)
    }

    func testMissingOrInvalidIdentifiersFailBeforeTransportRequest() async {
        let transport = MDBListTransportStub(data: Data(Self.validResponse.utf8))
        let client = MDBListMetadataClient(transport: transport, credentialReader: { "key" })

        await assertMDBListError(.noSupportedIdentifier) {
            try await client.titleRatings(for: self.item(externalIDs: [:]))
        }
        await assertMDBListError(.noSupportedIdentifier) {
            try await client.titleRatings(for: self.item(externalIDs: ["tmdb": "0", "imdb": "tt12"]))
        }
        let policies = await transport.recordedPolicies()
        XCTAssertEqual(policies.count, 0)
    }

    func testRoutePrefersValidTMDBThenTVDBThenIMDbAndUsesShowForSeries() async throws {
        let transport = MDBListTransportStub(data: Data(Self.validResponse.utf8))
        let client = MDBListMetadataClient(transport: transport, credentialReader: { "key" })
        let media = item(
            kind: .series,
            externalIDs: ["tmdb": "123", "tvdb": "456", "imdb": "tt12345"]
        )

        _ = try await client.titleRatings(for: media)

        let policies = await transport.recordedPolicies()
        XCTAssertEqual(policies.first?.url.path, "/tmdb/show/123")
    }

    func testInvalidHigherPriorityIdentifierFallsBackToValidIdentifier() async throws {
        let transport = MDBListTransportStub(data: Data(Self.validResponse.utf8))
        let client = MDBListMetadataClient(transport: transport, credentialReader: { "key" })

        _ = try await client.titleRatings(for: item(externalIDs: ["tmdb": "-1", "imdb": "TT12345"]))

        let policies = await transport.recordedPolicies()
        XCTAssertEqual(policies.first?.url.path, "/imdb/movie/tt12345")
    }

    func testMapsTransportAndHTTPFailuresToNonSecretErrors() async {
        let cases: [(HTTPTransportError, MDBListMetadataError)] = [
            (.unsuccessfulStatus(401), .authenticationRequired),
            (.unsuccessfulStatus(403), .authenticationRequired),
            (.unsuccessfulStatus(404), .notFound),
            (.unsuccessfulStatus(429), .rateLimited),
            (.unsuccessfulStatus(503), .temporarilyUnavailable),
            (.transportFailure, .temporarilyUnavailable),
            (.unsupportedContentType, .malformedResponse),
            (.invalidResponse, .malformedResponse),
            (.responseTooLarge, .responseTooLarge),
            (.redirectRejected, .malformedResponse)
        ]

        for (transportError, expected) in cases {
            let transport = MDBListTransportStub(error: transportError)
            let client = MDBListMetadataClient(transport: transport, credentialReader: { "key" })
            await assertMDBListError(expected) {
                try await client.titleRatings(for: self.item(externalIDs: ["tmdb": "550"]))
            }
        }
    }

    func testRejectsMalformedOrOversizedDataReturnedByInjectedTransport() async {
        await assertMDBListError(.malformedResponse) {
            try await self.client(data: Data("not-json".utf8))
                .titleRatings(for: self.item(externalIDs: ["tmdb": "550"]))
        }
        await assertMDBListError(.responseTooLarge) {
            try await self.client(data: Data(repeating: 0, count: 512 * 1_024 + 1))
                .titleRatings(for: self.item(externalIDs: ["tmdb": "550"]))
        }
    }

    func testCancellationRemainsCancellation() async {
        let transport = MDBListTransportStub(error: .cancelled)
        let client = MDBListMetadataClient(transport: transport, credentialReader: { "key" })

        do {
            _ = try await client.titleRatings(for: item(externalIDs: ["tmdb": "550"]))
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(type(of: error))")
        }
    }

    private func client(data: Data) -> MDBListMetadataClient {
        MDBListMetadataClient(
            transport: MDBListTransportStub(data: data),
            credentialReader: { "key" }
        )
    }

    private func item(
        kind: MediaItem.Kind = .movie,
        externalIDs: [String: String]
    ) -> MediaItem {
        MediaItem(
            id: "fixture",
            title: "Fixture",
            year: "2026",
            kind: kind,
            overview: "",
            genres: [],
            symbol: "film",
            artworkColors: [.clear],
            externalIDs: externalIDs,
            progress: nil
        )
    }

    private static let validResponse = #"{"score":"8.1","ratings":[{"source":"imdb","value":"7.2","votes":"190005"},{"source":"trakt","value":78,"votes":20216},{"source":"tomatoes","value":65,"votes":358},{"source":"future_source","value":"9.4","votes":null}]}"#
}

private actor MDBListTransportStub: HTTPTransporting {
    let data: Data
    let error: HTTPTransportError?
    private(set) var policies: [HTTPRequestPolicy] = []

    init(data: Data = Data(), error: HTTPTransportError? = nil) {
        self.data = data
        self.error = error
    }

    func data(for policy: HTTPRequestPolicy) async throws -> Data {
        policies.append(policy)
        if let error { throw error }
        return data
    }

    func recordedPolicies() -> [HTTPRequestPolicy] {
        policies
    }
}

@MainActor
private func assertMDBListError(
    _ expected: MDBListMetadataError,
    operation: () async throws -> MDBListTitleRatings?
) async {
    do {
        _ = try await operation()
        XCTFail("Expected \(expected)")
    } catch let error as MDBListMetadataError {
        XCTAssertEqual(error, expected)
    } catch {
        XCTFail("Expected MDBListMetadataError, got \(type(of: error))")
    }
}
