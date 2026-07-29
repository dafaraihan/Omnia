//
//  MediaItem.swift
//  Omnia
//

import Foundation
import SwiftUI

struct MediaItem: Identifiable, Hashable, Sendable {
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
        durationSeconds: Double? = nil
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
    }

    var progressText: String? {
        guard let progress else { return nil }
        if let durationSeconds, let positionSeconds {
            let remaining = max(durationSeconds - positionSeconds, 0)
            return Self.remainingTimeFormatter.string(from: remaining).map { "\($0) left" }
        }
        return "\(Int((1 - progress) * 100))% remaining"
    }

    var streamIdentifierCandidates: [String] {
        let preferredKeys = ["imdb", "imdb_id", "tmdb", "tvdb"]
        let external = preferredKeys.compactMap { externalIDs[$0] }
        let identifiers = external + [metadataProviderID, id].compactMap { $0 }
        return Array(Set(identifiers.filter { !$0.isEmpty }))
    }

    private static let remainingTimeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }()
}

struct MediaCredit: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let role: String?
    let character: String?
    let profileURL: URL?
}

struct MediaStudio: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
}

struct MediaCollection: Hashable, Sendable {
    let id: String
    let name: String
    let members: [MediaItem]
}

struct MediaEpisode: Identifiable, Hashable, Sendable {
    let id: String
    let seasonNumber: Int
    let episodeNumber: Int
    let title: String
    let overview: String
    let runtimeMinutes: Int?
    let stillURL: URL?
    let airDate: String?
}

struct MediaSeason: Identifiable, Hashable, Sendable {
    let id: String
    let seasonNumber: Int
    let title: String
    let overview: String?
    let posterURL: URL?
    let episodes: [MediaEpisode]
}

struct MediaVideo: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let type: String
    let thumbnailURL: URL?
    let watchURL: URL
    let publishedAt: String?
}

struct MediaTitleDetails: Hashable, Sendable {
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

/// The durable, local representation of a library title. Artwork colors are
/// derived from media kind on restore so no SwiftUI types are written to disk.
struct SavedMediaItem: Codable {
    let id: String
    let title: String
    let year: String
    let kind: MediaItem.Kind
    let overview: String
    let genres: [String]
    let symbol: String
    let artworkURL: URL?
    let backdropURL: URL?
    let logoURL: URL?
    let metadataProvider: MetadataProviderIdentifier?
    let metadataProviderID: String?
    let metadataRecordID: UUID?
    let externalIDs: [String: String]?
    let progress: Double?
    let positionSeconds: Double?
    let durationSeconds: Double?

    init(_ item: MediaItem) {
        id = item.id
        title = item.title
        year = item.year
        kind = item.kind
        overview = item.overview
        genres = item.genres
        symbol = item.symbol
        artworkURL = item.artworkURL
        backdropURL = item.backdropURL
        logoURL = item.logoURL
        metadataProvider = item.metadataProvider
        metadataProviderID = item.metadataProviderID
        metadataRecordID = item.metadataRecordID
        externalIDs = item.externalIDs
        progress = item.progress
        positionSeconds = item.positionSeconds
        durationSeconds = item.durationSeconds
    }

    var mediaItem: MediaItem {
        MediaItem(
            id: id,
            title: title,
            year: year,
            kind: kind,
            overview: overview,
            genres: genres,
            symbol: symbol,
            artworkColors: kind == .series ? [.cyan, .indigo] : [.indigo, .black],
            artworkURL: artworkURL,
            backdropURL: backdropURL,
            logoURL: logoURL,
            metadataProvider: metadataProvider,
            metadataProviderID: metadataProviderID,
            metadataRecordID: metadataRecordID,
            externalIDs: externalIDs ?? [:],
            progress: progress,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds
        )
    }
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
