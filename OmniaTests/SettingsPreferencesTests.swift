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
        XCTAssertEqual(value.customSubtitleAppearance, .default)
        XCTAssertEqual(value.mdblistRatings, .default)
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

    func testDecodingPreviousPayloadDefaultsCustomSubtitleStyle() throws {
        let current = try JSONEncoder().encode(SettingsPreferences.default)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: current) as? [String: Any])
        object.removeValue(forKey: "customSubtitleAppearance")

        let decoded = try JSONDecoder().decode(
            SettingsPreferences.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.customSubtitleAppearance, .default)
    }

    func testDecodingPreviousPayloadDefaultsMDBListRatingPreferences() throws {
        let current = try JSONEncoder().encode(SettingsPreferences.default)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: current) as? [String: Any])
        object.removeValue(forKey: "mdblistRatings")

        let decoded = try JSONDecoder().decode(
            SettingsPreferences.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.mdblistRatings, .default)
    }

    func testMDBListRatingNormalizationCanonicalizesAliasesAndRemovesInvalidIDs() {
        var value = SettingsPreferences.default
        value.mdblistRatings = MDBListRatingPreferences(
            discoveredProviderIDs: ["IMDb", "future_source", "contains/slash", ""],
            disabledProviderIDs: ["tomatoesaudience", "future_source", "café"]
        )

        let normalized = value.normalized.mdblistRatings

        XCTAssertEqual(normalized.discoveredProviderIDs, ["imdb", "future_source"])
        XCTAssertEqual(normalized.disabledProviderIDs, ["popcorn", "future_source"])
    }

    func testNewAndKnownMDBListProvidersAreEnabledUnlessExplicitlyDisabled() {
        let value = MDBListRatingPreferences(
            discoveredProviderIDs: ["future_source"],
            disabledProviderIDs: ["imdb"]
        )

        XCTAssertFalse(value.isEnabled(.imdb))
        XCTAssertTrue(value.isEnabled(.tmdb))
        XCTAssertTrue(value.isEnabled(try XCTUnwrap(MDBListRatingProviderID("future_source"))))
    }

    func testRediscoveryDoesNotReenableDisabledMDBListProvider() {
        let store = SettingsPreferencesStore(defaults: defaults)
        store.setMDBListRatingProvider(.imdb, enabled: false)

        store.recordMDBListRatingProviders([.imdb, .tmdb])

        XCTAssertEqual(store.preferences.mdblistRatings.discoveredProviderIDs, ["imdb", "tmdb"])
        XCTAssertEqual(store.preferences.mdblistRatings.disabledProviderIDs, ["imdb"])
    }

    func testDisabledUnknownMDBListProviderPersistsAcrossStoreRoundTrip() throws {
        let unknown = try XCTUnwrap(MDBListRatingProviderID("future_source"))
        var store: SettingsPreferencesStore? = SettingsPreferencesStore(defaults: defaults)
        store?.recordMDBListRatingProviders([unknown])
        store?.setMDBListRatingProvider(unknown, enabled: false)

        store = nil
        let restored = SettingsPreferencesStore(defaults: defaults)

        XCTAssertEqual(restored.preferences.mdblistRatings.discoveredProviderIDs, ["future_source"])
        XCTAssertEqual(restored.preferences.mdblistRatings.disabledProviderIDs, ["future_source"])
        XCTAssertFalse(restored.preferences.mdblistRatings.isEnabled(unknown))
    }
}
