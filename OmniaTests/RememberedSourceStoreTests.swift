import XCTest
@testable import Omnia

final class RememberedSourceStoreTests: XCTestCase {
    func testRetentionExpirationAndAddonRemoval() throws {
        let defaults = try makeDefaults()
        var now = Date(timeIntervalSince1970: 1_000)
        let store = RememberedSourceStore(defaults: defaults, now: { now })
        let key = MediaPlaybackKey(rawValue: "series:1:2")

        try store.remember(
            mediaKey: key,
            addonID: "addon",
            bingeGroup: "season-one",
            displayNameFingerprint: "fingerprint",
            retention: .hours24
        )
        XCTAssertNotNil(store.source(for: key, enabledAddonIDs: ["addon"]))

        now.addTimeInterval(SourceSelectionRetention.hours24.duration)
        XCTAssertNil(store.source(for: key, enabledAddonIDs: ["addon"]))

        try store.remember(
            mediaKey: key,
            addonID: "removed",
            bingeGroup: nil,
            displayNameFingerprint: "fingerprint",
            retention: .week1
        )
        XCTAssertNil(store.source(for: key, enabledAddonIDs: ["addon"]))
    }

    func testPersistedJSONContainsNoURLOrHeaders() throws {
        let defaults = try makeDefaults()
        let store = RememberedSourceStore(defaults: defaults, now: { Date(timeIntervalSince1970: 1_000) })
        try store.remember(
            mediaKey: MediaPlaybackKey(rawValue: "movie:one"),
            addonID: "addon",
            bingeGroup: "group",
            displayNameFingerprint: "fingerprint",
            retention: .days3
        )

        let data = try XCTUnwrap(defaults.data(forKey: RememberedSourceStore.storageKey))
        let text = String(decoding: data, as: UTF8.self).lowercased()
        XCTAssertFalse(text.contains("http"))
        XCTAssertFalse(text.contains("header"))
        XCTAssertFalse(text.contains("authorization"))
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "RememberedSourceStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
