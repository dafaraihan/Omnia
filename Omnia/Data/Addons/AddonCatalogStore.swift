//
//  AddonCatalogStore.swift
//  Omnia
//

import Foundation
import Observation

/// Loads add-on catalogs once for Home, instead of every shelf fetching its
/// own copy each time it appears. Each row loads and fails on its own, so one
/// broken add-on never empties the rest of Home.
@MainActor
@Observable
final class AddonCatalogStore {
    enum RowState: Equatable {
        case loading
        case loaded
        case failed
    }

    struct Row: Equatable {
        var state: RowState
        var previews: [AddonMetaPreview] = []
        var items: [MediaItem] = []
        /// Worked out once when the row loads; parsing release dates for
        /// every title on every render made Home stutter.
        var unreleased: [Bool] = []
    }

    /// Desktop Nuvio shows up to 64 titles per row, fetched in up to 4 pages.
    nonisolated static let rowItemLimit = 64
    nonisolated static let maximumPages = 4
    /// Requests in flight at once. Connections are shared, so this mostly
    /// sets how many rows can be on their way at the same moment.
    nonisolated static let concurrentRequests = 8
    /// Add-ons that page without declaring `skip` usually send 100 at a time.
    nonisolated static let fullPage = 100

    private(set) var rows: [String: Row] = [:]
    /// Bumped when Home reloads after being away, so the hero reshuffles.
    /// Rows refreshing behind a saved copy keep the same order.
    private(set) var generation = 0
    private var loadedSignature = ""
    private var loadTask: Task<Void, Never>?
    private var sessionID = UUID()
    private var lastRequested: [AddonHomeCatalog] = []
    private var loadedAt: Date?

    func resetAfterSignOut() {
        sessionID = UUID()
        loadTask?.cancel()
        loadTask = nil
        rows = [:]
        loadedSignature = ""
        lastRequested = []
        loadedAt = nil
        generation += 1
    }

    /// Every catalog that could be a Home row, in add-on install order.
    static func catalogs(in store: OmniaStore) -> [AddonHomeCatalog] {
        // Reading the add-ons keeps the caller observing them; the result is
        // cached until they change, since Home asks for it many times per render.
        let addons = store.installedAddons
        if let cached = store.addonHomeCatalogCache { return cached }
        var seen = Set<String>()
        let catalogs = addons.filter(\.isEnabled).flatMap { addon in
            addon.manifest.catalogs.compactMap { catalog -> AddonHomeCatalog? in
                guard catalog.canLoadWithoutExtra,
                      catalog.showInHome != false,
                      AddonHomeCatalog.isSupportedType(catalog.type)
                else { return nil }
                let key = store.catalogID(for: addon, catalog: catalog)
                guard seen.insert(key).inserted else { return nil }
                return AddonHomeCatalog(key: key, addon: addon, catalog: catalog)
            }
        }
        store.addonHomeCatalogCache = catalogs
        return catalogs
    }

    /// Add-on mode: as soon as an enabled add-on provides Home catalogs, Home
    /// is built from add-ons only and Omnia's built-in rows step aside.
    static func isAddonMode(_ store: OmniaStore) -> Bool {
        !catalogs(in: store).isEmpty
    }

    func state(for key: String) -> RowState? { rows[key]?.state }

    func items(for key: String, hidingUnreleased: Bool, now: Date = .now) -> [MediaItem] {
        guard let row = rows[key] else { return [] }
        guard hidingUnreleased, row.unreleased.count == row.items.count else { return row.items }
        return zip(row.items, row.unreleased)
            .filter { !$0.1 }
            .map(\.0)
    }

    /// Loads the given catalogs. Catalogs already loaded with the same add-on
    /// configuration are kept; pass `force` to reload everything.
    func load(_ catalogs: [AddonHomeCatalog], force: Bool = false) {
        let signature = catalogs.map { "\($0.key)@\($0.addon.manifestURL.absoluteString)" }.joined(separator: "|")
        guard force || signature != loadedSignature else { return }
        loadedSignature = signature
        lastRequested = catalogs
        loadedAt = .now

        let wanted = Set(catalogs.map(\.key))
        rows = rows.filter { wanted.contains($0.key) }
        let pending = catalogs.filter { force || rows[$0.key]?.state != .loaded }
        guard !pending.isEmpty else { return }
        for catalog in pending {
            // Keep any titles already on screen while the row refreshes.
            rows[catalog.key, default: Row(state: .loading)].state = .loading
        }

        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.fetch(pending, reshuffles: force)
        }
    }

    /// Catalogs such as Trending change through the day; reload them when
    /// Omnia returns to the front after an hour.
    func refreshIfStale(maxAge: TimeInterval = 60 * 60) {
        guard let loadedAt, Date.now.timeIntervalSince(loadedAt) > maxAge, !lastRequested.isEmpty else { return }
        load(lastRequested, force: true)
    }

    func retry(_ catalog: AddonHomeCatalog) {
        rows[catalog.key] = Row(state: .loading)
        Task { [weak self] in
            await self?.fetch([catalog])
        }
    }

    private func fetch(_ catalogs: [AddonHomeCatalog], reshuffles: Bool = false) async {
        let ticket = sessionID
        let jobs = catalogs.map { catalog in
            Job(
                key: catalog.key,
                addon: catalog.addon,
                catalog: catalog.catalog,
                paginates: catalog.supportsPagination,
                cacheKey: AddonCatalogCache.key(addon: catalog.addon, catalog: catalog.catalog)
            )
        }

        // The copy saved last time draws every row at once; the add-ons
        // then refresh them behind the scenes, like Nuvio.
        let empty = jobs.filter { rows[$0.key]?.items.isEmpty ?? true }
        if !empty.isEmpty {
            let cached = await Self.cachedRows(for: empty)
            if Task.isCancelled || ticket != sessionID { return }
            for job in empty {
                guard let row = cached[job.key], rows[job.key]?.items.isEmpty ?? true else { continue }
                apply(row, to: job, state: rows[job.key]?.state ?? .loading)
            }
        }

        // First page of every row, so the whole of Home fills quickly.
        var continuing: [(job: Job, first: FirstPage)] = []
        await run(jobs) { job -> FirstPage? in
            try? await Self.fetchFirstPage(job)
        } receive: { job, first in
            guard ticket == sessionID else { return }
            guard let first else {
                // Offline or a broken add-on: a saved copy beats an error.
                let hasItems = !(rows[job.key]?.items.isEmpty ?? true)
                rows[job.key, default: Row(state: .failed)].state = hasItems ? .loaded : .failed
                return
            }
            apply(first.row, to: job, state: .loaded)
            if (job.paginates && first.pageCount > 0) || first.pageCount >= Self.fullPage, first.row.previews.count < Self.rowItemLimit {
                continuing.append((job, first))
            } else {
                Task { await AddonCatalogCache.save(first.row.previews, for: job.cacheKey) }
            }
        }
        if Task.isCancelled || ticket != sessionID { return }
        if reshuffles { generation += 1 }

        // Then the remaining pages, up to 64 titles a row.
        let firstPages = Dictionary(continuing.map { ($0.job.key, $0.first) }, uniquingKeysWith: { first, _ in first })
        await run(continuing.map(\.job)) { job -> LoadedRow? in
            guard let first = firstPages[job.key] else { return nil }
            return await Self.fetchRemainingPages(job, after: first)
        } receive: { job, row in
            guard ticket == sessionID else { return }
            let final = row ?? firstPages[job.key]?.row
            if let row { apply(row, to: job, state: .loaded) }
            if let final {
                Task { await AddonCatalogCache.save(final.previews, for: job.cacheKey) }
            }
        }
    }

    private func apply(_ loaded: LoadedRow, to job: Job, state: RowState) {
        for (preview, item) in zip(loaded.previews, loaded.items) {
            AddonItemProvenance.record(itemID: item.id, addonID: job.addon.id, stremioType: preview.type)
        }
        rows[job.key] = Row(
            state: state,
            previews: loaded.previews,
            items: loaded.items,
            unreleased: loaded.unreleased
        )
    }

    /// Runs `operation` for every job, eight at a time. A new request starts
    /// as soon as any one finishes, and rows publish in the order they land.
    private func run<Result: Sendable>(
        _ jobs: [Job],
        operation: @escaping @Sendable (Job) async -> Result,
        receive: (Job, Result) -> Void
    ) async {
        guard !jobs.isEmpty else { return }
        await withTaskGroup(of: (Int, Result).self) { group in
            var next = 0
            while next < min(Self.concurrentRequests, jobs.count) {
                let index = next
                let job = jobs[index]
                group.addTask { (index, await operation(job)) }
                next += 1
            }
            for await (index, result) in group {
                if Task.isCancelled {
                    group.cancelAll()
                    return
                }
                receive(jobs[index], result)
                if next < jobs.count {
                    let index = next
                    let job = jobs[index]
                    group.addTask { (index, await operation(job)) }
                    next += 1
                }
            }
        }
    }

    /// What a row needs to load, copied out of the main actor.
    private nonisolated struct Job: Sendable {
        let key: String
        let addon: InstalledAddon
        let catalog: AddonCatalog
        let paginates: Bool
        let cacheKey: String
    }

    /// A catalog row prepared away from the main actor.
    private nonisolated struct LoadedRow: Sendable {
        var previews: [AddonMetaPreview]
        var items: [MediaItem]
        var unreleased: [Bool]
    }

    private nonisolated struct FirstPage: Sendable {
        var row: LoadedRow
        /// Titles the add-on sent, before duplicates and unsupported types
        /// were dropped. The next page starts here.
        var pageCount: Int
    }

    @concurrent
    private nonisolated static func cachedRows(for jobs: [Job]) async -> [String: LoadedRow] {
        let saved = await AddonCatalogCache.previews(for: jobs.map(\.cacheKey))
        let now = Date.now
        return jobs.reduce(into: [:]) { result, job in
            guard let previews = saved[job.cacheKey] else { return }
            let row = buildRow(previews, addon: job.addon, now: now)
            if !row.items.isEmpty { result[job.key] = row }
        }
    }

    @concurrent
    private nonisolated static func fetchFirstPage(_ job: Job) async throws -> FirstPage {
        let metas = try await StremioAddonClient.fetchCatalog(from: job.addon, catalog: job.catalog, extra: [:])
        var seen = Set<String>()
        let fresh = metas.filter { seen.insert("\($0.type):\($0.id)").inserted }
        return FirstPage(row: buildRow(fresh, addon: job.addon, now: .now), pageCount: metas.count)
    }

    /// Follows `skip` paging until the row has 64 titles, the add-on runs
    /// out, or a page brings nothing new. Returns nil when nothing was added.
    @concurrent
    private nonisolated static func fetchRemainingPages(_ job: Job, after first: FirstPage) async -> LoadedRow? {
        var collected = first.row.previews
        var seen = Set(collected.map { "\($0.type):\($0.id)" })
        var skip = first.pageCount
        for _ in 1..<maximumPages {
            guard collected.count < rowItemLimit,
                  let metas = try? await StremioAddonClient.fetchCatalog(
                      from: job.addon,
                      catalog: job.catalog,
                      extra: ["skip": String(skip)]
                  ),
                  !metas.isEmpty
            else { break }
            let fresh = metas.filter { seen.insert("\($0.type):\($0.id)").inserted }
            guard !fresh.isEmpty else { break }
            collected += fresh
            skip += metas.count
        }
        guard collected.count > first.row.previews.count else { return nil }
        return buildRow(collected, addon: job.addon, now: .now)
    }

    private nonisolated static func buildRow(_ previews: [AddonMetaPreview], addon: InstalledAddon, now: Date) -> LoadedRow {
        var row = LoadedRow(previews: [], items: [], unreleased: [])
        for preview in previews {
            guard row.items.count < rowItemLimit,
                  let item = preview.mediaItem(addon: addon)
            else { continue }
            row.previews.append(preview)
            row.items.append(item)
            row.unreleased.append(preview.isUnreleased(asOf: now))
        }
        return row
    }
}

/// Remembers which add-on and Stremio type each catalog title came from, so
/// its details can be requested from that add-on first, with the type the
/// add-on uses (for example `anime`).
@MainActor
enum AddonItemProvenance {
    private static var entries: [String: (addonID: String, stremioType: String)] = [:]

    static func record(itemID: String, addonID: String, stremioType: String) {
        entries[itemID] = (addonID, stremioType)
    }

    /// Splits `stremio:<addonID>:<metaID>`. Meta IDs such as `kitsu:123`
    /// contain colons, so only the first separator after the add-on is used.
    static func origin(of item: MediaItem) -> (addonID: String, metaID: String, stremioType: String?)? {
        guard item.id.hasPrefix("stremio:") else { return nil }
        let remainder = item.id.dropFirst("stremio:".count)
        guard let separator = remainder.firstIndex(of: ":") else { return nil }
        let addonID = String(remainder[..<separator])
        let metaID = String(remainder[remainder.index(after: separator)...])
        guard !addonID.isEmpty, !metaID.isEmpty else { return nil }
        return (addonID, metaID, entries[item.id]?.stremioType)
    }
}

/// Add-on-first title details: the add-on the title came from is asked first,
/// then the other meta add-ons in install order. The first answer wins.
enum AddonMetadataResolver {
    /// The add-on's answer per title. The Home hero asks again every time it
    /// rotates back to a title. Identity and progress are applied per call,
    /// so a cached answer never carries stale progress.
    private static var cache: [String: MediaItem] = [:]

    static func resolve(_ item: MediaItem, addons: [InstalledAddon]) async -> MediaItem? {
        let addonItem: MediaItem
        if let cached = cache[item.id] {
            addonItem = cached
        } else {
            guard let fetched = await fetchAddonItem(item, addons: addons) else { return nil }
            if cache.count > 200 { cache.removeAll() }
            cache[item.id] = fetched
            addonItem = fetched
        }
        return addonItem.replacingIdentity(with: item).fillingGaps(from: item)
    }

    private static func fetchAddonItem(_ item: MediaItem, addons: [InstalledAddon]) async -> MediaItem? {
        let origin = AddonItemProvenance.origin(of: item)
        let defaultType = item.kind == .movie ? "movie" : "series"
        var types = [origin?.stremioType, defaultType].compactMap { $0 }
        types = types.enumerated().filter { types.firstIndex(of: $0.element) == $0.offset }.map(\.element)

        var identifiers = item.streamIdentifierCandidates
        if let metaID = origin?.metaID {
            identifiers.removeAll { $0 == metaID }
            identifiers.insert(metaID, at: 0)
        }

        let candidates = addons.filter { $0.isEnabled && $0.manifest.supportsMeta }
        let ordered = candidates.filter { $0.id == origin?.addonID }
            + candidates.filter { $0.id != origin?.addonID }

        // Every add-on is asked at once; the first in order that answers
        // wins, so one slow add-on no longer holds up the rest. Asking them
        // one after another left the Home hero without its artwork and logo
        // whenever an early add-on was slow.
        let requestedTypes = types
        let requestedIdentifiers = identifiers
        return await withTaskGroup(of: (Int, MediaItem?).self) { group in
            for (index, addon) in ordered.enumerated() {
                group.addTask {
                    for type in requestedTypes {
                        guard !Task.isCancelled else { return (index, nil) }
                        if let meta = try? await StremioAddonClient.fetchMeta(from: addon, mediaType: type, identifiers: requestedIdentifiers),
                           let addonItem = meta.mediaItem(addon: addon) {
                            return (index, addonItem)
                        }
                    }
                    return (index, nil)
                }
            }
            var answers = [MediaItem??](repeating: nil, count: ordered.count)
            for await (index, item) in group {
                answers[index] = .some(item)
                // The best answer is the first add-on in order whose request
                // has finished with a result, once every earlier one is done.
                for answer in answers {
                    guard let finished = answer else { break }
                    if let item = finished {
                        group.cancelAll()
                        return item
                    }
                }
            }
            return nil
        }
    }
}

private extension MediaItem {
    /// The add-on answer keeps the requesting item's ID and progress, so the
    /// library, Continue Watching and navigation keep working.
    func replacingIdentity(with original: MediaItem) -> MediaItem {
        MediaItem(
            id: original.id,
            title: title,
            year: year,
            kind: original.kind,
            overview: overview,
            genres: genres,
            symbol: symbol,
            artworkColors: original.artworkColors,
            artworkURL: artworkURL,
            backdropURL: backdropURL,
            logoURL: logoURL,
            metadataProvider: original.metadataProvider,
            metadataProviderID: metadataProviderID,
            metadataRecordID: original.metadataRecordID,
            externalIDs: externalIDs,
            details: details,
            progress: original.progress,
            positionSeconds: original.positionSeconds,
            durationSeconds: original.durationSeconds,
            resumeEpisodeID: original.resumeEpisodeID,
            resumeSeasonNumber: original.resumeSeasonNumber,
            resumeEpisodeNumber: original.resumeEpisodeNumber,
            resumeEpisodeTitle: original.resumeEpisodeTitle,
            resumeEpisodeStillURL: original.resumeEpisodeStillURL
        )
    }
}
