//
//  StremioAddonContent.swift
//  Omnia
//

import Foundation
import SwiftUI

/// The compact card object returned by Stremio catalog resources.
struct AddonMetaPreview: Decodable, Hashable, Sendable {
    let id: String
    let type: String
    let name: String
    let poster: URL?
    let background: URL?
    let logo: URL?
    let description: String?
    let releaseInfo: String?
    let year: String?
    let genres: [String]?

    enum CodingKeys: String, CodingKey {
        case id, type, name, poster, background, logo, description, releaseInfo, year, genres
    }

    func mediaItem(addon: InstalledAddon) -> MediaItem? {
        guard let kind = MediaItem.Kind(stremioType: type) else { return nil }
        return MediaItem(
            id: "stremio:\(addon.id):\(id)",
            title: name,
            year: normalizedYear,
            kind: kind,
            overview: description?.nonBlank ?? "No overview is available yet.",
            genres: genres ?? [],
            symbol: kind == .movie ? "film.fill" : "tv.fill",
            artworkColors: kind == .movie ? [.indigo, .black] : [.cyan, .indigo],
            artworkURL: poster,
            backdropURL: background,
            logoURL: logo,
            metadataProviderID: id,
            externalIDs: externalIDs,
            progress: nil
        )
    }

    var normalizedYear: String {
        year?.nonBlank ?? releaseInfo?.firstYear ?? "—"
    }

    var externalIDs: [String: String] {
        id.hasPrefix("tt") ? ["imdb": id] : [:]
    }
}

/// The detailed object returned by a Stremio meta resource. Stremio permits
/// several optional fields, so Omnia keeps unknown or absent fields harmless.
struct AddonMeta: Decodable, Hashable, Sendable {
    let id: String
    let type: String
    let name: String
    let poster: URL?
    let background: URL?
    let logo: URL?
    let description: String?
    let releaseInfo: String?
    let year: String?
    let genres: [String]?
    let runtime: String?
    let cast: [String]?
    let director: [String]?
    let writer: [String]?
    let videos: [AddonVideo]?

    enum CodingKeys: String, CodingKey {
        case id, type, name, poster, background, logo, description, releaseInfo, year, genres, runtime, cast, director, writer, videos
    }

    func mediaItem(addon: InstalledAddon) -> MediaItem? {
        guard let preview = AddonMetaPreview(
            id: id,
            type: type,
            name: name,
            poster: poster,
            background: background,
            logo: logo,
            description: description,
            releaseInfo: releaseInfo,
            year: year,
            genres: genres
        ).mediaItem(addon: addon) else { return nil }

        return MediaItem(
            id: preview.id,
            title: preview.title,
            year: preview.year,
            kind: preview.kind,
            overview: preview.overview,
            genres: preview.genres,
            symbol: preview.symbol,
            artworkColors: preview.artworkColors,
            artworkURL: preview.artworkURL,
            backdropURL: preview.backdropURL,
            logoURL: preview.logoURL,
            metadataProviderID: id,
            externalIDs: preview.externalIDs,
            details: .init(
                ageRating: nil,
                runtimeMinutes: runtime?.durationMinutes,
                status: nil,
                budget: nil,
                revenue: nil,
                studios: [],
                cast: people(cast, role: nil),
                crew: people(director, role: "Director") + people(writer, role: "Writer"),
                studioTitles: [],
                collection: nil,
                recommendations: [],
                seasons: seasons,
                trailers: [],
                bonusContent: []
            ),
            progress: nil
        )
    }

    private func people(_ names: [String]?, role: String?) -> [MediaCredit] {
        (names ?? []).enumerated().map { offset, name in
            .init(id: "\(id):\(role ?? "cast"):\(offset)", name: name, role: role, character: nil, profileURL: nil)
        }
    }

    private var seasons: [MediaSeason] {
        let episodes = (videos ?? []).compactMap { video -> MediaEpisode? in
            guard let season = video.season, let episode = video.episode else { return nil }
            return .init(
                id: video.id,
                seasonNumber: season,
                episodeNumber: episode,
                title: video.title?.nonBlank ?? "Episode \(episode)",
                overview: video.overview?.nonBlank ?? "No episode synopsis is available yet.",
                runtimeMinutes: nil,
                stillURL: video.thumbnail,
                airDate: video.released
            )
        }
        let grouped = Dictionary(grouping: episodes, by: \.seasonNumber)
        return grouped.keys.sorted().map { season in
            .init(
                id: "\(id):\(season)",
                seasonNumber: season,
                title: "Season \(season)",
                overview: nil,
                posterURL: poster,
                episodes: (grouped[season] ?? []).sorted { $0.episodeNumber < $1.episodeNumber }
            )
        }
    }
}

struct AddonVideo: Decodable, Hashable, Sendable {
    let id: String
    let title: String?
    let season: Int?
    let episode: Int?
    let thumbnail: URL?
    let overview: String?
    let released: String?
}

struct AddonCatalogItem: Identifiable, Hashable, Sendable {
    let item: MediaItem
    let addon: InstalledAddon
    let catalog: AddonCatalog

    var id: String { "\(addon.id):\(catalog.id):\(item.id)" }
}

extension MediaItem.Kind {
    init?(stremioType: String) {
        switch stremioType.lowercased() {
        case "movie": self = .movie
        case "series", "tv", "anime": self = .series
        default: return nil
        }
    }
}

extension MediaItem {
    /// Retains the app's existing provider metadata while allowing an add-on to
    /// fill missing artwork, synopsis, IDs, and episode data for titles it
    /// uniquely understands.
    func mergingAddonMetadata(_ addonItem: MediaItem) -> MediaItem {
        let preferAddonOverview = overview == "No overview is available yet." || overview.isEmpty
        let builtInDetails = details
        let addonDetails = addonItem.details
        let useAddonDetails = builtInDetails == nil
            || (builtInDetails?.seasons.isEmpty == true && addonDetails?.seasons.isEmpty == false)

        return MediaItem(
            id: id,
            title: title.nonBlank ?? addonItem.title,
            year: year == "—" ? addonItem.year : year,
            kind: kind,
            overview: preferAddonOverview ? addonItem.overview : overview,
            genres: genres.isEmpty ? addonItem.genres : genres,
            symbol: symbol,
            artworkColors: artworkColors,
            artworkURL: artworkURL ?? addonItem.artworkURL,
            backdropURL: backdropURL ?? addonItem.backdropURL,
            logoURL: logoURL ?? addonItem.logoURL,
            metadataProvider: metadataProvider,
            metadataProviderID: metadataProviderID ?? addonItem.metadataProviderID,
            metadataRecordID: metadataRecordID,
            externalIDs: externalIDs.merging(addonItem.externalIDs) { current, _ in current },
            details: useAddonDetails ? addonDetails : builtInDetails,
            progress: progress,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds
        )
    }
}

private extension String {
    var nonBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var firstYear: String? {
        range(of: #"\b(?:18|19|20)\d{2}\b"#, options: .regularExpression).map { String(self[$0]) }
    }

    var durationMinutes: Int? {
        let numbers = components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
        guard let first = numbers.first else { return nil }
        if lowercased().contains("h"), numbers.count > 1 { return first * 60 + numbers[1] }
        return first
    }
}
