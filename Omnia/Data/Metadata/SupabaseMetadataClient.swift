//
//  SupabaseMetadataClient.swift
//  Omnia
//

import Foundation

/// Public configuration placed in the app at build time. This is intentionally
/// limited to the project's URL and publishable key; provider secrets remain in
/// the Supabase Edge Function.
nonisolated struct SupabaseConfiguration: Sendable, Equatable {
    let projectURL: URL
    let publishableKey: String

    init(projectURL: URL, publishableKey: String) {
        self.projectURL = projectURL
        self.publishableKey = publishableKey
    }

    static func load(from bundle: Bundle = .main) -> Self? {
        guard
            let urlString = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let projectURL = URL(string: urlString),
            projectURL.scheme == "https",
            projectURL.host != nil,
            !urlString.contains("$("),
            let publishableKey = bundle.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String,
            !publishableKey.isEmpty
        else {
            return nil
        }
        return .init(projectURL: projectURL, publishableKey: publishableKey)
    }
}

nonisolated enum SupabaseMetadataError: LocalizedError, Sendable {
    case invalidResponse
    case server(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Omnia received an invalid metadata response."
        case let .server(_, message):
            return message
        }
    }
}

nonisolated struct OmniaMetadataRecord: Codable, Identifiable, Hashable, Sendable {
    let canonicalKey: String
    let provider: String
    let providerID: String
    let type: String
    let title: String
    let originalTitle: String?
    let overview: String?
    let releaseDate: String?
    let posterPath: String?
    let backdropPath: String?
    let logoPath: String?
    /// Genre names are resolved by the metadata provider for title details.
    /// Catalog cards may omit them until the title is opened or featured.
    let genres: [String]?
    let externalIDs: [String: String]
    let sourceURL: URL?
    let metadataRecordID: UUID?
    let details: OmniaTitleDetails?

    var id: String { canonicalKey }
}

nonisolated struct OmniaMetadataCredit: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let role: String?
    let character: String?
    let profilePath: String?
}

nonisolated struct OmniaMetadataStudio: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let logoPath: String?
}

nonisolated struct OmniaMetadataCollection: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let members: [OmniaMetadataRecord]
}

nonisolated struct OmniaMetadataEpisode: Codable, Hashable, Sendable {
    let id: String
    let seasonNumber: Int
    let episodeNumber: Int
    let title: String
    let overview: String?
    let runtimeMinutes: Int?
    let stillPath: String?
    let airDate: String?
}

nonisolated struct OmniaMetadataSeason: Codable, Hashable, Sendable {
    let id: String
    let seasonNumber: Int
    let title: String
    let overview: String?
    let posterPath: String?
    let episodes: [OmniaMetadataEpisode]
}

nonisolated struct OmniaMetadataVideo: Codable, Hashable, Sendable {
    let id: String
    let title: String
    let type: String
    let site: String
    let key: String
    let official: Bool
    let publishedAt: String?
}

nonisolated struct OmniaTitleDetails: Codable, Hashable, Sendable {
    let ageRating: String?
    let runtimeMinutes: Int?
    let status: String?
    let budget: Int?
    let revenue: Int?
    let studios: [OmniaMetadataStudio]
    let cast: [OmniaMetadataCredit]
    let crew: [OmniaMetadataCredit]
    let studioTitles: [OmniaMetadataRecord]
    let collection: OmniaMetadataCollection?
    let recommendations: [OmniaMetadataRecord]
    let seasons: [OmniaMetadataSeason]
    let trailers: [OmniaMetadataVideo]
    let bonusContent: [OmniaMetadataVideo]
    // Detail payload version 5 (Nuvio detail page parity); absent in
    // responses from an older metadata function.
    let productionCompanies: [OmniaMetadataStudio]?
    let networks: [OmniaMetadataStudio]?
    let creators: [OmniaMetadataCredit]?
    let originCountries: [String]?
    let originalLanguage: String?
    let releaseDate: String?
    let similar: [OmniaMetadataRecord]?
    let recommendationsHaveMore: Bool?
    let similarHaveMore: Bool?
}

/// A person's page: biography and the titles they worked on.
nonisolated struct OmniaPersonDetails: Codable, Hashable, Sendable {
    struct Credit: Codable, Hashable, Sendable {
        let item: OmniaMetadataRecord
        let character: String?
        let job: String?
    }

    let id: String
    let name: String
    let biography: String?
    let birthday: String?
    let deathday: String?
    let placeOfBirth: String?
    let knownForDepartment: String?
    let profilePath: String?
    let imdbID: String?
    let cast: [Credit]
    let crew: [Credit]
}

nonisolated struct MetadataPersonResponse: Codable, Sendable {
    let person: OmniaPersonDetails
}

nonisolated enum MetadataEntityKind: String, Codable, Sendable {
    case company
    case network
}

nonisolated enum MetadataRelatedKind: String, Codable, Sendable {
    case recommendations
    case similar
}

nonisolated struct OmniaMetadataEntity: Codable, Hashable, Sendable {
    let id: String
    let kind: MetadataEntityKind
    let name: String
    let logoPath: String?
    let headquarters: String?
    let originCountry: String?
}

/// One page of a company's, network's or related list.
nonisolated struct MetadataPagedResponse: Codable, Sendable {
    let entity: OmniaMetadataEntity?
    let results: [OmniaMetadataRecord]
    let page: Int
    let totalPages: Int
}

nonisolated struct MetadataSearchResponse: Codable, Sendable {
    let results: [OmniaMetadataRecord]
    let providers: [String]
}

nonisolated struct MetadataDetailResponse: Codable, Sendable {
    let item: OmniaMetadataRecord
    let cached: Bool
}

/// A provider-owned discovery category. The API returns this list so the
/// client never needs to embed a parallel, potentially stale genre taxonomy.
nonisolated struct MetadataGenre: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
}

nonisolated struct MetadataGenresResponse: Codable, Sendable {
    let genres: [MetadataGenre]
    let providers: [String]
}

/// The small API client keeps Omnia's metadata transport independent from the
/// eventual Supabase Auth SDK integration. The published key only unlocks
/// read-only built-in discovery; user-owned data is handled separately with RLS.
actor SupabaseMetadataClient {
    private let configuration: SupabaseConfiguration
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(configuration: SupabaseConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func search(
        query: String,
        type: MediaType,
        routing: MetadataRoute? = nil,
        accessToken: String? = nil,
        language: String = "en-US"
    ) async throws -> MetadataSearchResponse {
        let request = MetadataRequest.search(
            query: query,
            type: type,
            providers: providerIdentifiers(for: routing),
            language: language
        )
        return try await invoke(request, accessToken: accessToken)
    }

    func catalog(
        type: MediaType,
        category: MetadataCatalogCategory = .trending,
        genreID: Int? = nil,
        page: Int = 1,
        routing: MetadataRoute? = nil,
        accessToken: String? = nil,
        language: String = "en-US"
    ) async throws -> MetadataSearchResponse {
        let request = MetadataRequest.catalog(
            type: type,
            category: category,
            genreID: genreID,
            page: page,
            providers: providerIdentifiers(for: routing),
            language: language
        )
        return try await invoke(request, accessToken: accessToken)
    }

    /// AniList is handled directly by `AniListMetadataClient`; the protected
    /// metadata function only receives providers it can actually serve. Do
    /// not add a companion provider here: an omitted fallback must remain
    /// omitted all the way to the request boundary.
    private func providerIdentifiers(for routing: MetadataRoute?) -> [String]? {
        guard let routing else { return nil }
        let identifiers = routing.requestedProviders
            .filter(\.isServedByMetadataService)
            .map(\.rawValue)
        return identifiers.isEmpty ? nil : identifiers
    }

    func genres(
        type: MediaType,
        accessToken: String? = nil,
        language: String = "en-US"
    ) async throws -> MetadataGenresResponse {
        try await invoke(.genres(type: type, language: language), accessToken: accessToken)
    }

    func details(
        provider: MetadataProviderIdentifier,
        id: String,
        type: MediaType,
        accessToken: String? = nil,
        language: String = "en-US",
        modules: TMDBEnrichmentPreferences? = nil
    ) async throws -> MetadataDetailResponse {
        if let modules {
            let data = try await OnDeviceMetadataService.shared.detailResponse(provider: provider.rawValue, id: id, type: type.rawValue, language: language, modules: modules)
            return try decoder.decode(MetadataDetailResponse.self, from: data)
        }
        let request = MetadataRequest.details(provider: provider, id: id, type: type, language: language)
        return try await invoke(request, accessToken: accessToken)
    }

    func findTVDB(imdbID: String, type: MediaType) async throws -> MetadataSearchResponse {
        let data = try await OnDeviceMetadataService.shared.findTVDB(imdbID: imdbID, type: type.rawValue)
        return try decoder.decode(MetadataSearchResponse.self, from: data)
    }

    func findTMDB(externalID: String, source: String, type: MediaType, language: String = "en-US") async throws -> MetadataSearchResponse {
        let data = try await OnDeviceMetadataService.shared.findTMDB(externalID: externalID, source: source, type: type.rawValue, language: language)
        return try decoder.decode(MetadataSearchResponse.self, from: data)
    }

    func person(id: String, language: String = "en-US") async throws -> MetadataPersonResponse {
        try await invoke(.person(id: id, language: language), accessToken: nil)
    }

    func entity(
        kind: MetadataEntityKind,
        id: String,
        type: MediaType,
        page: Int,
        language: String = "en-US"
    ) async throws -> MetadataPagedResponse {
        try await invoke(.entity(kind: kind, id: id, type: type, page: page, language: language), accessToken: nil)
    }

    func related(
        kind: MetadataRelatedKind,
        id: String,
        type: MediaType,
        page: Int,
        language: String = "en-US"
    ) async throws -> MetadataPagedResponse {
        try await invoke(.related(kind: kind, id: id, type: type, page: page, language: language), accessToken: nil)
    }

    /// TMDB and TVDB requests run on this device with the user's own keys
    /// (Dafa, 2026-10-26); Omnia's server and its shared keys are no longer
    /// asked. Requests and answers keep the server's JSON, so callers are
    /// unchanged.
    private func invoke<Response: Decodable>(
        _ body: MetadataRequest,
        accessToken: String?
    ) async throws -> Response {
        let data: Data
        do {
            data = try await OnDeviceMetadataService.shared.handle(try encoder.encode(body))
        } catch let error as OnDeviceMetadataError {
            throw SupabaseMetadataError.server(statusCode: 0, message: error.errorDescription ?? "Metadata is unavailable.")
        }
        return try decoder.decode(Response.self, from: data)
    }
}

nonisolated enum MediaType: String, Codable, Sendable {
    case movie
    case series
}

nonisolated enum MetadataCatalogCategory: String, Codable, CaseIterable, Sendable {
    case trending
    case popular
    case nowPlaying = "now_playing"
    case upcoming
    case topRated = "top_rated"
    case airingToday = "airing_today"
}

nonisolated private enum MetadataRequest: Encodable, Sendable {
    case search(query: String, type: MediaType, providers: [String]?, language: String)
    case catalog(type: MediaType, category: MetadataCatalogCategory, genreID: Int?, page: Int, providers: [String]?, language: String)
    case genres(type: MediaType, language: String)
    case details(provider: MetadataProviderIdentifier, id: String, type: MediaType, language: String)
    case person(id: String, language: String)
    case entity(kind: MetadataEntityKind, id: String, type: MediaType, page: Int, language: String)
    case related(kind: MetadataRelatedKind, id: String, type: MediaType, page: Int, language: String)

    private enum CodingKeys: String, CodingKey {
        case action, query, type, language, provider, providers, id, category, genreID = "genre_id", page, kind
    }

    private enum Action: String, Encodable {
        case search, catalog, genres, details, person, entity, related
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .search(query, type, providers, language):
            try container.encode(Action.search, forKey: .action)
            try container.encode(query, forKey: .query)
            try container.encode(type, forKey: .type)
            try container.encodeIfPresent(providers, forKey: .providers)
            try container.encode(language, forKey: .language)
        case let .catalog(type, category, genreID, page, providers, language):
            try container.encode(Action.catalog, forKey: .action)
            try container.encode(type, forKey: .type)
            try container.encode(category, forKey: .category)
            try container.encodeIfPresent(genreID, forKey: .genreID)
            try container.encode(page, forKey: .page)
            try container.encodeIfPresent(providers, forKey: .providers)
            try container.encode(language, forKey: .language)
        case let .genres(type, language):
            try container.encode(Action.genres, forKey: .action)
            try container.encode(type, forKey: .type)
            try container.encode(language, forKey: .language)
        case let .details(provider, id, type, language):
            try container.encode(Action.details, forKey: .action)
            try container.encode(provider, forKey: .provider)
            try container.encode(id, forKey: .id)
            try container.encode(type, forKey: .type)
            try container.encode(language, forKey: .language)
        case let .person(id, language):
            try container.encode(Action.person, forKey: .action)
            try container.encode(id, forKey: .id)
            try container.encode(language, forKey: .language)
        case let .entity(kind, id, type, page, language):
            try container.encode(Action.entity, forKey: .action)
            try container.encode(kind, forKey: .kind)
            try container.encode(id, forKey: .id)
            try container.encode(type, forKey: .type)
            try container.encode(page, forKey: .page)
            try container.encode(language, forKey: .language)
        case let .related(kind, id, type, page, language):
            try container.encode(Action.related, forKey: .action)
            try container.encode(kind, forKey: .kind)
            try container.encode(id, forKey: .id)
            try container.encode(type, forKey: .type)
            try container.encode(page, forKey: .page)
            try container.encode(language, forKey: .language)
        }
    }
}
