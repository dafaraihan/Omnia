//
//  UserManagedMetadataClients.swift
//  Omnia
//

import CryptoKit
import Foundation
import SwiftUI

/// MDBList requests use the current user's own API key. The key is read from
/// `ProviderCredentialStore` immediately before the request and is never sent
/// through the Omnia/Supabase metadata function.
@MainActor
protocol MDBListRatingServing: Sendable {
    func titleRatings(
        for item: MediaItem,
        bypassCache: Bool
    ) async throws -> MDBListTitleRatings?
}

@MainActor
extension MDBListRatingServing {
    func titleRatings(for item: MediaItem) async throws -> MDBListTitleRatings? {
        try await titleRatings(for: item, bypassCache: false)
    }
}

typealias MDBListCredentialReader = @MainActor @Sendable () throws -> String?

@MainActor
final class MDBListMetadataClient: MDBListRatingServing {
    private static let sharedCache = MDBListRatingsCache()
    private static let origin = NormalizedOrigin(
        scheme: "https",
        host: "api.mdblist.com",
        port: nil
    )
    private static let requestTimeout: TimeInterval = 15
    private static let maximumResponseBytes = 512 * 1_024

    private let transport: any HTTPTransporting
    private let cache: MDBListRatingsCache
    private let credentialReader: MDBListCredentialReader

    init(
        transport: any HTTPTransporting,
        cache: MDBListRatingsCache = MDBListRatingsCache(),
        credentialReader: @escaping MDBListCredentialReader = {
            try ProviderCredentialStore.value(for: .mdblist)
        }
    ) {
        self.transport = transport
        self.cache = cache
        self.credentialReader = credentialReader
    }

    convenience init() {
        self.init(transport: HTTPTransport(), cache: Self.sharedCache)
    }

    func titleRatings(
        for item: MediaItem,
        bypassCache: Bool = false
    ) async throws -> MDBListTitleRatings? {
        try Task.checkCancellation()
        guard let key = try credentialReader()
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
              !key.isEmpty else {
            return nil
        }

        let route = try Self.lookupRoute(for: item)
        let credentialScope = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        let response = try await cache.value(for: route, credentialScope: credentialScope, bypassCache: bypassCache) { [self] in
            try await fetchRatings(for: route, key: key)
        }
        // A completed request may outlive the key that authorized it.
        guard try credentialReader()?.trimmingCharacters(in: .whitespacesAndNewlines) == key else {
            throw CancellationError()
        }
        return response
    }

    private func fetchRatings(
        for route: MDBListLookupRoute,
        key: String
    ) async throws -> MDBListTitleRatings? {
        let url = try requestURL(for: route, key: key)
        let data: Data
        do {
            data = try await transport.data(for: HTTPRequestPolicy(
                url: url,
                allowedOrigin: Self.origin,
                timeout: Self.requestTimeout,
                maximumResponseBytes: Self.maximumResponseBytes,
                acceptedContentTypes: ["application/json"]
            ))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as HTTPTransportError {
            throw Self.metadataError(for: error)
        } catch {
            throw MDBListMetadataError.temporarilyUnavailable
        }
        try Task.checkCancellation()
        guard data.count <= Self.maximumResponseBytes else {
            throw MDBListMetadataError.responseTooLarge
        }

        do {
            return try JSONDecoder().decode(MDBListTitleRatings.self, from: data)
        } catch {
            throw MDBListMetadataError.malformedResponse
        }
    }

    /// A lightweight, authenticated lookup used by the settings connection
    /// check. TMDB's Fight Club ID is stable and no result is written locally.
    func verifyStoredCredential() async throws {
        let placeholder = MediaItem(
            id: "verification",
            title: "",
            year: "",
            kind: .movie,
            overview: "",
            genres: [],
            symbol: "film",
            artworkColors: [.clear],
            metadataProvider: .tmdb,
            metadataProviderID: "550",
            externalIDs: ["tmdb": "550"],
            progress: nil
        )
        _ = try await titleRatings(for: placeholder)
    }

    static func lookupRoute(for item: MediaItem) throws -> MDBListLookupRoute {
        let mediaType: MDBListLookupRoute.MediaType = item.kind == .movie ? .movie : .show
        let candidates: [(MDBListLookupRoute.Provider, [String?])] = [
            (
                .tmdb,
                [
                    item.externalIDs["tmdb"],
                    item.externalIDs["tmdb_id"],
                    item.metadataProvider == .tmdb ? item.metadataProviderID : nil
                ]
            ),
            (
                .tvdb,
                [
                    item.externalIDs["tvdb"],
                    item.externalIDs["tvdb_id"],
                    item.metadataProvider == .tvdb ? item.metadataProviderID : nil
                ]
            ),
            (
                .imdb,
                [item.externalIDs["imdb"], item.externalIDs["imdb_id"]]
            )
        ]

        for (provider, identifiers) in candidates {
            for candidate in identifiers.compactMap({ $0 }) {
                if let identifier = Self.validIdentifier(candidate, provider: provider) {
                    return MDBListLookupRoute(
                        provider: provider,
                        mediaType: mediaType,
                        identifier: identifier
                    )
                }
            }
        }
        throw MDBListMetadataError.noSupportedIdentifier
    }

    private func requestURL(for route: MDBListLookupRoute, key: String) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.mdblist.com"
        components.path = "/\(route.provider.rawValue)/\(route.mediaType.rawValue)/\(route.identifier)"
        components.queryItems = [URLQueryItem(name: "apikey", value: key)]
        guard let url = components.url else { throw MDBListMetadataError.malformedResponse }
        return url
    }

    private static func validIdentifier(
        _ source: String,
        provider: MDBListLookupRoute.Provider
    ) -> String? {
        let value = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let expression: String
        switch provider {
        case .tmdb, .tvdb:
            expression = #"^[1-9][0-9]{0,19}$"#
        case .imdb:
            expression = #"^tt[0-9]{5,12}$"#
        }
        guard value.range(of: expression, options: .regularExpression) != nil else { return nil }
        return value
    }

    private static func metadataError(for error: HTTPTransportError) -> Error {
        switch error {
        case let .unsuccessfulStatus(status) where status == 401 || status == 403:
            MDBListMetadataError.authenticationRequired
        case .unsuccessfulStatus(404):
            MDBListMetadataError.notFound
        case .unsuccessfulStatus(429):
            MDBListMetadataError.rateLimited
        case .unsuccessfulStatus, .timedOut, .transportFailure:
            MDBListMetadataError.temporarilyUnavailable
        case .responseTooLarge:
            MDBListMetadataError.responseTooLarge
        case .cancelled:
            CancellationError()
        case .httpsRequired, .originRejected, .redirectRejected,
             .invalidResponse, .unsupportedContentType:
            MDBListMetadataError.malformedResponse
        }
    }
}

nonisolated struct MDBListLookupRoute: Hashable, Sendable {
    enum Provider: String, Hashable, Sendable {
        case tmdb
        case tvdb
        case imdb
    }

    enum MediaType: String, Hashable, Sendable {
        case movie
        case show
    }

    let provider: Provider
    let mediaType: MediaType
    let identifier: String
}

nonisolated enum MDBListMetadataError: Error, Equatable, LocalizedError, Sendable {
    case noSupportedIdentifier
    case authenticationRequired
    case rateLimited
    case notFound
    case temporarilyUnavailable
    case malformedResponse
    case responseTooLarge

    var errorDescription: String? {
        switch self {
        case .noSupportedIdentifier:
            "This title has no supported identifier for MDBList ratings."
        case .authenticationRequired:
            "MDBList could not authenticate this API key."
        case .rateLimited:
            "The MDBList request limit was reached."
        case .notFound:
            "MDBList has no ratings for this title."
        case .temporarilyUnavailable:
            "MDBList ratings are temporarily unavailable."
        case .malformedResponse:
            "MDBList returned an invalid response."
        case .responseTooLarge:
            "The MDBList response was too large."
        }
    }
}

nonisolated struct MDBListTitleRatings: Decodable, Hashable, Sendable {
    let score: Double?
    let ratings: [MDBListRating]

    init(score: Double? = nil, ratings: [MDBListRating] = []) {
        self.score = score
        self.ratings = ratings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        score = Self.lossyDouble(from: container, key: .score)
            .flatMap(MDBListRatingProviderRegistry.validatedValue)
        // Provider-specific rating payloads evolve independently. The overall
        // MDBList score remains useful even if an individual provider's
        // optional rating object changes shape.
        let decoded = (try? container.decode(
            [LossyMDBListRating].self,
            forKey: .ratings
        )) ?? []
        ratings = decoded.prefix(64).compactMap(\.value)
    }

    private enum CodingKeys: String, CodingKey { case score, ratings }

    private static func lossyDouble(
        from container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Double? {
        if let value = try? container.decode(Double.self, forKey: key) { return value }
        if let text = try? container.decode(String.self, forKey: key) { return Double(text) }
        return nil
    }
}

nonisolated struct MDBListRating: Decodable, Hashable, Sendable {
    let providerID: MDBListRatingProviderID
    let value: Double
    let votes: Int?

    private enum CodingKeys: String, CodingKey { case source, value, votes }

    init(providerID: MDBListRatingProviderID, value: Double, votes: Int? = nil) {
        self.providerID = providerID
        self.value = value
        self.votes = votes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let source = try container.decode(String.self, forKey: .source)
        guard let providerID = MDBListRatingProviderID(source),
              let decodedValue = Self.lossyDouble(from: container, key: .value),
              let value = MDBListRatingProviderRegistry.validatedValue(decodedValue) else {
            throw MDBListMetadataError.malformedResponse
        }
        self.providerID = providerID
        self.value = value
        votes = Self.lossyInt(from: container, key: .votes)
    }

    private static func lossyDouble(
        from container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Double? {
        if let value = try? container.decode(Double.self, forKey: key) { return value }
        if let text = try? container.decode(String.self, forKey: key) { return Double(text) }
        return nil
    }

    private static func lossyInt(
        from container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Int? {
        if let value = try? container.decode(Int.self, forKey: key), value >= 0 { return value }
        if let text = try? container.decode(String.self, forKey: key),
           let value = Int(text), value >= 0 { return value }
        return nil
    }
}

private nonisolated struct LossyMDBListRating: Decodable {
    let value: MDBListRating?

    init(from decoder: Decoder) throws {
        value = try? MDBListRating(from: decoder)
    }
}

/// AniList's public GraphQL API provides anime discovery without a key. If a
/// user connects their AniList account, the optional Keychain token is sent as
/// a Bearer token only to AniList so account-specific lists can be added later.
@MainActor
final class AniListMetadataClient {
    private let session: URLSession
    private let endpoint = URL(string: "https://graphql.anilist.co")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func searchAnime(query: String, page: Int = 1, perPage: Int = 24) async throws -> [MediaItem] {
        let document = """
        query SearchAnime($search: String, $page: Int, $perPage: Int) {
          Page(page: $page, perPage: $perPage) {
            media(search: $search, type: ANIME, sort: SEARCH_MATCH) {
              id
              idMal
              format
              description(asHtml: false)
              genres
              startDate { year }
              title { userPreferred english romaji }
              coverImage { large }
              bannerImage
            }
          }
        }
        """
        let response: AniListGraphQLResponse<AniListSearchData> = try await request(document: document, variables: [
            "search": query,
            "page": page,
            "perPage": perPage
        ])
        return response.data.page.media.compactMap(Self.mediaItem(from:))
    }

    /// AniList owns the anime-native browse path. This stays a public request
    /// until a user elects to connect an account; an optional bearer token is
    /// still read solely from the Keychain by `request` below.
    func catalogAnime(
        category: MetadataCatalogCategory,
        genre: String? = nil,
        page: Int = 1,
        perPage: Int = 24
    ) async throws -> [MediaItem] {
        let sort: String
        let statusFilter: String
        switch category {
        case .trending:
            sort = "TRENDING_DESC"
            statusFilter = ""
        case .popular:
            sort = "POPULARITY_DESC"
            statusFilter = ""
        case .topRated:
            sort = "SCORE_DESC"
            statusFilter = ""
        case .airingToday:
            sort = "POPULARITY_DESC"
            statusFilter = ", status: RELEASING"
        case .nowPlaying, .upcoming:
            sort = "START_DATE_DESC"
            statusFilter = ""
        }

        let document = """
        query DiscoverAnime($page: Int, $perPage: Int, $genre: String) {
          Page(page: $page, perPage: $perPage) {
            media(type: ANIME, genre: $genre, sort: [\(sort)]\(statusFilter)) {
              id
              idMal
              format
              description(asHtml: false)
              genres
              startDate { year }
              title { userPreferred english romaji }
              coverImage { large }
              bannerImage
            }
          }
        }
        """
        let response: AniListGraphQLResponse<AniListSearchData> = try await request(document: document, variables: [
            "page": page,
            "perPage": perPage,
            "genre": genre ?? NSNull()
        ])
        return response.data.page.media.compactMap(Self.mediaItem(from:))
    }

    /// Confirms an optional user token without surfacing it in UI or logs.
    func viewerName() async throws -> String {
        let document = "query { Viewer { name } }"
        let response: AniListGraphQLResponse<AniListViewerData> = try await request(document: document, variables: [:])
        return response.data.viewer.name
    }

    private func request<Response: Decodable>(document: String, variables: [String: Any]) async throws -> Response {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = try ProviderCredentialStore.value(for: .anilist), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": document, "variables": variables])

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ProviderMetadataError.invalidResponse }
        guard 200 ..< 300 ~= response.statusCode else { throw ProviderMetadataError.httpStatus(response.statusCode) }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded
    }

    private static func mediaItem(from media: AniListMedia) -> MediaItem? {
        guard let artworkURL = media.coverImage.large.flatMap(URL.init(string:)) else { return nil }
        let title = media.title.userPreferred ?? media.title.english ?? media.title.romaji ?? "Untitled"
        let kind: MediaItem.Kind = media.format == "MOVIE" ? .movie : .series
        let overview = media.description?
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression) ?? "No overview is available yet."
        var externalIDs = ["anilist": String(media.id)]
        if let idMal = media.idMal { externalIDs["mal"] = String(idMal) }
        return MediaItem(
            id: "anilist:\(media.id)",
            title: title,
            year: media.startDate.year.map(String.init) ?? "—",
            kind: kind,
            overview: overview,
            genres: media.genres,
            symbol: "play.tv.fill",
            artworkColors: MediaItem.placeholderArtworkColors,
            artworkURL: artworkURL,
            backdropURL: media.bannerImage.flatMap(URL.init(string:)),
            metadataProvider: .anilist,
            metadataProviderID: String(media.id),
            externalIDs: externalIDs,
            progress: nil
        )
    }
}

enum ProviderMetadataError: LocalizedError {
    case invalidRequest
    case invalidResponse
    case httpStatus(Int)
    case noSupportedIdentifier

    var errorDescription: String? {
        switch self {
        case .invalidRequest: "The provider request could not be created."
        case .invalidResponse: "The provider returned an invalid response."
        case .httpStatus: "The provider could not complete the request."
        case .noSupportedIdentifier: "This title has no provider identifier for ratings."
        }
    }
}

private struct AniListGraphQLResponse<DataPayload: Decodable>: Decodable {
    let data: DataPayload
}

private struct AniListSearchData: Decodable {
    let page: AniListPage

    enum CodingKeys: String, CodingKey { case page = "Page" }
}

private struct AniListPage: Decodable {
    let media: [AniListMedia]
}

private struct AniListMedia: Decodable {
    let id: Int
    let idMal: Int?
    let format: String?
    let description: String?
    let genres: [String]
    let startDate: AniListDate
    let title: AniListTitle
    let coverImage: AniListCoverImage
    let bannerImage: String?
}

private struct AniListDate: Decodable { let year: Int? }
private struct AniListTitle: Decodable { let userPreferred: String?; let english: String?; let romaji: String? }
private struct AniListCoverImage: Decodable { let large: String? }
private struct AniListViewerData: Decodable { let viewer: AniListViewer }
private struct AniListViewer: Decodable { let name: String }
