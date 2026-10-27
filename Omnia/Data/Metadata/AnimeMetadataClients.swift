//
//  AnimeMetadataClients.swift
//  Omnia
//
//  Kitsu and MyAnimeList (through Jikan) as anime sources beside AniList,
//  as Nuvio offers (Dafa, 2026-10-27). Both are public and need no key.
//  Each also answers by ID, for Anime Enrichment.
//

import Foundation

/// The anime sources that answer by an anime database ID.
nonisolated enum AnimeMetadataSource {
    /// A title's record from `provider`, found by its ID there, for filling
    /// in what the add-on or TMDB left out.
    @MainActor
    static func record(for item: MediaItem, from provider: MetadataProviderIdentifier) async -> MediaItem? {
        func id(_ keys: [String]) -> Int? {
            keys.lazy.compactMap { item.externalIDs[$0].flatMap { Int($0) } }.first
                ?? Self.prefixedID(item.id, prefixes: keys)
        }
        switch provider {
        case .anilist:
            guard let anilist = id(["anilist", "anilist_id"]) else { return nil }
            return try? await AniListRecordClient.anime(id: anilist)
        case .kitsu:
            guard let kitsu = id(["kitsu", "kitsu_id"]) else { return nil }
            return try? await KitsuMetadataClient().anime(id: kitsu)
        case .myanimelist:
            guard let mal = id(["mal", "mal_id", "myanimelist"]) else { return nil }
            return try? await JikanMetadataClient().anime(id: mal)
        case .tmdb, .tvdb:
            return nil
        }
    }

    /// `kitsu:123` or `mal:45:1:2` style add-on IDs.
    private static func prefixedID(_ id: String, prefixes: [String]) -> Int? {
        let parts = id.split(separator: ":")
        guard parts.count >= 2, prefixes.contains(String(parts[0]).lowercased()) else { return nil }
        return Int(parts[1])
    }

    static func cleanedSynopsis(_ text: String?) -> String? {
        let cleaned = text?
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[Written by MAL Rewrite]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned?.isEmpty == false ? cleaned : nil
    }

    fileprivate static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        return URLSession(configuration: configuration)
    }()

    fileprivate static func get<T: Decodable>(_ url: URL, accept: String = "application/json") async throws -> T {
        var request = URLRequest(url: url)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ProviderMetadataError.invalidResponse }
        guard 200 ..< 300 ~= response.statusCode else { throw ProviderMetadataError.httpStatus(response.statusCode) }
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw ProviderMetadataError.invalidResponse }
    }

    fileprivate static func endpoint(_ base: URL, _ path: String, query: [String: String]) -> URL {
        var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url!
    }
}

// MARK: Kitsu

/// Kitsu's JSON:API (kitsu.io/api/edge).
@MainActor
final class KitsuMetadataClient {
    private let base = URL(string: "https://kitsu.io/api/edge")!
    private static let accept = "application/vnd.api+json"

    func searchAnime(query: String, page: Int = 1) async throws -> [MediaItem] {
        try await list(["filter[text]": query], page: page)
    }

    func catalogAnime(category: MetadataCatalogCategory, genre: String? = nil, page: Int = 1) async throws -> [MediaItem] {
        var query: [String: String] = [:]
        if let genre { query["filter[categories]"] = Self.categorySlug(genre) }
        switch category {
        case .trending where genre == nil && page == 1:
            // Trending isn't paged; later pages use popularity.
            let response: KitsuList = try await AnimeMetadataSource.get(
                AnimeMetadataSource.endpoint(base, "trending/anime", query: ["limit": "20"]),
                accept: Self.accept
            )
            return response.data.compactMap(\.mediaItem)
        case .trending, .popular:
            query["sort"] = "-userCount"
        case .topRated:
            query["sort"] = "ratingRank"
        case .airingToday, .nowPlaying:
            query["filter[status]"] = "current"
            query["sort"] = "-userCount"
        case .upcoming:
            query["filter[status]"] = "upcoming"
            query["sort"] = "-userCount"
        }
        return try await list(query, page: page)
    }

    func anime(id: Int) async throws -> MediaItem? {
        let response: KitsuSingle = try await AnimeMetadataSource.get(
            AnimeMetadataSource.endpoint(base, "anime/\(id)", query: [:]),
            accept: Self.accept
        )
        return response.data.mediaItem
    }

    private func list(_ query: [String: String], page: Int) async throws -> [MediaItem] {
        var query = query
        query["page[limit]"] = "20"
        query["page[offset]"] = String(max(page - 1, 0) * 20)
        let response: KitsuList = try await AnimeMetadataSource.get(
            AnimeMetadataSource.endpoint(base, "anime", query: query),
            accept: Self.accept
        )
        return response.data.compactMap(\.mediaItem)
    }

    /// Omnia's genres are AniList's names; Kitsu filters by category slug.
    private static func categorySlug(_ genre: String) -> String {
        switch genre.lowercased() {
        case "sci-fi": "science-fiction"
        case "mahou shoujo": "magical-girl"
        default: genre.lowercased().replacingOccurrences(of: " ", with: "-")
        }
    }
}

private nonisolated struct KitsuList: Decodable { let data: [KitsuAnime] }
private nonisolated struct KitsuSingle: Decodable { let data: KitsuAnime }

private nonisolated struct KitsuAnime: Decodable {
    struct Image: Decodable {
        let large: String?
        let original: String?
    }

    struct Attributes: Decodable {
        let canonicalTitle: String?
        let titles: [String: String?]?
        let synopsis: String?
        let startDate: String?
        let subtype: String?
        let posterImage: Image?
        let coverImage: Image?
    }

    let id: String
    let attributes: Attributes

    var mediaItem: MediaItem? {
        guard let posterURL = (attributes.posterImage?.large ?? attributes.posterImage?.original).flatMap(URL.init(string:))
        else { return nil }
        let english = attributes.titles?["en"] ?? nil
        return MediaItem(
            id: "kitsu:\(id)",
            title: english ?? attributes.canonicalTitle ?? "Untitled",
            year: attributes.startDate.map { String($0.prefix(4)) } ?? "—",
            kind: attributes.subtype?.lowercased() == "movie" ? .movie : .series,
            overview: AnimeMetadataSource.cleanedSynopsis(attributes.synopsis) ?? "No overview is available yet.",
            genres: [],
            symbol: "play.tv.fill",
            artworkColors: MediaItem.placeholderArtworkColors,
            artworkURL: posterURL,
            backdropURL: (attributes.coverImage?.original ?? attributes.coverImage?.large).flatMap(URL.init(string:)),
            metadataProvider: .kitsu,
            metadataProviderID: id,
            externalIDs: ["kitsu": id],
            progress: nil
        )
    }
}

// MARK: MyAnimeList (Jikan)

/// MyAnimeList through Jikan (api.jikan.moe/v4), which needs no key.
@MainActor
final class JikanMetadataClient {
    private let base = URL(string: "https://api.jikan.moe/v4")!

    func searchAnime(query: String, page: Int = 1) async throws -> [MediaItem] {
        try await list("anime", query: ["q": query, "order_by": "members", "sort": "desc"], page: page)
    }

    func catalogAnime(category: MetadataCatalogCategory, genre: String? = nil, page: Int = 1) async throws -> [MediaItem] {
        if let genre {
            guard let genreID = Self.genreIDs[genre.lowercased()] else { return [] }
            var query = ["genres": String(genreID), "order_by": "members", "sort": "desc"]
            switch category {
            case .topRated: query["order_by"] = "score"
            case .airingToday, .nowPlaying: query["status"] = "airing"
            case .upcoming: query["status"] = "upcoming"
            case .trending, .popular: break
            }
            return try await list("anime", query: query, page: page)
        }
        switch category {
        case .trending: return try await list("seasons/now", query: [:], page: page)
        case .popular: return try await list("top/anime", query: ["filter": "bypopularity"], page: page)
        case .topRated: return try await list("top/anime", query: [:], page: page)
        case .airingToday, .nowPlaying: return try await list("top/anime", query: ["filter": "airing"], page: page)
        case .upcoming: return try await list("seasons/upcoming", query: [:], page: page)
        }
    }

    func anime(id: Int) async throws -> MediaItem? {
        let response: JikanSingle = try await AnimeMetadataSource.get(AnimeMetadataSource.endpoint(base, "anime/\(id)", query: [:]))
        return response.data.mediaItem
    }

    private func list(_ path: String, query: [String: String], page: Int) async throws -> [MediaItem] {
        var query = query
        query["page"] = String(max(page, 1))
        query["limit"] = "24"
        query["sfw"] = "true"
        let response: JikanList = try await AnimeMetadataSource.get(AnimeMetadataSource.endpoint(base, path, query: query))
        var seen = Set<Int>()
        return response.data.filter { seen.insert($0.mal_id).inserted }.compactMap(\.mediaItem)
    }

    /// MyAnimeList's genre IDs for the genres Omnia offers (AniList's names).
    private static let genreIDs: [String: Int] = [
        "action": 1, "adventure": 2, "comedy": 4, "drama": 8, "ecchi": 9, "fantasy": 10,
        "horror": 14, "mahou shoujo": 66, "mecha": 18, "music": 19, "mystery": 7,
        "psychological": 40, "romance": 22, "sci-fi": 24, "slice of life": 36,
        "sports": 30, "supernatural": 37, "thriller": 41
    ]
}

private nonisolated struct JikanList: Decodable { let data: [JikanAnime] }
private nonisolated struct JikanSingle: Decodable { let data: JikanAnime }

private nonisolated struct JikanAnime: Decodable {
    struct Formats: Decodable {
        let large_image_url: String?
        let image_url: String?
    }

    struct Images: Decodable {
        let jpg: Formats?
        let webp: Formats?
    }

    struct Named: Decodable { let name: String }

    struct Aired: Decodable {
        struct From: Decodable { let year: Int? }
        struct Prop: Decodable { let from: From? }
        let prop: Prop?
    }

    let mal_id: Int
    let title: String?
    let title_english: String?
    let synopsis: String?
    let type: String?
    let year: Int?
    let aired: Aired?
    let images: Images?
    let genres: [Named]?

    var mediaItem: MediaItem? {
        let poster = images?.jpg?.large_image_url ?? images?.webp?.large_image_url ?? images?.jpg?.image_url
        guard let posterURL = poster.flatMap(URL.init(string:)) else { return nil }
        let releaseYear = year ?? aired?.prop?.from?.year
        return MediaItem(
            id: "mal:\(mal_id)",
            title: title_english ?? title ?? "Untitled",
            year: releaseYear.map(String.init) ?? "—",
            kind: type?.lowercased() == "movie" ? .movie : .series,
            overview: AnimeMetadataSource.cleanedSynopsis(synopsis) ?? "No overview is available yet.",
            genres: genres?.map(\.name) ?? [],
            symbol: "play.tv.fill",
            artworkColors: MediaItem.placeholderArtworkColors,
            artworkURL: posterURL,
            metadataProvider: .myanimelist,
            metadataProviderID: String(mal_id),
            externalIDs: ["mal": String(mal_id)],
            progress: nil
        )
    }
}

// MARK: AniList by ID

/// One AniList title by its ID, for enrichment. Public, so no token is sent.
@MainActor
enum AniListRecordClient {
    static func anime(id: Int) async throws -> MediaItem? {
        let document = """
        query ($id: Int) {
          Media(id: $id, type: ANIME) {
            id idMal format description(asHtml: false) genres
            startDate { year }
            title { userPreferred english romaji }
            coverImage { extraLarge large }
            bannerImage
          }
        }
        """
        var request = URLRequest(url: URL(string: "https://graphql.anilist.co")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": document, "variables": ["id": id]])
        let (data, response) = try await AnimeMetadataSource.session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, 200 ..< 300 ~= status else {
            throw ProviderMetadataError.invalidResponse
        }
        guard let media = try JSONDecoder().decode(AniListRecordResponse.self, from: data).data.Media else { return nil }
        let poster = (media.coverImage?.extraLarge ?? media.coverImage?.large).flatMap(URL.init(string:))
        var externalIDs = ["anilist": String(media.id)]
        if let idMal = media.idMal { externalIDs["mal"] = String(idMal) }
        return MediaItem(
            id: "anilist:\(media.id)",
            title: media.title?.english ?? media.title?.userPreferred ?? media.title?.romaji ?? "Untitled",
            year: media.startDate?.year.map(String.init) ?? "—",
            kind: media.format == "MOVIE" ? .movie : .series,
            overview: AnimeMetadataSource.cleanedSynopsis(media.description) ?? "No overview is available yet.",
            genres: media.genres ?? [],
            symbol: "play.tv.fill",
            artworkColors: MediaItem.placeholderArtworkColors,
            artworkURL: poster,
            backdropURL: media.bannerImage.flatMap(URL.init(string:)),
            metadataProvider: .anilist,
            metadataProviderID: String(media.id),
            externalIDs: externalIDs,
            progress: nil
        )
    }
}

private nonisolated struct AniListRecordResponse: Decodable {
    struct DateParts: Decodable { let year: Int? }

    struct Title: Decodable {
        let userPreferred: String?
        let english: String?
        let romaji: String?
    }

    struct Cover: Decodable {
        let extraLarge: String?
        let large: String?
    }

    struct Media: Decodable {
        let id: Int
        let idMal: Int?
        let format: String?
        let description: String?
        let genres: [String]?
        let startDate: DateParts?
        let title: Title?
        let coverImage: Cover?
        let bannerImage: String?
    }

    struct Payload: Decodable {
        let Media: Media?
    }

    let data: Payload
}
