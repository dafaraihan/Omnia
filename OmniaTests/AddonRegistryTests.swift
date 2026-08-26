import XCTest
@testable import Omnia

@MainActor
final class AddonRegistryTests: XCTestCase {
    func testToggleAndMovePreserveStableRegistryOrder() {
        let first = makeAddon(id: "first")
        let second = makeAddon(id: "second")
        defer {
            first.removeSecureManifestURL()
            second.removeSecureManifestURL()
        }
        let registry = AddonRegistry(addons: [first, second])

        registry.toggle(id: "first")
        registry.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)

        XCTAssertEqual(registry.addons.map(\.id), ["second", "first"])
        XCTAssertFalse(registry.addons[1].isEnabled)
    }

    func testAddingDuplicateIdentityReplacesInPlace() {
        let original = makeAddon(id: "same", name: "Original")
        let replacement = makeAddon(id: "same", name: "Replacement")
        defer { replacement.removeSecureManifestURL() }
        let registry = AddonRegistry(addons: [original])

        registry.add(replacement)

        XCTAssertEqual(registry.addons.count, 1)
        XCTAssertEqual(registry.addons[0].manifest.name, "Replacement")
    }

    func testConfirmedRemovalDeletesTheInstalledAddon() {
        let addon = makeAddon(id: "remove-me")
        let registry = AddonRegistry(addons: [addon])

        registry.remove(id: addon.id)

        XCTAssertTrue(registry.addons.isEmpty)
    }

    private func makeAddon(id: String, name: String? = nil) -> InstalledAddon {
        InstalledAddon(
            manifest: StremioAddonManifest(
                id: id,
                version: "1.0.0",
                name: name ?? id,
                description: "Fixture",
                resources: [.name("stream")],
                types: ["movie"],
                catalogs: [],
                addonCatalogs: nil,
                idPrefixes: nil,
                behaviorHints: nil
            ),
            manifestURL: URL(string: "https://\(id).example/manifest.json")!,
            isEnabled: true,
            addedAt: Date(timeIntervalSince1970: 1)
        )
    }
}
