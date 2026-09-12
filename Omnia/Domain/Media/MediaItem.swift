//
//  MediaItem.swift
//  Omnia
//

import Foundation
import SwiftUI

nonisolated struct MediaItem: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Codable, Sendable {
        case movie = "Movie"
        case series = "Series"
        case episode = "Episode"
    }

    let id: String
    let title: String
    let year: String
    let kind: Kind
    let overview: String
    let genres: [String]
    let symbol: String
    let artworkColors: [Color]
    let artworkURL: URL?
    let backdropURL: URL?
    let logoURL: URL?
    let metadataProvider: MetadataProviderIdentifier?
    let metadataProviderID: String?
    let metadataRecordID: UUID?
    let externalIDs: [String: String]
    /// Rich, title-specific metadata is fetched on demand from the protected
    /// metadata service. Catalog cards stay deliberately lightweight.
    let details: MediaTitleDetails?
    var progress: Double?
    var positionSeconds: Double?
    var durationSeconds: Double?
    /// Series playback is resumed at an episode, not merely at a title. These
    /// fields let Continue Watching use that episode's landscape still while
    /// remaining backward compatible with existing saved movie entries.
    var resumeEpisodeID: String?
    var resumeSeasonNumber: Int?
    var resumeEpisodeNumber: Int?
    var resumeEpisodeTitle: String?
    var resumeEpisodeStillURL: URL?

    init(
        id: String,
        title: String,
        year: String,
        kind: Kind,
        overview: String,
        genres: [String],
        symbol: String,
        artworkColors: [Color],
        artworkURL: URL? = nil,
        backdropURL: URL? = nil,
        logoURL: URL? = nil,
        metadataProvider: MetadataProviderIdentifier? = nil,
        metadataProviderID: String? = nil,
        metadataRecordID: UUID? = nil,
        externalIDs: [String: String] = [:],
        details: MediaTitleDetails? = nil,
        progress: Double?,
        positionSeconds: Double? = nil,
        durationSeconds: Double? = nil,
        resumeEpisodeID: String? = nil,
        resumeSeasonNumber: Int? = nil,
        resumeEpisodeNumber: Int? = nil,
        resumeEpisodeTitle: String? = nil,
        resumeEpisodeStillURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.year = year
        self.kind = kind
        self.overview = overview
        self.genres = genres
        self.symbol = symbol
        self.artworkColors = artworkColors
        self.artworkURL = artworkURL
        self.backdropURL = backdropURL
        self.logoURL = logoURL
        self.metadataProvider = metadataProvider
        self.metadataProviderID = metadataProviderID
        self.metadataRecordID = metadataRecordID
        self.externalIDs = externalIDs
        self.details = details
        self.progress = progress
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.resumeEpisodeID = resumeEpisodeID
        self.resumeSeasonNumber = resumeSeasonNumber
        self.resumeEpisodeNumber = resumeEpisodeNumber
        self.resumeEpisodeTitle = resumeEpisodeTitle
        self.resumeEpisodeStillURL = resumeEpisodeStillURL
    }

    var progressText: String? {
        guard let progress else { return nil }
        if let durationSeconds, let positionSeconds {
            let remaining = max(durationSeconds - positionSeconds, 0)
            return Self.remainingTimeFormatter.string(from: remaining).map { "\($0) left" }
        }
        return "\(Int((1 - progress) * 100))% remaining"
    }

    /// Restores the episode identity needed by source add-ons even when the
    /// locally persisted Continue Watching entry has no full season payload.
    var resumeEpisode: MediaEpisode? {
        guard kind == .series,
              let seasonNumber = resumeSeasonNumber,
              let episodeNumber = resumeEpisodeNumber
        else { return nil }

        if let episode = details?.seasons
            .flatMap(\.episodes)
            .first(where: {
                $0.id == resumeEpisodeID
                    || ($0.seasonNumber == seasonNumber && $0.episodeNumber == episodeNumber)
            }) {
            return episode
        }

        return MediaEpisode(
            id: resumeEpisodeID ?? "\(id):\(seasonNumber):\(episodeNumber)",
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            title: "Episode \(episodeNumber)",
            overview: "",
            runtimeMinutes: durationSeconds.map { Int($0 / 60) },
            stillURL: resumeEpisodeStillURL,
            airDate: nil
        )
    }

    var streamIdentifierCandidates: [String] {
        // Stream add-ons do not share a single identifier namespace. Preserve
        // every real cross-ID, with its documented prefix, instead of relying
        // on whichever provider record happened to populate the catalog card.
        var identifiers: [String] = []
        identifiers += values(for: ["imdb", "imdb_id"], prefix: nil)
        identifiers += values(for: ["tmdb", "tmdb_id"], prefix: "tmdb:")
        identifiers += values(for: ["tvdb", "tvdb_id"], prefix: "tvdb:")
        identifiers += values(for: ["anilist", "anilist_id"], prefix: "anilist:")
        identifiers += values(for: ["mal", "mal_id", "myanimelist"], prefix: "mal:")
        identifiers += values(for: ["kitsu", "kitsu_id"], prefix: "kitsu:")
        identifiers += values(for: ["anidb", "anidb_id"], prefix: "anidb:")

        if let metadataProviderID {
            switch metadataProvider {
            case .tmdb: identifiers.append("tmdb:\(metadataProviderID)")
            case .tvdb: identifiers.append("tvdb:\(metadataProviderID)")
            case .anilist: identifiers.append("anilist:\(metadataProviderID)")
            case .none: identifiers.append(metadataProviderID)
            }
        }
        identifiers.append(id)
        // A stream add-on may support more than one identifier. Preserve the
        // documented identifier preference rather than using `Set`, whose
        // iteration order can otherwise make the first request arbitrary.
        var seen = Set<String>()
        return identifiers.filter { identifier in
            !identifier.isEmpty && seen.insert(identifier).inserted
        }
    }

    var hasIMDbIdentifier: Bool {
        ["imdb", "imdb_id"].contains { key in
            externalIDs[key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    /// Most add-ons call anime a series, but anime-focused manifests expose a
    /// separate `anime` type. Ask both when the title has an anime identity.
    var streamMediaTypes: [String] {
        guard kind == .series else { return ["movie"] }
        return hasAnimeIdentity ? ["anime", "series"] : ["series"]
    }

    var hasAnimeIdentity: Bool {
        ["anilist", "anilist_id", "mal", "mal_id", "kitsu", "kitsu_id", "anidb", "anidb_id"]
            .contains { externalIDs[$0] != nil }
            || metadataProvider == .anilist
    }

    /// Stremio-compatible add-ons address an episode as the series identifier
    /// followed by `:season:episode` (for example `tt14688458:1:2`). Keep the
    /// series identifier untouched for movie and series-level playback.
    func streamIdentifierCandidates(for episode: MediaEpisode?) -> [String] {
        guard let episode else { return streamIdentifierCandidates }
        return streamIdentifierCandidates.map {
            "\($0):\(episode.seasonNumber):\(episode.episodeNumber)"
        }
    }

    /// Preserves the lightweight item shown by the UI while adding cross-ID
    /// values returned by an on-demand provider detail request. Source lookup
    /// uses this even when the user opens the picker before the detail screen
    /// has finished loading.
    func mergingSourceIdentifiers(from enrichedItem: MediaItem) -> MediaItem {
        MediaItem(
            id: id,
            title: title,
            year: year,
            kind: kind,
            overview: overview,
            genres: genres,
            symbol: symbol,
            artworkColors: artworkColors,
            artworkURL: artworkURL ?? enrichedItem.artworkURL,
            backdropURL: backdropURL ?? enrichedItem.backdropURL,
            logoURL: logoURL ?? enrichedItem.logoURL,
            metadataProvider: metadataProvider ?? enrichedItem.metadataProvider,
            metadataProviderID: metadataProviderID ?? enrichedItem.metadataProviderID,
            metadataRecordID: metadataRecordID ?? enrichedItem.metadataRecordID,
            externalIDs: externalIDs.merging(enrichedItem.externalIDs) { current, _ in current },
            details: details ?? enrichedItem.details,
            progress: progress,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds,
            resumeEpisodeID: resumeEpisodeID,
            resumeSeasonNumber: resumeSeasonNumber,
            resumeEpisodeNumber: resumeEpisodeNumber,
            resumeEpisodeTitle: resumeEpisodeTitle,
            resumeEpisodeStillURL: resumeEpisodeStillURL
        )
    }

    private static let remainingTimeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }()

    private func values(for keys: [String], prefix: String?) -> [String] {
        keys.compactMap { key in
            guard let value = externalIDs[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                return nil
            }
            guard let prefix else { return value }
            return value.hasPrefix(prefix) ? value : "\(prefix)\(value)"
        }
    }
}

nonisolated struct MediaCredit: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let role: String?
    let character: String?
    let profileURL: URL?
}

nonisolated struct MediaStudio: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
}

nonisolated struct MediaCollection: Hashable, Sendable {
    let id: String
    let name: String
    let members: [MediaItem]
}

nonisolated struct MediaEpisode: Identifiable, Hashable, Sendable {
    let id: String
    let seasonNumber: Int
    let episodeNumber: Int
    let title: String
    let overview: String
    let runtimeMinutes: Int?
    let stillURL: URL?
    let airDate: String?
}

nonisolated struct MediaSeason: Identifiable, Hashable, Sendable {
    let id: String
    let seasonNumber: Int
    let title: String
    let overview: String?
    let posterURL: URL?
    let episodes: [MediaEpisode]
}

nonisolated struct MediaVideo: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let type: String
    let thumbnailURL: URL?
    let watchURL: URL
    let publishedAt: String?
}

nonisolated struct MediaTitleDetails: Hashable, Sendable {
    let ageRating: String?
    let runtimeMinutes: Int?
    let status: String?
    let budget: Int?
    let revenue: Int?
    let studios: [MediaStudio]
    let cast: [MediaCredit]
    let crew: [MediaCredit]
    let studioTitles: [MediaItem]
    let collection: MediaCollection?
    let recommendations: [MediaItem]
    let seasons: [MediaSeason]
    let trailers: [MediaVideo]
    let bonusContent: [MediaVideo]
}

extension MediaItem {
    static let previewLibrary: [MediaItem] = [
        .init(id: "astra", title: "Astra", year: "2026", kind: .movie, overview: "A quiet navigator follows an impossible signal beyond the last mapped orbit.", genres: ["Science Fiction", "Drama"], symbol: "sparkles", artworkColors: [.indigo, .black], progress: 0.42),
        .init(id: "coastline", title: "Coastline", year: "2025", kind: .series, overview: "A cartographer returns to the island that erased her family from its maps.", genres: ["Mystery", "Drama"], symbol: "water.waves", artworkColors: [.cyan, .indigo], progress: 0.68),
        .init(id: "liminal", title: "Liminal", year: "2026", kind: .movie, overview: "An archivist discovers a corridor between memories that should not coexist.", genres: ["Thriller"], symbol: "door.left.hand.open", artworkColors: [.purple, .black], progress: 0.23),
        .init(id: "north", title: "North of Here", year: "2024", kind: .movie, overview: "Two climbers trade ambition for survival in an early winter storm.", genres: ["Adventure"], symbol: "mountain.2.fill", artworkColors: [.teal, .gray], progress: nil),
        .init(id: "golden", title: "Golden Hour", year: "2025", kind: .series, overview: "A photographer finds a new beginning in a city of borrowed light.", genres: ["Romance", "Drama"], symbol: "sun.max.fill", artworkColors: [.orange, .pink], progress: nil),
        .init(id: "depth", title: "The Depth", year: "2026", kind: .movie, overview: "A deep-sea mission receives an answer from below the ocean floor.", genres: ["Science Fiction"], symbol: "drop.fill", artworkColors: [.blue, .black], progress: nil),
        .init(id: "field", title: "Field Notes", year: "2024", kind: .series, overview: "Stories from people reconstructing a future with what the past left behind.", genres: ["Documentary"], symbol: "book.closed.fill", artworkColors: [.green, .black], progress: nil),
        .init(id: "signal", title: "The Signal", year: "2026", kind: .movie, overview: "A single broadcast changes what a small town believes about its sky.", genres: ["Mystery"], symbol: "dot.radiowaves.left.and.right", artworkColors: [.mint, .blue], progress: nil)
    ]
}
