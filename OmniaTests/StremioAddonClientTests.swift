import XCTest
@testable import Omnia

@MainActor
final class StremioAddonClientTests: XCTestCase {
    func testManifestFetchUsesConfiguredTimeoutAndBoundedJSONPolicy() async throws {
        let transport = RecordingTransport(data: validManifestData())

        let manifest = try await StremioAddonClient.fetchManifest(
            from: URL(string: "https://addon.example/manifest.json")!,
            timeout: .seconds5,
            transport: transport
        )
        let policy = await transport.recordedPolicy

        XCTAssertEqual(manifest.id, "org.example.addon")
        XCTAssertEqual(policy?.timeout, 5)
        XCTAssertEqual(policy?.maximumResponseBytes, 1_048_576)
        XCTAssertEqual(policy?.acceptedContentTypes, ["application/json"])
    }

    func testManifestFetchRejectsOversizedIdentityFields() async {
        let longName = String(repeating: "a", count: 257)
        let data = validManifestData(name: longName)
        let transport = RecordingTransport(data: data)

        do {
            _ = try await StremioAddonClient.fetchManifest(
                from: URL(string: "https://addon.example/manifest.json")!,
                timeout: .seconds20,
                transport: transport
            )
            XCTFail("Expected an invalid manifest error")
        } catch {
            XCTAssertEqual(error as? StremioAddonClient.AddonClientError, .invalidManifest)
        }
    }

    func testStreamFetchUsesBoundedTransportInsteadOfSharedSession() async throws {
        let streamData = Data(
            "{\"streams\":[{\"url\":\"https://media.example/video.m3u8\",\"name\":\"HD\"}]}".utf8
        )
        let transport = RecordingTransport(data: streamData)
        let addon = streamAddon()
        defer { addon.removeSecureManifestURL() }

        let candidates = try await StremioAddonClient.fetchStreamCandidates(
            from: addon,
            mediaTypes: ["movie"],
            identifiers: ["tt1234567"],
            timeout: .seconds10,
            transport: transport
        )
        let policy = await transport.recordedPolicy

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(policy?.url.absoluteString, "https://addon.example/stream/movie/tt1234567.json")
        XCTAssertEqual(policy?.timeout, 10)
        XCTAssertEqual(policy?.maximumResponseBytes, 2_097_152)
    }

    func testNotWebReadyDirectHTTPSRemainsAPlayerCandidate() async throws {
        let data = Data(
            """
            {"streams":[{"url":"https://media.example/opaque","name":"Remux","behaviorHints":{"notWebReady":true}}]}
            """.utf8
        )
        let transport = RecordingTransport(data: data)
        let addon = streamAddon()
        defer { addon.removeSecureManifestURL() }

        let candidates = try await StremioAddonClient.fetchStreamCandidates(
            from: addon,
            mediaTypes: ["movie"],
            identifiers: ["tt1234567"],
            timeout: .seconds10,
            transport: transport
        )

        guard case let .nativeHTTPS(url) = try XCTUnwrap(candidates.first).delivery else {
            return XCTFail("Expected direct HTTPS delivery")
        }
        XCTAssertEqual(url.absoluteString, "https://media.example/opaque")
    }

    private func validManifestData(name: String = "Example") -> Data {
        let object: [String: Any] = [
            "id": "org.example.addon",
            "version": "1.0.0",
            "name": name,
            "description": "Fixture",
            "resources": ["stream"],
            "types": ["movie"],
            "catalogs": []
        ]
        return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func streamAddon() -> InstalledAddon {
        InstalledAddon(
            manifest: StremioAddonManifest(
                id: "org.example.streams",
                version: "1.0.0",
                name: "Streams",
                description: "Fixture",
                resources: [.name("stream")],
                types: ["movie"],
                catalogs: [],
                addonCatalogs: nil,
                idPrefixes: nil,
                behaviorHints: nil
            ),
            manifestURL: URL(string: "https://addon.example/manifest.json")!,
            isEnabled: true,
            addedAt: Date(timeIntervalSince1970: 1)
        )
    }
}

private actor RecordingTransport: HTTPTransporting {
    let dataToReturn: Data
    private(set) var recordedPolicy: HTTPRequestPolicy?

    init(data: Data) {
        dataToReturn = data
    }

    func data(for policy: HTTPRequestPolicy) async throws -> Data {
        recordedPolicy = policy
        return dataToReturn
    }
}
