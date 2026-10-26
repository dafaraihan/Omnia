//
//  TrackerKind.swift
//  Omnia
//

import Foundation

/// Watch trackers Omnia can scrobble to, as Nuvio does (Dafa, 2026-10-26).
/// Each uses the user's own API app: Omnia ships no client ID or secret.
nonisolated enum TrackerKind: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case trakt
    case simkl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trakt: "Trakt"
        case .simkl: "Simkl"
        }
    }

    var summary: String {
        switch self {
        case .trakt: "Scrobble movies and episodes to your Trakt history."
        case .simkl: "Scrobble movies, shows and anime to your Simkl lists."
        }
    }

    /// Trakt's device code needs the app's secret to become a token;
    /// Simkl's PIN needs only the client ID.
    var needsClientSecret: Bool { self == .trakt }

    /// Where the user creates their own API app.
    var applicationURL: URL {
        switch self {
        case .trakt: URL(string: "https://trakt.tv/oauth/applications/new")!
        case .simkl: URL(string: "https://simkl.com/settings/developer/new/")!
        }
    }

    var applicationGuidance: String {
        switch self {
        case .trakt:
            "Create an app on Trakt, use urn:ietf:wg:oauth:2.0:oob as its redirect URI, then paste its Client ID and Client Secret here."
        case .simkl:
            "Create an app on Simkl, use urn:ietf:wg:oauth:2.0:oob as its redirect URI, then paste its Client ID here."
        }
    }

    var assetName: String {
        switch self {
        case .trakt: "TraktMark"
        case .simkl: "SimklMark"
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

    /// Trackers match on IDs; a title alone can match the wrong show, so
    /// nothing is sent without one (Nuvio does the same).
    var hasIdentifier: Bool { imdb != nil || tmdb != nil || tvdb != nil }

    var key: String {
        let id = imdb ?? tmdb.map { "tmdb:\($0)" } ?? tvdb.map { "tvdb:\($0)" } ?? title
        switch kind {
        case .movie: return "movie:\(id)"
        case let .episode(season, number): return "episode:\(id):\(season):\(number)"
        }
    }
}

nonisolated enum TrackerScrobbleAction: String, Sendable {
    case start, pause, stop
}
