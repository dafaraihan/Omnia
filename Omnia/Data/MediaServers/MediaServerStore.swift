//
//  MediaServerStore.swift
//  Omnia
//

import Foundation
import Observation

/// One Home row from a media server: a selected library, newest first, or
/// the server's Continue Watching (Nuvio's resume row).
nonisolated struct MediaServerHomeRow: Identifiable, Hashable, Sendable {
    let key: String
    let connectionID: String
    /// Nil for the Continue Watching row.
    let library: MediaServerLibrary?
    let title: String
    let serverName: String

    var id: String { key }

    static func key(connectionID: String, libraryID: String?) -> String {
        "server:\(connectionID):\(libraryID ?? "resume")"
    }
}

/// Nuvio's media servers (Settings › Content & Discovery › Media Servers):
/// signed-in Jellyfin and Emby servers, their selected libraries as Home
/// rows, their titles in search, and their files as stream sources.
/// Connections are saved in UserDefaults and tokens in the Keychain.
@MainActor
@Observable
final class MediaServerStore {
    static let shared = MediaServerStore()

    nonisolated static let storageKey = "media-servers-v1"
    private static let rowLimit = 20

    enum RowState: Equatable {
        case loading
        case loaded
        case failed
    }

    private(set) var connections: [MediaServerConnection] = []
    /// The last problem reaching each server, by connection id.
    private(set) var failures: [String: MediaServerFailure] = [:]
    private(set) var rowItems: [String: [MediaItem]] = [:]
    private(set) var rowStates: [String: RowState] = [:]
    /// Titles in progress on servers that import watch progress.
    private(set) var importedProgress: [MediaItem] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([MediaServerConnection].self, from: data) {
            connections = saved
        }
    }

    var enabledConnections: [MediaServerConnection] {
        connections.filter { $0.isEnabled && token(for: $0) != nil }
    }

    func connection(id: String) -> MediaServerConnection? {
        connections.first { $0.id == id }
    }

    // MARK: Home rows

    /// Every server row that can be on Home, in server order: Continue
    /// Watching first, then each selected library.
    var homeRows: [MediaServerHomeRow] {
        enabledConnections.flatMap { connection -> [MediaServerHomeRow] in
            let libraries = connection.selectedLibraries
            guard !libraries.isEmpty else { return [] }
            let resume = MediaServerHomeRow(
                key: MediaServerHomeRow.key(connectionID: connection.id, libraryID: nil),
                connectionID: connection.id,
                library: nil,
                title: "\(connection.name) · Continue Watching",
                serverName: connection.name
            )
            return [resume] + libraries.map { library in
                MediaServerHomeRow(
                    key: MediaServerHomeRow.key(connectionID: connection.id, libraryID: library.id),
                    connectionID: connection.id,
                    library: library,
                    title: "\(connection.name) · \(library.name)",
                    serverName: connection.name
                )
            }
        }
    }

    /// Changes whenever the rows to load change, for `.task(id:)`.
    var rowsSignature: String {
        enabledConnections.map { connection in
            "\(connection.id)|\(connection.usesAddonMetadata)|\(connection.importsWatchProgress)|"
                + connection.selectedLibraries.map(\.id).joined(separator: ",")
        }.joined(separator: ";")
    }

    func items(for row: MediaServerHomeRow) -> [MediaItem] {
        rowItems[row.key] ?? []
    }

    func state(for row: MediaServerHomeRow) -> RowState? {
        rowStates[row.key]
    }

    func loadRows() async {
        let rows = homeRows
        let keys = Set(rows.map(\.key))
        rowItems = rowItems.filter { keys.contains($0.key) }
        rowStates = rowStates.filter { keys.contains($0.key) }
        for row in rows where rowItems[row.key] == nil { rowStates[row.key] = .loading }
        await withTaskGroup(of: Void.self) { group in
            for row in rows {
                group.addTask { await self.load(row) }
            }
        }
        importedProgress = rows
            .filter { $0.library == nil && connection(id: $0.connectionID)?.importsWatchProgress == true }
            .flatMap { rowItems[$0.key] ?? [] }
    }

    func retry(_ row: MediaServerHomeRow) {
        rowStates[row.key] = .loading
        Task { await load(row) }
    }

    private func load(_ row: MediaServerHomeRow) async {
        guard let connection = connection(id: row.connectionID), let client = client(for: connection) else { return }
        let mapper = MediaServerMapper(connection: connection, client: client)
        do {
            let items: [MediaItem]
            if let library = row.library {
                let page = try await client.libraryPage(userID: connection.userID, library: library, start: 0, limit: Self.rowLimit)
                items = page.items.compactMap(mapper.item)
            } else {
                items = try await resumeItems(connection: connection, client: client, mapper: mapper)
            }
            rowItems[row.key] = items
            rowStates[row.key] = .loaded
            failures[connection.id] = nil
        } catch is CancellationError {
            rowStates[row.key] = nil
        } catch {
            rowStates[row.key] = .failed
            record(error, for: connection.id)
        }
    }

    /// Resume entries are episodes for shows; each becomes its show, with
    /// the episode to resume, so it opens like any Continue Watching title.
    private func resumeItems(
        connection: MediaServerConnection,
        client: MediaBrowserClient,
        mapper: MediaServerMapper
    ) async throws -> [MediaItem] {
        let entries = try await client.resumeItems(userID: connection.userID, limit: Self.rowLimit)
        var series: [String: MediaBrowserClient.BaseItem] = [:]
        for seriesID in Set(entries.compactMap(\.seriesID)) {
            series[seriesID] = try? await client.item(userID: connection.userID, id: seriesID, fields: MediaBrowserClient.listFields)
        }
        let selected = connection.selectedLibraries
        var seen = Set<String>()
        return entries.compactMap { entry -> MediaItem? in
            guard let item = mapper.resumeItem(entry, series: entry.seriesID.flatMap { series[$0] }) else { return nil }
            guard selected.contains(where: { $0.kind.holds(item.kind) }), seen.insert(item.id).inserted else { return nil }
            return item
        }
    }

    /// One page of a row for its See All page.
    func page(for row: MediaServerHomeRow, start: Int, limit: Int = 50) async throws -> (items: [MediaItem], hasMore: Bool) {
        guard let connection = connection(id: row.connectionID), let client = client(for: connection) else {
            throw MediaServerFailure.authenticationRequired
        }
        let mapper = MediaServerMapper(connection: connection, client: client)
        guard let library = row.library else {
            return (start == 0 ? try await resumeItems(connection: connection, client: client, mapper: mapper) : [], false)
        }
        let page = try await client.libraryPage(userID: connection.userID, library: library, start: start, limit: limit)
        let loaded = start + page.items.count
        let hasMore = !page.items.isEmpty && (page.totalRecordCount.map { loaded < $0 } ?? (page.items.count >= limit))
        return (page.items.compactMap(mapper.item), hasMore)
    }

    // MARK: Search

    /// Movies and series matching `query` on every enabled server.
    func search(_ query: String) async -> [MediaItem] {
        let targets = enabledConnections.compactMap { connection -> (MediaServerConnection, MediaBrowserClient)? in
            guard !connection.selectedLibraries.filter({ $0.kind != .collections }).isEmpty,
                  let client = client(for: connection) else { return nil }
            return (connection, client)
        }
        return await withTaskGroup(of: [MediaItem].self) { group in
            for (connection, client) in targets {
                group.addTask {
                    let types = Self.searchTypes(for: connection)
                    guard let matches = try? await client.search(
                        userID: connection.userID,
                        query: query,
                        itemTypes: types,
                        parentID: nil,
                        limit: 30
                    ) else { return [] }
                    let mapper = MediaServerMapper(connection: connection, client: client)
                    let libraries = connection.selectedLibraries
                    return matches.compactMap(mapper.item).filter { item in
                        libraries.contains { $0.kind.holds(item.kind) }
                    }
                }
            }
            var all: [MediaItem] = []
            for await items in group { all += items }
            return all
        }
    }

    nonisolated private static func searchTypes(for connection: MediaServerConnection) -> String {
        let kinds = connection.selectedLibraries.map(\.kind)
        let movies = kinds.contains { $0 == .movies || $0 == .mixed }
        let series = kinds.contains { $0 == .series || $0 == .mixed }
        return [movies ? "Movie" : nil, series ? "Series" : nil].compactMap { $0 }.joined(separator: ",")
    }

    // MARK: Details

    /// The server's own details for one of its titles, when the server
    /// doesn't use add-on metadata. Nil for other titles.
    func serverDetails(for item: MediaItem) async -> MediaItem? {
        guard let ref = MediaServerIdentifier.parse(item.id),
              let connection = connection(id: ref.connectionID),
              !connection.usesAddonMetadata,
              let client = client(for: connection)
        else { return nil }
        do {
            let base = try await client.item(
                userID: connection.userID,
                id: ref.itemID,
                fields: "Overview,Genres,ProviderIds,People,Studios,PremiereDate,EndDate,OfficialRating"
            )
            let episodes = base.mediaKind == .series
                ? (try? await client.episodes(userID: connection.userID, seriesID: ref.itemID, season: nil)) ?? []
                : []
            failures[connection.id] = nil
            return MediaServerMapper(connection: connection, client: client).detailed(base, episodes: episodes, keeping: item)
        } catch {
            record(error, for: connection.id)
            return nil
        }
    }

    // MARK: Streams

    /// The servers to ask for a title's streams, captured so the lookup can
    /// run off the main actor.
    func streamPlan() -> MediaServerStreamPlan {
        MediaServerStreamPlan(entries: enabledConnections.compactMap { connection in
            guard !connection.selectedLibraries.isEmpty, let token = token(for: connection) else { return nil }
            return .init(connection: connection, token: token)
        })
    }

    func streamPlan(forSourceID sourceID: String) -> MediaServerStreamPlan {
        let plan = streamPlan()
        return MediaServerStreamPlan(entries: plan.entries.filter {
            MediaServerIdentifier.sourceID(connectionID: $0.connection.id) == sourceID
        })
    }

    // MARK: Settings

    /// Signs in and saves the server. Signing in again to a server already
    /// added updates it and keeps its choices.
    @discardableResult
    func signIn(kind: MediaServerKind, address: String, username: String, password: String) async throws -> MediaServerConnection {
        let result = try await MediaBrowserClient.signIn(kind: kind, address: address, username: username, password: password)
        var connection: MediaServerConnection
        if let existing = connections.first(where: {
            $0.kind == kind && $0.serverID == result.serverID && $0.userID == result.userID
        }) {
            connection = existing
            connection.address = result.address
            connection.name = result.serverName
            connection.userName = result.userName
        } else {
            connection = MediaServerConnection(
                id: UUID().uuidString,
                kind: kind,
                name: result.serverName,
                address: result.address,
                serverID: result.serverID,
                userID: result.userID,
                userName: result.userName
            )
        }
        try KeychainStore.save(result.token, account: connection.keychainAccount)
        let client = MediaBrowserClient(connection: connection, token: result.token)
        if let libraries = try? await client.libraries(userID: connection.userID) {
            connection.libraries = Self.merged(libraries, keeping: connection.libraries)
        }
        failures[connection.id] = nil
        upsert(connection)
        return connection
    }

    func refreshLibraries(_ id: String) async {
        guard let connection = connection(id: id), let client = client(for: connection) else { return }
        do {
            let libraries = try await client.libraries(userID: connection.userID)
            update(id) { $0.libraries = Self.merged(libraries, keeping: $0.libraries) }
            failures[id] = nil
        } catch {
            record(error, for: id)
        }
    }

    func setLibrary(_ libraryID: String, selected: Bool, in id: String) {
        update(id) { connection in
            guard let index = connection.libraries.firstIndex(where: { $0.id == libraryID }) else { return }
            connection.libraries[index].isSelected = selected
        }
    }

    func setEnabled(_ enabled: Bool, for id: String) {
        update(id) { $0.isEnabled = enabled }
    }

    func setUsesAddonMetadata(_ enabled: Bool, for id: String) {
        update(id) { $0.usesAddonMetadata = enabled }
    }

    func setImportsWatchProgress(_ enabled: Bool, for id: String) {
        update(id) { $0.importsWatchProgress = enabled }
        if !enabled { importedProgress.removeAll { MediaServerIdentifier.parse($0.id)?.connectionID == id } }
    }

    /// Signs out on the server and forgets it on this device.
    func remove(_ id: String) async {
        guard let connection = connection(id: id) else { return }
        if let client = client(for: connection) { await client.signOut() }
        try? KeychainStore.delete(account: connection.keychainAccount)
        connections.removeAll { $0.id == id }
        failures[id] = nil
        importedProgress.removeAll { MediaServerIdentifier.parse($0.id)?.connectionID == id }
        save()
    }

    func hasToken(_ connection: MediaServerConnection) -> Bool {
        token(for: connection) != nil
    }

    // MARK: Helpers

    private func token(for connection: MediaServerConnection) -> String? {
        guard let token = try? KeychainStore.value(account: connection.keychainAccount), !token.isEmpty else { return nil }
        return token
    }

    private func client(for connection: MediaServerConnection) -> MediaBrowserClient? {
        token(for: connection).map { MediaBrowserClient(connection: connection, token: $0) }
    }

    private func record(_ error: Error, for id: String) {
        guard !(error is CancellationError) else { return }
        failures[id] = error as? MediaServerFailure ?? .failed
    }

    /// New libraries start selected, as in Nuvio; known ones keep their choice.
    private static func merged(_ fresh: [MediaServerLibrary], keeping old: [MediaServerLibrary]) -> [MediaServerLibrary] {
        let selection = Dictionary(old.map { ($0.id, $0.isSelected) }, uniquingKeysWith: { first, _ in first })
        return fresh.map { library in
            var library = library
            library.isSelected = selection[library.id] ?? true
            return library
        }
    }

    private func upsert(_ connection: MediaServerConnection) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
        } else {
            connections.append(connection)
        }
        save()
    }

    private func update(_ id: String, _ transform: (inout MediaServerConnection) -> Void) {
        guard let index = connections.firstIndex(where: { $0.id == id }) else { return }
        transform(&connections[index])
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(connections) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

// MARK: Mapping

/// Turns server items into Omnia titles. Artwork comes from the server; the
/// IMDb, TMDB and TVDB ids are kept so streams, add-ons and TMDB can match.
nonisolated struct MediaServerMapper: Sendable {
    let connection: MediaServerConnection
    let client: MediaBrowserClient

    func item(_ base: MediaBrowserClient.BaseItem) -> MediaItem? {
        guard let kind = base.mediaKind, kind != .episode, let title = base.name?.nonBlankValue else { return nil }
        let position = base.userData?.playbackPositionTicks.map { Double($0) / 10_000_000 }
        let duration = base.runtimeSeconds
        let progress: Double? = if let position, let duration, duration > 0, position > 0 {
            min(max(position / duration, 0), 1)
        } else {
            nil
        }
        return MediaItem(
            id: MediaServerIdentifier.itemID(connectionID: connection.id, itemID: base.id),
            title: title,
            year: base.productionYear.map(String.init) ?? "—",
            kind: kind,
            overview: base.overview?.nonBlankValue ?? "No overview is available yet.",
            genres: base.genres ?? [],
            symbol: kind == .movie ? "film.fill" : "tv.fill",
            artworkColors: MediaItem.placeholderArtworkColors,
            artworkURL: client.imageURL(itemID: base.id, type: "Primary", tag: base.imageTags?["Primary"], maxWidth: 500),
            backdropURL: client.imageURL(itemID: base.id, type: "Backdrop", tag: base.backdropImageTags?.first, maxWidth: 1_600),
            logoURL: client.imageURL(itemID: base.id, type: "Logo", tag: base.imageTags?["Logo"], maxWidth: 800),
            externalIDs: base.externalIDs,
            progress: progress,
            positionSeconds: progress == nil ? nil : position,
            durationSeconds: progress == nil ? nil : duration
        )
    }

    /// A Continue Watching title: the movie, or the show with the episode
    /// to resume.
    func resumeItem(_ entry: MediaBrowserClient.BaseItem, series: MediaBrowserClient.BaseItem?) -> MediaItem? {
        guard entry.mediaKind == .episode else { return item(entry) }
        guard let series, var show = item(series) else { return nil }
        let position = entry.userData?.playbackPositionTicks.map { Double($0) / 10_000_000 } ?? 0
        let duration = entry.runtimeSeconds ?? 0
        guard duration > 0 else { return nil }
        show.progress = min(max(position / duration, 0), 1)
        show.positionSeconds = position
        show.durationSeconds = duration
        show.resumeEpisodeID = entry.id
        show.resumeSeasonNumber = entry.parentIndexNumber
        show.resumeEpisodeNumber = entry.indexNumber
        show.resumeEpisodeTitle = entry.name
        show.resumeEpisodeStillURL = client.imageURL(itemID: entry.id, type: "Primary", tag: entry.imageTags?["Primary"], maxWidth: 800)
        return show
    }

    /// The title with the server's cast, studios and seasons.
    func detailed(
        _ base: MediaBrowserClient.BaseItem,
        episodes: [MediaBrowserClient.BaseItem],
        keeping original: MediaItem
    ) -> MediaItem {
        let mapped = item(base) ?? original
        let cast = (base.people ?? []).filter { $0.type?.lowercased() == "actor" }.prefix(30).compactMap { person -> MediaCredit? in
            guard let name = person.name?.nonBlankValue else { return nil }
            return MediaCredit(
                id: person.id ?? name,
                name: name,
                role: "Actor",
                character: person.role?.nonBlankValue,
                profileURL: person.id.flatMap { client.imageURL(itemID: $0, type: "Primary", tag: person.primaryImageTag, maxWidth: 300) }
            )
        }
        let crew = (base.people ?? []).filter { ["director", "writer", "producer"].contains($0.type?.lowercased() ?? "") }.compactMap { person -> MediaCredit? in
            guard let name = person.name?.nonBlankValue else { return nil }
            return MediaCredit(id: person.id ?? name, name: name, role: person.type, character: nil, profileURL: nil)
        }
        let studios = (base.studios ?? []).compactMap { studio -> MediaStudio? in
            guard let name = studio.name?.nonBlankValue else { return nil }
            return MediaStudio(id: "server:\(studio.id ?? name)", name: name)
        }
        let seasons = Dictionary(grouping: episodes.filter { !$0.isMissing && $0.indexNumber != nil }) { $0.parentIndexNumber ?? 1 }
            .sorted { $0.key < $1.key }
            .map { number, items in
                MediaSeason(
                    id: "\(base.id):season:\(number)",
                    seasonNumber: number,
                    title: number == 0 ? "Specials" : "Season \(number)",
                    overview: nil,
                    posterURL: nil,
                    episodes: items.sorted { ($0.indexNumber ?? 0) < ($1.indexNumber ?? 0) }.map { episode in
                        MediaEpisode(
                            id: episode.id,
                            seasonNumber: number,
                            episodeNumber: episode.indexNumber ?? 0,
                            title: episode.name ?? "Episode \(episode.indexNumber ?? 0)",
                            overview: episode.overview ?? "",
                            runtimeMinutes: episode.runtimeSeconds.map { Int($0 / 60) },
                            stillURL: client.imageURL(itemID: episode.id, type: "Primary", tag: episode.imageTags?["Primary"], maxWidth: 800),
                            airDate: episode.premiereDate.map { String($0.prefix(10)) }
                        )
                    }
                )
            }
        let details = MediaTitleDetails(
            ageRating: base.officialRating,
            runtimeMinutes: base.runtimeSeconds.map { Int($0 / 60) },
            status: nil,
            budget: nil,
            revenue: nil,
            studios: studios,
            cast: Array(cast),
            crew: crew,
            studioTitles: [],
            collection: nil,
            recommendations: [],
            seasons: seasons,
            trailers: [],
            bonusContent: [],
            releaseDate: base.premiereDate.map { String($0.prefix(10)) }
        )
        var result = MediaItem(
            id: original.id,
            title: mapped.title,
            year: mapped.year,
            kind: mapped.kind,
            overview: mapped.overview,
            genres: mapped.genres,
            symbol: mapped.symbol,
            artworkColors: original.artworkColors,
            artworkURL: mapped.artworkURL ?? original.artworkURL,
            backdropURL: mapped.backdropURL ?? original.backdropURL,
            logoURL: mapped.logoURL ?? original.logoURL,
            externalIDs: mapped.externalIDs,
            details: details,
            progress: original.progress,
            positionSeconds: original.positionSeconds,
            durationSeconds: original.durationSeconds
        )
        result.resumeEpisodeID = original.resumeEpisodeID
        result.resumeSeasonNumber = original.resumeSeasonNumber
        result.resumeEpisodeNumber = original.resumeEpisodeNumber
        result.resumeEpisodeTitle = original.resumeEpisodeTitle
        result.resumeEpisodeStillURL = original.resumeEpisodeStillURL
        return result
    }
}

// MARK: Streams

/// The servers to search for a title's files.
nonisolated struct MediaServerStreamPlan: Sendable {
    struct Entry: Sendable {
        let connection: MediaServerConnection
        let token: String
    }

    let entries: [Entry]

    static let empty = MediaServerStreamPlan(entries: [])
}

/// Finds a title on each server and lists its files as direct-play
/// sources, one source per server, after add-ons and plugins.
nonisolated enum MediaServerStreamResolver {
    static func resolve(
        _ entry: MediaServerStreamPlan.Entry,
        item: MediaItem,
        episode: MediaEpisode?
    ) async -> AddonSourceResolution {
        let connection = entry.connection
        let sourceID = MediaServerIdentifier.sourceID(connectionID: connection.id)
        let client = MediaBrowserClient(connection: connection, token: entry.token)
        do {
            guard let titleID = try await serverItemID(for: item, connection: connection, client: client) else {
                return AddonSourceResolution(addonID: sourceID, addonName: connection.name, candidates: [], state: .empty)
            }
            let target: MediaBrowserClient.BaseItem
            if item.kind == .series {
                guard let episode else {
                    return AddonSourceResolution(addonID: sourceID, addonName: connection.name, candidates: [], state: .empty)
                }
                let episodes = try await client.episodes(userID: connection.userID, seriesID: titleID, season: episode.seasonNumber)
                let matches = episodes.filter { candidate in
                    !candidate.isMissing
                        && (candidate.parentIndexNumber ?? episode.seasonNumber) == episode.seasonNumber
                        && candidate.indexNumber == episode.episodeNumber
                        || candidate.id == episode.id
                }
                guard let match = matches.first else {
                    return AddonSourceResolution(addonID: sourceID, addonName: connection.name, candidates: [], state: .empty)
                }
                target = match.mediaSources?.isEmpty == false
                    ? match
                    : try await client.item(userID: connection.userID, id: match.id)
            } else {
                target = try await client.item(userID: connection.userID, id: titleID)
            }
            let candidates = (target.mediaSources ?? []).enumerated().compactMap { position, source in
                AddonStreamCandidate(server: connection, client: client, item: target, source: source, position: position)
            }
            return AddonSourceResolution(
                addonID: sourceID,
                addonName: connection.name,
                candidates: candidates,
                state: candidates.isEmpty ? .empty : .loaded
            )
        } catch is CancellationError {
            return AddonSourceResolution(addonID: sourceID, addonName: connection.name, candidates: [], state: .failed, failure: .cancelled)
        } catch {
            let message = (error as? MediaServerFailure)?.errorDescription ?? "Could not reach the server."
            return AddonSourceResolution(addonID: sourceID, addonName: connection.name, candidates: [], state: .failed, failure: .plugin(message))
        }
    }

    /// The server's own item for a title: directly for its own titles, or
    /// by IMDb, TMDB or TVDB id through the library index.
    private static func serverItemID(
        for item: MediaItem,
        connection: MediaServerConnection,
        client: MediaBrowserClient
    ) async throws -> String? {
        if let ref = MediaServerIdentifier.parse(item.id), ref.connectionID == connection.id {
            return ref.itemID
        }
        let keys = matchKeys(for: item)
        guard !keys.isEmpty else { return nil }
        let index = try await MediaServerIndex.shared.index(for: connection, client: client)
        return keys.lazy.compactMap { index[$0] }.first
    }

    private static func matchKeys(for item: MediaItem) -> [String] {
        let kind = item.kind == .movie ? "movie" : "series"
        var keys: [String] = []
        for (source, names) in [("imdb", ["imdb", "imdb_id"]), ("tmdb", ["tmdb", "tmdb_id"]), ("tvdb", ["tvdb", "tvdb_id"])] {
            for name in names {
                if let value = item.externalIDs[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                    keys.append("\(kind):\(source):\(value.lowercased())")
                }
            }
        }
        if item.id.hasPrefix("tt") { keys.append("\(kind):imdb:\(item.id.split(separator: ":")[0].lowercased())") }
        if item.metadataProvider == .tmdb, let id = item.metadataProviderID { keys.append("\(kind):tmdb:\(id)") }
        if item.metadataProvider == .tvdb, let id = item.metadataProviderID { keys.append("\(kind):tvdb:\(id)") }
        return keys
    }
}

/// Each server's provider ids, built from its selected libraries and kept
/// for 30 minutes (Nuvio's external id index).
actor MediaServerIndex {
    static let shared = MediaServerIndex()

    private struct Built {
        let signature: String
        let builtAt: Date
        let map: [String: String]
    }

    private var built: [String: Built] = [:]
    private var building: [String: Task<[String: String], Error>] = [:]

    func index(for connection: MediaServerConnection, client: MediaBrowserClient) async throws -> [String: String] {
        let libraries = connection.selectedLibraries.filter { $0.kind != .collections }
        let signature = libraries.map(\.id).joined(separator: ",")
        if let cached = built[connection.id], cached.signature == signature, Date().timeIntervalSince(cached.builtAt) < 30 * 60 {
            return cached.map
        }
        if let task = building[connection.id] { return try await task.value }
        let userID = connection.userID
        let task = Task<[String: String], Error> {
            var map: [String: String] = [:]
            for library in libraries {
                var start = 0
                while true {
                    let page = try await client.providerIndexPage(userID: userID, library: library, start: start, limit: 500)
                    for entry in page.items {
                        let kind = entry.mediaKind == .movie ? "movie" : "series"
                        for (source, value) in entry.externalIDs {
                            map["\(kind):\(source):\(value.lowercased())"] = map["\(kind):\(source):\(value.lowercased())"] ?? entry.id
                        }
                    }
                    start += page.items.count
                    if page.items.isEmpty || start >= (page.totalRecordCount ?? 0) || start >= 50_000 { break }
                }
            }
            return map
        }
        building[connection.id] = task
        defer { building[connection.id] = nil }
        let map = try await task.value
        built[connection.id] = Built(signature: signature, builtAt: Date(), map: map)
        return map
    }
}

extension AddonStreamCandidate {
    /// One file of a server title, played directly. The token is sent as a
    /// request header and never kept with the link.
    nonisolated init?(
        server connection: MediaServerConnection,
        client: MediaBrowserClient,
        item: MediaBrowserClient.BaseItem,
        source: MediaBrowserClient.MediaSource,
        position: Int
    ) {
        guard let url = client.streamURL(itemID: item.id, mediaSourceID: source.id, tag: source.eTag) else { return nil }
        let sourceID = MediaServerIdentifier.sourceID(connectionID: connection.id)
        let video = source.mediaStreams?.first { $0.type?.lowercased() == "video" }
        let resolution: String? = video?.height.map { height in
            switch height {
            case 2_000...: "4K"
            case 1_000..<2_000: "1080p"
            case 700..<1_000: "720p"
            default: "\(height)p"
            }
        }
        let filename = source.path.map { URL(fileURLWithPath: $0).lastPathComponent }
        let details = [resolution, video?.codec?.uppercased(), source.container?.uppercased()].compactMap { $0 }
        id = "\(sourceID)::\(item.id)::\(position)::\(source.id)"
        addonID = sourceID
        addonName = connection.name
        streamIdentifier = item.id
        displayName = [connection.kind.displayName, resolution].compactMap { $0 }.joined(separator: " ")
        displayDescription = ([source.name ?? filename] + [details.isEmpty ? nil : details.joined(separator: " · ")])
            .compactMap { $0 }
            .joined(separator: "\n")
        delivery = .nativeHTTPS(url)
        self.filename = filename
        videoSize = source.size
        bingeGroup = "\(sourceID)::\(resolution ?? "")"
        hasPeerDiscoveryHints = false
        requestHeaders = client.requestHeaders
    }
}

private extension String {
    nonisolated var nonBlankValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
