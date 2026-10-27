//
//  TrackerClient.swift
//  Omnia
//
//  Trakt and Simkl requests, after Nuvio's TraktAuthRepository,
//  TraktScrobbleRepository, SimklAuthRepository and SimklMutationRepository
//  (NuvioMedia/NuvioMobile, GPL-3.0). PublicMetaDB requests follow its
//  External API reference (publicmetadb.com/api-docs).
//

import Foundation

/// The user's own API app and, once connected, their tokens. Kept together
/// as one Keychain item per tracker.
nonisolated struct TrackerCredentials: Codable, Equatable, Sendable {
    var clientID: String
    var clientSecret: String?
    var accessToken: String?
    var refreshToken: String?
    var expiresAt: Date?

    var isConnected: Bool { accessToken?.isEmpty == false }
}

/// A code the user enters on the tracker's site to connect Omnia.
nonisolated struct TrackerDeviceCode: Equatable, Sendable {
    let userCode: String
    let verificationURL: URL
    /// Trakt's device code; Simkl polls with the user code itself.
    let pollingCode: String
    let interval: TimeInterval
    let expiresAt: Date
}

nonisolated enum TrackerPollResult: Sendable {
    case pending
    case slowDown
    case connected(TrackerCredentials)
    case failed(String)
}

nonisolated enum TrackerClientError: LocalizedError {
    case invalidResponse
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The tracker sent an answer Omnia couldn't read."
        case .http(401), .http(403): "The tracker refused the sign-in. Check your app's details or API key."
        case .http(let status): "The tracker answered with HTTP \(status)."
        }
    }
}

nonisolated enum TrackerClient {
    private static let traktBase = URL(string: "https://api.trakt.tv")!
    private static let simklBase = URL(string: "https://api.simkl.com")!
    private static let pmdbBase = URL(string: "https://publicmetadb.com/api/external")!
    private static let anilistBase = URL(string: "https://graphql.anilist.co")!
    private static let appName = "Omnia"
    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        return URLSession(configuration: configuration)
    }()

    // MARK: Connecting

    static func requestDeviceCode(_ kind: TrackerKind, clientID: String) async throws -> TrackerDeviceCode {
        switch kind {
        case .pmdb, .anilist:
            // Connected with a key or pasted token; see `validateAPIKey`.
            throw TrackerClientError.invalidResponse
        case .trakt:
            let (data, _) = try await send(
                traktRequest("oauth/device/code", clientID: clientID, body: ["client_id": clientID]),
                accepting: [200]
            )
            let response = try decode(TraktDeviceCodeResponse.self, from: data)
            guard let url = URL(string: response.verification_url) else { throw TrackerClientError.invalidResponse }
            return TrackerDeviceCode(
                userCode: response.user_code,
                verificationURL: url,
                pollingCode: response.device_code,
                interval: TimeInterval(max(response.interval, 5)),
                expiresAt: .now.addingTimeInterval(TimeInterval(response.expires_in))
            )
        case .simkl:
            let (data, _) = try await send(simklRequest("oauth/pin", clientID: clientID, method: "GET"), accepting: [200])
            let response = try decode(SimklPinResponse.self, from: data)
            guard !response.user_code.isEmpty else { throw TrackerClientError.invalidResponse }
            return TrackerDeviceCode(
                userCode: response.user_code,
                verificationURL: URL(string: response.verification_url ?? "") ?? URL(string: "https://simkl.com/pin")!,
                pollingCode: response.user_code,
                interval: TimeInterval(max(response.interval ?? 5, 5)),
                expiresAt: .now.addingTimeInterval(TimeInterval(response.expires_in ?? 900))
            )
        }
    }

    static func poll(_ kind: TrackerKind, code: TrackerDeviceCode, app: TrackerCredentials) async -> TrackerPollResult {
        do {
            switch kind {
            case .trakt:
                let request = traktRequest("oauth/device/token", clientID: app.clientID, body: [
                    "code": code.pollingCode,
                    "client_id": app.clientID,
                    "client_secret": app.clientSecret ?? ""
                ])
                let (data, status) = try await send(request, accepting: [200, 400, 404, 409, 410, 418, 429])
                switch status {
                case 200:
                    return .connected(app.with(try decode(TraktTokenResponse.self, from: data)))
                case 400: return .pending
                case 429: return .slowDown
                case 418: return .failed("You declined the request on Trakt.")
                case 410: return .failed("The code expired. Try again.")
                default: return .failed("Trakt didn't accept the code. Check your Client ID and Secret.")
                }
            case .simkl:
                let (data, _) = try await send(
                    simklRequest("oauth/pin/\(code.pollingCode)", clientID: app.clientID, method: "GET"),
                    accepting: [200]
                )
                let response = try decode(SimklPinPollResponse.self, from: data)
                guard response.result?.uppercased() == "OK", let token = response.access_token, !token.isEmpty else {
                    return .pending
                }
                var connected = app
                connected.accessToken = token
                return .connected(connected)
            case .pmdb, .anilist:
                return .failed("\(kind.title) connects with a key or token.")
            }
        } catch {
            // A dropped request mid-wait is retried on the next tick.
            return .pending
        }
    }

    /// Checks a PublicMetaDB key by listing one of the user's lists, or an
    /// AniList token by asking who it belongs to.
    static func validateAPIKey(_ kind: TrackerKind, _ key: String) async throws {
        switch kind {
        case .anilist:
            let viewer: AniListViewerID = try await anilistQuery("query { Viewer { id } }", variables: [:], token: key)
            guard viewer.Viewer?.id != nil else { throw TrackerClientError.http(401) }
        default:
            _ = try await send(pmdbRequest("lists", key: key, query: ["perPage": "1"]), accepting: [200])
        }
    }

    /// Trakt tokens last three months; Simkl's and PublicMetaDB's keys
    /// don't expire.
    static func refreshIfNeeded(_ kind: TrackerKind, _ credentials: TrackerCredentials) async throws -> TrackerCredentials {
        guard kind == .trakt, let expiresAt = credentials.expiresAt, expiresAt.timeIntervalSinceNow < 86_400,
              let refreshToken = credentials.refreshToken
        else { return credentials }
        let request = traktRequest("oauth/token", clientID: credentials.clientID, body: [
            "refresh_token": refreshToken,
            "client_id": credentials.clientID,
            "client_secret": credentials.clientSecret ?? "",
            "redirect_uri": "urn:ietf:wg:oauth:2.0:oob",
            "grant_type": "refresh_token"
        ])
        let (data, _) = try await send(request, accepting: [200])
        return credentials.with(try decode(TraktTokenResponse.self, from: data))
    }

    // MARK: Scrobbling

    static func scrobble(
        _ kind: TrackerKind,
        action: TrackerScrobbleAction,
        media: TrackerMedia,
        progress: Double,
        runtimeSeconds: Double?,
        credentials: TrackerCredentials
    ) async throws {
        guard let token = credentials.accessToken else { return }
        let progress = (min(max(progress, 0), 100) * 100).rounded() / 100
        if kind == .anilist {
            try await updateAniList(action: action, media: media, progress: progress, token: token)
            return
        }
        guard media.hasVideoIdentifier else { return }
        if kind == .pmdb {
            try await savePMDBResume(action: action, media: media, progress: progress, runtimeSeconds: runtimeSeconds, key: token)
            return
        }
        var body = scrobbleBody(media)
        body["progress"] = progress
        var request: URLRequest
        switch kind {
        case .trakt:
            body["app_version"] = appVersion
            request = traktRequest("scrobble/\(action.rawValue)", clientID: credentials.clientID, body: body)
        case .simkl:
            request = simklRequest("scrobble/\(action.rawValue)", clientID: credentials.clientID, method: "POST", body: body)
        case .pmdb, .anilist:
            return
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // 409: already scrobbled a moment ago, which is fine.
        _ = try await send(request, accepting: [200, 201, 204, 409])
    }

    /// Trakt and Simkl take the same shape: a movie, or a show with an
    /// episode, each with its IDs.
    private static func scrobbleBody(_ media: TrackerMedia) -> [String: Any] {
        var ids: [String: Any] = [:]
        if let imdb = media.imdb { ids["imdb"] = imdb }
        if let tmdb = media.tmdb { ids["tmdb"] = tmdb }
        if let tvdb = media.tvdb { ids["tvdb"] = tvdb }
        var item: [String: Any] = ["title": media.title, "ids": ids]
        if let year = media.year { item["year"] = year }
        switch media.kind {
        case .movie:
            return ["movie": item]
        case let .episode(season, number):
            return ["show": item, "episode": ["season": season, "number": number]]
        }
    }

    /// PublicMetaDB has no scrobble: it keeps resume points, saved on pause
    /// and stop as its reference asks (not during playback). A save at 80%
    /// or more clears the point and answers "completed", and the title is
    /// then logged as watched.
    private static func savePMDBResume(
        action: TrackerScrobbleAction,
        media: TrackerMedia,
        progress: Double,
        runtimeSeconds: Double?,
        key: String
    ) async throws {
        guard action != .start, let runtimeSeconds, runtimeSeconds > 0, var body = pmdbBody(media) else { return }
        let runtime = Int((runtimeSeconds * 1000).rounded())
        body["runtime_ms"] = runtime
        body["position_ms"] = Int((Double(runtime) * progress / 100).rounded())
        let (data, _) = try await send(pmdbRequest("resume", key: key, method: "POST", body: body), accepting: [200, 201])
        guard (try? decode(PMDBResumeSaveResponse.self, from: data))?.action == "completed",
              let watched = pmdbBody(media)
        else { return }
        _ = try await send(pmdbRequest("watched", key: key, method: "POST", body: watched), accepting: [200, 201])
    }

    /// AniList keeps a count of episodes watched, not live playback: an
    /// episode or film stopped past 80% moves the anime's list entry on,
    /// and the last episode completes it.
    private static func updateAniList(action: TrackerScrobbleAction, media: TrackerMedia, progress: Double, token: String) async throws {
        guard action == .stop, progress >= 80, media.anilist != nil || media.mal != nil else { return }
        let lookup: AniListMediaLookup = try await anilistQuery(
            media.anilist != nil
                ? "query ($id: Int) { Media(id: $id, type: ANIME) { id episodes } }"
                : "query ($id: Int) { Media(idMal: $id, type: ANIME) { id episodes } }",
            variables: ["id": media.anilist ?? media.mal ?? 0],
            token: token
        )
        guard let anime = lookup.Media else { return }
        let watched: Int
        switch media.kind {
        case .movie: watched = anime.episodes ?? 1
        case let .episode(_, number): watched = number
        }
        let completed = anime.episodes.map { watched >= $0 } ?? false
        let _: AniListSaved = try await anilistQuery(
            "mutation ($mediaId: Int, $progress: Int, $status: MediaListStatus) { SaveMediaListEntry(mediaId: $mediaId, progress: $progress, status: $status) { id } }",
            variables: ["mediaId": anime.id, "progress": watched, "status": completed ? "COMPLETED" : "CURRENT"],
            token: token
        )
    }

    /// One AniList GraphQL request with the user's token.
    static func anilistQuery<T: Decodable>(_ document: String, variables: [String: Any], token: String) async throws -> T {
        var request = URLRequest(url: anilistBase)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("\(appName)/\(appVersion)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": document, "variables": variables])
        let (data, _) = try await send(request, accepting: [200])
        guard let payload = try decode(AniListPayload<T>.self, from: data).data else { throw TrackerClientError.invalidResponse }
        return payload
    }

    /// PublicMetaDB matches on TMDB IDs, or on an IMDb ID it maps itself.
    private static func pmdbBody(_ media: TrackerMedia) -> [String: Any]? {
        var body: [String: Any]
        if let tmdb = media.tmdb {
            body = ["tmdb_id": tmdb]
        } else if let imdb = media.imdb {
            body = ["id_type": "imdb", "id_value": imdb]
        } else if let tvdb = media.tvdb {
            body = ["id_type": "tvdb", "id_value": String(tvdb)]
        } else {
            return nil
        }
        switch media.kind {
        case .movie:
            body["media_type"] = "movie"
        case let .episode(season, number):
            body["media_type"] = "tv"
            body["season"] = season
            body["episode"] = number
        }
        return body
    }

    // MARK: Requests

    private static func traktRequest(_ path: String, clientID: String, body: [String: Any]) -> URLRequest {
        var request = URLRequest(url: traktBase.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        request.setValue(clientID, forHTTPHeaderField: "trakt-api-key")
        request.setValue("\(appName)/\(appVersion)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func simklRequest(
        _ path: String,
        clientID: String,
        method: String,
        body: [String: Any]? = nil
    ) -> URLRequest {
        var components = URLComponents(url: simklBase.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "app-name", value: appName),
            URLQueryItem(name: "app-version", value: appVersion)
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(clientID, forHTTPHeaderField: "simkl-api-key")
        request.setValue("\(appName)/\(appVersion)", forHTTPHeaderField: "User-Agent")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    static func pmdbRequest(
        _ path: String,
        key: String,
        method: String = "GET",
        query: [String: String] = [:],
        body: [String: Any]? = nil
    ) -> URLRequest {
        var components = URLComponents(url: pmdbBase.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("\(appName)/\(appVersion)", forHTTPHeaderField: "User-Agent")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    static func send(_ request: URLRequest, accepting statuses: Set<Int>) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw TrackerClientError.invalidResponse }
        guard statuses.contains(status) else { throw TrackerClientError.http(status) }
        return (data, status)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) } catch { throw TrackerClientError.invalidResponse }
    }
}

// MARK: Wire formats

private nonisolated struct TraktDeviceCodeResponse: Decodable {
    let device_code: String
    let user_code: String
    let verification_url: String
    let expires_in: Int
    let interval: Int
}

private nonisolated struct TraktTokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int?
    let created_at: Int?
}

private nonisolated struct SimklPinResponse: Decodable {
    let user_code: String
    let verification_url: String?
    let expires_in: Int?
    let interval: Int?
}

private nonisolated struct AniListPayload<T: Decodable>: Decodable {
    let data: T?
}

private nonisolated struct AniListViewerID: Decodable {
    struct Viewer: Decodable { let id: Int? }
    let Viewer: Viewer?
}

private nonisolated struct AniListMediaLookup: Decodable {
    struct Media: Decodable {
        let id: Int
        let episodes: Int?
    }
    let Media: Media?
}

private nonisolated struct AniListSaved: Decodable {
    struct Entry: Decodable { let id: Int? }
    let SaveMediaListEntry: Entry?
}

private nonisolated struct PMDBResumeSaveResponse: Decodable {
    let action: String?
}

private nonisolated struct SimklPinPollResponse: Decodable {
    let result: String?
    let access_token: String?
}

private extension TrackerCredentials {
    nonisolated func with(_ token: TraktTokenResponse) -> TrackerCredentials {
        var copy = self
        copy.accessToken = token.access_token
        copy.refreshToken = token.refresh_token ?? refreshToken
        if let expiresIn = token.expires_in {
            let created = token.created_at.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? .now
            copy.expiresAt = created.addingTimeInterval(TimeInterval(expiresIn))
        }
        return copy
    }
}
