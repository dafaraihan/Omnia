//
//  TrackerKind.swift
//  Omnia
//

import Foundation

/// Watch trackers Omnia can scrobble to, as Nuvio does (Dafa, 2026-10-26).
/// Each uses the user's own API app or key: Omnia ships no client ID,
/// secret or key. PublicMetaDB and AniList were added 2026-10-27.
nonisolated enum TrackerKind: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case trakt
    case simkl
    case pmdb
    case anilist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trakt: "Trakt"
        case .simkl: "Simkl"
        case .pmdb: "PublicMetaDB"
        case .anilist: "AniList"
        }
    }

    /// The short name used in menus, like Nuvio's "All PMDB".
    var shortTitle: String {
        switch self {
        case .pmdb: "PMDB"
        default: title
        }
    }

    var summary: String {
        switch self {
        case .trakt: "Scrobble movies and episodes to your Trakt history."
        case .simkl: "Scrobble movies, shows and anime to your Simkl lists."
        case .pmdb: "Save where you stopped to PublicMetaDB, and log what you finish to your watch history."
        case .anilist: "Update your AniList anime list as you finish episodes."
        }
    }

    /// Trakt's device code needs the app's secret to become a token;
    /// Simkl's PIN needs only the client ID.
    var needsClientSecret: Bool { self == .trakt }

    /// PublicMetaDB connects with an API key from its settings instead of
    /// a code entered on its site.
    var usesAPIKey: Bool { self == .pmdb }

    /// AniList signs in in the browser with the user's client ID, then
    /// shows a token to paste back (its PIN redirect).
    var usesPastedToken: Bool { self == .anilist }

    /// The page that asks the user to approve their AniList client.
    func authorizationURL(clientID: String) -> URL? {
        guard self == .anilist else { return nil }
        var components = URLComponents(string: "https://anilist.co/api/v2/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "token")
        ]
        return components.url
    }

    /// Where the user creates their own API app.
    var applicationURL: URL {
        switch self {
        case .trakt: URL(string: "https://trakt.tv/oauth/applications/new")!
        case .simkl: URL(string: "https://simkl.com/settings/developer/new/")!
        case .pmdb: URL(string: "https://publicmetadb.com/settings")!
        case .anilist: URL(string: "https://anilist.co/settings/developer")!
        }
    }

    var applicationGuidance: String {
        switch self {
        case .trakt:
            "Create an app on Trakt, use urn:ietf:wg:oauth:2.0:oob as its redirect URI, then paste its Client ID and Client Secret here."
        case .simkl:
            "Create an app on Simkl, use urn:ietf:wg:oauth:2.0:oob as its redirect URI, then paste its Client ID here."
        case .pmdb:
            "Create a key under Settings › API on PublicMetaDB (it starts with pm-), then paste it here."
        case .anilist:
            "Create a client on AniList with https://anilist.co/api/v2/oauth/pin as its redirect URL, paste its Client ID here, sign in, then paste the token AniList shows."
        }
    }

    /// PublicMetaDB's mark is a wordmark, drawn by `TrackerMark`.
    var assetName: String? {
        switch self {
        case .trakt: "TraktMark"
        case .simkl: "SimklMark"
        case .pmdb: nil
        case .anilist: "AniListMark"
        }
    }
}

/// What is playing, in the terms trackers match on.
nonisolated struct TrackerMedia: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case movie
        case episode(season: Int, number: Int)
    }

    let kind: Kind
    let title: String
    let year: Int?
    let imdb: String?
    let tmdb: Int?
    let tvdb: Int?
    /// AniList matches anime only, by its own or MyAnimeList's ID.
    var anilist: Int? = nil
    var mal: Int? = nil

    /// Trackers match on IDs; a title alone can match the wrong show, so
    /// nothing is sent without one (Nuvio does the same).
    var hasIdentifier: Bool { imdb != nil || tmdb != nil || tvdb != nil || anilist != nil || mal != nil }

    /// Trakt, Simkl and PublicMetaDB match on IMDb, TMDB or TVDB IDs.
    var hasVideoIdentifier: Bool { imdb != nil || tmdb != nil || tvdb != nil }

    var key: String {
        let id = imdb ?? tmdb.map { "tmdb:\($0)" } ?? tvdb.map { "tvdb:\($0)" }
            ?? anilist.map { "anilist:\($0)" } ?? mal.map { "mal:\($0)" } ?? title
        switch kind {
        case .movie: return "movie:\(id)"
        case let .episode(season, number): return "episode:\(id):\(season):\(number)"
        }
    }
}

nonisolated enum TrackerScrobbleAction: String, Sendable {
    case start, pause, stop
}
