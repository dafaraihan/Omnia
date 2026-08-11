//
//  OmniaStore.swift
//  Omnia
//

import Observation
import SwiftUI

@Observable
@MainActor
final class OmniaStore {
    private static let addonsStorageKey = "installed-addons"
    private static let disabledCatalogsStorageKey = "disabled-addon-catalogs"
    private static let appearanceStorageKey = "app-appearance"
    private static let playbackCompletionThresholdKey = "playback-completion-threshold"
    private static let metadataRoutingStorageKey = "metadata-routing-preferences"

    private(set) var library: [MediaItem]
    private(set) var localMediaSnapshots: [LocalMediaSnapshot]
    private(set) var localMediaPersistenceFailed = false
    private let localMediaStore: LocalMediaStore?
    var installedAddons: [InstalledAddon]
    private(set) var disabledAddonCatalogIDs: Set<String>
    var appearance: AppAppearance {
        didSet { saveAppearance() }
    }
    var accentColor: Color = .blue
    var metadataRouting: MetadataRoutingPreferences {
        didSet { saveMetadataRouting() }
    }

    init(
        library: [MediaItem]? = nil,
        installedAddons: [InstalledAddon]? = nil,
        disabledAddonCatalogIDs: Set<String>? = nil,
        appearance: AppAppearance? = nil,
        metadataRouting: MetadataRoutingPreferences? = nil
    ) {
        let restoresPersistedAddons = installedAddons == nil
        self.library = library ?? []
        self.localMediaSnapshots = (library ?? []).map {
            LocalMediaSnapshot(item: $0, isInWatchlist: true, savedAt: nil, lastPlayedAt: nil)
        }
        self.localMediaStore = library == nil ? try? LocalMediaStore.live() : nil
        self.installedAddons = installedAddons ?? Self.loadAddons()
        self.disabledAddonCatalogIDs = disabledAddonCatalogIDs ?? Self.loadDisabledCatalogIDs()
        self.appearance = appearance ?? Self.loadAppearance()
        self.metadataRouting = metadataRouting ?? Self.loadMetadataRouting()

        // Successful legacy decoding migrates confidential manifest endpoints
        // into Keychain through InstalledAddon, then this rewrite removes the
        // old URL field from UserDefaults immediately.
        if restoresPersistedAddons, !self.installedAddons.isEmpty {
            saveAddons()
        }
    }

    static let preview = OmniaStore(
        library: MediaItem.previewLibrary,
        installedAddons: [.preview]
    )

    func add(_ addon: InstalledAddon) {
        installedAddons.removeAll { $0.id == addon.id }
        installedAddons.append(addon)
        saveAddons()
    }

    func installAddon(manifestURL: URL) async throws {
        let manifest = try await StremioAddonClient.fetchManifest(from: manifestURL)
        add(.init(manifest: manifest, manifestURL: manifestURL, isEnabled: true, addedAt: .now))
    }

    func removeAddon(id: String) {
        installedAddons.first(where: { $0.id == id })?.removeSecureManifestURL()
        installedAddons.removeAll { $0.id == id }
        disabledAddonCatalogIDs = disabledAddonCatalogIDs.filter { !$0.hasPrefix("\(id)::") }
        saveAddons()
        saveDisabledCatalogIDs()
    }

    func replaceAddon(id: String, manifest: StremioAddonManifest, manifestURL: URL) {
        guard let index = installedAddons.firstIndex(where: { $0.id == id }) else { return }
        let existing = installedAddons[index]
        installedAddons[index] = .init(
            manifest: manifest,
            manifestURL: manifestURL,
            isEnabled: existing.isEnabled,
            addedAt: existing.addedAt
        )
        saveAddons()
    }

    func moveAddons(from source: IndexSet, to destination: Int) {
        installedAddons.move(fromOffsets: source, toOffset: destination)
        saveAddons()
    }

    func toggleAddon(id: String) {
        guard let index = installedAddons.firstIndex(where: { $0.id == id }) else { return }
        installedAddons[index].isEnabled.toggle()
        saveAddons()
    }

    func catalogID(for addon: InstalledAddon, catalog: AddonCatalog) -> String {
        "\(addon.id)::\(catalog.type)::\(catalog.id)"
    }

    func isCatalogEnabled(for addon: InstalledAddon, catalog: AddonCatalog) -> Bool {
        addon.isEnabled && !disabledAddonCatalogIDs.contains(catalogID(for: addon, catalog: catalog))
    }

    func toggleCatalog(for addon: InstalledAddon, catalog: AddonCatalog) {
        let id = catalogID(for: addon, catalog: catalog)
        if disabledAddonCatalogIDs.contains(id) {
            disabledAddonCatalogIDs.remove(id)
        } else {
            disabledAddonCatalogIDs.insert(id)
        }
        saveDisabledCatalogIDs()
    }

    var enabledAddonCatalogCount: Int {
        installedAddons.reduce(into: 0) { count, addon in
            count += addon.manifest.catalogs.filter { isCatalogEnabled(for: addon, catalog: $0) }.count
        }
    }

    func isSaved(_ item: MediaItem) -> Bool {
        localMediaSnapshots.first(where: { $0.mediaID == item.id })?.isInWatchlist
            ?? library.contains { $0.id == item.id }
    }

    func toggleSaved(_ item: MediaItem) {
        guard let localMediaStore else {
            if let index = library.firstIndex(where: { $0.id == item.id }) {
                library.remove(at: index)
            } else {
                library.insert(item, at: 0)
            }
            return
        }

        let includesItem = !isSaved(item)
        Task {
            do {
                try await localMediaStore.setWatchlist(item, isIncluded: includesItem, at: .now)
                await refreshLocalMedia()
            } catch {
                localMediaPersistenceFailed = true
            }
        }
    }

    /// Stores a durable local resume point. The title is added to the library
    /// when necessary so Continue Watching never depends on a remote catalog.
    func recordPlayback(
        for item: MediaItem,
        episode: MediaEpisode? = nil,
        positionSeconds: Double,
        durationSeconds: Double?
    ) {
        guard let localMediaStore else {
            recordPlaybackInMemory(
                for: item,
                episode: episode,
                positionSeconds: positionSeconds,
                durationSeconds: durationSeconds
            )
            return
        }

        Task {
            do {
                try await localMediaStore.recordPlayback(
                    for: item,
                    episode: episode,
                    positionSeconds: positionSeconds,
                    durationSeconds: durationSeconds,
                    completionThreshold: Self.playbackCompletionThreshold,
                    at: .now
                )
                await refreshLocalMedia()
            } catch {
                localMediaPersistenceFailed = true
            }
        }
    }

    func prepareLocalMedia() async {
        guard let localMediaStore else { return }
        do {
            try await LegacyLibraryMigration(defaults: .standard, store: localMediaStore).runIfNeeded()
            await refreshLocalMedia()
        } catch {
            localMediaPersistenceFailed = true
        }
    }

    func exportLocalMedia() async throws -> Data {
        guard let localMediaStore else {
            return try LocalMediaBackupDocument(
                snapshots: localMediaSnapshots,
                exportedAt: .now
            ).encoded()
        }
        return try await localMediaStore.exportDocument().encoded()
    }

    func importLocalMedia(_ data: Data, replacingExisting: Bool) async throws {
        guard let localMediaStore else { throw LocalMediaStoreError.verificationFailed }
        let review = try await localMediaStore.reviewImport(data)
        let mode: LocalMediaImportMode = replacingExisting
            ? .replace(review.confirmation)
            : .merge
        try await localMediaStore.applyImport(review, mode: mode)
        await refreshLocalMedia()
    }

    func clearLocalMedia(_ action: LocalMediaDestructiveAction) async throws {
        guard let localMediaStore else { throw LocalMediaStoreError.verificationFailed }
        let confirmation = await localMediaStore.confirmation(for: action)
        try await localMediaStore.perform(action, confirmation: confirmation)
        await refreshLocalMedia()
    }

    private func recordPlaybackInMemory(
        for item: MediaItem,
        episode: MediaEpisode?,
        positionSeconds: Double,
        durationSeconds: Double?
    ) {
        let position = max(positionSeconds, 0)
        let duration = durationSeconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let normalized = duration.map { min(max(position / $0, 0), 1) }
        let completed = normalized.map { $0 >= Self.playbackCompletionThreshold } ?? false

        var updated = item
        if let episode {
            updated.resumeEpisodeID = episode.id
            updated.resumeSeasonNumber = episode.seasonNumber
            updated.resumeEpisodeNumber = episode.episodeNumber
            updated.resumeEpisodeStillURL = episode.stillURL
        } else if let existing = library.first(where: { $0.id == item.id }) {
            // A subsequent time tick receives the title again, not a fresh
            // episode object. Retain the known episode context until playback
            // of another episode replaces it.
            updated.resumeEpisodeID = existing.resumeEpisodeID
            updated.resumeSeasonNumber = existing.resumeSeasonNumber
            updated.resumeEpisodeNumber = existing.resumeEpisodeNumber
            updated.resumeEpisodeStillURL = existing.resumeEpisodeStillURL
        }
        updated.positionSeconds = position
        updated.durationSeconds = duration
        updated.progress = completed ? nil : normalized
        if completed {
            updated.resumeEpisodeID = nil
            updated.resumeSeasonNumber = nil
            updated.resumeEpisodeNumber = nil
            updated.resumeEpisodeStillURL = nil
        }

        if let index = library.firstIndex(where: { $0.id == item.id }) {
            library[index] = updated
        } else if !completed {
            library.insert(updated, at: 0)
        }
    }

    private func refreshLocalMedia() async {
        guard let localMediaStore else { return }
        do {
            let snapshots = try await localMediaStore.snapshot()
            localMediaSnapshots = snapshots
            library = snapshots.map(\.item)
            localMediaPersistenceFailed = false
        } catch {
            localMediaPersistenceFailed = true
        }
    }

    private static func loadAddons() -> [InstalledAddon] {
        guard let data = UserDefaults.standard.data(forKey: addonsStorageKey) else { return [] }
        return (try? JSONDecoder().decode([InstalledAddon].self, from: data)) ?? []
    }

    private static func loadDisabledCatalogIDs() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: disabledCatalogsStorageKey) else { return [] }
        return (try? JSONDecoder().decode(Set<String>.self, from: data)) ?? []
    }

    private static func loadAppearance() -> AppAppearance {
        guard let value = UserDefaults.standard.string(forKey: appearanceStorageKey) else { return .system }
        return AppAppearance(rawValue: value) ?? .system
    }

    private static func loadMetadataRouting() -> MetadataRoutingPreferences {
        guard let data = UserDefaults.standard.data(forKey: metadataRoutingStorageKey) else { return .init() }
        return (try? JSONDecoder().decode(MetadataRoutingPreferences.self, from: data)) ?? .init()
    }

    /// The point at which a title stops appearing in Continue Watching. The
    /// preference is intentionally read here, where completion is decided,
    /// rather than merely displayed in Settings.
    private static var playbackCompletionThreshold: Double {
        switch UserDefaults.standard.integer(forKey: playbackCompletionThresholdKey) {
        case 80, 90, 95:
            Double(UserDefaults.standard.integer(forKey: playbackCompletionThresholdKey)) / 100
        default:
            0.95
        }
    }

    private func saveAddons() {
        guard let data = try? JSONEncoder().encode(installedAddons) else { return }
        UserDefaults.standard.set(data, forKey: Self.addonsStorageKey)
    }

    private func saveDisabledCatalogIDs() {
        guard let data = try? JSONEncoder().encode(disabledAddonCatalogIDs) else { return }
        UserDefaults.standard.set(data, forKey: Self.disabledCatalogsStorageKey)
    }

    private func saveAppearance() {
        UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceStorageKey)
    }

    private func saveMetadataRouting() {
        guard let data = try? JSONEncoder().encode(metadataRouting) else { return }
        UserDefaults.standard.set(data, forKey: Self.metadataRoutingStorageKey)
    }
}
