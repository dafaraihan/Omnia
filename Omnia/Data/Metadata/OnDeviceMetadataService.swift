//
//  OnDeviceMetadataService.swift
//  Omnia
//
//  The metadata Edge Function (supabase/functions/metadata/index.ts) run on
//  this device with the user's own TMDB and TVDB keys (Dafa, 2026-10-26).
//  It answers the same requests with the same JSON, so everything above
//  SupabaseMetadataClient is unchanged. Omnia's shared server keys are no
//  longer used; without a key, TMDB and TVDB are simply unavailable and
//  add-ons such as Cinemeta provide catalogs, details and search.
//

import Foundation

nonisolated enum OnDeviceMetadataError: LocalizedError, Sendable {
    case missingKey(String)
    case invalidRequest
    case provider(Int)
    case unusableResponse

    var errorDescription: String? {
        switch self {
        case .missingKey(let provider):
            "Add your own \(provider) key in Settings › Integrations › Metadata Sources to use \(provider)."
        case .invalidRequest:
            "Invalid metadata request."
        case .provider(let status):
            "The metadata provider answered with HTTP \(status)."
        case .unusableResponse:
            "The metadata provider's answer didn't contain a usable title."
        }
    }
}

actor OnDeviceMetadataService {
    static let shared = OnDeviceMetadataService()

    private typealias JSON = [String: Any]

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        return URLSession(configuration: configuration)
    }()
    private var tvdbToken: (value: String, key: String, expiresAt: Date)?
    /// Title details, kept for a day like the server's record cache.
    private var detailCache: [String: (body: JSON, expiresAt: Date)] = [:]

    /// The user's key, read straight from Keychain under the account
    /// `UserManagedProviderCredential` saves it to.
    private static func storedKey(_ provider: String) -> String? {
        guard let value = try? KeychainStore.value(account: "provider.\(provider).credential")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
        else { return nil }
        return value
    }

    /// Settings' Test Connection: one small request with the stored key.
    func verify(_ provider: MetadataProviderIdentifier) async throws {
        switch provider {
        case .tmdb: _ = try await tmdb("/configuration", language: "en-US")
        case .tvdb:
            tvdbToken = nil
            _ = try await tvdbLoginToken()
        case .anilist: return
        }
    }

    /// Answers one encoded metadata request with the Edge Function's JSON.
    func handle(_ body: Data) async throws -> Data {
        guard let request = try JSONSerialization.jsonObject(with: body) as? JSON,
              let action = request["action"] as? String
        else { throw OnDeviceMetadataError.invalidRequest }
        let language = request["language"] as? String ?? "en-US"
        let type = request["type"] as? String ?? "movie"
        let result: JSON
        switch action {
        case "search":
            let query = (request["query"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard (2...120).contains(query.count) else { throw OnDeviceMetadataError.invalidRequest }
            result = try await fanOut(providers(request)) { provider in
                provider == "tmdb"
                    ? try await self.tmdbSearch(query, type: type, language: language)
                    : try await self.tvdbSearch(query, type: type)
            }
        case "catalog":
            let category = request["category"] as? String ?? "trending"
            let page = request["page"] as? Int ?? 1
            let genreID = request["genre_id"] as? Int
            result = try await fanOut(providers(request)) { provider in
                provider == "tmdb"
                    ? try await self.tmdbCatalog(type: type, category: category, language: language, genreID: genreID, page: page)
                    : try await self.tvdbCatalog(type: type)
            }
        case "genres":
            result = ["genres": try await tmdbGenres(type: type, language: language), "providers": ["tmdb"]]
        case "person":
            result = ["person": try await tmdbPerson(id: try identifier(request), language: language)]
        case "entity":
            let kind = request["kind"] as? String ?? "company"
            guard kind == "company" || kind == "network" else { throw OnDeviceMetadataError.invalidRequest }
            result = try await tmdbEntity(kind: kind, id: try identifier(request), type: type, page: request["page"] as? Int ?? 1, language: language)
        case "related":
            let kind = request["kind"] as? String ?? "recommendations"
            guard kind == "recommendations" || kind == "similar" else { throw OnDeviceMetadataError.invalidRequest }
            result = try await tmdbRelated(id: try identifier(request), type: type, kind: kind, page: request["page"] as? Int ?? 1, language: language)
        case "details":
            guard let id = request["id"] as? String, let provider = request["provider"] as? String,
                  provider == "tmdb" || provider == "tvdb"
            else { throw OnDeviceMetadataError.invalidRequest }
            result = try await details(provider: provider, id: id, type: type, language: language)
        default:
            throw OnDeviceMetadataError.invalidRequest
        }
        return try JSONSerialization.data(withJSONObject: result)
    }

    private func providers(_ request: JSON) -> [String] {
        let requested = (request["providers"] as? [String])?.filter { $0 == "tmdb" || $0 == "tvdb" }
        return requested?.isEmpty == false ? requested! : ["tmdb", "tvdb"]
    }

    private func identifier(_ request: JSON) throws -> String {
        guard let id = request["id"] as? String, id.range(of: #"^\d{1,12}$"#, options: .regularExpression) != nil else {
            throw OnDeviceMetadataError.invalidRequest
        }
        return id
    }

    /// Asks each provider, keeps the ones that answered, and fails only when
    /// none did, like the server's Promise.allSettled.
    private func fanOut(_ providers: [String], _ request: @escaping @Sendable (String) async throws -> [JSON]) async throws -> JSON {
        var answered: [(Int, String, [JSON])] = []
        var firstError: Error?
        await withTaskGroup(of: (Int, String, Result<[JSON], Error>).self) { group in
            for (index, provider) in providers.enumerated() {
                group.addTask {
                    do { return (index, provider, .success(try await request(provider))) }
                    catch { return (index, provider, .failure(error)) }
                }
            }
            for await (index, provider, result) in group {
                switch result {
                case .success(let items): answered.append((index, provider, items))
                case .failure(let error): firstError = firstError ?? error
                }
            }
        }
        guard !answered.isEmpty else { throw firstError ?? OnDeviceMetadataError.unusableResponse }
        answered.sort { $0.0 < $1.0 }
        return ["results": answered.flatMap(\.2), "providers": answered.map(\.1)]
    }

    // MARK: TMDB

    /// A v4 read access token goes in the Authorization header; a v3 API key
    /// goes in the query.
    private func tmdb(_ path: String, language: String, parameters: [String: String] = [:]) async throws -> JSON {
        guard let key = Self.storedKey("tmdb") else { throw OnDeviceMetadataError.missingKey("TMDB") }
        var components = URLComponents(string: "https://api.themoviedb.org/3\(path)")!
        var items = [URLQueryItem(name: "language", value: language)]
        items += parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        let isReadToken = key.hasPrefix("eyJ")
        if !isReadToken { items.append(URLQueryItem(name: "api_key", value: key)) }
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if isReadToken { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        return try await json(request)
    }

    private func tmdbResults(_ payload: JSON, type: String) -> [JSON] {
        Self.records(payload["results"]).compactMap { Self.normalizeTMDB($0, type: type) }
    }

    private func tmdbSearch(_ query: String, type: String, language: String) async throws -> [JSON] {
        let payload = try await tmdb(type == "movie" ? "/search/movie" : "/search/tv", language: language, parameters: [
            "query": query, "include_adult": "false"
        ])
        return Array(tmdbResults(payload, type: type).prefix(20))
    }

    private func tmdbCatalog(type: String, category: String, language: String, genreID: Int?, page: Int) async throws -> [JSON] {
        if let genreID {
            let payload = try await tmdb(type == "movie" ? "/discover/movie" : "/discover/tv", language: language, parameters: [
                "with_genres": String(genreID), "sort_by": "popularity.desc", "include_adult": "false", "page": String(page)
            ])
            return Array(tmdbResults(payload, type: type).prefix(20))
        }
        let endpoint: String
        switch (type, category) {
        case (_, "trending"): endpoint = type == "movie" ? "/trending/movie/week" : "/trending/tv/week"
        case ("movie", "popular"): endpoint = "/movie/popular"
        case ("movie", "now_playing"): endpoint = "/movie/now_playing"
        case ("movie", "upcoming"): endpoint = "/movie/upcoming"
        case ("movie", _): endpoint = "/movie/top_rated"
        case (_, "top_rated"): endpoint = "/tv/top_rated"
        case (_, "airing_today"): endpoint = "/tv/airing_today"
        default: endpoint = "/tv/popular"
        }
        let payload = try await tmdb(endpoint, language: language, parameters: ["page": String(page)])
        return Array(tmdbResults(payload, type: type).prefix(20))
    }

    private func tmdbGenres(type: String, language: String) async throws -> [JSON] {
        let payload = try await tmdb(type == "movie" ? "/genre/movie/list" : "/genre/tv/list", language: language)
        return Self.records(payload["genres"]).compactMap { genre in
            guard let id = genre["id"] as? Int, let name = genre["name"] as? String else { return nil }
            return ["id": id, "name": name]
        }
    }

    private func tmdbPerson(id: String, language: String) async throws -> JSON {
        let value = try await tmdb("/person/\(id)", language: language, parameters: [
            "append_to_response": "combined_credits,external_ids"
        ])
        guard let name = Self.text(value["name"]) else { throw OnDeviceMetadataError.unusableResponse }
        let credits = value["combined_credits"] as? JSON ?? [:]
        func personCredits(_ entries: [JSON], roleKey: String) -> [JSON] {
            var seen = Set<String>()
            return entries
                .filter { ($0["media_type"] as? String) == "movie" || ($0["media_type"] as? String) == "tv" }
                .sorted { Self.number($0["popularity"]) > Self.number($1["popularity"]) }
                .compactMap { entry -> JSON? in
                    guard let item = Self.normalizeTMDB(entry, type: entry["media_type"] as? String == "tv" ? "series" : "movie"),
                          item["posterPath"] != nil, let key = item["canonicalKey"] as? String, seen.insert(key).inserted
                    else { return nil }
                    var credit: JSON = ["item": item]
                    if let role = Self.text(entry[roleKey]) { credit[roleKey == "character" ? "character" : "job"] = role }
                    return credit
                }
                .prefix(60).map { $0 }
        }
        let external = value["external_ids"] as? JSON ?? [:]
        var person: JSON = [
            "id": id,
            "name": name,
            "cast": personCredits(Self.records(credits["cast"]), roleKey: "character"),
            "crew": personCredits(Self.records(credits["crew"]), roleKey: "job")
        ]
        person["biography"] = Self.text(value["biography"])
        person["birthday"] = Self.isoDate(value["birthday"])
        person["deathday"] = Self.isoDate(value["deathday"])
        person["placeOfBirth"] = Self.text(value["place_of_birth"])
        person["knownForDepartment"] = Self.text(value["known_for_department"])
        person["profilePath"] = Self.text(value["profile_path"])
        person["imdbID"] = Self.text(external["imdb_id"])
        return person
    }

    private func tmdbEntity(kind: String, id: String, type: String, page: Int, language: String) async throws -> JSON {
        guard !(kind == "network" && type == "movie") else { throw OnDeviceMetadataError.invalidRequest }
        async let info = tmdb("/\(kind)/\(id)", language: language)
        async let listing = tmdb(type == "movie" ? "/discover/movie" : "/discover/tv", language: language, parameters: [
            kind == "network" ? "with_networks" : "with_companies": id,
            "sort_by": "popularity.desc", "include_adult": "false", "page": String(page)
        ])
        let (entityInfo, entityListing) = try await (info, listing)
        var entity: JSON = ["id": id, "kind": kind, "name": Self.text(entityInfo["name"]) ?? ""]
        entity["logoPath"] = Self.text(entityInfo["logo_path"])
        entity["headquarters"] = Self.text(entityInfo["headquarters"])
        entity["originCountry"] = Self.text(entityInfo["origin_country"])
        return [
            "entity": entity,
            "results": tmdbResults(entityListing, type: type),
            "page": page,
            "totalPages": Self.positiveInteger(entityListing["total_pages"]) ?? 1,
            "providers": ["tmdb"]
        ]
    }

    private func tmdbRelated(id: String, type: String, kind: String, page: Int, language: String) async throws -> JSON {
        let listing = try await tmdb("/\(type == "movie" ? "movie" : "tv")/\(id)/\(kind)", language: language, parameters: [
            "page": String(page)
        ])
        return [
            "results": tmdbResults(listing, type: type),
            "page": page,
            "totalPages": Self.positiveInteger(listing["total_pages"]) ?? 1,
            "providers": ["tmdb"]
        ]
    }

    private func tmdbTitleDetails(_ value: JSON, type: String, language: String, providerID: String) async throws -> JSON {
        let studios = Self.tmdbStudios(value)
        async let studioTitles = tmdbStudioTitles(studios.first, type: type, language: language, excluding: providerID)
        async let collection = type == "movie" ? tmdbCollection(value, language: language) : nil
        async let seasons = type == "series" ? tmdbSeasons(value, language: language, seriesID: providerID) : []
        let credits = Self.tmdbCredits(value, type: type)
        let episodeRuntime = (value["episode_run_time"] as? [Any])?.compactMap { Self.positiveInteger($0) }.first
        let videos = Self.tmdbVideos(value)
        var details: JSON = [
            "studios": studios,
            "cast": credits.cast,
            "crew": credits.crew,
            "studioTitles": try await studioTitles,
            "recommendations": Array(Self.resultList(value["recommendations"], type: type).filter { $0["providerID"] as? String != providerID }.prefix(20)),
            "seasons": try await seasons,
            "trailers": videos.trailers,
            "bonusContent": videos.bonus,
            "productionCompanies": Array(Self.companies(Self.records(value["production_companies"])).prefix(8)),
            "networks": Array(Self.companies(Self.records(value["networks"])).prefix(8)),
            "creators": Self.records(value["created_by"]).compactMap { person -> JSON? in
                guard let id = Self.idString(person["id"]), let name = Self.text(person["name"]) else { return nil }
                var credit: JSON = ["id": id, "name": name, "role": "Creator"]
                credit["profilePath"] = Self.text(person["profile_path"])
                return credit
            },
            "originCountries": Self.originCountries(value),
            "similar": Array(Self.resultList(value["similar"], type: type).filter { $0["providerID"] as? String != providerID }.prefix(20)),
            "recommendationsHaveMore": Self.hasMore(value["recommendations"]),
            "similarHaveMore": Self.hasMore(value["similar"])
        ]
        details["collection"] = try await collection
        details["ageRating"] = Self.ageRating(value, type: type)
        details["runtimeMinutes"] = type == "movie" ? Self.positiveInteger(value["runtime"]) : episodeRuntime
        details["status"] = Self.text(value["status"])
        details["budget"] = Self.positiveInteger(value["budget"])
        details["revenue"] = Self.positiveInteger(value["revenue"])
        details["originalLanguage"] = Self.text(value["original_language"])
        details["releaseDate"] = Self.isoDate(type == "movie" ? value["release_date"] : value["first_air_date"])
        return details
    }

    private func tmdbStudioTitles(_ studio: JSON?, type: String, language: String, excluding providerID: String) async throws -> [JSON] {
        guard let id = studio?["id"] as? String else { return [] }
        let payload = try await tmdb(type == "movie" ? "/discover/movie" : "/discover/tv", language: language, parameters: [
            "with_companies": id, "sort_by": "popularity.desc", "include_adult": "false"
        ])
        return Array(tmdbResults(payload, type: type).filter { $0["providerID"] as? String != providerID }.prefix(16))
    }

    private func tmdbCollection(_ value: JSON, language: String) async throws -> JSON? {
        guard let source = value["belongs_to_collection"] as? JSON,
              let id = Self.idString(source["id"]), let name = Self.text(source["name"])
        else { return nil }
        let payload = try await tmdb("/collection/\(id)", language: language)
        return [
            "id": id,
            "name": name,
            "members": Array(Self.records(payload["parts"]).compactMap { Self.normalizeTMDB($0, type: "movie") }.prefix(20))
        ]
    }

    private func tmdbSeasons(_ value: JSON, language: String, seriesID: String) async throws -> [JSON] {
        let summaries: [JSON] = Self.records(value["seasons"]).compactMap { season in
            guard let number = Self.positiveInteger(season["season_number"]), number >= 1,
                  let id = Self.idString(season["id"]), let title = Self.text(season["name"])
            else { return nil }
            var summary: JSON = ["id": id, "seasonNumber": number, "title": title]
            summary["overview"] = Self.text(season["overview"])
            summary["posterPath"] = Self.text(season["poster_path"])
            return summary
        }
        let limited = Array(summaries.prefix(20))
        var resolved: [(Int, JSON)] = []
        try await withThrowingTaskGroup(of: (Int, JSON).self) { group in
            for (index, summary) in limited.enumerated() {
                let number = summary["seasonNumber"] as? Int ?? 1
                nonisolated(unsafe) let summary = summary
                group.addTask {
                    let payload = try await self.tmdb("/tv/\(seriesID)/season/\(number)", language: language)
                    var season = summary
                    season["episodes"] = Self.records(payload["episodes"]).compactMap { Self.tmdbEpisode($0, fallbackSeason: number) }
                    return (index, season)
                }
            }
            for try await season in group { resolved.append(season) }
        }
        return resolved.sorted { $0.0 < $1.0 }.map(\.1).filter { ($0["episodes"] as? [JSON])?.isEmpty == false }
    }

    // MARK: TVDB

    /// The key, or the key and a subscriber PIN separated by a space.
    private func tvdbLoginToken() async throws -> String {
        guard let stored = Self.storedKey("tvdb") else { throw OnDeviceMetadataError.missingKey("TVDB") }
        if let tvdbToken, tvdbToken.key == stored, tvdbToken.expiresAt > .now { return tvdbToken.value }
        let parts = stored.split(whereSeparator: \.isWhitespace).map(String.init)
        var body: JSON = ["apikey": parts[0]]
        if parts.count > 1 { body["pin"] = parts[1] }
        var request = URLRequest(url: URL(string: "https://api4.thetvdb.com/v4/login")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let payload = try await json(request)
        guard let token = (payload["data"] as? JSON)?["token"] as? String else { throw OnDeviceMetadataError.unusableResponse }
        tvdbToken = (token, stored, Date.now.addingTimeInterval(25 * 86_400))
        return token
    }

    private func tvdb(_ path: String, query: [String: String] = [:]) async throws -> JSON {
        let token = try await tvdbLoginToken()
        var components = URLComponents(string: "https://api4.thetvdb.com/v4\(path)")!
        if !query.isEmpty { components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await json(request)
    }

    private func tvdbSearch(_ query: String, type: String) async throws -> [JSON] {
        let payload = try await tvdb("/search", query: ["query": query, "type": type])
        return Array(Self.records(payload["data"]).compactMap { Self.normalizeTVDB($0, type: type) }.prefix(20))
    }

    private func tvdbCatalog(type: String) async throws -> [JSON] {
        let payload = try await tvdb(type == "movie" ? "/movies/filter" : "/series/filter", query: [
            "country": "usa", "lang": "eng", "sort": "score", "sortType": "desc"
        ])
        return Array(Self.records(payload["data"]).compactMap { Self.normalizeTVDB($0, type: type) }.prefix(20))
    }

    // MARK: Details

    private func details(provider: String, id: String, type: String, language: String) async throws -> JSON {
        let key = "\(provider):\(type):\(id):\(language)"
        if let cached = detailCache[key], cached.expiresAt > .now { return ["item": cached.body, "cached": true] }
        let item: JSON
        if provider == "tmdb" {
            let raw = try await tmdb("/\(type == "movie" ? "movie" : "tv")/\(id)", language: language, parameters: [
                "append_to_response": type == "movie"
                    ? "images,external_ids,credits,similar,recommendations,release_dates,videos"
                    : "images,external_ids,aggregate_credits,similar,recommendations,content_ratings,videos",
                "include_image_language": "\(language.split(separator: "-").first ?? "en"),null"
            ])
            guard var normalized = Self.normalizeTMDB(raw, type: type) else { throw OnDeviceMetadataError.unusableResponse }
            normalized["details"] = try await tmdbTitleDetails(raw, type: type, language: language, providerID: normalized["providerID"] as? String ?? id)
            item = normalized
        } else {
            let raw = try await tvdb("/\(type == "movie" ? "movies" : "series")/\(id)/extended")
            guard let data = raw["data"] as? JSON, let normalized = Self.normalizeTVDB(data, type: type) else {
                throw OnDeviceMetadataError.unusableResponse
            }
            item = normalized
        }
        detailCache[key] = (item, Date.now.addingTimeInterval(86_400))
        return ["item": item, "cached": false]
    }

    private func json(_ request: URLRequest) async throws -> JSON {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw OnDeviceMetadataError.provider(status) }
        guard let object = try JSONSerialization.jsonObject(with: data) as? JSON else { throw OnDeviceMetadataError.unusableResponse }
        return object
    }

    // MARK: Normalizing, as in index.ts

    private static func normalizeTMDB(_ value: JSON, type: String) -> JSON? {
        guard let providerID = idString(value["id"]),
              let title = (type == "movie" ? value["title"] : value["name"]) as? String
        else { return nil }
        var item: JSON = [
            "canonicalKey": "tmdb:\(type):\(providerID)",
            "provider": "tmdb",
            "providerID": providerID,
            "type": type,
            "title": title,
            "genres": namedValues(value["genres"]),
            "externalIDs": tmdbExternalIDs(value, providerID: providerID),
            "sourceURL": "https://www.themoviedb.org/\(type == "movie" ? "movie" : "tv")/\(providerID)"
        ]
        item["originalTitle"] = text(type == "movie" ? value["original_title"] : value["original_name"])
        item["overview"] = text(value["overview"])
        item["releaseDate"] = isoDate(type == "movie" ? value["release_date"] : value["first_air_date"])
        item["posterPath"] = text(value["poster_path"])
        item["backdropPath"] = text(value["backdrop_path"])
        item["logoPath"] = tmdbLogoPath(value)
        return item
    }

    private static func tmdbLogoPath(_ value: JSON, language: String = "en") -> String? {
        let logos = records((value["images"] as? JSON)?["logos"])
        let match = logos.first { $0["iso_639_1"] as? String == language }
            ?? logos.first { $0["iso_639_1"] is NSNull || $0["iso_639_1"] == nil }
            ?? logos.first
        return text(match?["file_path"])
    }

    private static func tmdbExternalIDs(_ value: JSON, providerID: String) -> [String: String] {
        var identifiers = ["tmdb": providerID]
        guard let external = value["external_ids"] as? JSON else { return identifiers }
        for key in ["imdb_id", "tvdb_id", "wikidata_id"] {
            guard let identifier = text(external[key]) ?? (external[key] as? Int).map(String.init) else { continue }
            identifiers[key == "imdb_id" ? "imdb" : key.replacingOccurrences(of: "_id", with: "")] = identifier
        }
        return identifiers
    }

    private static func normalizeTVDB(_ value: JSON, type: String) -> JSON? {
        guard let providerID = idString(value["tvdb_id"] ?? value["id"] ?? value["objectID"]),
              let title = (value["name"] ?? value["seriesName"] ?? value["movieName"]) as? String
        else { return nil }
        var item: JSON = [
            "canonicalKey": "tvdb:\(type):\(providerID)",
            "provider": "tvdb",
            "providerID": providerID,
            "type": type,
            "title": title,
            "genres": namedValues(value["genres"]),
            "externalIDs": tvdbExternalIDs(providerID: providerID, remoteIDs: value["remoteIds"]),
            "sourceURL": "https://thetvdb.com/\(type == "movie" ? "movies" : "series")/\(providerID)"
        ]
        item["overview"] = text(value["overview"])
        item["releaseDate"] = isoDate(value["firstAired"] ?? value["year"])
        item["posterPath"] = text(value["image_url"] ?? value["image"])
        item["backdropPath"] = text(value["thumbnail"])
        return item
    }

    private static func tvdbExternalIDs(providerID: String, remoteIDs: Any?) -> [String: String] {
        var identifiers = ["tvdb": providerID]
        for remote in records(remoteIDs) {
            guard let identifier = (remote["id"] as? String)?.trimmingCharacters(in: .whitespaces), !identifier.isEmpty else { continue }
            let source = (remote["sourceName"] as? String ?? "").lowercased().filter { $0.isLetter || $0.isNumber }
            if identifiers["imdb"] == nil, source.contains("imdb") || identifier.range(of: #"^tt\d+$"#, options: [.regularExpression, .caseInsensitive]) != nil {
                identifiers["imdb"] = identifier
            } else if identifiers["tmdb"] == nil, source == "tmdb" || source.contains("themoviedb") {
                identifiers["tmdb"] = identifier
            }
        }
        return identifiers
    }

    private static func tmdbCredits(_ value: JSON, type: String) -> (cast: [JSON], crew: [JSON]) {
        let container = ((type == "series" ? value["aggregate_credits"] : value["credits"]) ?? value["credits"]) as? JSON ?? [:]
        let cast: [JSON] = records(container["cast"]).compactMap { person in
            guard let id = idString(person["id"]), let name = text(person["name"]) else { return nil }
            var credit: JSON = ["id": id, "name": name]
            credit["character"] = text(person["character"]) ?? text(records(person["roles"]).first?["character"])
            credit["profilePath"] = text(person["profile_path"])
            return credit
        }
        let crew: [JSON] = records(container["crew"]).compactMap { person in
            guard let id = idString(person["id"]), let name = text(person["name"]) else { return nil }
            let roles = records(person["jobs"] ?? person["roles"])
            var credit: JSON = ["id": id, "name": name]
            credit["role"] = text(person["job"]) ?? text(roles.first?["job"]) ?? text(roles.first?["character"])
            credit["profilePath"] = text(person["profile_path"])
            return credit
        }
        return (Array(cast.prefix(18)), crew)
    }

    private static func tmdbStudios(_ value: JSON) -> [JSON] {
        let sources = records(value["production_companies"])
        return Array(companies(sources.isEmpty ? records(value["networks"]) : sources).prefix(4))
    }

    private static func companies(_ values: [JSON]) -> [JSON] {
        values.compactMap { company in
            guard let id = idString(company["id"]), let name = text(company["name"]) else { return nil }
            var studio: JSON = ["id": id, "name": name]
            studio["logoPath"] = text(company["logo_path"])
            return studio
        }
    }

    private static func tmdbEpisode(_ value: JSON, fallbackSeason: Int) -> JSON? {
        guard let id = idString(value["id"]), let number = positiveInteger(value["episode_number"]),
              let title = text(value["name"])
        else { return nil }
        var episode: JSON = [
            "id": id,
            "seasonNumber": positiveInteger(value["season_number"]) ?? fallbackSeason,
            "episodeNumber": number,
            "title": title
        ]
        episode["overview"] = text(value["overview"])
        episode["runtimeMinutes"] = positiveInteger(value["runtime"])
        episode["stillPath"] = text(value["still_path"])
        episode["airDate"] = isoDate(value["air_date"])
        return episode
    }

    private static func tmdbVideos(_ value: JSON) -> (trailers: [JSON], bonus: [JSON]) {
        let videos: [JSON] = records((value["videos"] as? JSON)?["results"]).compactMap { video in
            guard let id = idString(video["id"]), let title = text(video["name"]), let type = text(video["type"]),
                  let site = text(video["site"]), let key = text(video["key"]), site.lowercased() == "youtube"
            else { return nil }
            var item: JSON = ["id": id, "title": title, "type": type, "site": site, "key": key, "official": video["official"] as? Bool == true]
            item["publishedAt"] = isoDate(video["published_at"])
            return item
        }
        .sorted { ($0["official"] as? Bool == true ? 1 : 0) > ($1["official"] as? Bool == true ? 1 : 0) }
        let bonusTypes: Set<String> = ["Behind the Scenes", "Featurette", "Bloopers", "Clip"]
        return (
            Array(videos.filter { ["Trailer", "Teaser"].contains($0["type"] as? String ?? "") }.prefix(12)),
            Array(videos.filter { bonusTypes.contains($0["type"] as? String ?? "") }.prefix(12))
        )
    }

    private static func ageRating(_ value: JSON, type: String) -> String? {
        if type == "movie" {
            let results = records((value["release_dates"] as? JSON)?["results"])
            let preferred = results.first { $0["iso_3166_1"] as? String == "US" } ?? results.first
            return records(preferred?["release_dates"]).compactMap { text($0["certification"]) }.first
        }
        let results = records((value["content_ratings"] as? JSON)?["results"])
        let preferred = results.first { $0["iso_3166_1"] as? String == "US" } ?? results.first
        return text(preferred?["rating"])
    }

    private static func originCountries(_ value: JSON) -> [String] {
        let named = records(value["production_countries"]).compactMap { text($0["iso_3166_1"]) }
        let codes = (value["origin_country"] as? [String] ?? []).filter { !$0.isEmpty }
        var seen = Set<String>()
        return Array((codes + named).filter { seen.insert($0).inserted }.prefix(4))
    }

    private static func resultList(_ value: Any?, type: String) -> [JSON] {
        records((value as? JSON)?["results"]).compactMap { normalizeTMDB($0, type: type) }
    }

    private static func hasMore(_ value: Any?) -> Bool {
        (positiveInteger((value as? JSON)?["total_pages"]) ?? 1) > 1
    }

    private static func records(_ value: Any?) -> [JSON] {
        (value as? [Any])?.compactMap { $0 as? JSON } ?? []
    }

    private static func namedValues(_ value: Any?) -> [String] {
        records(value).compactMap { text($0["name"]) }
    }

    private static func text(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }

    private static func idString(_ value: Any?) -> String? {
        if let number = value as? Int { return String(number) }
        return text(value)
    }

    private static func isoDate(_ value: Any?) -> String? {
        let date = text(value) ?? (value as? Int).map(String.init)
        guard let date, date.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil else { return nil }
        return String(date.prefix(10))
    }

    private static func positiveInteger(_ value: Any?) -> Int? {
        guard let number = (value as? NSNumber)?.doubleValue, number.isFinite, number > 0 else { return nil }
        return Int(number.rounded())
    }

    private static func number(_ value: Any?) -> Double {
        (value as? NSNumber)?.doubleValue ?? 0
    }
}
