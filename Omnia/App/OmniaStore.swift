//
//  OmniaStore.swift
//  Omnia
//

import Observation
import SwiftUI

@Observable
@MainActor
final class OmniaStore {
    private static let guestLibraryKey = "signed-out-library-id"
    private static let disabledCatalogsStorageKey = "disabled-addon-catalogs"
    private static let appearanceStorageKey = "app-appearance"
    private static let playbackCompletionThresholdKey = "playback-completion-threshold"
    private static let metadataRoutingStorageKey = "metadata-routing-preferences"

    private(set) var library: [MediaItem]
    private(set) var localMediaSnapshots: [LocalMediaSnapshot] {
        didSet { libraryRevision &+= 1 }
    }
    /// Goes up whenever the library or progress changes, so profile sync
    /// notices.
    private(set) var libraryRevision = 0
    /// Each playback tick, for the profile's watch time.
    @ObservationIgnored var onPlaybackProgress: ((_ key: String, _ positionSeconds: Double) -> Void)?
    private(set) var localMediaPersistenceFailed = false
    @ObservationIgnored private var playbackPersistenceTask: Task<Void, Never>?
    /// The episode whose ending already produced a Next Up entry, so later
    /// ticks past the end don't repeat it.
    @ObservationIgnored private var finishedEpisodeKey: String?
    @ObservationIgnored private var localMediaStore: LocalMediaStore?
    @ObservationIgnored private var libraryProfileID: UUID?
    @ObservationIgnored private var libraryGeneration = UUID()
    @ObservationIgnored private var addonGeneration = UUID()
    private let addonPersistence: InstalledAddonPersistence?
    var installedAddons: [InstalledAddon] {
        didSet { addonHomeCatalogCache = nil }
    }
    /// Home catalogs derived from `installedAddons`, rebuilt only when the
    /// add-ons change. Home and Settings read them on every render.
    @ObservationIgnored var addonHomeCatalogCache: [AddonHomeCatalog]?
    private(set) var installedAddonsAreLoading: Bool
    private(set) var installedAddonRestoreIssues: [InstalledAddonRestoreIssue]
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
        metadataRouting: MetadataRoutingPreferences? = nil,
        installedAddonRestoreIssues: [InstalledAddonRestoreIssue] = []
    ) {
        self.library = library ?? []
        self.localMediaSnapshots = (library ?? []).map {
            LocalMediaSnapshot(item: $0, isInWatchlist: true, savedAt: nil, lastPlayedAt: nil)
        }
        self.localMediaStore = library == nil ? try? Self.defaultLocalMediaStore() : nil
        self.addonPersistence = installedAddons == nil ? InstalledAddonPersistence() : nil
        self.installedAddons = installedAddons ?? []
        self.installedAddonsAreLoading = installedAddons == nil
        self.installedAddonRestoreIssues = installedAddonRestoreIssues
        self.disabledAddonCatalogIDs = disabledAddonCatalogIDs ?? Self.loadDisabledCatalogIDs()
        self.appearance = appearance ?? Self.loadAppearance()
        self.metadataRouting = metadataRouting ?? Self.loadMetadataRouting()
    }

    static let preview = OmniaStore(
        library: MediaItem.previewLibrary,
        installedAddons: [.preview]
    )

    /// Installing from an address that is already installed replaces that
    /// add-on in place. Another configuration of the same add-on (same
    /// manifest id, different address) is added next to it instead of
    /// replacing it.
    func add(_ addon: InstalledAddon) {
        var addon = addon
        if let index = installedAddons.firstIndex(where: { $0.manifestURL == addon.manifestURL }) {
            let existing = installedAddons[index]
            addon = InstalledAddon(
                manifest: addon.manifest,
                manifestURL: addon.manifestURL,
                isEnabled: addon.isEnabled,
                addedAt: existing.addedAt,
                customName: existing.customName,
                installID: existing.installID
            )
            installedAddons[index] = addon
        } else {
            if installedAddons.contains(where: { $0.id == addon.id }) {
                addon = InstalledAddon(
                    manifest: addon.manifest,
                    manifestURL: addon.manifestURL,
                    isEnabled: addon.isEnabled,
                    addedAt: addon.addedAt,
                    customName: addon.customName,
                    installID: InstalledAddon.secondaryInstallID(manifestID: addon.manifest.id, manifestURL: addon.manifestURL)
                )
                // Installing the same second configuration again replaces it.
                installedAddons.removeAll { $0.id == addon.id }
            }
            installedAddons.append(addon)
        }
        installedAddonRestoreIssues.removeAll { $0.addonID == addon.id }
        saveAddons()
    }

    func installAddon(manifestURL: URL) async throws {
        let ticket = addonGeneration
        let manifest = try await StremioAddonClient.fetchManifest(from: manifestURL)
        guard ticket == addonGeneration else { throw CancellationError() }
        add(.init(manifest: manifest, manifestURL: manifestURL, isEnabled: true, addedAt: .now))
    }

    func removeAddon(id: String) {
        let removedAddon = installedAddons.first(where: { $0.id == id })
        installedAddons.removeAll { $0.id == id }
        disabledAddonCatalogIDs = disabledAddonCatalogIDs.filter { !$0.hasPrefix("\(id)::") }
        if let removedAddon, let addonPersistence {
            let remainingAddons = installedAddons
            Task {
                await addonPersistence.remove(removedAddon, remainingAddons: remainingAddons)
            }
        } else {
            saveAddons()
        }
        saveDisabledCatalogIDs()
    }

    func replaceAddon(id: String, manifest: StremioAddonManifest, manifestURL: URL) {
        guard let index = installedAddons.firstIndex(where: { $0.id == id }) else { return }
        let existing = installedAddons[index]
        installedAddons[index] = .init(
            manifest: manifest,
            manifestURL: manifestURL,
            isEnabled: existing.isEnabled,
            addedAt: existing.addedAt,
            customName: existing.customName,
            installID: existing.installID
        )
        saveAddons()
    }

    /// Add-ons such as Xperience change their manifest when they are
    /// reconfigured on the web, while the address stays the same. Like
    /// Nuvio, fetch every enabled manifest again at launch, so newly enabled
    /// catalogs, and the collection folders that point at them, show up.
    func refreshInstalledManifests() async {
        let ticket = addonGeneration
        let addons = installedAddons.filter(\.isEnabled).map { (id: $0.id, url: $0.manifestURL) }
        await withTaskGroup(of: (String, URL, Result<StremioAddonManifest, Error>).self) { group in
            for addon in addons {
                group.addTask {
                    do {
                        return (addon.id, addon.url, .success(try await StremioAddonClient.fetchManifest(from: addon.url)))
                    } catch {
                        return (addon.id, addon.url, .failure(error))
                    }
                }
            }
            for await (id, url, result) in group {
                guard ticket == addonGeneration else { group.cancelAll(); return }
                let manifest: StremioAddonManifest
                switch result {
                case let .success(fetched):
                    AddonDiagnostics.shared.recordSuccess(.manifest, addonID: id)
                    manifest = fetched
                case let .failure(error):
                    // The last manifest keeps working; Settings shows why
                    // it couldn't be refreshed.
                    AddonDiagnostics.shared.recordFailure(.manifest, addonID: id, error: error)
                    continue
                }
                guard let current = installedAddons.first(where: { $0.id == id }),
                      manifest.id == current.manifest.id,
                      current.manifestURL == url,
                      current.manifest != manifest
                else { continue }
                replaceAddon(id: id, manifest: manifest, manifestURL: url)
            }
        }
    }

    /// Nuvio's Refresh addon: fetch one add-on's manifest again now. Returns
    /// the error when it couldn't be fetched; the last manifest keeps working.
    @discardableResult
    func refreshAddonManifest(id: String) async -> Error? {
        guard let addon = installedAddons.first(where: { $0.id == id }) else { return nil }
        let url = addon.manifestURL
        let manifest: StremioAddonManifest
        do {
            manifest = try await StremioAddonClient.fetchManifest(from: url)
            AddonDiagnostics.shared.recordSuccess(.manifest, addonID: id)
        } catch {
            AddonDiagnostics.shared.recordFailure(.manifest, addonID: id, error: error)
            return error
        }
        guard let current = installedAddons.first(where: { $0.id == id }),
              manifest.id == current.manifest.id,
              current.manifestURL == url,
              current.manifest != manifest
        else { return nil }
        replaceAddon(id: id, manifest: manifest, manifestURL: url)
        return nil
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

    func renameAddon(id: String, to name: String) {
        guard let index = installedAddons.firstIndex(where: { $0.id == id }) else { return }
        installedAddons[index].rename(to: name)
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

    /// Home Layout's Reset to Default shows every catalog again.
    func enableAllCatalogs() {
        guard !disabledAddonCatalogIDs.isEmpty else { return }
        disabledAddonCatalogIDs.removeAll()
        saveDisabledCatalogIDs()
    }

    var enabledAddonCatalogCount: Int {
        installedAddons.reduce(into: 0) { count, addon in
            count += addon.manifest.catalogs.filter { isCatalogEnabled(for: addon, catalog: $0) }.count
        }
    }

    func isSaved(_ item: MediaItem) -> Bool {
        savedSnapshot(matching: item)?.isInWatchlist
            ?? library.contains { $0.isSameTitle(as: item) }
    }

    /// The stored entry for this title, found by its exact ID first, then by
    /// any shared IMDb/TMDB/TVDB ID, so a title added from Home and found
    /// again through search is one entry, not two.
    private func savedSnapshot(matching item: MediaItem) -> LocalMediaSnapshot? {
        localMediaSnapshots.first { $0.mediaID == item.id }
            ?? localMediaSnapshots.first { $0.isInWatchlist && $0.item.isSameTitle(as: item) }
            ?? localMediaSnapshots.first { $0.item.isSameTitle(as: item) }
    }

    func toggleSaved(_ item: MediaItem) {
        setSaved(item, isIncluded: !isSaved(item))
    }

    func setSaved(_ requested: MediaItem, isIncluded: Bool) {
        // Save to, or remove, the entry already stored for this title.
        let item = savedSnapshot(matching: requested)?.item ?? requested
        guard let localMediaStore else {
            if isIncluded {
                if !library.contains(where: { $0.isSameTitle(as: item) }) {
                    library.insert(item, at: 0)
                }
            } else {
                library.removeAll { $0.isSameTitle(as: item) }
            }

            let snapshotIndex = localMediaSnapshots.firstIndex { $0.mediaID == item.id }
            let existing = snapshotIndex.map { localMediaSnapshots[$0] }
            let updated = LocalMediaSnapshot(
                item: existing?.item ?? item,
                isInWatchlist: isIncluded,
                savedAt: isIncluded ? (existing?.savedAt ?? .now) : nil,
                lastPlayedAt: existing?.lastPlayedAt,
                watchState: existing?.watchState ?? .empty
            )
            if let snapshotIndex {
                if !isIncluded, updated.progress == nil, updated.watchState.isEmpty {
                    localMediaSnapshots.remove(at: snapshotIndex)
                } else {
                    localMediaSnapshots[snapshotIndex] = updated
                }
            } else if isIncluded {
                localMediaSnapshots.insert(updated, at: 0)
            }
            return
        }

        // Removing also clears any duplicate saved before titles were
        // matched across IDs.
        let duplicates = isIncluded ? [] : localMediaSnapshots
            .filter { $0.isInWatchlist && $0.mediaID != item.id && $0.item.isSameTitle(as: item) }
            .map(\.item)
        Task {
            do {
                try await localMediaStore.setWatchlist(item, isIncluded: isIncluded, at: .now)
                for duplicate in duplicates {
                    try await localMediaStore.setWatchlist(duplicate, isIncluded: false, at: .now)
                }
                await refreshLocalMedia()
            } catch {
                localMediaPersistenceFailed = true
            }
        }
    }

    /// What Continue Watching offers once an episode ends: the series'
    /// episodes and the Next Up options from Settings.
    struct NextUpRequest {
        let episodes: [MediaEpisode]
        let fromFurthest: Bool
        let includesUnaired: Bool
        /// Shuffle's random pick, which replaces the following episode.
        var shuffledNext: MediaEpisode? = nil
    }

    /// Stores a durable local resume point. The title is added to the library
    /// when necessary so Continue Watching never depends on a remote catalog.
    func recordPlayback(
        for item: MediaItem,
        episode: MediaEpisode? = nil,
        positionSeconds: Double,
        durationSeconds: Double?,
        nextUp: NextUpRequest? = nil
    ) {
        onPlaybackProgress?(episode.map { "\(item.id)|\($0.id)" } ?? item.id, positionSeconds)
        let finished = finishedEpisodeCommand(
            for: item,
            episode: episode,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds,
            nextUp: nextUp
        )

        guard let localMediaStore else {
            recordPlaybackInMemory(
                for: item,
                episode: episode,
                positionSeconds: positionSeconds,
                durationSeconds: durationSeconds
            )
            if let finished, let nextUp {
                applyWatchCommandInMemory(finished, to: item, episodes: nextUp.episodes)
            }
            return
        }

        // Update the observable snapshot immediately so the current card and
        // detail action cannot lag behind the player. Disk writes are chained
        // in arrival order so a slower earlier tick can never overwrite a
        // newer resume point.
        recordPlaybackInMemory(
            for: item,
            episode: episode,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds
        )
        if let finished, let nextUp {
            applyWatchCommandInMemory(finished, to: item, episodes: nextUp.episodes)
        }
        let previousWrite = playbackPersistenceTask
        playbackPersistenceTask = Task { [weak self] in
            await previousWrite?.value
            guard let self else { return }
            do {
                try await localMediaStore.recordPlayback(
                    for: item,
                    episode: episode,
                    positionSeconds: positionSeconds,
                    durationSeconds: durationSeconds,
                    completionThreshold: Self.playbackCompletionThreshold,
                    at: .now
                )
                // Written after the resume point is cleared, in the same
                // chain, so the Next Up entry can't be overwritten.
                if let finished, let nextUp {
                    try await localMediaStore.applyWatchCommand(
                        finished,
                        to: item,
                        episodes: nextUp.episodes,
                        at: .now
                    )
                }
                await refreshLocalMedia()
            } catch {
                localMediaPersistenceFailed = true
            }
        }
    }

    /// The Next Up command for the tick that first passes the end of an
    /// episode, or nil.
    private func finishedEpisodeCommand(
        for item: MediaItem,
        episode: MediaEpisode?,
        positionSeconds: Double,
        durationSeconds: Double?,
        nextUp: NextUpRequest?
    ) -> LocalMediaWatchCommand? {
        guard item.kind == .series, let episode else { return nil }
        let key = "\(item.id)|\(episode.id)"
        let duration = durationSeconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let progress = duration.map { min(max(positionSeconds, 0) / $0, 1) } ?? 0
        guard progress >= Self.playbackCompletionThreshold else {
            // Starting the episode again allows another Next Up later.
            if finishedEpisodeKey == key { finishedEpisodeKey = nil }
            return nil
        }
        guard finishedEpisodeKey != key, let nextUp, !nextUp.episodes.isEmpty else { return nil }
        finishedEpisodeKey = key
        let target = nextUp.shuffledNext ?? NextUpEpisode.after(
            episode,
            episodes: nextUp.episodes,
            watchState: watchState(for: item),
            fromFurthest: nextUp.fromFurthest,
            includesUnaired: nextUp.includesUnaired
        )
        return .finishEpisode(episode, nextUp: target)
    }

    func removeFromContinueWatching(_ item: MediaItem) {
        guard let localMediaStore else {
            removeFromContinueWatchingInMemory(item)
            return
        }

        Task {
            do {
                try await localMediaStore.clearProgress(for: item.id)
                await refreshLocalMedia()
            } catch {
                localMediaPersistenceFailed = true
            }
        }
    }

    func watchState(for item: MediaItem) -> LocalMediaWatchState {
        savedSnapshot(matching: item)?.watchState ?? .empty
    }

    /// - Parameter leavingContinueWatching: Mark Watched on a title's hero
    ///   also takes the title out of Continue Watching, next episode
    ///   included (Dafa, 2026-10-21).
    func applyWatchCommand(
        _ command: LocalMediaWatchCommand,
        to requested: MediaItem,
        episodes: [MediaEpisode],
        leavingContinueWatching: Bool = false
    ) {
        // The entry already stored for this title, even when the page that
        // asks knows it by another ID (an add-on ID against a TMDB one).
        // Otherwise the command made a second entry and the one in
        // Continue Watching never changed.
        let item = savedSnapshot(matching: requested)?.item ?? requested
        guard let localMediaStore else {
            applyWatchCommandInMemory(command, to: item, episodes: episodes)
            if leavingContinueWatching { removeFromContinueWatchingInMemory(item) }
            return
        }

        Task {
            do {
                try await localMediaStore.applyWatchCommand(
                    command,
                    to: item,
                    episodes: episodes,
                    at: .now
                )
                if leavingContinueWatching {
                    try await localMediaStore.clearProgress(for: item.id)
                }
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

    /// NuvioTV's default add-ons (Dafa, 2026-10-21): Cinemeta and
    /// OpenSubtitles, installed once each. One that is removed stays removed,
    /// and one that couldn't be reached is tried again at the next launch.
    static let defaultAddonManifestURLs = [
        "https://v3-cinemeta.strem.io/manifest.json",
        "https://opensubtitles-v3.strem.io/manifest.json",
    ]
    private static let installedDefaultAddonsKey = "installed-default-addons"

    /// `force` installs them again, for a new profile's fresh add-ons.
    func installDefaultAddonsIfNeeded(force: Bool = false) async {
        let ticket = addonGeneration
        guard addonPersistence != nil, !installedAddonsAreLoading else { return }
        let defaults = UserDefaults.standard
        var done = force ? [] : Set(defaults.stringArray(forKey: Self.installedDefaultAddonsKey) ?? [])
        for address in Self.defaultAddonManifestURLs where !done.contains(address) {
            guard let url = URL(string: address) else { continue }
            if installedAddons.contains(where: { $0.manifestURL == url }) {
                done.insert(address)
                continue
            }
            guard let manifest = try? await StremioAddonClient.fetchManifest(from: url) else { continue }
            guard ticket == addonGeneration else { return }
            // Already installed from another address: count it as done.
            if !installedAddons.contains(where: { $0.manifest.id == manifest.id }) {
                add(.init(manifest: manifest, manifestURL: url, isEnabled: true, addedAt: .now))
            }
            done.insert(address)
        }
        defaults.set(Array(done).sorted(), forKey: Self.installedDefaultAddonsKey)
    }

    func prepareInstalledAddons() async {
        guard let addonPersistence, installedAddonsAreLoading else { return }
        let ticket = addonGeneration
        let result = await addonPersistence.load()
        guard ticket == addonGeneration else { return }
        installedAddons = result.addons
        installedAddonRestoreIssues = result.issues
        installedAddonsAreLoading = false

        // Successful legacy decoding migrates confidential manifest endpoints
        // into Keychain. Re-encoding removes the old URL field from defaults.
        if !result.addons.isEmpty, result.issues.isEmpty {
            await addonPersistence.save(result.addons)
        }
    }

    func exportLocalMedia(at date: Date = .now) async throws -> Data {
        guard let localMediaStore else {
            return try LocalMediaBackupDocument(
                snapshots: localMediaSnapshots,
                exportedAt: date
            ).encoded()
        }
        return try await localMediaStore.exportDocument(at: date).encoded()
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
            updated.resumeEpisodeTitle = episode.title
            updated.resumeEpisodeStillURL = episode.stillURL
        } else if let existing = localMediaSnapshots.first(where: { $0.mediaID == item.id })?.item
            ?? library.first(where: { $0.id == item.id }) {
            // A subsequent time tick receives the title again, not a fresh
            // episode object. Retain the known episode context until playback
            // of another episode replaces it.
            updated.resumeEpisodeID = existing.resumeEpisodeID
            updated.resumeSeasonNumber = existing.resumeSeasonNumber
            updated.resumeEpisodeNumber = existing.resumeEpisodeNumber
            updated.resumeEpisodeTitle = existing.resumeEpisodeTitle
            updated.resumeEpisodeStillURL = existing.resumeEpisodeStillURL
        }
        updated.positionSeconds = position
        updated.durationSeconds = duration
        updated.progress = completed ? nil : normalized
        if completed {
            updated.resumeEpisodeID = nil
            updated.resumeSeasonNumber = nil
            updated.resumeEpisodeNumber = nil
            updated.resumeEpisodeTitle = nil
            updated.resumeEpisodeStillURL = nil
        }

        let snapshotIndex = localMediaSnapshots.firstIndex { $0.mediaID == item.id }
        let existingSnapshot = snapshotIndex.map { localMediaSnapshots[$0] }
        let isInWatchlist = existingSnapshot?.isInWatchlist
            ?? library.contains(where: { $0.id == item.id })
        let snapshot = LocalMediaSnapshot(
            item: updated,
            isInWatchlist: isInWatchlist,
            savedAt: existingSnapshot?.savedAt,
            lastPlayedAt: completed ? nil : .now,
            watchState: existingSnapshot?.watchState ?? .empty
        )
        if let snapshotIndex {
            if completed, !isInWatchlist, snapshot.watchState.isEmpty {
                localMediaSnapshots.remove(at: snapshotIndex)
            } else {
                localMediaSnapshots[snapshotIndex] = snapshot
            }
        } else if !completed || isInWatchlist {
            localMediaSnapshots.insert(snapshot, at: 0)
        }

        if isInWatchlist {
            if let index = library.firstIndex(where: { $0.id == item.id }) {
                library[index] = updated
            } else {
                library.insert(updated, at: 0)
            }
        } else {
            library.removeAll { $0.id == item.id }
        }
    }

    private func removeFromContinueWatchingInMemory(_ item: MediaItem) {
        let snapshotIndex = localMediaSnapshots.firstIndex { $0.mediaID == item.id }
        let snapshot = snapshotIndex.map { localMediaSnapshots[$0] }
        let libraryIndex = library.firstIndex { $0.id == item.id }
        guard var cleared = snapshot?.item ?? libraryIndex.map({ library[$0] }) else { return }
        cleared.progress = nil
        cleared.positionSeconds = nil
        cleared.durationSeconds = nil
        cleared.resumeEpisodeID = nil
        cleared.resumeSeasonNumber = nil
        cleared.resumeEpisodeNumber = nil
        cleared.resumeEpisodeTitle = nil
        cleared.resumeEpisodeStillURL = nil
        if let snapshotIndex, let snapshot {
            if !snapshot.isInWatchlist, snapshot.watchState.isEmpty {
                localMediaSnapshots.remove(at: snapshotIndex)
            } else {
                localMediaSnapshots[snapshotIndex] = LocalMediaSnapshot(
                item: cleared,
                isInWatchlist: snapshot.isInWatchlist,
                savedAt: snapshot.savedAt,
                lastPlayedAt: nil,
                watchState: snapshot.watchState
            )
            }
        }

        if let libraryIndex {
            if snapshot?.isInWatchlist == true {
                library[libraryIndex] = cleared
            } else {
                library.remove(at: libraryIndex)
            }
        }
    }

    private func applyWatchCommandInMemory(
        _ command: LocalMediaWatchCommand,
        to item: MediaItem,
        episodes: [MediaEpisode]
    ) {
        let snapshotIndex = localMediaSnapshots.firstIndex { $0.mediaID == item.id }
        let existingSnapshot = snapshotIndex.map { localMediaSnapshots[$0] }
        var updatedItem = existingSnapshot?.item
            ?? library.first(where: { $0.id == item.id })
            ?? item
        var state = existingSnapshot?.watchState ?? .empty
        let orderedEpisodes = episodes.sorted {
            ($0.seasonNumber, $0.episodeNumber, $0.id)
                < ($1.seasonNumber, $1.episodeNumber, $1.id)
        }

        func matches(_ lhs: MediaEpisode, _ rhs: MediaEpisode) -> Bool {
            lhs.id == rhs.id
                || (lhs.seasonNumber == rhs.seasonNumber && lhs.episodeNumber == rhs.episodeNumber)
        }

        func setResumeTarget(_ episode: MediaEpisode?) {
            guard let episode else {
                updatedItem.progress = nil
                updatedItem.positionSeconds = nil
                updatedItem.durationSeconds = nil
                updatedItem.resumeEpisodeID = nil
                updatedItem.resumeSeasonNumber = nil
                updatedItem.resumeEpisodeNumber = nil
                updatedItem.resumeEpisodeTitle = nil
                updatedItem.resumeEpisodeStillURL = nil
                return
            }
            updatedItem.progress = 0
            updatedItem.positionSeconds = 0
            updatedItem.durationSeconds = episode.runtimeMinutes.map { Double($0 * 60) }
            updatedItem.resumeEpisodeID = episode.id
            updatedItem.resumeSeasonNumber = episode.seasonNumber
            updatedItem.resumeEpisodeNumber = episode.episodeNumber
            updatedItem.resumeEpisodeTitle = episode.title
            updatedItem.resumeEpisodeStillURL = episode.stillURL
        }

        switch command {
        case let .markMovie(watched):
            state.movieWatched = watched
            setResumeTarget(nil)
        case let .markEpisode(episode, watched):
            state.setWatched(watched, for: episode)
            if watched,
               let index = orderedEpisodes.firstIndex(where: { matches($0, episode) }),
               orderedEpisodes.indices.contains(index + 1) {
                setResumeTarget(orderedEpisodes[index + 1])
            } else {
                setResumeTarget(watched ? nil : episode)
            }
        case let .markSeason(current, watched):
            let seasonEpisodes = orderedEpisodes.filter { $0.seasonNumber == current.seasonNumber }
            seasonEpisodes.forEach { state.setWatched(watched, for: $0) }
            setResumeTarget(
                watched
                    ? orderedEpisodes.first { $0.seasonNumber > current.seasonNumber }
                    : seasonEpisodes.first
            )
        case let .markThrough(current, watched):
            guard let index = orderedEpisodes.firstIndex(where: { matches($0, current) }) else { return }
            orderedEpisodes.prefix(through: index).forEach { state.setWatched(watched, for: $0) }
            setResumeTarget(
                watched && orderedEpisodes.indices.contains(index + 1)
                    ? orderedEpisodes[index + 1]
                    : orderedEpisodes.first
            )
        case let .revertToPrevious(current):
            guard let index = orderedEpisodes.firstIndex(where: { matches($0, current) }), index > 0 else { return }
            let previous = orderedEpisodes[index - 1]
            state.setWatched(false, for: previous)
            setResumeTarget(previous)
        case let .finishEpisode(finished, nextUp):
            state.setWatched(true, for: finished)
            setResumeTarget(nextUp)
        }

        let isInWatchlist = existingSnapshot?.isInWatchlist
            ?? library.contains(where: { $0.id == item.id })
        let updatedSnapshot = LocalMediaSnapshot(
            item: updatedItem,
            isInWatchlist: isInWatchlist,
            savedAt: existingSnapshot?.savedAt,
            lastPlayedAt: updatedItem.progress == nil ? nil : .now,
            watchState: state
        )
        if let snapshotIndex {
            localMediaSnapshots[snapshotIndex] = updatedSnapshot
        } else {
            localMediaSnapshots.insert(updatedSnapshot, at: 0)
        }

        if let libraryIndex = library.firstIndex(where: { $0.id == item.id }) {
            library[libraryIndex] = updatedItem
        }
    }

    // MARK: Profiles

    /// A profile's add-ons, with their addresses, and its hidden catalogs.
    nonisolated struct AddonProfileSnapshot: Codable, Sendable {
        struct Entry: Codable, Sendable {
            var manifest: StremioAddonManifest
            var manifestURL: URL
            var isEnabled: Bool
            var addedAt: Date
            var customName: String?
            var installID: String
        }

        var addons: [Entry]
        var disabledCatalogIDs: [String]
    }

    func addonProfileSnapshot() -> AddonProfileSnapshot {
        AddonProfileSnapshot(
            addons: installedAddons.map {
                .init(
                    manifest: $0.manifest, manifestURL: $0.manifestURL, isEnabled: $0.isEnabled,
                    addedAt: $0.addedAt, customName: $0.customName, installID: $0.installID
                )
            },
            disabledCatalogIDs: disabledAddonCatalogIDs.sorted()
        )
    }

    /// Switching profiles: another profile's add-ons, or Cinemeta and
    /// OpenSubtitles for a new one, as on a first launch.
    func restoreAddons(_ snapshot: AddonProfileSnapshot?) async {
        installedAddons = snapshot?.addons.map {
            InstalledAddon(
                manifest: $0.manifest, manifestURL: $0.manifestURL, isEnabled: $0.isEnabled,
                addedAt: $0.addedAt, customName: $0.customName, installID: $0.installID
            )
        } ?? []
        installedAddonRestoreIssues = []
        disabledAddonCatalogIDs = Set(snapshot?.disabledCatalogIDs ?? [])
        saveAddons()
        saveDisabledCatalogIDs()
        if snapshot == nil {
            await installDefaultAddonsIfNeeded(force: true)
        }
        await refreshInstalledManifests()
    }

    private static func defaultLocalMediaStore() throws -> LocalMediaStore {
        if let raw = UserDefaults.standard.string(forKey: guestLibraryKey), let id = UUID(uuidString: raw) {
            return try LocalMediaStore.live(profileID: id)
        }
        return try LocalMediaStore.live()
    }

    func resetAddonsAfterSignOut() async {
        addonGeneration = UUID()
        UserDefaults.standard.removeObject(forKey: Self.installedDefaultAddonsKey)
        installedAddons = []
        installedAddonsAreLoading = false
        installedAddonRestoreIssues = []
        disabledAddonCatalogIDs = []
        await addonPersistence?.save([])
        saveDisabledCatalogIDs()
    }

    func resetLibraryAfterSignOut() async throws {
        libraryGeneration = UUID()
        playbackPersistenceTask?.cancel()
        await playbackPersistenceTask?.value
        playbackPersistenceTask = nil
        let id = UUID()
        let fresh = try LocalMediaStore.live(profileID: id)
        UserDefaults.standard.set(id.uuidString, forKey: Self.guestLibraryKey)
        libraryProfileID = nil
        localMediaStore = fresh
        library = []
        localMediaSnapshots = []
        finishedEpisodeKey = nil
        localMediaPersistenceFailed = false
    }

    /// Switches the library, watchlist and progress to a profile's own.
    func useLibrary(for profileID: UUID, ownsDefaultLibrary: Bool) async {
        guard addonPersistence != nil, libraryProfileID != profileID else { return }
        // At launch the default library is already open.
        if ownsDefaultLibrary, libraryProfileID == nil {
            libraryProfileID = profileID
            return
        }
        // Progress still being written belongs to the previous profile.
        let ticket = UUID()
        libraryGeneration = ticket
        libraryProfileID = profileID
        await playbackPersistenceTask?.value
        guard ticket == libraryGeneration else { return }
        playbackPersistenceTask = nil
        finishedEpisodeKey = nil
        localMediaStore = ownsDefaultLibrary
            ? try? Self.defaultLocalMediaStore()
            : try? LocalMediaStore.live(profileID: profileID)
        library = []
        localMediaSnapshots = []
        await refreshLocalMedia()
    }

    private func refreshLocalMedia() async {
        guard let localMediaStore else { return }
        do {
            let profileID = libraryProfileID
            let snapshots = try await localMediaStore.snapshot()
            guard self.localMediaStore === localMediaStore, libraryProfileID == profileID else { return }
            localMediaSnapshots = snapshots
            library = snapshots.filter(\.isInWatchlist).map(\.item)
            localMediaPersistenceFailed = false
        } catch {
            localMediaPersistenceFailed = true
        }
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
        guard let addonPersistence else { return }
        let addons = installedAddons
        let ticket = addonGeneration
        Task {
            guard ticket == addonGeneration else { return }
            await addonPersistence.save(addons)
        }
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
