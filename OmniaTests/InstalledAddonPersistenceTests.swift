import XCTest
@testable import Omnia

final class InstalledAddonPersistenceTests: XCTestCase {
    @MainActor
    func testRoundTripKeepsManifestURLInKeychainAndOutOfDefaults() async throws {
        let suiteName = "InstalledAddonPersistenceTests.\(UUID().uuidString)"
        let storageKey = "installed-addons-test"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let persistence = InstalledAddonPersistence(defaults: defaults, storageKey: storageKey)
        let addon = makeAddon(id: "org.omnia.tests.\(UUID().uuidString)")
        let manifestURLString = addon.manifestURL.absoluteString

        await persistence.save([addon])
        let storedData = try XCTUnwrap(defaults.data(forKey: storageKey))
        let storedText = String(decoding: storedData, as: UTF8.self)

        XCTAssertFalse(storedText.contains(manifestURLString))
        let result = await persistence.load()
        XCTAssertEqual(result.addons, [addon])
        XCTAssertTrue(result.issues.isEmpty)

        await persistence.remove(addon, remainingAddons: [])
        let remainingResult = await persistence.load()
        XCTAssertEqual(remainingResult.addons, [])
        defaults.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    func testLoadPreservesValidSiblingWhenOneSecureEndpointIsMissing() async throws {
        let suiteName = "InstalledAddonPersistenceTests.\(UUID().uuidString)"
        let storageKey = "installed-addons-test"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let persistence = InstalledAddonPersistence(defaults: defaults, storageKey: storageKey)
        let validAddon = makeAddon(id: "org.omnia.tests.valid.\(UUID().uuidString)")
        let unavailableAddon = makeAddon(id: "org.omnia.tests.unavailable.\(UUID().uuidString)")

        await persistence.save([validAddon, unavailableAddon])
        let storedData = try XCTUnwrap(defaults.data(forKey: storageKey))
        unavailableAddon.removeSecureManifestURL()

        let result = await persistence.load()

        XCTAssertEqual(result.addons, [validAddon])
        XCTAssertEqual(
            result.issues,
            [
                InstalledAddonRestoreIssue(
                    addonID: unavailableAddon.id,
                    addonName: unavailableAddon.manifest.name
                )
            ]
        )
        XCTAssertEqual(defaults.data(forKey: storageKey), storedData)

        await persistence.remove(validAddon, remainingAddons: [])
        defaults.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    func testReinstallingUnavailableAddonClearsItsRestoreIssue() {
        let addon = makeAddon(id: "org.omnia.tests.reinstalled")
        let store = OmniaStore(
            library: [],
            installedAddons: [],
            installedAddonRestoreIssues: [
                InstalledAddonRestoreIssue(
                    addonID: addon.id,
                    addonName: addon.manifest.name
                )
            ]
        )

        store.add(addon)

        XCTAssertEqual(store.installedAddons, [addon])
        XCTAssertTrue(store.installedAddonRestoreIssues.isEmpty)
    }

    private func makeAddon(id: String) -> InstalledAddon {
        InstalledAddon(
            manifest: StremioAddonManifest(
                id: id,
                version: "1.0.0",
                name: "Persistence Fixture",
                description: "Fixture",
                resources: [.name("stream")],
                types: ["movie"],
                catalogs: [],
                addonCatalogs: nil,
                idPrefixes: nil,
                behaviorHints: nil
            ),
            manifestURL: URL(string: "https://addon.example/private/manifest.json?token=test")!,
            isEnabled: true,
            addedAt: Date(timeIntervalSince1970: 1)
        )
    }
}
