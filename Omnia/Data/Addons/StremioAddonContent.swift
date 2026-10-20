//
//  StremioAddonContent.swift
//  Omnia
//

import Foundation
import SwiftUI

/// The compact card object returned by Stremio catalog resources.
nonisolated struct AddonMetaPreview: Codable, Hashable, Sendable {
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
    var released: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, type, name, poster, background, logo, description, releaseInfo, year, genres, released
    }

    func mediaItem(addon: InstalledAddon) -> MediaItem? {
        // Types Omnia has no shelf for (`other`, `channel`, `documentary`)
        // are shown as films rather than dropped, as Stremio does.
        let kind = MediaItem.Kind(stremioType: type) ?? .movie
        return MediaItem(
            id: "stremio:\(addon.id):\(id)",
            title: name,
            year: normalizedYear,
            kind: kind,
            overview: description?.nonBlank ?? "No overview is available yet.",
            genres: genres ?? [],
            symbol: kind == .movie ? "film.fill" : "tv.fill",
            artworkColors: MediaItem.placeholderArtworkColors,
            artworkURL: poster,
            backdropURL: background,
            logoURL: logo,
            metadataProviderID: id,
            externalIDs: externalIDs,
            progress: nil
        )
    }

    var normalizedYear: String {
        year?.nonBlank ?? releaseInfo?.firstYear ?? released?.firstYear ?? "—"
    }

    var externalIDs: [String: String] {
        id.hasPrefix("tt") ? ["imdb": id] : [:]
    }

    /// Nuvio's "Hide Unreleased Content" rule: a title is unreleased when its
    /// release date is in the future, or when the first year it mentions is
    /// after the current year.
    func isUnreleased(asOf now: Date, calendar: Calendar = .current) -> Bool {
        if let released, let date = AddonDateParser.date(from: released) {
            return date > now
        }
        if let date = releaseInfo.flatMap(AddonDateParser.date(from:)) {
            return date > now
        }
        let currentYear = calendar.component(.year, from: now)
        if let year = (year?.nonBlank ?? releaseInfo?.firstYear).flatMap({ Int($0.prefix(4)) }) {
            return year > currentYear
        }
        return false
    }
}

nonisolated extension AddonMetaPreview {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Stremio and Nuvio show an entry as long as it has an id: numeric
        // ids are read as text, a missing name falls back to the id and a
        // missing type is left for the item mapping to settle.
        guard let id = container.lenientString(forKey: .id)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty
        else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "A catalog entry needs an id.")
        }
        self.id = id
        type = container.lenientString(forKey: .type) ?? ""
        name = container.lenientString(forKey: .name)?.nonBlank ?? id
        poster = container.lenientURL(forKey: .poster)
        background = container.lenientURL(forKey: .background)
        logo = container.lenientURL(forKey: .logo)
        description = container.lenientString(forKey: .description)
        releaseInfo = container.lenientString(forKey: .releaseInfo)
        year = container.lenientString(forKey: .year)
        genres = try? container.decodeIfPresent([String].self, forKey: .genres)
        released = container.lenientString(forKey: .released)
    }
}

/// The detailed object returned by a Stremio meta resource. Stremio permits
/// several optional fields, so Omnia keeps unknown or absent fields harmless.
nonisolated struct AddonMeta: Decodable, Hashable, Sendable {
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
    var released: String? = nil
    var trailers: [AddonTrailer]? = nil
    var trailerStreams: [AddonTrailer]? = nil
    var links: [AddonMetaLink]? = nil

    enum CodingKeys: String, CodingKey {
        case id, type, name, poster, background, logo, description, releaseInfo, year, genres, runtime, cast, director, writer, videos
        case released, trailers, trailerStreams, links
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
            genres: genres ?? linkNames(category: "genres"),
            released: released
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
                cast: people(cast ?? linkNames(category: "cast"), role: nil),
                crew: people(director ?? linkNames(category: "directors"), role: "Director")
                    + people(writer ?? linkNames(category: "writers"), role: "Writer"),
                studioTitles: [],
                collection: nil,
                recommendations: [],
                seasons: seasons,
                trailers: trailerVideos,
                bonusContent: []
            ),
            progress: nil
        )
    }

    /// Stremio has carried trailers in three shapes over time: the legacy
    /// `trailers` (`source` is the YouTube id), `trailerStreams` (`ytId`) and
    /// TMDB-style objects (`key` + `site`). All of them become YouTube videos.
    var trailerVideos: [MediaVideo] {
        var seen = Set<String>()
        return ((trailers ?? []) + (trailerStreams ?? [])).compactMap { trailer -> MediaVideo? in
            guard let videoID = trailer.youTubeID, seen.insert(videoID).inserted,
                  let watchURL = URL(string: "https://www.youtube.com/watch?v=\(videoID)")
            else { return nil }
            return MediaVideo(
                id: videoID,
                title: trailer.displayName ?? "Trailer",
                type: trailer.type ?? "Trailer",
                thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg"),
                watchURL: watchURL,
                publishedAt: trailer.publishedAt
            )
        }
    }

    private func linkNames(category: String) -> [String]? {
        let names = (links ?? [])
            .filter { $0.category?.lowercased() == category }
            .compactMap { $0.name?.nonBlank }
        return names.isEmpty ? nil : names
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
                // Episode cards and Upcoming expect `yyyy-MM-dd`; Stremio
                // sends ISO 8601 date-times.
                airDate: video.released.flatMap(AddonDateParser.dayString(from:))
            )
        }
        let grouped = Dictionary(grouping: episodes, by: \.seasonNumber)
        return grouped.keys.sorted().map { season in
            .init(
                id: "\(id):\(season)",
                seasonNumber: season,
                title: season == 0 ? "Specials" : "Season \(season)",
                overview: nil,
                posterURL: poster,
                episodes: (grouped[season] ?? []).sorted { $0.episodeNumber < $1.episodeNumber }
            )
        }
    }
}

nonisolated extension AddonMeta {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Stremio and Nuvio show an entry as long as it has an id: numeric
        // ids are read as text, a missing name falls back to the id and a
        // missing type is left for the item mapping to settle.
        guard let id = container.lenientString(forKey: .id)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty
        else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "A catalog entry needs an id.")
        }
        self.id = id
        type = container.lenientString(forKey: .type) ?? ""
        name = container.lenientString(forKey: .name)?.nonBlank ?? id
        poster = container.lenientURL(forKey: .poster)
        background = container.lenientURL(forKey: .background)
        logo = container.lenientURL(forKey: .logo)
        description = container.lenientString(forKey: .description)
        releaseInfo = container.lenientString(forKey: .releaseInfo)
        year = container.lenientString(forKey: .year)
        genres = try? container.decodeIfPresent([String].self, forKey: .genres)
        runtime = container.lenientString(forKey: .runtime)
        cast = try? container.decodeIfPresent([String].self, forKey: .cast)
        director = try? container.decodeIfPresent([String].self, forKey: .director)
        writer = try? container.decodeIfPresent([String].self, forKey: .writer)
        videos = container.lossyArray(AddonVideo.self, forKey: .videos)
        released = container.lenientString(forKey: .released)
        trailers = container.lossyArray(AddonTrailer.self, forKey: .trailers)
        trailerStreams = container.lossyArray(AddonTrailer.self, forKey: .trailerStreams)
        links = container.lossyArray(AddonMetaLink.self, forKey: .links)
    }
}

nonisolated struct AddonVideo: Decodable, Hashable, Sendable {
    let id: String
    let title: String?
    let season: Int?
    let episode: Int?
    let thumbnail: URL?
    let overview: String?
    let released: String?

    private enum CodingKeys: String, CodingKey {
        case id, title, name, season, episode, number, thumbnail, overview, description, released, firstAired
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = container.lenientString(forKey: .title) ?? container.lenientString(forKey: .name)
        season = container.lenientInt(forKey: .season)
        episode = container.lenientInt(forKey: .episode) ?? container.lenientInt(forKey: .number)
        thumbnail = container.lenientURL(forKey: .thumbnail)
        overview = container.lenientString(forKey: .overview) ?? container.lenientString(forKey: .description)
        released = container.lenientString(forKey: .released) ?? container.lenientString(forKey: .firstAired)
    }
}

/// One trailer entry in any of the shapes add-ons use.
nonisolated struct AddonTrailer: Decodable, Hashable, Sendable {
    let source: String?
    let ytId: String?
    let key: String?
    let site: String?
    let type: String?
    let name: String?
    let title: String?
    let publishedAt: String?

    private enum CodingKeys: String, CodingKey {
        case source, ytId, key, site, type, name, title
        case publishedAt = "published_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = container.lenientString(forKey: .source)
        ytId = container.lenientString(forKey: .ytId)
        key = container.lenientString(forKey: .key)
        site = container.lenientString(forKey: .site)
        type = container.lenientString(forKey: .type)
        name = container.lenientString(forKey: .name)
        title = container.lenientString(forKey: .title)
        publishedAt = container.lenientString(forKey: .publishedAt)
    }

    var displayName: String? { name?.nonBlank ?? title?.nonBlank }

    var youTubeID: String? {
        if let ytId = ytId?.nonBlank, ytId.isYouTubeVideoID { return ytId }
        if let key = key?.nonBlank, key.isYouTubeVideoID,
           site == nil || site?.lowercased() == "youtube" {
            return key
        }
        if let source = source?.nonBlank, source.isYouTubeVideoID { return source }
        return nil
    }
}

nonisolated struct AddonMetaLink: Decodable, Hashable, Sendable {
    let name: String?
    let category: String?
    let url: String?

    private enum CodingKeys: String, CodingKey {
        case name, category, url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = container.lenientString(forKey: .name)
        category = container.lenientString(forKey: .category)
        url = container.lenientString(forKey: .url)
    }
}

nonisolated struct AddonCatalogItem: Identifiable, Hashable, Sendable {
    let item: MediaItem
    let addon: InstalledAddon
    let catalog: AddonCatalog

    var id: String { "\(addon.id):\(catalog.id):\(item.id)" }
}

nonisolated extension MediaItem.Kind {
    init?(stremioType: String) {
        // AIOMetadata and Xperience use display types such as `anime.movie`.
        let type = stremioType.lowercased()
        switch type {
        case "movie": self = .movie
        case "series", "tv", "anime", "show", "tvshow", "tvseries", "shows": self = .series
        default:
            if type.hasSuffix(".movie") || type.hasSuffix("movies") || type.contains("film") {
                self = .movie
            } else if type.hasSuffix(".series") || type.hasSuffix(".tv")
                        || type.contains("series") || type.contains("show") {
                self = .series
            } else {
                return nil
            }
        }
    }
}

nonisolated extension MediaItem {
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
            durationSeconds: durationSeconds,
            resumeEpisodeID: resumeEpisodeID,
            resumeSeasonNumber: resumeSeasonNumber,
            resumeEpisodeNumber: resumeEpisodeNumber,
            resumeEpisodeTitle: resumeEpisodeTitle,
            resumeEpisodeStillURL: resumeEpisodeStillURL
        )
    }

    /// Keeps this item's values and uses `other` only where this item has
    /// nothing: the add-on-first rule for detail pages, where the add-on's
    /// meta is authoritative and TMDB/TVDB only fills gaps.
    func fillingGaps(from other: MediaItem) -> MediaItem {
        let hasOverview = !overview.isEmpty && overview != "No overview is available yet."

        return MediaItem(
            id: id,
            title: title.nonBlank ?? other.title,
            year: year == "—" ? other.year : year,
            kind: kind,
            overview: hasOverview ? overview : other.overview,
            genres: genres.isEmpty ? other.genres : genres,
            symbol: symbol,
            artworkColors: artworkColors,
            artworkURL: artworkURL ?? other.artworkURL,
            backdropURL: backdropURL ?? other.backdropURL,
            logoURL: logoURL ?? other.logoURL,
            metadataProvider: metadataProvider ?? other.metadataProvider,
            metadataProviderID: metadataProviderID ?? other.metadataProviderID,
            metadataRecordID: metadataRecordID ?? other.metadataRecordID,
            externalIDs: externalIDs.merging(other.externalIDs) { current, _ in current },
            details: MediaTitleDetails.filling(details, from: other.details),
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
}

nonisolated extension MediaTitleDetails {
    /// Field-by-field gap filling; a non-empty value in `primary` always wins.
    static func filling(_ primary: MediaTitleDetails?, from fallback: MediaTitleDetails?) -> MediaTitleDetails? {
        guard let primary else { return fallback }
        guard let fallback else { return primary }
        return MediaTitleDetails(
            ageRating: primary.ageRating ?? fallback.ageRating,
            runtimeMinutes: primary.runtimeMinutes ?? fallback.runtimeMinutes,
            status: primary.status ?? fallback.status,
            budget: primary.budget ?? fallback.budget,
            revenue: primary.revenue ?? fallback.revenue,
            studios: primary.studios.isEmpty ? fallback.studios : primary.studios,
            // Add-on credits are names only; TMDB's carry photos and roles.
            cast: primary.cast.contains(where: { $0.profileURL != nil }) || fallback.cast.isEmpty
                ? primary.cast : fallback.cast,
            crew: primary.crew.isEmpty ? fallback.crew : primary.crew,
            studioTitles: primary.studioTitles.isEmpty ? fallback.studioTitles : primary.studioTitles,
            collection: primary.collection ?? fallback.collection,
            recommendations: primary.recommendations.isEmpty ? fallback.recommendations : primary.recommendations,
            seasons: primary.seasons.isEmpty ? fallback.seasons : primary.seasons,
            trailers: primary.trailers.isEmpty ? fallback.trailers : primary.trailers,
            bonusContent: primary.bonusContent.isEmpty ? fallback.bonusContent : primary.bonusContent
        )
    }
}

/// Stremio dates arrive as ISO 8601 date-times (`2024-03-01T00:00:00.000Z`),
/// plain days, or free text such as `2019–2023`.
nonisolated enum AddonDateParser {
    static func date(from value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = try? Date(trimmed, strategy: .iso8601) { return date }
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        if let date = try? Date(trimmed, strategy: fractional) { return date }
        guard trimmed.count >= 10 else { return nil }
        let day = String(trimmed.prefix(10))
        guard day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        return try? Date("\(day)T00:00:00Z", strategy: .iso8601)
    }

    static func dayString(from value: String) -> String? {
        guard let date = date(from: value) else { return nil }
        return date.formatted(.iso8601.year().month().day())
    }
}

nonisolated extension KeyedDecodingContainer {
    /// Accepts a URL string but drops anything that isn't http(s), so one bad
    /// image value doesn't fail the whole object.
    func lenientURL(forKey key: Key) -> URL? {
        guard let value = lenientString(forKey: key),
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http"
        else { return nil }
        return url
    }

    func lenientString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return String(value) }
        return nil
    }

    func lenientInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Int(value) }
        return nil
    }

    func lossyArray<Element: Decodable>(_ type: Element.Type, forKey key: Key) -> [Element]? {
        guard let values = try? decodeIfPresent([AddonLossyElement<Element>].self, forKey: key) else { return nil }
        return values.compactMap(\.value)
    }
}

private nonisolated struct AddonLossyElement<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

private nonisolated extension String {
    var nonBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var firstYear: String? {
        range(of: #"\b(?:18|19|20)\d{2}\b"#, options: .regularExpression).map { String(self[$0]) }
    }

    var isYouTubeVideoID: Bool {
        range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil
    }

    var durationMinutes: Int? {
        let numbers = components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
        guard let first = numbers.first else { return nil }
        if lowercased().contains("h"), numbers.count > 1 { return first * 60 + numbers[1] }
        return first
    }
}
