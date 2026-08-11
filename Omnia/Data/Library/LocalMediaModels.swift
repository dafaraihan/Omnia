import Foundation
import SwiftData
import SwiftUI

@Model
final class LocalMediaRecord {
    @Attribute(.unique) var mediaID: String
    var mediaData: Data
    var isInWatchlist: Bool
    var progress: Double?
    var positionSeconds: Double?
    var durationSeconds: Double?
    var resumeEpisodeID: String?
    var resumeSeasonNumber: Int?
    var resumeEpisodeNumber: Int?
    var resumeEpisodeStillURL: URL?
    var savedAt: Date?
    var lastPlayedAt: Date?

    init(
        mediaID: String,
        mediaData: Data,
        isInWatchlist: Bool = false,
        savedAt: Date? = nil
    ) {
        self.mediaID = mediaID
        self.mediaData = mediaData
        self.isInWatchlist = isInWatchlist
        self.savedAt = savedAt
    }
}

struct LocalMediaSnapshot: Equatable, Sendable {
    let item: MediaItem
    let isInWatchlist: Bool
    let savedAt: Date?
    let lastPlayedAt: Date?

    var mediaID: String { item.id }
    var progress: Double? { item.progress }
    var positionSeconds: Double? { item.positionSeconds }
    var durationSeconds: Double? { item.durationSeconds }
}

/// Stable JSON representation used by legacy migration and local backup.
/// SwiftUI-only values are derived when reconstructing the domain model.
struct SavedMediaItem: Codable, Equatable, Sendable {
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
    let resumeEpisodeID: String?
    let resumeSeasonNumber: Int?
    let resumeEpisodeNumber: Int?
    let resumeEpisodeStillURL: URL?

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
        resumeEpisodeID = item.resumeEpisodeID
        resumeSeasonNumber = item.resumeSeasonNumber
        resumeEpisodeNumber = item.resumeEpisodeNumber
        resumeEpisodeStillURL = item.resumeEpisodeStillURL
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
            durationSeconds: durationSeconds,
            resumeEpisodeID: resumeEpisodeID,
            resumeSeasonNumber: resumeSeasonNumber,
            resumeEpisodeNumber: resumeEpisodeNumber,
            resumeEpisodeStillURL: resumeEpisodeStillURL
        )
    }
}
