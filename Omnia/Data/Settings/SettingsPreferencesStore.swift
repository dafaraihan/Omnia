import Foundation
import Observation

@MainActor
@Observable
final class SettingsPreferencesStore {
    static let defaultStorageKey = "settings-preferences-v1"

    private struct Envelope: Codable {
        let version: Int
        let preferences: SettingsPreferences
    }

    private let defaults: UserDefaults
    private let storageKey: String

    private(set) var preferences: SettingsPreferences

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = SettingsPreferencesStore.defaultStorageKey
    ) {
        self.defaults = defaults
        self.storageKey = storageKey

        guard let data = defaults.data(forKey: storageKey) else {
            preferences = .default
            return
        }

        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.version == 1 else {
                throw CocoaError(.coderReadCorrupt)
            }
            preferences = envelope.preferences.normalized
        } catch {
            defaults.removeObject(forKey: storageKey)
            preferences = .default
        }
    }

    func update(_ transform: (inout SettingsPreferences) -> Void) {
        var updated = preferences
        transform(&updated)
        preferences = updated.normalized
        persist()
    }

    func reset() {
        preferences = .default
        defaults.removeObject(forKey: storageKey)
    }

    private func persist() {
        let envelope = Envelope(version: 1, preferences: preferences)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
