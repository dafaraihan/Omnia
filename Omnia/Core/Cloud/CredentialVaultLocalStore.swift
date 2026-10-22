import Foundation

/// Validates account-vault data before crossing into local Keychain and settings.
@MainActor
final class CredentialVaultLocalStore {
    enum Failure: Error { case invalidEntry, oversized, rollbackFailed }
    private struct ServerEntry: Codable {
        let connection: MediaServerConnection
        let token: String?
    }
    private let profiles: ProfileStore
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private let decoder = JSONDecoder()
    private let pinIDsKey = "credential-vault-pin-identifiers"

    init(profiles: ProfileStore) { self.profiles = profiles }

    private var pinIDs: Set<UUID> {
        Set(profiles.vaultPINIDs()).union((UserDefaults.standard.stringArray(forKey: pinIDsKey) ?? []).compactMap(UUID.init(uuidString:)))
    }

    func capture() throws -> [String: Data] {
        var entries: [String: Data] = [:]
        for provider in UserManagedProviderCredential.allCases {
            if let value = try ProviderCredentialStore.value(for: provider) {
                entries["provider.\(provider.rawValue)"] = try encoder.encode(value)
            }
        }
        if let value = try KeychainStore.value(account: PluginStore.tmdbKeyAccount) {
            entries["provider.plugin-tmdb"] = try encoder.encode(value)
        }
        for id in pinIDs {
            if let value = try profiles.vaultPIN(id) { entries["pin.\(id.uuidString)"] = try encoder.encode(value) }
        }
        for connection in MediaServerStore.shared.connections {
            let token = try KeychainStore.value(account: connection.keychainAccount)
            entries["server.\(connection.id)"] = try encoder.encode(ServerEntry(connection: connection, token: token))
        }
        let liveTV = LiveTVStore.shared
        entries["livetv.configuration"] = try encoder.encode(liveTV.configuration)
        entries["livetv.secrets"] = try encoder.encode(liveTV.vaultSecrets())
        guard entries.count <= 1_000, entries.values.allSatisfy({ $0.count <= 256 * 1_024 }) else { throw Failure.oversized }
        return entries
    }

    func apply(id: String, payload: Data?) throws {
        guard payload.map({ $0.count <= 256 * 1_024 }) ?? true else { throw Failure.oversized }
        if id.hasPrefix("provider.") {
            let account: String
            switch id {
            case "provider.mdblist": account = UserManagedProviderCredential.mdblist.keychainAccount
            case "provider.anilist": account = UserManagedProviderCredential.anilist.keychainAccount
            case "provider.plugin-tmdb": account = PluginStore.tmdbKeyAccount
            default: throw Failure.invalidEntry
            }
            let value = try payload.map { try decoder.decode(String.self, from: $0) }
            if let value { guard !value.isEmpty, value.utf8.count <= 64 * 1_024 else { throw Failure.invalidEntry } }
            try Self.replaceCredential(value, account: account)
            if id == "provider.plugin-tmdb" { PluginStore.vaultCredentialChanged() }
        } else if id.hasPrefix("pin."), let uuid = UUID(uuidString: String(id.dropFirst(4))) {
            let value = try payload.map { try decoder.decode(String.self, from: $0) }
            if let value {
                let parts = value.split(separator: ":", omittingEmptySubsequences: false)
                guard parts.count == 2, UUID(uuidString: String(parts[0])) != nil,
                      parts[1].count == 64, parts[1].allSatisfy({ $0.isASCII && $0.isHexDigit }) else { throw Failure.invalidEntry }
            }
            try profiles.applyVaultPIN(value, id: uuid)
            var ids = pinIDs
            if value != nil { ids.insert(uuid) } else { ids.remove(uuid) }
            UserDefaults.standard.set(ids.map(\.uuidString).sorted(), forKey: pinIDsKey)
        } else if id.hasPrefix("server.") {
            let connectionID = String(id.dropFirst(7))
            guard UUID(uuidString: connectionID) != nil else { throw Failure.invalidEntry }
            let entry = try payload.map { try decoder.decode(ServerEntry.self, from: $0) }
            if let entry {
                let connection = entry.connection
                guard connection.id == connectionID, MediaServerAddressPolicy.permits(connection.address),
                      connection.address.fragment == nil, connection.address.query == nil,
                      !connection.serverID.isEmpty, !connection.userID.isEmpty,
                      connection.libraries.count <= 1_000,
                      Set(connection.libraries.map(\.id)).count == connection.libraries.count,
                      entry.token.map({ !$0.isEmpty && $0.utf8.count <= 64 * 1_024 }) ?? true else { throw Failure.invalidEntry }
            }
            try MediaServerStore.shared.applyVaultConnection(entry?.connection, id: connectionID, token: entry?.token)
        } else if id == "livetv.configuration" {
            let value = try payload.map { try decoder.decode(LiveTVConfiguration.self, from: $0) } ?? LiveTVConfiguration()
            let ids = value.playlists.map(\.id) + value.guides.map(\.id)
            guard ids.count <= 1_000, Set(ids).count == ids.count,
                  ids.allSatisfy({ UUID(uuidString: $0) != nil }),
                  value.playlists.allSatisfy({ !$0.name.isEmpty && $0.name.count <= 1_024 }),
                  value.guides.allSatisfy({ !$0.name.isEmpty && $0.name.count <= 1_024 }) else { throw Failure.invalidEntry }
            try LiveTVStore.shared.applyVaultConfiguration(value)
        } else if id == "livetv.secrets" {
            let value = try payload.map { try decoder.decode(LiveTVSecrets.self, from: $0) }
            if let value {
                let urls = Array(value.playlistURLs.values) + Array(value.guideURLs.values)
                let ids = Array(value.playlistURLs.keys) + Array(value.guideURLs.keys)
                guard ids.count <= 1_000, ids.allSatisfy({ UUID(uuidString: $0) != nil }),
                      urls.allSatisfy({ LiveTVAddressPolicy.permits($0) && $0.absoluteString.utf8.count <= 16_384 }) else { throw Failure.invalidEntry }
                if let account = value.xtream {
                    guard LiveTVAddressPolicy.permits(account.server), account.server.query == nil,
                          account.server.fragment == nil, !account.username.isEmpty else { throw Failure.invalidEntry }
                }
                if let account = value.stalker {
                    guard LiveTVAddressPolicy.permits(account.portal),
                          LiveTVAddress.macAddress(from: account.macAddress) == account.macAddress else { throw Failure.invalidEntry }
                }
            }
            try LiveTVStore.shared.applyVaultSecrets(value)
        } else { throw Failure.invalidEntry }
    }

    /// Detach only credentials/configuration. Ordinary profile data stays owned by ProfileStore.
    func clear() throws {
        let saved = try capture()
        MediaServerStore.shared.invalidateVaultWork()
        var changed: [String] = []
        do {
            for id in saved.keys.sorted() {
                if id.hasPrefix("pin."), let uuid = UUID(uuidString: String(id.dropFirst(4))) {
                    try profiles.applyVaultPIN(nil, id: uuid, updateLock: false)
                } else { try apply(id: id, payload: nil) }
                changed.append(id)
            }
            UserDefaults.standard.removeObject(forKey: pinIDsKey)
        } catch {
            let original = error
            var failed = false
            for id in changed.reversed() {
                do { try apply(id: id, payload: saved[id]) } catch { failed = true }
            }
            if failed { throw Failure.rollbackFailed }
            throw original
        }
    }

    var playlistIDs: [String] {
        LiveTVStore.shared.configuration.playlists.filter { $0.kind == .localFile }.map(\.id).sorted()
    }

    func playlistData(id: String) throws -> Data? {
        guard UUID(uuidString: id) != nil else { throw Failure.invalidEntry }
        let data = try LiveTVStore.shared.vaultPlaylist(id)
        guard data.map({ $0.count <= 64 * 1_024 * 1_024 }) ?? true else { throw Failure.oversized }
        return data
    }

    func applyPlaylist(id: String, data: Data?) throws {
        guard UUID(uuidString: id) != nil else { throw Failure.invalidEntry }
        if let data {
            guard data.count <= 64 * 1_024 * 1_024 else { throw Failure.oversized }
            guard LiveTVHTTP.text(from: data).range(of: "#EXTINF", options: .caseInsensitive) != nil else { throw Failure.invalidEntry }
        }
        try LiveTVStore.shared.applyVaultPlaylist(data, id: id)
    }

    static func replaceCredential(_ value: String?, account: String) throws {
        let previous = try KeychainStore.value(account: account)
        do {
            if let value { try KeychainStore.save(value, account: account) }
            else { try KeychainStore.delete(account: account) }
        } catch {
            if let previous {
                do { try KeychainStore.save(previous, account: account) } catch { throw Failure.rollbackFailed }
            }
            throw error
        }
    }
}
