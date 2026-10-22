import CryptoKit
import Foundation

nonisolated struct CredentialVaultPendingChange: Codable, Sendable {
    var revision: Int
    var data: Data?
}

nonisolated struct CredentialVaultDeviceState: Codable, Sendable {
    var version = 1
    var values: [String: Data] = [:]
    var revisions: [String: Int] = [:]
    var pending: [String: CredentialVaultPendingChange] = [:]
    var conflicts: Set<String> = []
    var pulled = false
    var adoptingGuest = false
    var staged: Set<String> = []
}

/// Device-only encrypted snapshots, partitioned by account. No key is synced.
@MainActor
enum CredentialVaultDiskStore {
    private static let keyAccount = "credential-vault-device-key"
    static let ownerAccount = "credential-vault-device-owner"
    static let transitionAccount = "credential-vault-device-transition"

    private static func directory() throws -> URL {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CredentialVaultError.persistence
        }
        let directory = support.appending(path: "CredentialVault", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        return directory
    }

    private static func key() throws -> SymmetricKey {
        if let encoded = try KeychainStore.value(account: keyAccount) {
            guard let bytes = Data(base64Encoded: encoded), bytes.count == 32 else { throw CredentialVaultError.persistence }
            return SymmetricKey(data: bytes)
        }
        let directory = try directory()
        guard try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty else {
            throw CredentialVaultError.persistence
        }
        let key = SymmetricKey(size: .bits256)
        try KeychainStore.save(key.withUnsafeBytes { Data($0).base64EncodedString() }, account: keyAccount)
        return key
    }

    private static func name(_ owner: UUID?) -> String { owner?.uuidString ?? "guest" }

    private struct StoredPending: Codable {
        var revision: Int
        var reference: String?
    }

    private struct StoredState: Codable {
        var version = 1
        var values: [String: String]
        var revisions: [String: Int]
        var pending: [String: StoredPending]
        var conflicts: Set<String>
        var pulled: Bool
        var adoptingGuest: Bool
        var staged: Set<String>?
    }

    private static func blobDirectory(owner: UUID?) throws -> URL {
        let directory = try directory().appending(path: name(owner), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func reference(id: String, data: Data, key: SymmetricKey) -> String {
        var hash = HMAC<SHA256>(key: key)
        hash.update(data: Data((id + "|").utf8))
        hash.update(data: data)
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func storeBlob(id: String, data: Data, owner: UUID?, key: SymmetricKey) throws -> String {
        let reference = reference(id: id, data: data, key: key)
        let file = try blobDirectory(owner: owner).appending(path: reference)
        if !FileManager.default.fileExists(atPath: file.path) {
            let aad = Data((name(owner) + "|" + reference).utf8)
            guard let combined = try AES.GCM.seal(data, using: key, authenticating: aad).combined else {
                throw CredentialVaultError.persistence
            }
            try combined.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
        return reference
    }

    private static func loadBlob(id: String, reference: String, owner: UUID?, key: SymmetricKey) throws -> Data {
        guard reference.count == 64, reference.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            throw CredentialVaultError.persistence
        }
        let file = try blobDirectory(owner: owner).appending(path: reference)
        let limit = id.hasPrefix("playlist.") ? 64 * 1_024 * 1_024 : 256 * 1_024
        guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= limit + 28 else {
            throw CredentialVaultError.persistence
        }
        let box = try AES.GCM.SealedBox(combined: Data(contentsOf: file))
        let data = try AES.GCM.open(box, using: key, authenticating: Data((name(owner) + "|" + reference).utf8))
        guard data.count <= limit, Self.reference(id: id, data: data, key: key) == reference else { throw CredentialVaultError.persistence }
        return data
    }

    static func hasSnapshot(owner: UUID?) throws -> Bool {
        let file = try directory().appending(path: name(owner) + ".sealed")
        return FileManager.default.fileExists(atPath: file.path)
    }

    static func load(owner: UUID?) throws -> CredentialVaultDeviceState {
        let file = try directory().appending(path: name(owner) + ".sealed")
        guard FileManager.default.fileExists(atPath: file.path) else { return CredentialVaultDeviceState() }
        guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 2 * 1_024 * 1_024 else {
            throw CredentialVaultError.persistence
        }
        do {
            let key = try key()
            let box = try AES.GCM.SealedBox(combined: Data(contentsOf: file))
            let data = try AES.GCM.open(box, using: key, authenticating: Data(name(owner).utf8))
            let stored = try JSONDecoder().decode(StoredState.self, from: data)
            guard stored.version == 1, stored.values.count <= 2_000, stored.pending.count <= 2_000 else {
                throw CredentialVaultError.persistence
            }
            var state = CredentialVaultDeviceState()
            var total = 0
            for (id, reference) in stored.values {
                let value = try loadBlob(id: id, reference: reference, owner: owner, key: key)
                total += value.count
                guard total <= 512 * 1_024 * 1_024 else { throw CredentialVaultError.persistence }
                state.values[id] = value
            }
            for (id, change) in stored.pending {
                let value = try change.reference.map { try loadBlob(id: id, reference: $0, owner: owner, key: key) }
                total += value?.count ?? 0
                guard total <= 1_024 * 1_024 * 1_024 else { throw CredentialVaultError.persistence }
                state.pending[id] = CredentialVaultPendingChange(revision: change.revision, data: value)
            }
            state.revisions = stored.revisions
            state.conflicts = stored.conflicts
            state.pulled = stored.pulled
            state.adoptingGuest = stored.adoptingGuest
            state.staged = stored.staged ?? []
            return state
        } catch { throw CredentialVaultError.persistence }
    }

    static func save(_ state: CredentialVaultDeviceState, owner: UUID?) throws {
        do {
            let key = try key()
            var values: [String: String] = [:]
            var pending: [String: StoredPending] = [:]
            for (id, data) in state.values { values[id] = try storeBlob(id: id, data: data, owner: owner, key: key) }
            for (id, change) in state.pending {
                let reference = try change.data.map { try storeBlob(id: id, data: $0, owner: owner, key: key) }
                pending[id] = StoredPending(revision: change.revision, reference: reference)
            }
            let stored = StoredState(values: values, revisions: state.revisions, pending: pending,
                                     conflicts: state.conflicts, pulled: state.pulled, adoptingGuest: state.adoptingGuest, staged: state.staged)
            let data = try JSONEncoder().encode(stored)
            let sealed = try AES.GCM.seal(data, using: key, authenticating: Data(name(owner).utf8))
            guard let combined = sealed.combined else { throw CredentialVaultError.persistence }
            let file = try directory().appending(path: name(owner) + ".sealed")
            try combined.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            // State publication is atomic; only then retire unreferenced encrypted blobs.
            let retained = Set(values.values).union(pending.values.compactMap(\.reference))
            let directory = try blobDirectory(owner: owner)
            for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                where !retained.contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        } catch { throw CredentialVaultError.persistence }
    }
}
