import CryptoKit
import Foundation
import Observation
import Synchronization

/// The parts of a profile that are its own, as in Nuvio. Settings, Home
/// layout and collections follow "use the main profile's settings";
/// add-ons and plugins have their own switches; library, progress and watch
/// time always belong to the profile.
nonisolated enum ProfileDataKind: String, CaseIterable, Codable, Sendable {
    case settings
    case homeLayout = "home_layout"
    case collections
    case addons
    case plugins
    case library
    case stats

    /// Kept in the live stores for whoever is watching, and swapped when
    /// the profile changes. The library swaps by itself (one store file per
    /// profile) and watch time is kept for every profile at once.
    static let swapped: [ProfileDataKind] = [.settings, .homeLayout, .collections, .addons, .plugins]

    func usesMain(_ profile: ViewerProfile) -> Bool {
        switch self {
        case .settings, .homeLayout, .collections: profile.usesMainSettings
        case .addons: profile.usesMainAddons
        case .plugins: profile.usesMainPlugins
        case .library, .stats: false
        }
    }

    /// Big payloads wait longer, so playback doesn't upload every tick.
    var pushDelay: Duration {
        switch self {
        case .library, .stats: .seconds(20)
        default: .seconds(3)
        }
    }
}

/// Everything under Settings that isn't Home: the preferences plus the
/// appearance and metadata choices OmniaStore keeps.
nonisolated struct ProfileSettingsBundle: Codable, Sendable {
    var preferences: SettingsPreferences
    var appearance: String?
    var metadataRouting: MetadataRoutingPreferences?
}

/// Keeps each profile's settings, add-ons, plugins, library and watch time
/// apart on this Mac, and in the account once signed in.
///
/// On this Mac the live stores always hold the watching profile's data;
/// switching saves them for the profile being left (encrypted, since add-on
/// addresses can hold private tokens) and loads the next one's, or a fresh
/// start. In the account each kind of each profile is one row of
/// `profile_data`; the newest copy wins, and a copy changed elsewhere since
/// this Mac last synced replaces the one here.
@Observable
@MainActor
final class ProfileDataSync {
    private(set) var lastSyncedAt: Date?
    private(set) var problem: String?
    private(set) var isSyncing = false
    /// Seconds watched, by profile.
    private(set) var watchSeconds: [UUID: Double]

    @ObservationIgnored private let store: OmniaStore
    @ObservationIgnored private let settings: SettingsPreferencesStore
    @ObservationIgnored private let homeLayout: HomeLayoutStore
    @ObservationIgnored private let collections: CollectionsStore
    @ObservationIgnored private let plugins: PluginStore
    @ObservationIgnored private let profiles: ProfileStore
    @ObservationIgnored private let account: OmniaAccount

    /// Whose data each swapped kind's live store holds right now.
    @ObservationIgnored private var holders: [ProfileDataKind: UUID]
    /// The account copy's time when this Mac last matched it, by key.
    @ObservationIgnored private var syncedAt: [String: Date]
    /// Keys changed here and not uploaded yet.
    @ObservationIgnored private var dirty: Set<String>
    /// What each key looked like when last loaded or saved, to tell real
    /// changes from a store simply being refilled.
    @ObservationIgnored private var baselines: [String: String] = [:]
    @ObservationIgnored private var pushTasks: [ProfileDataKind: Task<Void, Never>] = [:]
    @ObservationIgnored private var isActivating = false
    @ObservationIgnored private var needsActivation = false
    @ObservationIgnored private var hasPulled = false
    @ObservationIgnored private var lastTick: (key: String, position: Double, date: Date)?

    private enum Keys {
        static let holders = "profile-data-holders"
        static let synced = "profile-data-synced"
        static let dirty = "profile-data-dirty"
        static let watchSeconds = "profile-watch-seconds"
    }

    init(
        store: OmniaStore,
        settings: SettingsPreferencesStore,
        homeLayout: HomeLayoutStore,
        collections: CollectionsStore,
        plugins: PluginStore,
        profiles: ProfileStore,
        account: OmniaAccount
    ) {
        self.store = store
        self.settings = settings
        self.homeLayout = homeLayout
        self.collections = collections
        self.plugins = plugins
        self.profiles = profiles
        self.account = account
        let defaults = UserDefaults.standard
        holders = (defaults.dictionary(forKey: Keys.holders) as? [String: String] ?? [:])
            .reduce(into: [:]) { result, pair in
                if let kind = ProfileDataKind(rawValue: pair.key), let id = UUID(uuidString: pair.value) {
                    result[kind] = id
                }
            }
        syncedAt = (defaults.dictionary(forKey: Keys.synced) as? [String: Double] ?? [:])
            .mapValues { Date(timeIntervalSince1970: $0) }
        dirty = Set(defaults.stringArray(forKey: Keys.dirty) ?? [])
        watchSeconds = (defaults.dictionary(forKey: Keys.watchSeconds) as? [String: Double] ?? [:])
            .reduce(into: [:]) { result, pair in
                if let id = UUID(uuidString: pair.key) { result[id] = pair.value }
            }
        profiles.onDelete = { [weak self] id in self?.forget(id) }
        store.onPlaybackProgress = { [weak self] key, position in self?.recordTick(key: key, position: position) }
    }

    var activeWatchSeconds: Double {
        profiles.activeProfile.map { watchSeconds[$0.id] ?? 0 } ?? 0
    }

    // MARK: Switching

    /// Puts the watching profile's data in the live stores. Called at
    /// launch, when the profile changes, and when its sharing changes.
    func activate() async {
        guard !isActivating else {
            needsActivation = true
            return
        }
        guard let active = profiles.activeProfile else { return }
        isActivating = true
        // Before profiles, everything belonged to what is now the main one.
        let legacyHolder = profiles.mainProfileID ?? active.id
        for kind in ProfileDataKind.swapped {
            let target = owner(of: kind, for: active)
            let current = holders[kind] ?? legacyHolder
            if current != target {
                if let data = await export(kind) {
                    ProfileDataVault.write(data, owner: current, kind: kind)
                }
                await apply(kind, data: ProfileDataVault.read(owner: target, kind: kind))
            }
            holders[kind] = target
            if let data = await export(kind) { baselines[key(target, kind)] = data.fingerprint }
        }
        saveHolders()
        isActivating = false
        // The profile changed again while this one was being loaded.
        if needsActivation {
            needsActivation = false
            await activate()
            return
        }
        await applyPendingLibrary()
        if let data = await export(.library) { baselines[key(active.id, .library)] = data.fingerprint }
        await sync()
    }

    private func owner(of kind: ProfileDataKind, for profile: ViewerProfile) -> UUID {
        guard kind.usesMain(profile), let main = profiles.mainProfileID else { return profile.id }
        return main
    }

    /// Whose copy of `kind` the live stores hold.
    private func liveOwner(of kind: ProfileDataKind) -> UUID? {
        switch kind {
        case .library, .stats: profiles.activeProfile?.id
        default: holders[kind]
        }
    }

    // MARK: Changes here

    /// A store changed. Uploaded after a short pause once it really differs
    /// from what was last loaded or saved.
    func localChange(_ kind: ProfileDataKind) {
        guard !isActivating, let owner = liveOwner(of: kind) else { return }
        pushTasks[kind]?.cancel()
        pushTasks[kind] = Task { [weak self] in
            try? await Task.sleep(for: kind.pushDelay)
            guard let self, !Task.isCancelled, !self.isActivating,
                  self.liveOwner(of: kind) == owner,
                  let data = await self.export(kind)
            else { return }
            let key = self.key(owner, kind)
            guard self.baselines[key] != data.fingerprint else { return }
            self.baselines[key] = data.fingerprint
            self.dirty.insert(key)
            self.saveDirty()
            await self.push()
        }
    }

    // MARK: Account

    /// Brings down copies changed elsewhere, then uploads what changed here.
    func sync() async {
        guard account.user != nil, account.isConfigured, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let index = try await account.fetchProfileDataIndex()
            let known = Set(profiles.profiles.map(\.id))
            for row in index where known.contains(row.profileID) {
                guard let kind = ProfileDataKind(rawValue: row.kind) else { continue }
                let key = key(row.profileID, kind)
                if let synced = syncedAt[key], synced >= row.updatedAt.addingTimeInterval(-0.001) { continue }
                guard let payload = try await account.fetchProfileDataPayload(profileID: row.profileID, kind: row.kind),
                      let data = payload.data(using: .utf8)
                else { continue }
                await receive(data, owner: row.profileID, kind: kind)
                syncedAt[key] = row.updatedAt
                dirty.remove(key)
            }
            saveSynced()
            saveDirty()
            hasPulled = true
            try await uploadDirty()
            lastSyncedAt = .now
            problem = nil
        } catch {
            problem = "Couldn't sync with your account. Everything stays on this Mac and syncs again later."
        }
    }

    private func push() async {
        guard hasPulled else {
            await sync()
            return
        }
        guard account.user != nil, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await uploadDirty()
            lastSyncedAt = .now
            problem = nil
        } catch {
            problem = "Couldn't sync with your account. Everything stays on this Mac and syncs again later."
        }
    }

    private func uploadDirty() async throws {
        guard account.user != nil else { return }
        for key in dirty.sorted() {
            guard let (owner, kind) = parse(key), profiles.profiles.contains(where: { $0.id == owner }) else {
                dirty.remove(key)
                continue
            }
            let data = liveOwner(of: kind) == owner
                ? await export(kind)
                : ProfileDataVault.read(owner: owner, kind: kind)
            guard let data, let payload = String(data: data, encoding: .utf8) else {
                dirty.remove(key)
                continue
            }
            let now = Date.now
            try await account.saveProfileData(profileID: owner, kind: kind.rawValue, payload: payload, updatedAt: now)
            syncedAt[key] = now
            dirty.remove(key)
            saveSynced()
            saveDirty()
        }
    }

    /// A copy from the account: into the live store when it's the one in
    /// use, otherwise saved for when that profile is next opened.
    private func receive(_ data: Data, owner: UUID, kind: ProfileDataKind) async {
        if kind == .stats {
            let remote = (try? JSONDecoder().decode(WatchStats.self, from: data))?.seconds ?? 0
            watchSeconds[owner] = max(watchSeconds[owner] ?? 0, remote)
            saveWatchSeconds()
            return
        }
        if liveOwner(of: kind) == owner {
            await apply(kind, data: data)
            if let refreshed = await export(kind) { baselines[key(owner, kind)] = refreshed.fingerprint }
        } else {
            ProfileDataVault.write(data, owner: owner, kind: kind)
            // Another profile's library lives in its own store file and is
            // put in place when that profile next opens.
            if kind == .library { ProfileDataVault.markPendingLibrary(owner) }
        }
    }

    private func applyPendingLibrary() async {
        guard let active = profiles.activeProfile, ProfileDataVault.hasPendingLibrary(active.id),
              let data = ProfileDataVault.read(owner: active.id, kind: .library)
        else { return }
        await apply(.library, data: data)
        ProfileDataVault.clearPendingLibrary(active.id)
    }

    // MARK: Stores

    private func export(_ kind: ProfileDataKind) async -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        switch kind {
        case .settings:
            return try? encoder.encode(ProfileSettingsBundle(
                preferences: settings.preferences,
                appearance: store.appearance.rawValue,
                metadataRouting: store.metadataRouting
            ))
        case .homeLayout:
            return try? encoder.encode(homeLayout.preferences)
        case .collections:
            return try? encoder.encode(collections.profileSnapshot())
        case .addons:
            return try? encoder.encode(store.addonProfileSnapshot())
        case .plugins:
            return try? encoder.encode(plugins.profileState())
        case .library:
            // A fixed date, so an unchanged library encodes the same.
            return try? await store.exportLocalMedia(at: Date(timeIntervalSince1970: 0))
        case .stats:
            return try? encoder.encode(WatchStats(seconds: activeWatchSeconds))
        }
    }

    /// Fills a live store from `data`, or with a fresh start when nil.
    private func apply(_ kind: ProfileDataKind, data: Data?) async {
        let decoder = JSONDecoder()
        switch kind {
        case .settings:
            let bundle = data.flatMap { try? decoder.decode(ProfileSettingsBundle.self, from: $0) }
            settings.replace(with: bundle?.preferences)
            store.appearance = bundle?.appearance.flatMap(AppAppearance.init(rawValue:)) ?? .system
            if let routing = bundle?.metadataRouting { store.metadataRouting = routing }
        case .homeLayout:
            homeLayout.replace(with: data.flatMap { try? decoder.decode(HomeLayoutPreferences.self, from: $0) })
        case .collections:
            collections.restore(data.flatMap { try? decoder.decode(CollectionsStore.ProfileSnapshot.self, from: $0) })
        case .addons:
            await store.restoreAddons(data.flatMap { try? decoder.decode(OmniaStore.AddonProfileSnapshot.self, from: $0) })
        case .plugins:
            plugins.restore(data.flatMap { try? decoder.decode(PluginStore.StoredState.self, from: $0) })
        case .library:
            guard let data else { return }
            try? await store.importLocalMedia(data, replacingExisting: true)
        case .stats:
            break
        }
    }

    // MARK: Watch time

    private nonisolated struct WatchStats: Codable {
        var seconds: Double
    }

    /// Counts the time between playback ticks while the position moves on
    /// at about the speed of the clock, so seeking and pauses don't count.
    private func recordTick(key: String, position: Double) {
        let now = Date.now
        defer { lastTick = (key, position, now) }
        guard let last = lastTick, last.key == key, let profile = profiles.activeProfile else { return }
        let elapsed = now.timeIntervalSince(last.date)
        let advanced = position - last.position
        guard elapsed > 0, elapsed <= 60, advanced > 0, advanced <= elapsed * 2.5 + 2 else { return }
        watchSeconds[profile.id, default: 0] += advanced
        saveWatchSeconds()
        localChange(.stats)
    }

    // MARK: Profiles going away

    private func forget(_ id: UUID) {
        ProfileDataVault.removeAll(owner: id)
        watchSeconds[id] = nil
        saveWatchSeconds()
        for kind in ProfileDataKind.allCases {
            syncedAt[key(id, kind)] = nil
            dirty.remove(key(id, kind))
        }
        saveSynced()
        saveDirty()
        Task { try? await account.deleteProfileData(profileID: id) }
    }

    // MARK: Saving

    private func key(_ owner: UUID, _ kind: ProfileDataKind) -> String {
        "\(owner.uuidString).\(kind.rawValue)"
    }

    private func parse(_ key: String) -> (UUID, ProfileDataKind)? {
        let parts = key.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[0]), let kind = ProfileDataKind(rawValue: parts[1])
        else { return nil }
        return (id, kind)
    }

    private func saveHolders() {
        UserDefaults.standard.set(
            Dictionary(uniqueKeysWithValues: holders.map { ($0.key.rawValue, $0.value.uuidString) }),
            forKey: Keys.holders
        )
    }

    private func saveSynced() {
        UserDefaults.standard.set(syncedAt.mapValues(\.timeIntervalSince1970), forKey: Keys.synced)
    }

    private func saveDirty() {
        UserDefaults.standard.set(dirty.sorted(), forKey: Keys.dirty)
    }

    private func saveWatchSeconds() {
        UserDefaults.standard.set(
            Dictionary(uniqueKeysWithValues: watchSeconds.map { ($0.key.uuidString, $0.value) }),
            forKey: Keys.watchSeconds
        )
    }
}

/// Profiles' saved data on this Mac, sealed with a key in the Keychain:
/// add-on addresses can hold private tokens.
nonisolated enum ProfileDataVault {
    private static let keyAccount = "profile-data-key"
    private static let cachedKey = Mutex<SymmetricKey?>(nil)
    private static let pendingLibrariesKey = "profile-data-pending-libraries"

    private static func directory(for owner: UUID) -> URL? {
        ProfileStore.defaultDirectory?
            .appending(path: "Data", directoryHint: .isDirectory)
            .appending(path: owner.uuidString, directoryHint: .isDirectory)
    }

    static func write(_ data: Data, owner: UUID, kind: ProfileDataKind) {
        guard let key = key(), let directory = directory(for: owner),
              let sealed = try? AES.GCM.seal(data, using: key).combined
        else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? sealed.write(to: directory.appending(path: "\(kind.rawValue).bin"), options: .atomic)
    }

    static func read(owner: UUID, kind: ProfileDataKind) -> Data? {
        guard let key = key(),
              let file = directory(for: owner)?.appending(path: "\(kind.rawValue).bin"),
              let combined = try? Data(contentsOf: file),
              let box = try? AES.GCM.SealedBox(combined: combined)
        else { return nil }
        return try? AES.GCM.open(box, using: key)
    }

    static func removeAll(owner: UUID) {
        if let directory = directory(for: owner) { try? FileManager.default.removeItem(at: directory) }
        clearPendingLibrary(owner)
    }

    static func markPendingLibrary(_ owner: UUID) {
        var pending = Set(UserDefaults.standard.stringArray(forKey: pendingLibrariesKey) ?? [])
        pending.insert(owner.uuidString)
        UserDefaults.standard.set(pending.sorted(), forKey: pendingLibrariesKey)
    }

    static func hasPendingLibrary(_ owner: UUID) -> Bool {
        (UserDefaults.standard.stringArray(forKey: pendingLibrariesKey) ?? []).contains(owner.uuidString)
    }

    static func clearPendingLibrary(_ owner: UUID) {
        let pending = (UserDefaults.standard.stringArray(forKey: pendingLibrariesKey) ?? [])
            .filter { $0 != owner.uuidString }
        UserDefaults.standard.set(pending, forKey: pendingLibrariesKey)
    }

    private static func key() -> SymmetricKey? {
        cachedKey.withLock { cached in
            if let cached { return cached }
            if let saved = try? KeychainStore.value(account: keyAccount), let data = Data(base64Encoded: saved) {
                cached = SymmetricKey(data: data)
                return cached
            }
            let fresh = SymmetricKey(size: .bits256)
            let encoded = fresh.withUnsafeBytes { Data($0).base64EncodedString() }
            guard (try? KeychainStore.save(encoded, account: keyAccount)) != nil else { return nil }
            cached = fresh
            return fresh
        }
    }
}

private extension Data {
    /// The whole payload's digest. `hashValue` looked at only part of the
    /// bytes, so a changed resume position could look unchanged and never
    /// reach the account.
    nonisolated var fingerprint: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
