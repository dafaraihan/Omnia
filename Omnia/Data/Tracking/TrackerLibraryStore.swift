//
//  TrackerLibraryStore.swift
//  Omnia
//

import Foundation
import Observation

/// Where Continue Watching and the watchlist come from: Omnia's own
/// progress (in the Omnia account or on this device), or a connected
/// tracker, as Nuvio's "All Local / All Trakt / All PMDB" switch does
/// (Dafa, 2026-10-27). The "+ AniList Anime" choices take anime from the
/// AniList Watching list and everything else from Trakt or Omnia, as
/// Nuvio's do.
nonisolated enum TrackerLibrarySource: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case local
    case trakt
    case simkl
    case pmdb
    case anilist
    case traktAniList
    case localAniList

    var id: String { rawValue }

    /// Where everything (or, with AniList anime added, everything but
    /// anime) comes from; nil for Omnia's own.
    var tracker: TrackerKind? {
        switch self {
        case .local, .localAniList: nil
        case .trakt, .traktAniList: .trakt
        case .simkl: .simkl
        case .pmdb: .pmdb
        case .anilist: .anilist
        }
    }

    var addsAniListAnime: Bool { self == .traktAniList || self == .localAniList }

    /// Every tracker this source reads.
    var trackers: [TrackerKind] {
        (tracker.map { [$0] } ?? []) + (addsAniListAnime ? [.anilist] : [])
    }

    init(_ tracker: TrackerKind) {
        switch tracker {
        case .trakt: self = .trakt
        case .simkl: self = .simkl
        case .pmdb: self = .pmdb
        case .anilist: self = .anilist
        }
    }

    var title: String {
        switch self {
        case .traktAniList: "Trakt + AniList Anime"
        case .localAniList: "Local + AniList Anime"
        default: tracker?.shortTitle ?? "Local"
        }
    }

    /// Nuvio's menu wording: "All Local", "All Trakt", "Trakt + AniList Anime".
    var menuTitle: String { addsAniListAnime ? title : "All \(title)" }
}

/// Each connected tracker's in-progress titles and watchlist, read from the
/// tracker and kept on disk so Home shows them at once on the next launch.
/// What plays is written back by scrobbling (`TrackerAccountStore`).
@Observable
@MainActor
final class TrackerLibraryStore {
    static let shared = TrackerLibraryStore()

    enum SyncState: Equatable {
        case idle
        case syncing
        case synced(Date)
        case failed(String)
    }

    private(set) var entries: [TrackerKind: [TrackerLibraryList: [TrackerLibraryEntry]]] = [:]
    /// Entries drawn as titles, with artwork and names from the add-ons.
    private(set) var items: [TrackerKind: [TrackerLibraryList: [MediaItem]]] = [:]
    private(set) var syncStates: [TrackerKind: SyncState] = [:]

    var continueWatchingSource: TrackerLibrarySource {
        didSet { save(continueWatchingSource, key: Self.continueWatchingKey) }
    }

    var watchlistSource: TrackerLibrarySource {
        didSet { save(watchlistSource, key: Self.watchlistKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var syncTasks: [TrackerKind: Task<Void, Never>] = [:]
    @ObservationIgnored private var lastSync: [TrackerKind: Date] = [:]
    @ObservationIgnored private var addonsKey = ""
    private static let continueWatchingKey = "tracker-continue-watching-source"
    private static let watchlistKey = "tracker-watchlist-source"
    /// A tracker is read again when Home or Library appears after this long.
    private static let refreshInterval: TimeInterval = 5 * 60

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        continueWatchingSource = defaults.string(forKey: Self.continueWatchingKey).flatMap(TrackerLibrarySource.init) ?? .local
        watchlistSource = defaults.string(forKey: Self.watchlistKey).flatMap(TrackerLibrarySource.init) ?? .local
        for kind in TrackerKind.allCases {
            entries[kind] = Self.loadCache(kind)
        }
    }

    // MARK: Reading

    /// The source in use: a tracker that has since been disconnected falls
    /// back to Omnia's own.
    func effectiveSource(_ source: TrackerLibrarySource) -> TrackerLibrarySource {
        source.trackers.allSatisfy(TrackerAccountStore.shared.isConnected) ? source : .local
    }

    /// Local, each connected tracker, and the AniList anime blends, for
    /// Continue Watching's pickers.
    var availableSources: [TrackerLibrarySource] {
        TrackerLibrarySource.allCases.filter { $0 == .local || effectiveSource($0) == $0 }
    }

    /// The Library's choices: the blends are for Continue Watching only.
    var availableWatchlistSources: [TrackerLibrarySource] {
        availableSources.filter { !$0.addsAniListAnime }
    }

    /// Continue Watching from `source`: a tracker's paused titles, or
    /// Omnia's own (`local`), with AniList's Watching list in place of
    /// their anime when the source adds it.
    func progressItems(_ source: TrackerLibrarySource, local: [MediaItem]) -> [MediaItem] {
        let base = source.tracker.map { items(.progress, from: $0) } ?? local
        guard source.addsAniListAnime else { return base }
        let anime = items(.progress, from: .anilist)
        let rest = base.filter { item in
            !Self.isAnime(item) && !anime.contains { $0.isSameTitle(as: item) }
        }
        return anime + rest
    }

    private static func isAnime(_ item: MediaItem) -> Bool {
        let animeKeys = ["anilist", "anilist_id", "mal", "mal_id", "myanimelist", "kitsu", "kitsu_id"]
        if animeKeys.contains(where: { item.externalIDs[$0] != nil }) { return true }
        let prefix = item.id.split(separator: ":").first.map { String($0).lowercased() } ?? ""
        if ["anilist", "mal", "kitsu", "anidb"].contains(prefix) { return true }
        return item.genres.contains { $0.caseInsensitiveCompare("Anime") == .orderedSame }
    }

    func items(_ list: TrackerLibraryList, from kind: TrackerKind) -> [MediaItem] {
        if let drawn = items[kind]?[list] { return drawn }
        return (entries[kind]?[list] ?? []).map(\.mediaItem)
    }

    func state(_ kind: TrackerKind) -> SyncState { syncStates[kind] ?? .idle }

    // MARK: Syncing

    /// Reads the tracker again unless it was read in the last few minutes.
    func syncIfNeeded(_ kind: TrackerKind, addons: [InstalledAddon]) {
        let addonsChanged = Self.key(for: addons) != addonsKey
        if !addonsChanged, let last = lastSync[kind], Date.now.timeIntervalSince(last) < Self.refreshInterval { return }
        if !addonsChanged, items[kind] != nil, syncTasks[kind] != nil { return }
        sync(kind, addons: addons)
    }

    /// Continue Watching's "Sync Now".
    func sync(_ kind: TrackerKind, addons: [InstalledAddon]) {
        guard let credentials = TrackerAccountStore.shared.credentials[kind], credentials.isConnected else { return }
        addonsKey = Self.key(for: addons)
        syncTasks[kind]?.cancel()
        syncStates[kind] = .syncing
        lastSync[kind] = .now
        syncTasks[kind] = Task { [weak self] in
            do {
                async let progress = TrackerLibraryClient.fetch(.progress, from: kind, credentials: credentials)
                async let watchlist = TrackerLibraryClient.fetch(.watchlist, from: kind, credentials: credentials)
                let fetched: [TrackerLibraryList: [TrackerLibraryEntry]] = [.progress: try await progress, .watchlist: try await watchlist]
                guard !Task.isCancelled, let self else { return }
                self.entries[kind] = fetched
                Self.saveCache(fetched, for: kind)
                await self.draw(kind, addons: addons)
                guard !Task.isCancelled else { return }
                self.syncStates[kind] = .synced(.now)
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.lastSync[kind] = nil
                self.syncStates[kind] = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                // The cached lists still show, drawn with what's known.
                if self.items[kind] == nil { await self.draw(kind, addons: addons) }
            }
            self?.syncTasks[kind] = nil
        }
    }

    /// Continue Watching's "Clear Cache": forgets what was read and reads
    /// the tracker afresh.
    func clearCache(_ kind: TrackerKind, addons: [InstalledAddon]) {
        syncTasks[kind]?.cancel()
        syncTasks[kind] = nil
        entries[kind] = [:]
        items[kind] = nil
        lastSync[kind] = nil
        syncStates[kind] = .idle
        try? FileManager.default.removeItem(at: Self.cacheURL(kind))
        sync(kind, addons: addons)
    }

    /// Forgets a disconnected tracker's lists.
    func forget(_ kind: TrackerKind) {
        syncTasks[kind]?.cancel()
        syncTasks[kind] = nil
        entries[kind] = nil
        items[kind] = nil
        lastSync[kind] = nil
        syncStates[kind] = nil
        try? FileManager.default.removeItem(at: Self.cacheURL(kind))
    }

    /// Continue Watching's Remove on a tracker's title: hides it here and
    /// clears the tracker's paused playback.
    func removeFromProgress(_ item: MediaItem, kind: TrackerKind) {
        guard let entry = entries[kind]?[.progress]?.first(where: { $0.mediaID == item.id }) else { return }
        entries[kind]?[.progress]?.removeAll { $0 == entry }
        items[kind]?[.progress]?.removeAll { $0.id == item.id }
        if let current = entries[kind] { Self.saveCache(current, for: kind) }
        guard let credentials = TrackerAccountStore.shared.credentials[kind] else { return }
        Task { try? await TrackerLibraryClient.removePlayback(entry, from: kind, credentials: credentials) }
    }

    /// Fills each entry with the add-ons' name and artwork.
    private func draw(_ kind: TrackerKind, addons: [InstalledAddon]) async {
        var drawn: [TrackerLibraryList: [MediaItem]] = [:]
        for (list, listEntries) in entries[kind] ?? [:] {
            let plain = listEntries.map(\.mediaItem)
            drawn[list] = await withTaskGroup(of: (Int, MediaItem).self) { group in
                for (index, item) in plain.enumerated() {
                    group.addTask {
                        (index, await AddonMetadataResolver.resolve(item, addons: addons) ?? item)
                    }
                }
                var resolved = plain
                for await (index, item) in group { resolved[index] = item }
                return resolved
            }
        }
        items[kind] = drawn
    }

    // MARK: Storage

    private func save(_ source: TrackerLibrarySource, key: String) {
        defaults.set(source.rawValue, forKey: key)
        // Choosing a tracker as the store turns its scrobbling on, so what
        // plays is written there too.
        for tracker in source.trackers { TrackerAccountStore.shared.setScrobbles(true, for: tracker) }
    }

    private static func key(for addons: [InstalledAddon]) -> String {
        addons.filter(\.isEnabled).map(\.manifestURL.absoluteString).joined(separator: "|")
    }

    private static func cacheURL(_ kind: TrackerKind) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appending(path: "Trackers", directoryHint: .isDirectory).appending(path: "\(kind.rawValue).json")
    }

    private static func loadCache(_ kind: TrackerKind) -> [TrackerLibraryList: [TrackerLibraryEntry]] {
        guard let data = try? Data(contentsOf: cacheURL(kind)),
              let cache = try? JSONDecoder.trackerCache.decode(TrackerLibraryCache.self, from: data)
        else { return [:] }
        return [.progress: cache.progress, .watchlist: cache.watchlist]
    }

    private static func saveCache(_ lists: [TrackerLibraryList: [TrackerLibraryEntry]], for kind: TrackerKind) {
        let cache = TrackerLibraryCache(progress: lists[.progress] ?? [], watchlist: lists[.watchlist] ?? [])
        let url = cacheURL(kind)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder.trackerCache.encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

private nonisolated struct TrackerLibraryCache: Codable {
    var progress: [TrackerLibraryEntry]
    var watchlist: [TrackerLibraryEntry]
}

private extension JSONEncoder {
    static var trackerCache: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var trackerCache: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

nonisolated extension TrackerLibraryEntry {
    /// The title's ID in Omnia: its IMDb ID, as Cinemeta and most stream
    /// add-ons use, or a prefixed TMDB or TVDB ID.
    var mediaID: String {
        imdb ?? tmdb.map { "tmdb:\($0)" } ?? tvdb.map { "tvdb:\($0)" }
            ?? anilist.map { "anilist:\($0)" } ?? mal.map { "mal:\($0)" } ?? title
    }

    /// The bare title before the add-ons fill it in.
    var mediaItem: MediaItem {
        var externalIDs: [String: String] = [:]
        if let imdb { externalIDs["imdb"] = imdb }
        if let tmdb { externalIDs["tmdb"] = String(tmdb) }
        if let tvdb { externalIDs["tvdb"] = String(tvdb) }
        if let anilist { externalIDs["anilist"] = String(anilist) }
        if let mal { externalIDs["mal"] = String(mal) }
        let isSeries = kind == .series
        let position = progress.flatMap { progress in runtimeSeconds.map { progress * $0 } }
        return MediaItem(
            id: mediaID,
            title: title.isEmpty ? "Untitled" : title,
            year: year.map(String.init) ?? "—",
            kind: isSeries ? .series : .movie,
            overview: "",
            genres: [],
            symbol: isSeries ? "tv.fill" : "film.fill",
            artworkColors: MediaItem.placeholderArtworkColors,
            artworkURL: posterURL,
            backdropURL: backdropURL,
            externalIDs: externalIDs,
            progress: progress,
            positionSeconds: position,
            durationSeconds: position == nil ? nil : runtimeSeconds,
            resumeSeasonNumber: isSeries ? season : nil,
            resumeEpisodeNumber: isSeries ? episode : nil
        )
    }
}
