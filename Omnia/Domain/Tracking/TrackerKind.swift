//
//  TrackerKind.swift
//  Omnia
//

import Foundation

/// Watch trackers Omnia can scrobble to and read from, as Nuvio does (Dafa,
/// 2026-10-26). Trakt, Simkl, MDBList and AniList sign in with Omnia's own
/// registered apps, as Nuvio's do (built in from Config/Secrets.xcconfig);
/// PublicMetaDB takes the user's API key. PublicMetaDB, AniList and MDBList
/// were added 2026-10-27.
nonisolated enum TrackerKind: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case trakt
    case simkl
    case mdblist
    case pmdb
    case anilist

    /// How the user signs in.
    enum Connection: Sendable {
        /// A code shown in Omnia and entered on the tracker's site, which
        /// Omnia polls until it's approved (Trakt, Simkl's PIN, MDBList).
        case code
        /// The tracker's API key, pasted in (PublicMetaDB).
        case apiKey
        /// The tracker's sign-in page in the browser, which returns to Omnia
        /// through the omnia:// link (AniList).
        case browser
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trakt: "Trakt"
        case .simkl: "Simkl"
        case .mdblist: "MDBList"
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
        case .trakt: "Sync your watchlist, watch progress, continue watching and scrobbles with Trakt."
        case .simkl: "Sync your plan-to-watch list, watch progress and scrobbles with Simkl."
        case .mdblist: "Sync your watchlist, watch progress and scrobbles with MDBList."
        case .pmdb: "Save where you stopped to PublicMetaDB, and log what you finish to your watch history."
        case .anilist: "Sync your anime Watching and Planning lists, and update them as you finish episodes."
        }
    }

    var connection: Connection {
        switch self {
        case .trakt, .simkl, .mdblist: .code
        case .pmdb: .apiKey
        case .anilist: .browser
        }
    }

    var usesAPIKey: Bool { connection == .apiKey }

    /// The tracker's own site, for "Visit".
    var websiteURL: URL {
        switch self {
        case .trakt: URL(string: "https://trakt.tv")!
        case .simkl: URL(string: "https://simkl.com")!
        case .mdblist: URL(string: "https://mdblist.com")!
        case .pmdb: URL(string: "https://publicmetadb.com")!
        case .anilist: URL(string: "https://anilist.co")!
        }
    }

    /// Where a PublicMetaDB user creates their API key.
    var apiKeyURL: URL? {
        self == .pmdb ? URL(string: "https://publicmetadb.com/settings")! : nil
    }

    var assetName: String? {
        switch self {
        case .trakt: "TraktMark"
        case .simkl: "SimklMark"
        case .mdblist: "MDBListMark"
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
