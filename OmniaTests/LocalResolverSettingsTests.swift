import XCTest
@testable import Omnia

@MainActor
final class LocalResolverSettingsTests: XCTestCase {
    func testDefaultsRequireConsentAndUseTwentyGigabyteQuota() {
        let value = LocalResolverPreferences.default

        XCTAssertFalse(value.hasCurrentConsent)
        XCTAssertEqual(value.cacheQuota, .gigabytes20)
        XCTAssertEqual(value.downloadLimitKilobytesPerSecond, 0)
        XCTAssertEqual(value.uploadLimitKilobytesPerSecond, 1_024)
        XCTAssertFalse(value.retainsIncompleteJobs)
    }

    func testStoreRoundTripsAndBoundsBandwidthValues() throws {
        let suiteName = "LocalResolverSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LocalResolverSettingsStore(defaults: defaults)
        store.update {
            $0.acceptedConsentVersion = LocalResolverPreferences.consentVersion
            $0.cacheQuota = .gigabytes50
            $0.downloadLimitKilobytesPerSecond = -1
            $0.uploadLimitKilobytesPerSecond = 1_000_001
            $0.retainsIncompleteJobs = true
        }
        let restored = LocalResolverSettingsStore(defaults: defaults)

        XCTAssertTrue(restored.preferences.hasCurrentConsent)
        XCTAssertEqual(restored.preferences.cacheQuota, .gigabytes50)
        XCTAssertEqual(restored.preferences.downloadLimitKilobytesPerSecond, 0)
        XCTAssertEqual(restored.preferences.uploadLimitKilobytesPerSecond, 1_000_000)
        XCTAssertTrue(restored.preferences.retainsIncompleteJobs)
    }

    func testCorruptPayloadRecoversAndConsentCanBeRevoked() throws {
        let suiteName = "LocalResolverSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not-json".utf8), forKey: LocalResolverSettingsStore.storageKey)

        let store = LocalResolverSettingsStore(defaults: defaults)
        XCTAssertEqual(store.preferences, .default)
        store.acceptConsent()
        XCTAssertTrue(store.preferences.hasCurrentConsent)
        store.revokeConsent()
        XCTAssertFalse(store.preferences.hasCurrentConsent)
    }
}
