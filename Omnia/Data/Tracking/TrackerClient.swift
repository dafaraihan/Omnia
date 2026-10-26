//
//  TrackerClient.swift
//  Omnia
//
//  Trakt and Simkl requests, after Nuvio's TraktAuthRepository,
//  TraktScrobbleRepository, SimklAuthRepository and SimklMutationRepository
//  (NuvioMedia/NuvioMobile, GPL-3.0).
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
        case .http(401), .http(403): "The tracker refused the client ID or the sign-in. Check your app's details."
        case .http(let status): "The tracker answered with HTTP \(status)."
        }
    }
}

nonisolated enum TrackerClient {
    private static let traktBase = URL(string: "https://api.trakt.tv")!
    private static let simklBase = URL(string: "https://api.simkl.com")!
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
            }
        } catch {
            // A dropped request mid-wait is retried on the next tick.
            return .pending
        }
    }

    /// Trakt tokens last three months; Simkl's don't expire.
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
        credentials: TrackerCredentials
    ) async throws {
        guard let token = credentials.accessToken else { return }
        let progress = (min(max(progress, 0), 100) * 100).rounded() / 100
        var body = scrobbleBody(media)
        body["progress"] = progress
        var request: URLRequest
        switch kind {
        case .trakt:
            body["app_version"] = appVersion
            request = traktRequest("scrobble/\(action.rawValue)", clientID: credentials.clientID, body: body)
        case .simkl:
            request = simklRequest("scrobble/\(action.rawValue)", clientID: credentials.clientID, method: "POST", body: body)
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

    private static func send(_ request: URLRequest, accepting statuses: Set<Int>) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw TrackerClientError.invalidResponse }
        guard statuses.contains(status) else { throw TrackerClientError.http(status) }
        return (data, status)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
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
