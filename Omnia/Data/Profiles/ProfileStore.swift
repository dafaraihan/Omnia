import CryptoKit
import Foundation
import Observation

/// The profiles on this Mac and which one is watching. Profiles are saved
/// next to the library, follow the account to other devices once signed
/// in, and each keeps its own library and progress (see
/// `OmniaStore.useLibrary(for:ownsDefaultLibrary:)`). PINs stay in this
/// device's Keychain, with encrypted account-vault backup.
@Observable
@MainActor
final class ProfileStore {
    private(set) var profiles: [ViewerProfile] = []
    private(set) var activeProfileID: UUID?
    /// True until someone picks who is watching for this launch.
    var needsSelection = false
    var rememberLastProfile: Bool {
        didSet { UserDefaults.standard.set(rememberLastProfile, forKey: Keys.rememberLast) }
    }
    private(set) var syncProblem: String?

    @ObservationIgnored weak var account: OmniaAccount?
    /// Lets the profile's saved settings, add-ons and plugins go too.
    @ObservationIgnored var onDelete: ((UUID) -> Void)?
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var deletedIDs: Set<UUID>
    @ObservationIgnored private var failedPINAttempts: [UUID: (count: Int, lockedUntil: Date?)] = [:]
    @ObservationIgnored private let fileURL: URL?

    private enum Keys {
        static let active = "active-viewer-profile"
        static let rememberLast = "remember-last-viewer-profile"
        static let deleted = "deleted-viewer-profiles"
        static let defaultLibraryOwner = "default-library-profile"
    }

    var activeProfile: ViewerProfile? {
        profiles.first { $0.id == activeProfileID } ?? profiles.first
    }

    var canAddProfile: Bool { profiles.count < ViewerProfile.maximumCount }

    /// The profile that owns the library this Mac had before profiles.
    var defaultLibraryOwnerID: UUID? {
        UserDefaults.standard.string(forKey: Keys.defaultLibraryOwner).flatMap(UUID.init(uuidString:))
    }

    /// The first profile, as in Nuvio: it can't be deleted, and the others
    /// can use its settings, add-ons and plugins.
    var mainProfileID: UUID? {
        if let owner = defaultLibraryOwnerID, profiles.contains(where: { $0.id == owner }) { return owner }
        return profiles.min { $0.createdAt < $1.createdAt }?.id
    }

    var mainProfile: ViewerProfile? {
        profiles.first { $0.id == mainProfileID }
    }

    func isMain(_ id: UUID) -> Bool { id == mainProfileID }

    init(directory: URL? = ProfileStore.defaultDirectory) {
        let defaults = UserDefaults.standard
        rememberLastProfile = defaults.object(forKey: Keys.rememberLast) as? Bool ?? true
        deletedIDs = Set((defaults.stringArray(forKey: Keys.deleted) ?? []).compactMap(UUID.init(uuidString:)))
        fileURL = directory?.appending(path: "profiles.json")
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder.profiles.decode([ViewerProfile].self, from: data) {
            profiles = Array(stored.prefix(ViewerProfile.maximumCount))
        }
        activeProfileID = defaults.string(forKey: Keys.active).flatMap(UUID.init(uuidString:))
        if !profiles.contains(where: { $0.id == activeProfileID }) {
            activeProfileID = profiles.first?.id
        }
        needsSelection = (profiles.count > 1 && !rememberLastProfile) || activeProfile?.isLocked == true
    }

    nonisolated static var defaultDirectory: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return support.appending(path: "Profiles", directoryHint: .isDirectory)
    }

    /// Local detachment only. Never creates deletion tombstones or invokes onDelete.
    func resetAfterSignOut() throws {
        pushTask?.cancel()
        pushTask = nil
        if let fileURL {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder.profiles.encode([ViewerProfile]()).write(to: fileURL, options: .atomic)
        }
        profiles = []
        activeProfileID = nil
        deletedIDs = []
        failedPINAttempts = [:]
        needsSelection = false
        rememberLastProfile = true
        syncProblem = nil
        for key in [Keys.active, Keys.deleted, Keys.defaultLibraryOwner] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: Editing

    @discardableResult
    func create(name: String, avatarID: String?, colorHex: String) -> ViewerProfile? {
        guard canAddProfile else { return nil }
        let cleanName = ViewerProfile.cleanName(name)
        let profile = ViewerProfile(
            name: cleanName.isEmpty ? "Profile \(profiles.count + 1)" : cleanName,
            avatarID: avatarID,
            colorHex: colorHex
        )
        profiles.append(profile)
        // The first profile on this Mac inherits the library from before.
        if defaultLibraryOwnerID == nil {
            UserDefaults.standard.set(profile.id.uuidString, forKey: Keys.defaultLibraryOwner)
        }
        if activeProfileID == nil { activeProfileID = profile.id }
        save()
        return profile
    }

    func update(_ profile: ViewerProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        var updated = profile
        let cleanName = ViewerProfile.cleanName(profile.name)
        updated.name = cleanName.isEmpty ? profiles[index].name : cleanName
        if isMain(profile.id) {
            updated.usesMainSettings = false
            updated.usesMainAddons = false
            updated.usesMainPlugins = false
        }
        updated.updatedAt = .now
        profiles[index] = updated
        save()
    }

    /// Removes the profile and, on this Mac, its library and progress.
    func delete(_ id: UUID) {
        guard profiles.count > 1, !isMain(id), let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        do { try KeychainStore.delete(account: Self.pinAccount(id)) } catch { return }
        profiles.remove(at: index)
        deletedIDs.insert(id)
        NotificationCenter.default.post(name: .credentialVaultDidChange, object: nil)
        onDelete?(id)
        if defaultLibraryOwnerID == id {
            UserDefaults.standard.removeObject(forKey: Keys.defaultLibraryOwner)
        } else if let url = LocalMediaStore.profileStoreURL(for: id) {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }
        if activeProfileID == id { activeProfileID = profiles.first?.id }
        save()
    }

    /// Makes `id` the watching profile. A locked profile needs its PIN.
    @discardableResult
    func select(_ id: UUID, pin: String? = nil) -> PINResult {
        guard let profile = profiles.first(where: { $0.id == id }) else { return .wrong }
        if profile.isLocked, id != activeProfileID || needsSelection {
            let result = checkPIN(pin ?? "", for: id)
            guard result == .accepted else { return result }
        }
        activeProfileID = id
        needsSelection = false
        UserDefaults.standard.set(id.uuidString, forKey: Keys.active)
        return .accepted
    }

    // MARK: PIN

    enum PINResult: Equatable {
        case accepted
        case wrong
        case unavailable
        case lockedOut(until: Date)
    }

    static func isValidPIN(_ pin: String) -> Bool {
        pin.count == 4 && pin.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// Sets or, with nil, removes the PIN. Only a salted hash is kept.
    func setPIN(_ pin: String?, for id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        do {
            if let pin {
                guard Self.isValidPIN(pin) else { return }
                let salt = UUID().uuidString
                try KeychainStore.save("\(salt):\(Self.hash(pin, salt: salt))", account: Self.pinAccount(id))
                profiles[index].isLocked = true
            } else {
                try KeychainStore.delete(account: Self.pinAccount(id))
                profiles[index].isLocked = false
            }
        } catch { return }
        NotificationCenter.default.post(name: .credentialVaultDidChange, object: nil)
        profiles[index].updatedAt = .now
        save()
    }

    /// Five wrong tries lock the profile for 30 seconds, then longer.
    func checkPIN(_ pin: String, for id: UUID) -> PINResult {
        var attempts = failedPINAttempts[id] ?? (0, nil)
        if let lockedUntil = attempts.lockedUntil, lockedUntil > .now { return .lockedOut(until: lockedUntil) }
        guard let stored = try? KeychainStore.value(account: Self.pinAccount(id)) else {
            // A missing/locked Keychain item must not weaken profile protection.
            return .unavailable
        }
        let parts = stored.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.count == 2, Self.hash(pin, salt: parts[0]) == parts[1] {
            failedPINAttempts[id] = nil
            return .accepted
        }
        attempts.count += 1
        if attempts.count >= 5 {
            let lockedUntil = Date.now.addingTimeInterval(30 * Double(attempts.count - 4))
            attempts.lockedUntil = lockedUntil
            failedPINAttempts[id] = attempts
            return .lockedOut(until: lockedUntil)
        }
        failedPINAttempts[id] = attempts
        return .wrong
    }

    func vaultPINIDs() -> [UUID] { profiles.map(\.id) }

    func vaultPIN(_ id: UUID) throws -> String? {
        try KeychainStore.value(account: Self.pinAccount(id))
    }

    func applyVaultPIN(_ value: String?, id: UUID, updateLock: Bool = true) throws {
        try CredentialVaultLocalStore.replaceCredential(value, account: Self.pinAccount(id))
        failedPINAttempts[id] = nil
        if updateLock, let index = profiles.firstIndex(where: { $0.id == id }) {
            profiles[index].isLocked = value != nil
            if value != nil, activeProfileID == id { needsSelection = true }
            save(pushing: false)
        }
    }

    private static func pinAccount(_ id: UUID) -> String { "profile-pin.\(id.uuidString)" }

    private static func hash(_ pin: String, salt: String) -> String {
        SHA256.hash(data: Data("\(salt)|\(pin)".utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Cloud

    /// Merges this Mac's profiles with the account's: the newest edit of
    /// each wins and deletions on either side stick. Without the account
    /// table (or offline) profiles simply stay on this Mac.
    func sync(with account: OmniaAccount) async {
        guard let userID = account.user?.id else { return }
        do {
            let remote = try await account.fetchViewerProfiles()
            guard account.user?.id == userID, !Task.isCancelled else { return }
            var merged = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
            var positions = Dictionary(uniqueKeysWithValues: profiles.enumerated().map { ($1.id, $0) })
            for row in remote {
                if row.deletedAt != nil {
                    deletedIDs.insert(row.id)
                    continue
                }
                if let local = merged[row.id], local.updatedAt >= row.updatedAt { continue }
                var profile = ViewerProfile(
                    id: row.id,
                    name: row.name,
                    avatarID: row.avatarID,
                    colorHex: row.colorHex,
                    isLocked: row.isLocked,
                    createdAt: row.createdAt
                )
                profile.usesMainSettings = row.usesMainSettings ?? false
                profile.usesMainAddons = row.usesMainAddons ?? false
                profile.usesMainPlugins = row.usesMainPlugins ?? false
                profile.updatedAt = row.updatedAt
                merged[row.id] = profile
                positions[row.id] = row.position
            }
            for id in deletedIDs { merged[id] = nil }
            let ordered = merged.values.sorted {
                let left = positions[$0.id] ?? 99
                let right = positions[$1.id] ?? 99
                return left == right ? $0.createdAt < $1.createdAt : left < right
            }
            if !ordered.isEmpty {
                profiles = Array(ordered.prefix(ViewerProfile.maximumCount))
                if !profiles.contains(where: { $0.id == activeProfileID }) { activeProfileID = profiles.first?.id }
                if activeProfile?.isLocked == true { needsSelection = true }
                save(pushing: false)
            }
            var rows = profiles.enumerated().map { index, profile in
                OmniaAccount.ViewerProfileRow(
                    userID: userID, id: profile.id, name: profile.name, avatarID: profile.avatarID,
                    colorHex: profile.colorHex, position: index, isLocked: profile.isLocked,
                    usesMainSettings: profile.usesMainSettings, usesMainAddons: profile.usesMainAddons,
                    usesMainPlugins: profile.usesMainPlugins,
                    deletedAt: nil, createdAt: profile.createdAt, updatedAt: profile.updatedAt
                )
            }
            rows += deletedIDs.map { id in
                OmniaAccount.ViewerProfileRow(
                    userID: userID, id: id, name: "Deleted", avatarID: nil, colorHex: "705CFF",
                    position: 0, isLocked: false, usesMainSettings: nil, usesMainAddons: nil,
                    usesMainPlugins: nil, deletedAt: .now, createdAt: .now, updatedAt: .now
                )
            }
            try await account.saveViewerProfiles(rows)
            guard account.user?.id == userID, !Task.isCancelled else { return }
            syncProblem = nil
        } catch {
            guard account.user?.id == userID, !Task.isCancelled else { return }
            syncProblem = "Profiles are saved on this Mac but couldn't sync with your account."
        }
    }

    // MARK: Saving

    private func save(pushing: Bool = true) {
        if let fileURL {
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if let data = try? JSONEncoder.profiles.encode(profiles) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
        if let activeProfileID {
            UserDefaults.standard.set(activeProfileID.uuidString, forKey: Keys.active)
        }
        UserDefaults.standard.set(deletedIDs.map(\.uuidString), forKey: Keys.deleted)
        guard pushing, let account, account.user != nil else { return }
        // Several quick edits become one upload.
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            await self.sync(with: account)
        }
    }
}

private extension JSONEncoder {
    static var profiles: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var profiles: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
