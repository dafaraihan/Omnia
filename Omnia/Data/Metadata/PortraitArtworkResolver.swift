//
//  PortraitArtworkResolver.swift
//  Omnia
//

import Foundation

/// Finds a title's textless poster ("No Language" on TMDB) for the iPhone's
/// portrait hero, where the logo is drawn over the art instead. Asks TMDB,
/// then fanart.tv, with the keys from Settings › Integrations; without
/// either there is no textless poster and the hero crops the backdrop.
actor PortraitArtworkResolver {
    static let shared = PortraitArtworkResolver()

    private let session: URLSession
    /// Answers by title, including "none", so a hero rotating through its
    /// titles asks TMDB once per title.
    private var cache: [String: URL?] = [:]
    private let cacheLimit = 200

    init(session: URLSession = .shared) {
        self.session = session
    }

    func textlessPoster(for item: MediaItem) async -> URL? {
        let kind = item.kind == .movie ? "movie" : "tv"
        let cacheKey = "\(kind):\(item.id)"
        if let cached = cache[cacheKey] { return cached }
        let tmdbKey = Self.key("tmdb")
        let fanartKey = Self.key("fanart")
        guard tmdbKey != nil || fanartKey != nil else { return nil }

        var tmdbID: String?
        var poster: URL?
        if let key = tmdbKey {
            tmdbID = await self.tmdbID(for: item, kind: kind, key: key)
            poster = await tmdbPoster(tmdbID: tmdbID, kind: kind, key: key)
        }
        if poster == nil, let fanartKey {
            poster = await fanartPoster(for: item, kind: kind, tmdbID: tmdbID, key: fanartKey)
        }
        guard !Task.isCancelled else { return nil }
        if cache.count >= cacheLimit { cache.removeAll() }
        cache[cacheKey] = poster
        return poster
    }

    /// Settings' Test Connection: fanart.tv answers a known title.
    func verifyFanartKey() async throws {
        guard let key = Self.key("fanart") else { throw URLError(.userAuthenticationRequired) }
        _ = try await fanart("/movies/603", key: key)
    }

    private func tmdbPoster(tmdbID: String?, kind: String, key: String) async -> URL? {
        var poster: URL?
        if let tmdbID,
           let images = try? await request("/\(kind)/\(tmdbID)/images", query: ["include_image_language": "null"], key: key),
           let posters = images["posters"] as? [[String: Any]] {
            // Highest rated first, as TMDB's own image picker orders them.
            let best = posters
                .filter { $0["iso_639_1"] == nil || $0["iso_639_1"] is NSNull }
                .max { score($0) < score($1) }
            if let path = best?["file_path"] as? String, path.hasPrefix("/") {
                poster = URL(string: "https://image.tmdb.org/t/p/w780\(path)")
            }
        }
        return poster
    }

    /// fanart.tv marks textless art with the language "00". Movies are found
    /// by TMDB or IMDb ID, shows only by TVDB ID.
    private func fanartPoster(for item: MediaItem, kind: String, tmdbID: String?, key: String) async -> URL? {
        let path: String
        let type: String
        if kind == "movie" {
            let imdb = (item.externalIDs["imdb"] ?? item.externalIDs["imdb_id"] ?? (item.id.hasPrefix("tt") ? item.id : nil))?
                .split(separator: ":").first.map(String.init)
            guard let id = tmdbID ?? Self.number(item.externalIDs["tmdb"] ?? item.externalIDs["tmdb_id"])
                ?? imdb.flatMap({ $0.hasPrefix("tt") && $0.dropFirst(2).allSatisfy(\.isNumber) ? $0 : nil })
            else { return nil }
            path = "/movies/\(id)"
            type = "movieposter"
        } else {
            let tvdb = Self.number(item.externalIDs["tvdb"] ?? item.externalIDs["tvdb_id"])
                ?? (item.metadataProvider == .tvdb ? Self.number(item.metadataProviderID) : nil)
            guard let tvdb else { return nil }
            path = "/tv/\(tvdb)"
            type = "tvposter"
        }
        guard let response = try? await fanart(path, key: key),
              let images = response[type] as? [[String: Any]]
        else { return nil }
        let best = images
            .filter { ($0["lang"] as? String) == "00" }
            .max { Int($0["likes"] as? String ?? "") ?? 0 < Int($1["likes"] as? String ?? "") ?? 0 }
        guard let address = best?["url"] as? String, let url = URL(string: address), url.scheme == "https" else {
            return nil
        }
        return url
    }

    private func fanart(_ path: String, key: String) async throws -> [String: Any] {
        guard var components = URLComponents(string: "https://webservice.fanart.tv/v3\(path)") else {
            throw URLError(.badURL)
        }
        // A personal key is fanart.tv's client_key, accepted on its own.
        components.queryItems = [URLQueryItem(name: "client_key", value: key)]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw URLError(.badServerResponse) }
        return object
    }

    private func tmdbID(for item: MediaItem, kind: String, key: String) async -> String? {
        if let id = Self.number(item.externalIDs["tmdb"] ?? item.externalIDs["tmdb_id"]) { return id }
        if item.metadataProvider == .tmdb, let id = Self.number(item.metadataProviderID) { return id }
        // Add-on titles usually carry only an IMDb ID.
        guard let imdb = (item.externalIDs["imdb"] ?? item.externalIDs["imdb_id"] ?? (item.id.hasPrefix("tt") ? item.id : nil))?
            .split(separator: ":").first.map(String.init),
            imdb.hasPrefix("tt"), imdb.dropFirst(2).allSatisfy(\.isNumber),
            let found = try? await request("/find/\(imdb)", query: ["external_source": "imdb_id"], key: key),
            let match = (found[kind == "movie" ? "movie_results" : "tv_results"] as? [[String: Any]])?.first,
            let id = match["id"] as? Int
        else { return nil }
        return String(id)
    }

    private func score(_ image: [String: Any]) -> Double {
        let average = image["vote_average"] as? Double ?? 0
        let count = image["vote_count"] as? Double ?? Double(image["vote_count"] as? Int ?? 0)
        return average * 10 + count
    }

    private func request(_ path: String, query: [String: String], key: String) async throws -> [String: Any] {
        guard var components = URLComponents(string: "https://api.themoviedb.org/3\(path)") else {
            throw URLError(.badURL)
        }
        var items = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        let isReadToken = key.hasPrefix("eyJ")
        if !isReadToken { items.append(URLQueryItem(name: "api_key", value: key)) }
        components.queryItems = items
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if isReadToken { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw URLError(.badServerResponse) }
        return object
    }

    private static func number(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == ":" || $0 == "/" }).last.map(String.init),
            !value.isEmpty, value.allSatisfy(\.isNumber)
        else { return nil }
        return value
    }

    /// The Keychain entries Settings › Integrations saves.
    private static func key(_ provider: String) -> String? {
        guard let value = try? KeychainStore.value(account: "provider.\(provider).credential")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
        else { return nil }
        return value
    }
}
