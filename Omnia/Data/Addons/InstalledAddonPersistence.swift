import Foundation

struct InstalledAddonRestoreIssue: Identifiable, Equatable, Sendable {
    let id: String
    let addonID: String?
    let addonName: String

    init(addonID: String?, addonName: String) {
        self.id = addonID ?? addonName
        self.addonID = addonID
        self.addonName = addonName
    }
}

struct InstalledAddonLoadResult: Equatable, Sendable {
    let addons: [InstalledAddon]
    let issues: [InstalledAddonRestoreIssue]

    static let empty = Self(addons: [], issues: [])
}

/// Serializes add-on persistence away from SwiftUI's main actor. Keychain
/// queries may block while macOS displays or unlocks the user's login keychain.
actor InstalledAddonPersistence {
    nonisolated static let storageKey = "installed-addons"

    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = InstalledAddonPersistence.storageKey
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func load() -> InstalledAddonLoadResult {
        guard let data = defaults.data(forKey: storageKey) else { return .empty }
        guard let records = try? JSONDecoder().decode([RestorableAddonRecord].self, from: data) else {
            return InstalledAddonLoadResult(
                addons: [],
                issues: [InstalledAddonRestoreIssue(addonID: nil, addonName: "Saved add-on")]
            )
        }
        return InstalledAddonLoadResult(
            addons: records.compactMap(\.addon),
            issues: records.compactMap(\.issue)
        )
    }

    func save(_ addons: [InstalledAddon]) {
        guard let data = try? JSONEncoder().encode(addons) else { return }
        defaults.set(data, forKey: storageKey)
    }

    func remove(_ addon: InstalledAddon, remainingAddons: [InstalledAddon]) {
        addon.removeSecureManifestURL()
        save(remainingAddons)
    }
}

private struct RestorableAddonRecord: Decodable {
    let addon: InstalledAddon?
    let issue: InstalledAddonRestoreIssue?

    init(from decoder: Decoder) throws {
        do {
            addon = try InstalledAddon(from: decoder)
            issue = nil
        } catch {
            addon = nil
            let identity = try? StoredAddonIdentity(from: decoder)
            issue = InstalledAddonRestoreIssue(
                addonID: identity?.manifest.id,
                addonName: identity?.manifest.name ?? "Saved add-on"
            )
        }
    }
}

private struct StoredAddonIdentity: Decodable {
    struct ManifestIdentity: Decodable {
        let id: String
        let name: String
    }

    let manifest: ManifestIdentity
}
