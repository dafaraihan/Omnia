//
//  TrackerLibraryClient.swift
//  Omnia
//
//  Reads what is in progress and on the watchlist from Trakt, Simkl,
//  PublicMetaDB and AniList, after Nuvio's TraktProgressRepository,
//  TraktLibraryRepository and SimklSyncRemote (NuvioMedia/NuvioMobile,
//  GPL-3.0) and PublicMetaDB's External API reference.
//

import Foundation

/// One title a tracker has in progress or on its watchlist, in the terms
/// the tracker sent. Kept on disk as the tracker's cache.
nonisolated struct TrackerLibraryEntry: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case movie
        case series
    }

    var kind: Kind
    var title: String
    var year: Int?
    var imdb: String?
    var tmdb: Int?
    var tvdb: Int?
    var anilist: Int?
    var mal: Int?
    /// AniList sends its own artwork; the other trackers leave it to the
    /// add-ons.
    var posterURL: URL?
    var backdropURL: URL?
    /// The episode a series is paused in.
    var season: Int?
    var episode: Int?
    /// 0 to 1.
    var progress: Double?
    var runtimeSeconds: Double?
    var updatedAt: Date?
    /// The tracker's own ID for the paused playback, for removing it.
    var playbackID: String?

    var hasIdentifier: Bool { imdb != nil || tmdb != nil || tvdb != nil || anilist != nil || mal != nil }

    /// AniList, Kitsu and MyAnimeList IDs mark a title as anime.
    var isAnime: Bool { anilist != nil || mal != nil }
}

nonisolated enum TrackerLibraryList: String, Sendable {
    case progress
    case watchlist
}

nonisolated enum TrackerLibraryClient {
    private static let traktBase = URL(string: "https://api.trakt.tv")!
    private static let simklBase = URL(string: "https://api.simkl.com")!
    private static let mdblistBase = URL(string: "https://api.mdblist.com")!
    /// Bounds on what one sync reads, so a huge library can't stall Home.
    private static let maximumEntries = 500
    private static let maximumPMDBMappingLookups = 60

    private static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        return "Omnia/\(version)"
    }

    static func fetch(
        _ list: TrackerLibraryList,
        from kind: TrackerKind,
        credentials: TrackerCredentials
    ) async throws -> [TrackerLibraryEntry] {
        guard let token = credentials.accessToken, !token.isEmpty else { return [] }
        let entries: [TrackerLibraryEntry]
        switch (kind, list) {
        case (.trakt, .progress):
            // extended=full adds each title's runtime, which turns Trakt's
            // percentage into a resume point.
            async let movies = traktGET("sync/playback/movies", [TraktPlayback].self, token: token, clientID: credentials.clientID, query: ["extended": "full"])
            async let episodes = traktGET("sync/playback/episodes", [TraktPlayback].self, token: token, clientID: credentials.clientID, query: ["extended": "full"])
            entries = try await (movies + episodes).compactMap(\.entry)
        case (.trakt, .watchlist):
            entries = try await traktGET("sync/watchlist", [TraktListed].self, token: token, clientID: credentials.clientID)
                .compactMap(\.entry)
        case (.simkl, .progress):
            entries = try await simklGET("sync/playback", [SimklPlayback]?.self, token: token, clientID: credentials.clientID)?
                .compactMap(\.entry) ?? []
        case (.simkl, .watchlist):
            var found: [TrackerLibraryEntry] = []
            for type in ["shows", "movies", "anime"] {
                let response = try await simklGET(
                    "sync/all-items/\(type)/plantowatch",
                    SimklAllItems?.self,
                    token: token,
                    clientID: credentials.clientID
                )
                found += response?.entries ?? []
            }
            entries = found
        case (.pmdb, .progress):
            let page = try await pmdbGET("resume", PMDBPage<PMDBResume>.self, key: token, query: ["perPage": "200"])
            entries = await withIMDbIDs(page.items?.compactMap(\.entry) ?? [], key: token)
        case (.pmdb, .watchlist):
            let lists = try await pmdbGET("lists", PMDBPage<PMDBList>.self, key: token, query: ["perPage": "100"])
            guard let watchlist = lists.items?.first(where: { $0.type == "watchlist" }),
                  watchlist.id.allSatisfy(\.isPathSafe)
            else { return [] }
            let page = try await pmdbGET(
                "lists/\(watchlist.id)/items",
                PMDBPage<PMDBListItem>.self,
                key: token,
                query: ["perPage": "500"]
            )
            entries = await withIMDbIDs(page.items?.compactMap(\.entry) ?? [], key: token)
        case (.mdblist, .progress):
            entries = try await mdblistGET("sync/playback", [MDBListPlayback]?.self, token: token)?
                .compactMap(\.entry) ?? []
        case (.mdblist, .watchlist):
            entries = try await mdblistGET("watchlist/items", MDBListItems?.self, token: token)?.entries ?? []
        case (.anilist, .progress):
            entries = try await anilistList(["CURRENT", "REPEATING"], token: token, inProgress: true)
        case (.anilist, .watchlist):
            entries = try await anilistList(["PLANNING"], token: token, inProgress: false)
        }
        let newestFirst = entries
            .filter(\.hasIdentifier)
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        return Array(newestFirst.prefix(maximumEntries))
    }

    /// Removes a paused playback, as Continue Watching's Remove does.
    static func removePlayback(_ entry: TrackerLibraryEntry, from kind: TrackerKind, credentials: TrackerCredentials) async throws {
        guard let token = credentials.accessToken, let id = entry.playbackID, !id.isEmpty, id.allSatisfy(\.isPathSafe)
        else { return }
        var request: URLRequest
        switch kind {
        case .trakt: request = traktRequest("sync/playback/\(id)", token: token, clientID: credentials.clientID)
        case .simkl: request = simklRequest("sync/playback/\(id)", token: token, clientID: credentials.clientID)
        case .pmdb: request = TrackerClient.pmdbRequest("resume/\(id)", key: token)
        case .mdblist: request = mdblistRequest("sync/playback/\(id)", token: token)
        case .anilist: return
        }
        request.httpMethod = "DELETE"
        _ = try await TrackerClient.send(request, accepting: [200, 204, 404])
    }

    // MARK: AniList

    /// The signed-in user's anime list entries with these statuses: Watching
    /// (and Rewatching) for Continue Watching, Planning for the watchlist.
    private static func anilistList(_ statuses: [String], token: String, inProgress: Bool) async throws -> [TrackerLibraryEntry] {
        let viewer: AniListViewer = try await TrackerClient.anilistQuery("query { Viewer { id } }", variables: [:], token: token)
        guard let userID = viewer.Viewer?.id else { throw TrackerClientError.invalidResponse }
        let collection: AniListCollection = try await TrackerClient.anilistQuery(
            """
            query ($userId: Int, $status: [MediaListStatus]) {
              MediaListCollection(userId: $userId, type: ANIME, status_in: $status, sort: UPDATED_TIME_DESC) {
                lists { entries {
                  progress updatedAt
                  media { id idMal format episodes startDate { year }
                    title { english userPreferred romaji }
                    coverImage { extraLarge large } bannerImage }
                } }
              }
            }
            """,
            variables: ["userId": userID, "status": statuses],
            token: token
        )
        return (collection.MediaListCollection?.lists ?? []).flatMap { $0.entries ?? [] }.map { $0.entry(inProgress: inProgress) }
    }

    // MARK: PublicMetaDB IDs

    /// PublicMetaDB lists titles by TMDB ID only. Stream add-ons mostly
    /// want IMDb IDs, so they're looked up from its mappings.
    private static func withIMDbIDs(_ entries: [TrackerLibraryEntry], key: String) async -> [TrackerLibraryEntry] {
        var resolved = entries
        await withTaskGroup(of: (Int, String?).self) { group in
            for (index, entry) in entries.enumerated().prefix(maximumPMDBMappingLookups) {
                guard entry.imdb == nil, let tmdb = entry.tmdb else { continue }
                group.addTask {
                    let response = try? await pmdbGET(
                        "mappings",
                        PMDBMappings.self,
                        key: key,
                        query: [
                            "tmdb_id": String(tmdb),
                            "media_type": entry.kind == .movie ? "movie" : "tv",
                            "id_type": "imdb"
                        ]
                    )
                    let imdb = response?.mappings?["imdb"]?.first?.value
                    return (index, imdb.flatMap { $0.hasPrefix("tt") ? $0 : nil })
                }
            }
            for await (index, imdb) in group where imdb != nil {
                resolved[index].imdb = imdb
            }
        }
        return resolved
    }

    // MARK: Requests

    private static func traktRequest(_ path: String, token: String, clientID: String) -> URLRequest {
        var request = URLRequest(url: traktBase.appending(path: path))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        request.setValue(clientID, forHTTPHeaderField: "trakt-api-key")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func simklRequest(_ path: String, token: String, clientID: String) -> URLRequest {
        var request = URLRequest(url: simklBase.appending(path: path))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(clientID, forHTTPHeaderField: "simkl-api-key")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func mdblistRequest(_ path: String, token: String) -> URLRequest {
        var request = URLRequest(url: mdblistBase.appending(path: path))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    /// MDBList answers an empty list with `[]` or `{}`, decoded as nil.
    private static func mdblistGET<T: Decodable>(_ path: String, _ type: T?.Type, token: String) async throws -> T? {
        let (data, _) = try await TrackerClient.send(mdblistRequest(path, token: token), accepting: [200])
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text == "null" || text == "[]" || text == "{}" { return nil }
        return try TrackerClient.decode(type, from: data)
    }

    private static func traktGET<T: Decodable>(
        _ path: String,
        _ type: T.Type,
        token: String,
        clientID: String,
        query: [String: String] = [:]
    ) async throws -> T {
        var request = traktRequest(path, token: token, clientID: clientID)
        if !query.isEmpty, let url = request.url {
            request.url = url.appending(queryItems: query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) })
        }
        let (data, _) = try await TrackerClient.send(request, accepting: [200])
        return try TrackerClient.decode(type, from: data)
    }

    /// Simkl answers an empty list with `null`, `[]` or nothing, so `T` is
    /// an optional and those decode as nil.
    private static func simklGET<T: Decodable>(_ path: String, _ type: T?.Type, token: String, clientID: String) async throws -> T? {
        let (data, _) = try await TrackerClient.send(simklRequest(path, token: token, clientID: clientID), accepting: [200])
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text == "null" || text == "[]" || text == "{}" { return nil }
        return try TrackerClient.decode(type, from: data)
    }

    private static func pmdbGET<T: Decodable>(_ path: String, _ type: T.Type, key: String, query: [String: String]) async throws -> T {
        let (data, _) = try await TrackerClient.send(TrackerClient.pmdbRequest(path, key: key, query: query), accepting: [200])
        return try TrackerClient.decode(type, from: data)
    }

    fileprivate static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

private extension Character {
    /// IDs put into a request path come from the tracker, so only plain
    /// ones are used.
    nonisolated var isPathSafe: Bool { isASCII && (isLetter || isNumber || self == "_" || self == "-") }
}

// MARK: Wire formats

/// Trakt and Simkl IDs; Simkl sends some as text and some as numbers.
private nonisolated struct TrackerWireIDs: Decodable {
    let imdb: String?
    let tmdb: Int?
    let tvdb: Int?

    private enum CodingKeys: String, CodingKey { case imdb, tmdb, tvdb }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func int(_ key: CodingKeys) -> Int? {
            if let value = try? c.decodeIfPresent(Int.self, forKey: key) { return value }
            return (try? c.decodeIfPresent(String.self, forKey: key))?.flatMap { Int($0) }
        }
        let imdb = (try? c.decodeIfPresent(String.self, forKey: .imdb))?.trimmingCharacters(in: .whitespaces)
        self.imdb = imdb?.hasPrefix("tt") == true ? imdb : nil
        tmdb = int(.tmdb)
        tvdb = int(.tvdb)
    }
}

private nonisolated struct TrackerWireMedia: Decodable {
    let title: String?
    let year: Int?
    let ids: TrackerWireIDs?
    /// Minutes, with Trakt's extended=full.
    let runtime: Int?
}

private nonisolated struct TrackerWireEpisode: Decodable {
    let season: Int?
    let number: Int?
    /// Minutes, with Trakt's extended=full.
    let runtime: Int?
}

/// A playback's runtime in seconds: the episode's, else the show's usual
/// episode length, else the movie's.
private nonisolated func playbackRuntimeSeconds(movie: TrackerWireMedia?, show: TrackerWireMedia?, episode: TrackerWireEpisode?) -> Double? {
    let minutes = movie != nil ? movie?.runtime : (episode?.runtime ?? show?.runtime)
    return minutes.flatMap { $0 > 0 ? Double($0) * 60 : nil }
}

private nonisolated extension TrackerLibraryEntry {
    init?(_ kind: Kind, media: TrackerWireMedia?, episode: TrackerWireEpisode? = nil) {
        guard let media, let ids = media.ids else { return nil }
        self.init(
            kind: kind,
            title: media.title ?? "",
            year: media.year,
            imdb: ids.imdb,
            tmdb: ids.tmdb,
            tvdb: ids.tvdb,
            season: episode?.season,
            episode: episode?.number
        )
    }
}

private nonisolated struct TraktPlayback: Decodable {
    let id: Int?
    let progress: Double?
    let paused_at: String?
    let movie: TrackerWireMedia?
    let show: TrackerWireMedia?
    let episode: TrackerWireEpisode?

    var entry: TrackerLibraryEntry? {
        var entry = movie != nil
            ? TrackerLibraryEntry(.movie, media: movie)
            : TrackerLibraryEntry(.series, media: show, episode: episode)
        entry?.progress = progress.map { min(max($0 / 100, 0), 1) }
        entry?.runtimeSeconds = playbackRuntimeSeconds(movie: movie, show: show, episode: episode)
        entry?.updatedAt = TrackerLibraryClient.date(paused_at)
        entry?.playbackID = id.map(String.init)
        return entry
    }
}

private nonisolated struct TraktListed: Decodable {
    let type: String?
    let listed_at: String?
    let movie: TrackerWireMedia?
    let show: TrackerWireMedia?

    var entry: TrackerLibraryEntry? {
        var entry: TrackerLibraryEntry?
        switch type {
        case "movie": entry = TrackerLibraryEntry(.movie, media: movie)
        case "show": entry = TrackerLibraryEntry(.series, media: show)
        default: return nil
        }
        entry?.updatedAt = TrackerLibraryClient.date(listed_at)
        return entry
    }
}

private nonisolated struct SimklPlayback: Decodable {
    let id: Int?
    let progress: Double?
    let paused_at: String?
    let movie: TrackerWireMedia?
    let show: TrackerWireMedia?
    let anime: TrackerWireMedia?
    let episode: TrackerWireEpisode?

    var entry: TrackerLibraryEntry? {
        var entry = movie != nil
            ? TrackerLibraryEntry(.movie, media: movie)
            : TrackerLibraryEntry(.series, media: show ?? anime, episode: episode)
        entry?.progress = progress.map { min(max($0 / 100, 0), 1) }
        entry?.runtimeSeconds = playbackRuntimeSeconds(movie: movie, show: show ?? anime, episode: episode)
        entry?.updatedAt = TrackerLibraryClient.date(paused_at)
        entry?.playbackID = id.map(String.init)
        return entry
    }
}

private nonisolated struct SimklAllItems: Decodable {
    struct Item: Decodable {
        let added_to_watchlist_at: String?
        let anime_type: String?
        let movie: TrackerWireMedia?
        let show: TrackerWireMedia?
    }

    let shows: [Item]?
    let movies: [Item]?
    let anime: [Item]?

    var entries: [TrackerLibraryEntry] {
        let items = (shows ?? []) + (movies ?? []) + (anime ?? [])
        return items.compactMap { item in
            let isMovie = item.movie != nil || item.anime_type == "movie"
            var entry = TrackerLibraryEntry(isMovie ? .movie : .series, media: item.movie ?? item.show)
            entry?.updatedAt = TrackerLibraryClient.date(item.added_to_watchlist_at)
            return entry
        }
    }
}

private nonisolated struct AniListViewer: Decodable {
    struct Viewer: Decodable { let id: Int? }
    let Viewer: Viewer?
}

private nonisolated struct AniListCollection: Decodable {
    struct Title: Decodable {
        let english: String?
        let userPreferred: String?
        let romaji: String?
    }

    struct Cover: Decodable {
        let extraLarge: String?
        let large: String?
    }

    struct DateParts: Decodable { let year: Int? }

    struct Media: Decodable {
        let id: Int
        let idMal: Int?
        let format: String?
        let episodes: Int?
        let startDate: DateParts?
        let title: Title?
        let coverImage: Cover?
        let bannerImage: String?
    }

    struct Entry: Decodable {
        let progress: Int?
        let updatedAt: Int?
        let media: Media

        func entry(inProgress: Bool) -> TrackerLibraryEntry {
            let isMovie = media.format == "MOVIE"
            let watched = progress ?? 0
            // The next episode to watch, within what has aired.
            let next = media.episodes.map { min(watched + 1, $0) } ?? watched + 1
            return TrackerLibraryEntry(
                kind: isMovie ? .movie : .series,
                title: media.title?.english ?? media.title?.userPreferred ?? media.title?.romaji ?? "",
                year: media.startDate?.year,
                anilist: media.id,
                mal: media.idMal,
                posterURL: (media.coverImage?.extraLarge ?? media.coverImage?.large).flatMap(URL.init(string:)),
                backdropURL: media.bannerImage.flatMap(URL.init(string:)),
                season: inProgress && !isMovie ? 1 : nil,
                episode: inProgress && !isMovie ? next : nil,
                progress: inProgress ? media.episodes.flatMap { $0 > 0 ? Double(watched) / Double($0) : nil } ?? 0 : nil,
                updatedAt: updatedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            )
        }
    }

    struct List: Decodable { let entries: [Entry]? }
    struct Collection: Decodable { let lists: [List]? }

    let MediaListCollection: Collection?
}

/// MDBList's IDs: `imdb`/`tmdb`/`tvdb`, sometimes as `imdbid`/`tmdbid`.
private nonisolated struct MDBListIDs: Decodable {
    let imdb: String?
    let tmdb: Int?
    let tvdb: Int?

    private enum CodingKeys: String, CodingKey { case imdb, imdbid, tmdb, tmdbid, tvdb, tvdbid }

    init(imdb: String?, tmdb: Int?, tvdb: Int?) {
        self.imdb = imdb
        self.tmdb = tmdb
        self.tvdb = tvdb
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func int(_ keys: CodingKeys...) -> Int? {
            for key in keys {
                if let value = try? c.decodeIfPresent(Int.self, forKey: key) { return value }
                if let value = (try? c.decodeIfPresent(String.self, forKey: key))?.flatMap({ Int($0) }) { return value }
            }
            return nil
        }
        let imdb: String? = ((try? c.decodeIfPresent(String.self, forKey: .imdb)) ?? nil)
            ?? ((try? c.decodeIfPresent(String.self, forKey: .imdbid)) ?? nil)
        self.imdb = imdb?.hasPrefix("tt") == true ? imdb : nil
        tmdb = int(.tmdb, .tmdbid)
        tvdb = int(.tvdb, .tvdbid)
    }
}

private nonisolated struct MDBListMediaWire: Decodable {
    let title: String?
    let name: String?
    let year: Int?
    let ids: MDBListIDs?
}

private nonisolated struct MDBListPlayback: Decodable {
    struct Episode: Decodable {
        let season: Int?
        let number: Int?
        let episode: Int?
        let show: MDBListMediaWire?
    }

    let id: Int?
    let type: String?
    let progress: Double?
    let paused_at: String?
    let updated_at: String?
    let movie: MDBListMediaWire?
    let show: MDBListMediaWire?
    let episode: Episode?

    var entry: TrackerLibraryEntry? {
        let isMovie = type == "movie"
        guard let media = isMovie ? movie : (show ?? episode?.show), let ids = media.ids else { return nil }
        return TrackerLibraryEntry(
            kind: isMovie ? .movie : .series,
            title: media.title ?? media.name ?? "",
            year: media.year,
            imdb: ids.imdb,
            tmdb: ids.tmdb,
            tvdb: ids.tvdb,
            season: isMovie ? nil : episode?.season,
            episode: isMovie ? nil : (episode?.number ?? episode?.episode),
            progress: progress.map { min(max($0 / 100, 0), 1) },
            updatedAt: TrackerLibraryClient.date(paused_at ?? updated_at),
            playbackID: id.map(String.init)
        )
    }
}

/// MDBList's watchlist: `{movies, shows}` or `{items}`.
private nonisolated struct MDBListItems: Decodable {
    struct Item: Decodable {
        let id: Int?
        let imdb_id: String?
        let tvdb_id: Int?
        let ids: MDBListIDs?
        let title: String?
        let release_year: Int?
        let mediatype: String?
        let type: String?
        let listed_at: String?
        let poster: String?

        func entry(defaultKind: TrackerLibraryEntry.Kind?) -> TrackerLibraryEntry? {
            let declared = (mediatype ?? type)?.lowercased()
            let kind: TrackerLibraryEntry.Kind
            switch declared {
            case "movie": kind = .movie
            case "show", "series", "tv": kind = .series
            case nil: guard let defaultKind else { return nil }; kind = defaultKind
            default: return nil
            }
            let imdb = ids?.imdb ?? imdb_id.flatMap { $0.hasPrefix("tt") ? $0 : nil }
            let posterURL: URL? = poster.flatMap { value in
                if value.hasPrefix("https://") { return URL(string: value) }
                if value.hasPrefix("/") { return URL(string: "https://image.tmdb.org/t/p/w500\(value)") }
                return nil
            }
            return TrackerLibraryEntry(
                kind: kind,
                title: title ?? "",
                year: release_year,
                imdb: imdb,
                tmdb: ids?.tmdb ?? id,
                tvdb: ids?.tvdb ?? tvdb_id,
                posterURL: posterURL,
                updatedAt: TrackerLibraryClient.date(listed_at)
            )
        }
    }

    let movies: [Item]?
    let shows: [Item]?
    let items: [Item]?

    var entries: [TrackerLibraryEntry] {
        (movies ?? []).compactMap { $0.entry(defaultKind: .movie) }
            + (shows ?? []).compactMap { $0.entry(defaultKind: .series) }
            + (items ?? []).compactMap { $0.entry(defaultKind: nil) }
    }
}

private nonisolated struct PMDBPage<Item: Decodable>: Decodable {
    let items: [Item]?
}

private nonisolated struct PMDBResume: Decodable {
    let id: String?
    let tmdb_id: Int?
    let media_type: String?
    let season: Int?
    let episode: Int?
    let runtime_ms: Double?
    let progress: Double?
    let updated: String?

    var entry: TrackerLibraryEntry? {
        guard let tmdb_id else { return nil }
        let isMovie = media_type == "movie"
        return TrackerLibraryEntry(
            kind: isMovie ? .movie : .series,
            title: "",
            tmdb: tmdb_id,
            season: isMovie ? nil : season,
            episode: isMovie ? nil : episode,
            progress: progress.map { min(max($0 / 100, 0), 1) },
            runtimeSeconds: runtime_ms.map { $0 / 1000 },
            updatedAt: TrackerLibraryClient.date(updated),
            playbackID: id
        )
    }
}

private nonisolated struct PMDBList: Decodable {
    let id: String
    let type: String?
}

private nonisolated struct PMDBListItem: Decodable {
    let tmdb_id: Int?
    let media_type: String?

    var entry: TrackerLibraryEntry? {
        guard let tmdb_id else { return nil }
        return TrackerLibraryEntry(kind: media_type == "movie" ? .movie : .series, title: "", tmdb: tmdb_id)
    }
}

private nonisolated struct PMDBMappings: Decodable {
    struct Mapping: Decodable {
        let value: String?
    }

    let mappings: [String: [Mapping]]?
}
