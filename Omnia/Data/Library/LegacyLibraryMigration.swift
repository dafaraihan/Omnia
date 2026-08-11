import Foundation

struct LegacyLibraryMigration {
    static let markerKey = "saved-library-swiftdata-migration-v1"
    private static let legacyKey = "saved-library"

    let defaults: UserDefaults
    let store: LocalMediaStore

    func runIfNeeded() async throws {
        guard !defaults.bool(forKey: Self.markerKey) else { return }
        guard let data = defaults.data(forKey: Self.legacyKey) else {
            defaults.set(true, forKey: Self.markerKey)
            return
        }

        let legacy = try JSONDecoder().decode([SavedMediaItem].self, from: data)
        try await store.importLegacy(legacy)
        let expected = legacy.map(\.id).sorted()
        let actual = try await store.snapshot()
            .filter(\.isInWatchlist)
            .map(\.mediaID)
            .sorted()
        guard actual == expected else {
            throw LocalMediaStoreError.verificationFailed
        }

        defaults.removeObject(forKey: Self.legacyKey)
        defaults.set(true, forKey: Self.markerKey)
    }
}
