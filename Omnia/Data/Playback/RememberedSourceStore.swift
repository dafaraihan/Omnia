import Foundation

enum RememberedSourceStoreError: Error {
    case invalidField
}

final class RememberedSourceStore {
    static let storageKey = "remembered-playback-sources-v1"

    private let defaults: UserDefaults
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    func remember(
        mediaKey: MediaPlaybackKey,
        addonID: String,
        bingeGroup: String?,
        displayNameFingerprint: String,
        retention: SourceSelectionRetention
    ) throws {
        guard !mediaKey.rawValue.isEmpty, mediaKey.rawValue.count <= 512,
              !addonID.isEmpty, addonID.count <= 256,
              (bingeGroup?.count ?? 0) <= 512
        else { throw RememberedSourceStoreError.invalidField }

        var values = load()
        let normalizedFingerprint = displayNameFingerprint.allSatisfy(\.isHexDigit)
            ? displayNameFingerprint.lowercased()
            : DisplayNameFingerprint.make(displayNameFingerprint)
        values[mediaKey.rawValue] = RememberedSource(
            mediaKey: mediaKey,
            addonID: addonID,
            bingeGroup: bingeGroup,
            displayNameFingerprint: normalizedFingerprint,
            expiresAt: now().addingTimeInterval(retention.duration)
        )
        try save(values)
    }

    func source(
        for mediaKey: MediaPlaybackKey,
        enabledAddonIDs: Set<String>
    ) -> RememberedSource? {
        var values = load()
        guard let value = values[mediaKey.rawValue],
              value.expiresAt > now(),
              enabledAddonIDs.contains(value.addonID)
        else {
            values.removeValue(forKey: mediaKey.rawValue)
            try? save(values)
            return nil
        }
        return value
    }

    func removeSources(forAddonID addonID: String) throws {
        let filtered = load().filter { $0.value.addonID != addonID }
        try save(filtered)
    }

    private func load() -> [String: RememberedSource] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: RememberedSource].self, from: data)) ?? [:]
    }

    private func save(_ values: [String: RememberedSource]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        defaults.set(try encoder.encode(values), forKey: Self.storageKey)
    }
}
