import Foundation
import Observation

/// Owns all remote credential operations and checks identity after every await.
@MainActor
@Observable
final class CredentialVaultSync {
    private(set) var isSyncing = false
    private(set) var isRestoring = false
    private(set) var problem: String?
    private(set) var lastSyncedAt: Date?
    private(set) var conflictIDs: [String] = []
    private(set) var hasPendingChanges = false
    private(set) var identityBlocked = false

    @ObservationIgnored private let profiles: ProfileStore
    @ObservationIgnored private let account: OmniaAccount
    @ObservationIgnored private let local: CredentialVaultLocalStore
    @ObservationIgnored private let client: CredentialVaultClient
    private var owner: UUID?
    @ObservationIgnored private var state = CredentialVaultDeviceState()
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var isApplying = false
    @ObservationIgnored private var localFailure = false
    @ObservationIgnored private var changesDuringSync = false

    /// Signed out without asking for it. This device keeps its credentials and
    /// their owner, and picks the sync back up when that account signs in again.
    var sessionEnded: Bool { owner != nil && account.user == nil }

    init(account: OmniaAccount, profiles: ProfileStore) {
        self.profiles = profiles
        self.account = account
        local = CredentialVaultLocalStore(profiles: profiles)
        client = CredentialVaultClient(account: account)
        do {
            let savedOwner = try KeychainStore.value(account: CredentialVaultDiskStore.ownerAccount)
            owner = savedOwner.flatMap(UUID.init(uuidString:))
            state = try CredentialVaultDiskStore.load(owner: owner)
            try recoverStoredWrites()
            refreshSummary()
        } catch {
            localFailure = true
            identityBlocked = true
            problem = CredentialVaultError.persistence.localizedDescription
        }
    }

    /// Called synchronously before OmniaAccount publishes a new user identity.
    /// Any failure prevents the new identity from becoming usable.
    func prepareIdentityChange(to next: UUID?) throws {
        guard !localFailure else { throw CredentialVaultError.persistence }
        guard next != owner else { return }
        generation = UUID()
        work?.cancel()
        work = nil
        isSyncing = false
        // Only Sign Out clears this device. A session that ended by itself leaves
        // everything in place; local changes queue until the next sign-in.
        if next == nil, !account.isSigningOut {
            isRestoring = false
            return
        }
        isRestoring = next != nil
        isApplying = true
        defer { isApplying = false }
        do {
            try captureChanges()
            try CredentialVaultDiskStore.save(state, owner: owner)
            let oldValues = state.values
            var incoming = next == nil ? CredentialVaultDeviceState() : try CredentialVaultDiskStore.load(owner: next)
            // Signing in keeps what was entered while signed out. Sign-out already
            // emptied the guest copy, so nothing of a previous account is in it.
            // What this account already holds wins, and is never overwritten.
            if owner == nil, next != nil {
                let isFirstUse = !(try CredentialVaultDiskStore.hasSnapshot(owner: next))
                for (id, value) in oldValues where incoming.values[id] == nil {
                    incoming.values[id] = value
                    incoming.pending[id] = CredentialVaultPendingChange(revision: incoming.revisions[id] ?? 0, data: value)
                }
                incoming.adoptingGuest = isFirstUse && !oldValues.isEmpty
            }
            // Publish both snapshots before mutation. The marker makes an interrupted
            // transition recover the snapshot named by the last committed owner.
            try CredentialVaultDiskStore.save(incoming, owner: next)
            try KeychainStore.save("1", account: CredentialVaultDiskStore.transitionAccount)
            // Clear before changing ownership, then apply only that account's local copy.
            let previousPlaylists = local.playlistIDs
            try local.clear()
            for id in previousPlaylists { try local.applyPlaylist(id: id, data: nil) }
            for (id, value) in incoming.values.sorted(by: { applyOrder($0.key, $1.key) }) {
                try apply(id: id, data: value)
            }
            if let next {
                try KeychainStore.save(next.uuidString, account: CredentialVaultDiskStore.ownerAccount)
            } else {
                try KeychainStore.save("signed-out", account: CredentialVaultDiskStore.ownerAccount)
            }
            owner = next
            state = incoming
            try KeychainStore.delete(account: CredentialVaultDiskStore.transitionAccount)
            identityBlocked = false
            problem = nil
            refreshSummary()
        } catch {
            identityBlocked = true
            isRestoring = false
            problem = CredentialVaultError.persistence.localizedDescription
            throw CredentialVaultError.persistence
        }
    }

    private func recoverStoredWrites(forceFull: Bool = false) throws {
        let transition = try KeychainStore.value(account: CredentialVaultDiskStore.transitionAccount) != nil
        guard transition || forceFull || !state.staged.isEmpty else { return }
        isApplying = true
        defer { isApplying = false }
        if transition || forceFull {
            let previousPlaylists = local.playlistIDs
            try local.clear()
            for id in previousPlaylists { try local.applyPlaylist(id: id, data: nil) }
            for (id, value) in state.values.sorted(by: { applyOrder($0.key, $1.key) }) {
                try apply(id: id, data: value)
            }
        } else {
            for id in state.staged.sorted(by: applyOrder) {
                try apply(id: id, data: state.values[id])
            }
        }
        state.staged.removeAll()
        try CredentialVaultDiskStore.save(state, owner: owner)
        try KeychainStore.delete(account: CredentialVaultDiskStore.transitionAccount)
    }

    func retrySecureStorage() {
        do {
            let saved = try KeychainStore.value(account: CredentialVaultDiskStore.ownerAccount)
            owner = saved.flatMap(UUID.init(uuidString:))
            let hasSnapshot = try CredentialVaultDiskStore.hasSnapshot(owner: owner)
            state = try CredentialVaultDiskStore.load(owner: owner)
            if hasSnapshot {
                try recoverStoredWrites(forceFull: true)
            } else {
                // First-use Keychain failure has no recovery snapshot. Preserve
                // the existing installation rather than interpreting absence as empty.
                guard try KeychainStore.value(account: CredentialVaultDiskStore.transitionAccount) == nil else {
                    throw CredentialVaultError.persistence
                }
                try captureChanges()
                try CredentialVaultDiskStore.save(state, owner: owner)
            }
            localFailure = false
            identityBlocked = false
            isRestoring = false
            problem = nil
            refreshSummary()
        } catch { problem = CredentialVaultError.persistence.localizedDescription }
    }

    func identityChanged() async {
        guard !localFailure else { return }
        do { try prepareIdentityChange(to: account.user?.id) }
        catch { return }
        guard account.user != nil else {
            isRestoring = false
            return
        }
        await sync()
    }

    func localChanged() {
        guard !isApplying, !localFailure, !identityBlocked else { return }
        do {
            try captureChanges()
            try save()
        } catch {
            problem = CredentialVaultError.persistence.localizedDescription
            return
        }
        guard account.user?.id == owner, owner != nil else { return }
        if isSyncing { changesDuringSync = true; return }
        schedule()
    }

    private func schedule() {
        guard !isSyncing else { return }
        work?.cancel()
        work = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            await self.sync()
        }
    }

    func sync() async {
        guard !isSyncing, !localFailure, !identityBlocked,
              let owner, account.user?.id == owner else { return }
        let ticket = generation
        isSyncing = true
        isRestoring = !state.pulled
        defer {
            if ticket == generation {
                isSyncing = false
                isRestoring = false
                refreshSummary()
                let repeatSync = changesDuringSync && state.pending.keys.contains { !state.conflicts.contains($0) }
                changesDuringSync = false
                if repeatSync { schedule() }
            }
        }
        do {
            try captureChanges()
            try save()
            let index = try await client.list()
            try check(owner, ticket)
            var failed: [String] = []
            for summary in index.sorted(by: { applyOrder($0.id, $1.id) }) {
                try check(owner, ticket)
                // Same revision but nothing here: an earlier restore didn't land
                // (or an older build couldn't store it), so fetch it again.
                let isMissing = !summary.deleted && state.values[summary.id] == nil && state.pending[summary.id] == nil
                guard state.revisions[summary.id] != summary.revision || isMissing else { continue }
                do {
                    let remote = try await client.read(id: summary.id)
                    try check(owner, ticket)
                    guard remote.id == summary.id else { throw CredentialVaultError.invalidData }
                    let value = try await decoded(remote)
                    try check(owner, ticket)
                    if let pending = state.pending[remote.id], !state.adoptingGuest {
                        if pending.revision != remote.revision {
                            state.conflicts.insert(remote.id)
                        }
                    } else { state.pending[remote.id] = nil }
                    try applyRemote(remote, value: value)
                    try save()
                } catch is CancellationError { throw CancellationError() }
                catch { failed.append(Self.category(summary.id)) }
            }
            state.adoptingGuest = false
            state.pulled = true
            try save()
            for id in state.pending.keys.sorted() where !state.conflicts.contains(id) {
                try check(owner, ticket)
                guard let pending = state.pending[id] else { continue }
                do {
                    let saved: CredentialVaultEntry
                    if id.hasPrefix("playlist."), let data = pending.data {
                        saved = try await client.upload(id: id, revision: pending.revision, data: data)
                    } else {
                        saved = try await client.write(id: id, revision: pending.revision, data: pending.data)
                    }
                    try check(owner, ticket)
                    state.revisions[id] = saved.revision
                    // Preserve edits made while this request was in flight.
                    if state.pending[id]?.data == pending.data {
                        state.pending[id] = nil
                    } else { state.pending[id]?.revision = saved.revision }
                    try save()
                } catch let CredentialVaultError.conflict(remote) {
                    try check(owner, ticket)
                    guard remote.id == id else { throw CredentialVaultError.invalidData }
                    state.conflicts.insert(id)
                    do {
                        let value = try await decoded(remote)
                        try check(owner, ticket)
                        try applyRemote(remote, value: value)
                        try save()
                    } catch is CancellationError { throw CancellationError() }
                    catch { failed.append(Self.category(id)) }
                } catch is CancellationError { throw CancellationError() }
                catch { failed.append(Self.category(id)) }
            }
            try check(owner, ticket)
            try save()
            problem = failed.isEmpty ? nil : "Some saved credentials need retry: \(Set(failed).sorted().joined(separator: ", "))."
            if failed.isEmpty && state.pending.isEmpty { lastSyncedAt = .now }
        } catch is CancellationError {
            // The next identity owns all visible state and subsequent writes.
        } catch {
            if ticket == generation { problem = (error as? CredentialVaultError)?.localizedDescription ?? CredentialVaultError.unavailable.localizedDescription }
        }
    }

    func resolve(id: String, keepDevice: Bool) {
        guard state.conflicts.contains(id), account.user?.id == owner else { return }
        if keepDevice, var pending = state.pending[id] {
            pending.revision = state.revisions[id] ?? 0
            state.pending[id] = pending
            do {
                isApplying = true
                defer { isApplying = false }
                try apply(id: id, data: pending.data)
                state.values[id] = pending.data
            } catch {
                problem = CredentialVaultError.persistence.localizedDescription
                return
            }
        } else { state.pending[id] = nil }
        state.conflicts.remove(id)
        do { try save() } catch { problem = CredentialVaultError.persistence.localizedDescription }
        schedule()
    }

    private func captureChanges() throws {
        let captured = try capture()
        for id in Set(captured.keys).union(state.values.keys) {
            guard captured[id] != state.values[id] else { continue }
            let revision = state.pending[id]?.revision ?? state.revisions[id] ?? 0
            state.pending[id] = CredentialVaultPendingChange(revision: revision, data: captured[id])
        }
        state.values = captured
        refreshSummary()
    }

    private func capture() throws -> [String: Data] {
        var values = try local.capture()
        var total = 0
        for id in local.playlistIDs {
            guard let data = try local.playlistData(id: id) else { continue }
            total += data.count
            guard total <= 256 * 1_024 * 1_024 else { throw CredentialVaultError.invalidData }
            values["playlist." + id] = data
        }
        return values
    }

    private func apply(id: String, data: Data?) throws {
        if id == "livetv.configuration", let data {
            let config = try JSONDecoder().decode(LiveTVConfiguration.self, from: data)
            for source in config.playlists where source.kind == .localFile {
                guard try local.playlistData(id: source.id) != nil else { throw CredentialVaultError.invalidData }
            }
        }
        if id.hasPrefix("playlist.") { try local.applyPlaylist(id: String(id.dropFirst(9)), data: data) }
        else { try local.apply(id: id, payload: data) }
    }

    private func applyRemote(_ remote: CredentialVaultEntry, value: Data?) throws {
        isApplying = true
        defer { isApplying = false }
        let previous = state
        var updated = state
        updated.values[remote.id] = value
        updated.revisions[remote.id] = remote.revision
        updated.staged.insert(remote.id)
        // A staged ID is recovered before startup captures any live changes.
        try CredentialVaultDiskStore.save(updated, owner: owner)
        var applied = false
        do {
            try apply(id: remote.id, data: value)
            applied = true
            updated.staged.remove(remote.id)
            try CredentialVaultDiskStore.save(updated, owner: owner)
            state = updated
        } catch {
            do {
                if applied { try apply(id: remote.id, data: previous.values[remote.id]) }
                try CredentialVaultDiskStore.save(previous, owner: owner)
            } catch { identityBlocked = true }
            throw CredentialVaultError.persistence
        }
    }

    private func decoded(_ entry: CredentialVaultEntry) async throws -> Data? {
        if entry.deleted { return nil }
        if entry.id.hasPrefix("playlist.") { return try await client.download(entry) }
        guard let payload = entry.payload, payload.utf8.count <= 350_000,
              let data = Data(base64Encoded: payload), data.count <= 256 * 1_024 else {
            throw CredentialVaultError.invalidData
        }
        return data
    }

    private func save() throws {
        try CredentialVaultDiskStore.save(state, owner: owner)
        refreshSummary()
    }

    private func refreshSummary() {
        conflictIDs = state.conflicts.sorted()
        hasPendingChanges = !state.pending.isEmpty
    }

    private func check(_ expected: UUID, _ ticket: UUID) throws {
        try Task.checkCancellation()
        guard generation == ticket, owner == expected, account.user?.id == expected else { throw CancellationError() }
    }

    private func applyOrder(_ lhs: String, _ rhs: String) -> Bool {
        // Restore attachments before publishing a Live TV source configuration.
        let left = lhs.hasPrefix("playlist.") ? 0 : lhs == "livetv.configuration" ? 2 : 1
        let right = rhs.hasPrefix("playlist.") ? 0 : rhs == "livetv.configuration" ? 2 : 1
        return left == right ? lhs < rhs : left < right
    }

    func label(for id: String) -> String {
        switch id {
        case "provider.mdblist": return "MDBList API key"
        case "provider.anilist": return "AniList token"
        case "provider.plugin-tmdb": return "Plugin TMDB key"
        case "provider.tmdb": return "TMDB API key"
        case "provider.tvdb": return "TVDB API key"
        case "provider.fanart": return "fanart.tv API key"
        case "livetv.configuration": return "Live TV sources and settings"
        case "livetv.secrets": return "Live TV credentials"
        default: break
        }
        if id.hasPrefix("pin."), let uuid = UUID(uuidString: String(id.dropFirst(4))),
           let profile = profiles.profiles.first(where: { $0.id == uuid }) { return "\(profile.name)'s PIN" }
        if id.hasPrefix("server."), let connection = MediaServerStore.shared.connection(id: String(id.dropFirst(7))) {
            return "\(connection.name) connection"
        }
        if id.hasPrefix("playlist."),
           let source = LiveTVStore.shared.configuration.playlists.first(where: { $0.id == String(id.dropFirst(9)) }) {
            return "\(source.name) playlist"
        }
        return Self.category(id)
    }

    static func category(_ id: String) -> String {
        if id.hasPrefix("provider.") { return "Provider keys" }
        if id.hasPrefix("tracker.") { return "Tracker sign-ins" }
        if id.hasPrefix("pin.") { return "Profile PINs" }
        if id.hasPrefix("server.") { return "Media servers" }
        return "Live TV"
    }
}
