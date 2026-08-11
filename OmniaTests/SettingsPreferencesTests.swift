import XCTest
@testable import Omnia

@MainActor
final class SettingsPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsPreferencesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsMatchApprovedDesign() {
        let value = SettingsPreferences.default

        XCTAssertEqual(value.addonTimeout, .seconds20)
        XCTAssertEqual(value.continueWatchingLimit, .unlimited)
        XCTAssertEqual(value.watchlistMode, .local)
        XCTAssertTrue(value.showUpcoming)
        XCTAssertEqual(value.upcomingLookAhead, .days60)
        XCTAssertEqual(value.upcomingItemLimit, .unlimited)
        XCTAssertTrue(value.showSkipIntro)
        XCTAssertFalse(value.autoSkipIntro)
        XCTAssertFalse(value.autoplayNextEpisode)
        XCTAssertEqual(value.upNextLeadTime, .seconds30)
        XCTAssertTrue(value.rememberLastSelection)
        XCTAssertEqual(value.sourceSelectionRetention, .days3)
        XCTAssertFalse(value.autoplayFirstCompatibleSource)
        XCTAssertFalse(value.directContinueWatchingPlayback)
        XCTAssertTrue(value.compatibleFormatsOnly)
        XCTAssertEqual(value.preferredAudioLanguage, .followSystem)
        XCTAssertEqual(value.audioFallbackLanguage, .none)
        XCTAssertEqual(value.preferredSubtitleLanguage, .followSystem)
        XCTAssertEqual(value.subtitleFallbackLanguage, .none)
        XCTAssertEqual(value.sdhPreference, .followSystem)
        XCTAssertEqual(value.animeAudioPreference, .followPreferred)
        XCTAssertEqual(value.subtitleAppearance, .followSystem)
    }

    func testNormalizationDisablesDependentPreferences() {
        var value = SettingsPreferences.default
        value.showSkipIntro = false
        value.autoSkipIntro = true
        value.rememberLastSelection = false
        value.autoplayFirstCompatibleSource = true

        let normalized = value.normalized

        XCTAssertFalse(normalized.autoSkipIntro)
        XCTAssertFalse(normalized.autoplayFirstCompatibleSource)
    }

    func testStorePersistsNormalizedRoundTrip() {
        var store: SettingsPreferencesStore? = SettingsPreferencesStore(defaults: defaults)
        store?.update {
            $0.showUpcoming = false
            $0.upcomingLookAhead = .days14
            $0.showSkipIntro = false
            $0.autoSkipIntro = true
        }

        store = nil
        let restored = SettingsPreferencesStore(defaults: defaults)

        XCTAssertFalse(restored.preferences.showUpcoming)
        XCTAssertEqual(restored.preferences.upcomingLookAhead, .days14)
        XCTAssertFalse(restored.preferences.showSkipIntro)
        XCTAssertFalse(restored.preferences.autoSkipIntro)
    }

    func testStoreRecoversFromCorruptPayload() {
        defaults.set(Data("not-json".utf8), forKey: SettingsPreferencesStore.defaultStorageKey)

        let store = SettingsPreferencesStore(defaults: defaults)

        XCTAssertEqual(store.preferences, .default)
        XCTAssertNil(defaults.data(forKey: SettingsPreferencesStore.defaultStorageKey))
    }
}
