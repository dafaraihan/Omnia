import Foundation
import Observation

nonisolated enum ResolverCacheQuota: Int64, Codable, CaseIterable, Sendable {
    case gigabytes5 = 5
    case gigabytes10 = 10
    case gigabytes20 = 20
    case gigabytes50 = 50

    var bytes: Int64 { rawValue * 1_024 * 1_024 * 1_024 }

    var title: String { "\(rawValue) GB" }
}

nonisolated struct LocalResolverPreferences: Codable, Equatable, Sendable {
    static let consentVersion = 1
    static let maximumBandwidthKilobytesPerSecond = 1_000_000

    var acceptedConsentVersion: Int?
    var cacheQuota: ResolverCacheQuota
    var downloadLimitKilobytesPerSecond: Int
    var uploadLimitKilobytesPerSecond: Int
    var retainsIncompleteJobs: Bool

    static let `default` = LocalResolverPreferences(
        acceptedConsentVersion: nil,
        cacheQuota: .gigabytes20,
        downloadLimitKilobytesPerSecond: 0,
        uploadLimitKilobytesPerSecond: 1_024,
        retainsIncompleteJobs: false
    )

    var hasCurrentConsent: Bool {
        acceptedConsentVersion == Self.consentVersion
    }

    func normalized() -> LocalResolverPreferences {
        var value = self
        value.downloadLimitKilobytesPerSecond = min(
            max(downloadLimitKilobytesPerSecond, 0),
            Self.maximumBandwidthKilobytesPerSecond
        )
        value.uploadLimitKilobytesPerSecond = min(
            max(uploadLimitKilobytesPerSecond, 0),
            Self.maximumBandwidthKilobytesPerSecond
        )
        if value.acceptedConsentVersion != Self.consentVersion {
            value.acceptedConsentVersion = nil
        }
        return value
    }
}

@MainActor
@Observable
final class LocalResolverSettingsStore {
    static let storageKey = "local-playback-resolver-preferences-v1"

    private(set) var preferences: LocalResolverPreferences
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(LocalResolverPreferences.self, from: data) {
            preferences = decoded.normalized()
        } else {
            preferences = .default
        }
    }

    func update(_ transform: (inout LocalResolverPreferences) -> Void) {
        var value = preferences
        transform(&value)
        preferences = value.normalized()
        persist()
    }

    func acceptConsent() {
        update { $0.acceptedConsentVersion = LocalResolverPreferences.consentVersion }
    }

    func revokeConsent() {
        update { $0.acceptedConsentVersion = nil }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
