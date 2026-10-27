//
//  TrackerClient.swift
//  Omnia
//
//  Trakt, Simkl and MDBList requests, after Nuvio's TraktAuthRepository,
//  TraktScrobbleRepository, SimklAuthRepository, SimklMutationRepository,
//  MdbListAuthRepository and MdbListScrobbleService (NuvioMedia/NuvioMobile,
//  GPL-3.0). PublicMetaDB requests follow its External API reference
//  (publicmetadb.com/api-docs); AniList's its OAuth implicit grant.
//

import Foundation

/// The app a tracker was connected with and the user's tokens. Kept
/// together as one Keychain item per tracker. Accounts connected before
/// Omnia had built-in apps keep the user's own app details here.
nonisolated struct TrackerCredentials: Codable, Equatable, Sendable {
    var clientID: String
    var clientSecret: String?
    var accessToken: String?
    var refreshToken: String?
    var expiresAt: Date?
    /// The account's name, for "Connected as".
    var username: String?

    var isConnected: Bool { accessToken?.isEmpty == false }
}

/// Omnia's own registered tracker apps, built in from Config/Secrets.xcconfig
/// through Info.plist (OmniaTrackerApps), as Nuvio builds in its own.
nonisolated enum TrackerAppCredentials {
    private static var apps: [String: String] {
        Bundle.main.object(forInfoDictionaryKey: "OmniaTrackerApps") as? [String: String] ?? [:]
    }

    private static func value(_ key: String) -> String? {
        let value = apps[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // An unset build setting can arrive empty or as its own `$(NAME)`.
        return value.isEmpty || value.hasPrefix("$(") ? nil : value
    }

    /// The app to sign in with, or nil when this build doesn't have one.
    static func app(for kind: TrackerKind) -> TrackerCredentials? {
        switch kind {
        case .trakt:
            // Trakt's new apps get no secret: sign-in is PKCE or the device
            // code, which need only the client ID. Older apps may still have
            // one; it's sent only when set.
            guard let id = value("TraktClientID") else { return nil }
            return TrackerCredentials(clientID: id, clientSecret: value("TraktClientSecret"))
        case .simkl:
            return value("SimklClientID").map { TrackerCredentials(clientID: $0) }
        case .mdblist:
            return value("MDBListClientID").map { TrackerCredentials(clientID: $0) }
        case .anilist:
            return value("AniListClientID").map { TrackerCredentials(clientID: $0) }
        case .pmdb:
            return TrackerCredentials(clientID: "")
        }
    }

    /// The redirect URI Omnia's Trakt app was created with, which Trakt
    /// requires (exactly) when refreshing a token. The device code sign-in
    /// never opens it.
    static var traktRedirectURI: String {
        value("TraktRedirectURI") ?? "urn:ietf:wg:oauth:2.0:oob"
    }
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
    private static let mdblistBase = URL(string: "https://api.mdblist.com")!
    /// Where AniList returns after sign-in; registered on Omnia's AniList app.
    static let anilistRedirect = URL(string: "omnia://anilist")!
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
            // Connected with a key or in the browser; see `validateAPIKey`
            // and `anilistAuthorizationURL`.
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
        case .mdblist:
            return try await deviceAuthorization(
                oauthForm(mdblistBase, "oauth/device-authorization/", ["client_id": clientID, "scope": "write"]),
                host: "mdblist.com"
            )
        case .simkl:
            // Simkl AUTH V2's device flow, which every app type may use.
            return try await deviceAuthorization(
                oauthForm(simklBase, "oauth2/device", ["client_id": clientID, "scope": "media:read media:write"]),
                host: "simkl.com"
            )
        }
    }

    static func poll(_ kind: TrackerKind, code: TrackerDeviceCode, app: TrackerCredentials) async -> TrackerPollResult {
        do {
            switch kind {
            case .trakt:
                var body: [String: Any] = ["code": code.pollingCode, "client_id": app.clientID]
                if let secret = app.clientSecret, !secret.isEmpty { body["client_secret"] = secret }
                let request = traktRequest("oauth/device/token", clientID: app.clientID, body: body)
                let (data, status) = try await send(request, accepting: [200, 400, 404, 409, 410, 418, 429])
                switch status {
                case 200:
                    return .connected(app.with(try decode(OAuthTokenResponse.self, from: data)))
                case 400: return .pending
                case 429: return .slowDown
                case 418: return .failed("You declined the request on Trakt.")
                case 410: return .failed("The code expired. Try again.")
                default: return .failed("Trakt didn't accept the code. Try again.")
                }
            case .simkl:
                return try await pollDeviceToken(oauthForm(simklBase, "oauth2/token", [
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                    "device_code": code.pollingCode,
                    "client_id": app.clientID
                ]), app: app, title: kind.title)
            case .mdblist:
                return try await pollDeviceToken(oauthForm(mdblistBase, "oauth/token/", [
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                    "device_code": code.pollingCode,
                    "client_id": app.clientID,
                    "scope": "write"
                ]), app: app, title: kind.title)
            case .pmdb, .anilist:
                return .failed("\(kind.title) connects with a key or in the browser.")
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

    /// Trakt, Simkl (AUTH V2) and MDBList tokens expire and are refreshed
    /// shortly before; PublicMetaDB's keys and AniList's (a year) tokens, and
    /// Simkl's older V1 tokens, are used as they are.
    static func refreshIfNeeded(_ kind: TrackerKind, _ credentials: TrackerCredentials) async throws -> TrackerCredentials {
        // Trakt's tokens last 7 days and each refresh token works once.
        guard [.trakt, .simkl, .mdblist].contains(kind), let expiresAt = credentials.expiresAt,
              expiresAt.timeIntervalSinceNow < (kind == .mdblist ? 120 : 86_400),
              let refreshToken = credentials.refreshToken
        else { return credentials }
        let request: URLRequest
        if kind == .trakt {
            var body: [String: Any] = [
                "refresh_token": refreshToken,
                "client_id": credentials.clientID,
                "redirect_uri": TrackerAppCredentials.traktRedirectURI,
                "grant_type": "refresh_token"
            ]
            if let secret = credentials.clientSecret, !secret.isEmpty { body["client_secret"] = secret }
            request = traktRequest("oauth/token", clientID: credentials.clientID, body: body)
        } else {
            request = oauthForm(kind == .simkl ? simklBase : mdblistBase, kind == .simkl ? "oauth2/token" : "oauth/token/", [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": credentials.clientID
            ])
        }
        let (data, _) = try await send(request, accepting: [200])
        return credentials.with(try decode(OAuthTokenResponse.self, from: data))
    }

    /// The signed-in account's name, for "Connected as". PublicMetaDB has
    /// no profile endpoint.
    static func username(_ kind: TrackerKind, credentials: TrackerCredentials) async -> String? {
        guard let token = credentials.accessToken else { return nil }
        do {
            switch kind {
            case .trakt:
                var request = traktRequest("users/settings", clientID: credentials.clientID, body: [:])
                request.httpMethod = "GET"
                request.httpBody = nil
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (data, _) = try await send(request, accepting: [200])
                let settings = try decode(TraktUserSettings.self, from: data)
                return settings.user?.username ?? settings.user?.name
            case .simkl:
                var request = simklRequest("users/settings", clientID: credentials.clientID, method: "GET")
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (data, _) = try await send(request, accepting: [200])
                return try decode(SimklUserSettings.self, from: data).user?.name
            case .mdblist:
                var request = URLRequest(url: mdblistBase.appending(path: "user"))
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("\(appName)/\(appVersion)", forHTTPHeaderField: "User-Agent")
                let (data, _) = try await send(request, accepting: [200])
                let user = try decode(MDBListUser.self, from: data)
                return user.username ?? user.name
            case .anilist:
                let viewer: AniListViewerName = try await anilistQuery("query { Viewer { name } }", variables: [:], token: token)
                return viewer.Viewer?.name
            case .pmdb:
                return nil
            }
        } catch {
            return nil
        }
    }

    // MARK: AniList sign-in

    /// AniList's sign-in page for Omnia's app; it returns to omnia://anilist
    /// with the token in the fragment.
    static func anilistAuthorizationURL(clientID: String) -> URL? {
        var components = URLComponents(string: "https://anilist.co/api/v2/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "token")
        ]
        return components?.url
    }

    /// The token in AniList's return link, if this is one.
    static func anilistToken(from url: URL) -> (token: String, expiresIn: TimeInterval?)? {
        guard url.scheme?.lowercased() == anilistRedirect.scheme, url.host?.lowercased() == anilistRedirect.host,
              let fragment = url.fragment ?? URLComponents(url: url, resolvingAgainstBaseURL: false)?.query
        else { return nil }
        var fields: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { fields[parts[0]] = parts[1].removingPercentEncoding ?? parts[1] }
        }
        guard let token = fields["access_token"], !token.isEmpty, token.count <= 4_096 else { return nil }
        return (token, fields["expires_in"].flatMap(TimeInterval.init))
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
        if kind == .mdblist {
            var body = mdblistScrobbleBody(media)
            body["progress"] = progress
            var request = URLRequest(url: mdblistBase.appending(path: "scrobble/\(action.rawValue)"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("\(appName)/\(appVersion)", forHTTPHeaderField: "User-Agent")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            _ = try await send(request, accepting: [200, 201, 204, 409])
            return
        }
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
        case .pmdb, .anilist, .mdblist:
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

    /// MDBList's scrobble body: like Trakt's, but an episode's season and
    /// number sit inside `show`.
    private static func mdblistScrobbleBody(_ media: TrackerMedia) -> [String: Any] {
        var ids: [String: Any] = [:]
        if let imdb = media.imdb { ids["imdb"] = imdb }
        if let tmdb = media.tmdb { ids["tmdb"] = tmdb }
        if let tvdb = media.tvdb { ids["tvdb"] = tvdb }
        switch media.kind {
        case .movie:
            return ["movie": ["ids": ids]]
        case let .episode(season, number):
            return ["show": ["ids": ids, "season": season, "episode": number]]
        }
    }

    /// RFC 8628 device authorization (Simkl AUTH V2, MDBList): the code to
    /// show, and the page it's entered on, which must be the tracker's own.
    private static func deviceAuthorization(_ request: URLRequest, host: String) async throws -> TrackerDeviceCode {
        let (data, _) = try await send(request, accepting: [200])
        let response = try decode(DeviceAuthorizationResponse.self, from: data)
        guard let userCode = response.user_code, !userCode.isEmpty,
              let deviceCode = response.device_code, !deviceCode.isEmpty,
              let url = (response.verification_uri_complete ?? response.verification_uri).flatMap(URL.init(string:)),
              url.scheme == "https", url.host == host
        else { throw TrackerClientError.invalidResponse }
        return TrackerDeviceCode(
            userCode: userCode,
            verificationURL: url,
            pollingCode: deviceCode,
            interval: TimeInterval(min(max(response.interval ?? 5, 5), 60)),
            expiresAt: .now.addingTimeInterval(TimeInterval(min(response.expires_in ?? 600, 1_800)))
        )
    }

    /// One RFC 8628 token poll.
    private static func pollDeviceToken(_ request: URLRequest, app: TrackerCredentials, title: String) async throws -> TrackerPollResult {
        let (data, status) = try await send(request, accepting: [200, 400, 401, 403, 429])
        if status == 200 {
            return .connected(app.with(try decode(OAuthTokenResponse.self, from: data)))
        }
        switch (try? decode(OAuthErrorResponse.self, from: data))?.error {
        case "authorization_pending": return .pending
        case "slow_down": return .slowDown
        case "access_denied": return .failed("You declined the request on \(title).")
        case "expired_token": return .failed("The code expired. Try again.")
        case "invalid_client": return .failed("\(title) didn't recognise Omnia's app. Check its client ID.")
        default: return status == 429 ? .slowDown : .failed("\(title) didn't accept the code. Try again.")
        }
    }

    /// An OAuth form request.
    private static func oauthForm(_ base: URL, _ path: String, _ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("\(appName)/\(appVersion)", forHTTPHeaderField: "User-Agent")
        var components = URLComponents()
        components.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
            .data(using: .utf8)
        return request
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

private nonisolated struct OAuthTokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int?
    let created_at: Int?
}

private nonisolated struct DeviceAuthorizationResponse: Decodable {
    let device_code: String?
    let user_code: String?
    let verification_uri: String?
    let verification_uri_complete: String?
    let expires_in: Int?
    let interval: Int?
}

private nonisolated struct OAuthErrorResponse: Decodable {
    let error: String?
}

private nonisolated struct MDBListUser: Decodable {
    let username: String?
    let name: String?
}

private nonisolated struct TraktUserSettings: Decodable {
    struct User: Decodable {
        let username: String?
        let name: String?
    }
    let user: User?
}

private nonisolated struct SimklUserSettings: Decodable {
    struct User: Decodable { let name: String? }
    let user: User?
}

private nonisolated struct AniListViewerName: Decodable {
    struct Viewer: Decodable { let name: String? }
    let Viewer: Viewer?
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

private extension TrackerCredentials {
    nonisolated func with(_ token: OAuthTokenResponse) -> TrackerCredentials {
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
