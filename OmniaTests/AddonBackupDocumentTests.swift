import XCTest
@testable import Omnia

final class AddonBackupDocumentTests: XCTestCase {
    func testExportExcludesConfiguredOrSecretBearingManifestURLs() throws {
        let publicAddon = makeAddon(
            id: "org.example.public",
            manifestURL: URL(string: "https://addon.example/manifest.json")!,
            configurable: false
        )
        let configuredAddon = makeAddon(
            id: "org.example.private",
            manifestURL: URL(string: "https://addon.example/private-token/manifest.json?key=secret")!,
            configurable: true
        )
        defer {
            publicAddon.removeSecureManifestURL()
            configuredAddon.removeSecureManifestURL()
        }

        let result = AddonBackupDocument.exporting([publicAddon, configuredAddon])
        let data = try JSONEncoder().encode(result.document)
        let text = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(result.document.addons.count, 1)
        XCTAssertEqual(result.excludedPrivateCount, 1)
        XCTAssertTrue(text.contains("https:\\/\\/addon.example\\/manifest.json"))
        XCTAssertFalse(text.contains("private-token"))
        XCTAssertFalse(text.contains("secret"))
    }

    func testDecodeRejectsDuplicateManifestReferences() throws {
        let record = AddonBackupDocument.Record(
            manifestURL: URL(string: "https://addon.example/manifest.json")!,
            isEnabled: true
        )
        let data = try JSONEncoder().encode(
            AddonBackupDocument(version: 1, addons: [record, record])
        )

        XCTAssertThrowsError(try AddonBackupDocument.decodeValidated(data)) { error in
            XCTAssertEqual(error as? AddonBackupError, .duplicateManifest)
        }
    }

    private func makeAddon(
        id: String,
        manifestURL: URL,
        configurable: Bool
    ) -> InstalledAddon {
        InstalledAddon(
            manifest: StremioAddonManifest(
                id: id,
                version: "1.0.0",
                name: id,
                description: "Fixture",
                resources: [.name("stream")],
                types: ["movie"],
                catalogs: [],
                addonCatalogs: nil,
                idPrefixes: nil,
                behaviorHints: AddonBehaviorHints(
                    configurable: configurable,
                    configurationRequired: configurable
                )
            ),
            manifestURL: manifestURL,
            isEnabled: true,
            addedAt: Date(timeIntervalSince1970: 1)
        )
    }
}
