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
        accessToken: String? = nil,
        language: String = "en-US"
    ) async throws -> MetadataSearchResponse {
        let request = MetadataRequest.search(query: query, type: type, language: language)
        return try await invoke(request, accessToken: accessToken)
    }

    func catalog(
        type: MediaType,
        category: MetadataCatalogCategory = .trending,
        genreID: Int? = nil,
        page: Int = 1,
        accessToken: String? = nil,
        language: String = "en-US"
    ) async throws -> MetadataSearchResponse {
        let request = MetadataRequest.catalog(type: type, category: category, genreID: genreID, page: page, language: language)
        return try await invoke(request, accessToken: accessToken)
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
        language: String = "en-US"
    ) async throws -> MetadataDetailResponse {
        let request = MetadataRequest.details(provider: provider, id: id, type: type, language: language)
        return try await invoke(request, accessToken: accessToken)
    }

    private func invoke<Response: Decodable>(
        _ body: MetadataRequest,
        accessToken: String?
    ) async throws -> Response {
        let endpoint = configuration.projectURL
            .appending(path: "functions")
            .appending(path: "v1")
            .appending(path: "metadata")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        if let accessToken, !accessToken.isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, urlResponse) = try await session.data(for: request)
        guard let response = urlResponse as? HTTPURLResponse else {
            throw SupabaseMetadataError.invalidResponse
        }
        guard 200 ..< 300 ~= response.statusCode else {
            let message = (try? decoder.decode(MetadataErrorEnvelope.self, from: data))?.error.message
                ?? "Metadata is temporarily unavailable."
            throw SupabaseMetadataError.server(statusCode: response.statusCode, message: message)
        }
        return try decoder.decode(Response.self, from: data)
    }
}

nonisolated enum MetadataProviderIdentifier: String, Codable, Sendable {
    case tmdb
    case tvdb
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
    case search(query: String, type: MediaType, language: String)
    case catalog(type: MediaType, category: MetadataCatalogCategory, genreID: Int?, page: Int, language: String)
    case genres(type: MediaType, language: String)
    case details(provider: MetadataProviderIdentifier, id: String, type: MediaType, language: String)

    private enum CodingKeys: String, CodingKey {
        case action, query, type, language, provider, id, category, genreID = "genre_id", page
    }

    private enum Action: String, Encodable {
        case search, catalog, genres, details
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .search(query, type, language):
            try container.encode(Action.search, forKey: .action)
            try container.encode(query, forKey: .query)
            try container.encode(type, forKey: .type)
            try container.encode(language, forKey: .language)
        case let .catalog(type, category, genreID, page, language):
            try container.encode(Action.catalog, forKey: .action)
            try container.encode(type, forKey: .type)
            try container.encode(category, forKey: .category)
            try container.encodeIfPresent(genreID, forKey: .genreID)
            try container.encode(page, forKey: .page)
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
        }
    }
}

nonisolated private struct MetadataErrorEnvelope: Decodable {
    struct Payload: Decodable {
        let message: String
    }

    let error: Payload
}
