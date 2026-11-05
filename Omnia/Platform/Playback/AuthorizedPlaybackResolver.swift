//
//  AuthorizedPlaybackResolver.swift
//  Omnia
//

import Foundation

/// User-owned authorization for a playback resolver. This is deliberately
/// separate from metadata credentials: it is sent only to the resolver URL
/// chosen by the user and never leaves the device through Omnia's cloud sync.
enum PlaybackResolverCredentialStore {
    private static let keychainAccount = "playback.resolver.authorization"

    static func authorizationToken() throws -> String? {
        try KeychainStore.value(account: keychainAccount)
    }

    static func deleteAuthorizationToken() throws {
        try KeychainStore.delete(account: keychainAccount)
    }

    static var hasAuthorizationToken: Bool {
        guard let value = try? authorizationToken() else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Settings stored locally because they identify a user-operated service. The
/// resolver's bearer token is Keychain-only; endpoint and allow-lists contain
/// no credential and are never synced as library data.
enum PlaybackResolverSettings {
    static let endpointKey = "playback-resolver-endpoint"
    static let approvedAddonIDsKey = "playback-resolver-approved-addon-ids"
    static let approvedStreamHostsKey = "playback-resolver-approved-stream-hosts"

    @MainActor
    static func configuration(defaults: UserDefaults = .standard) throws -> AuthorizedPlaybackResolverConfiguration {
        guard
            let endpointText = defaults.string(forKey: endpointKey),
            let endpoint = URL.httpsURL(from: endpointText),
            let token = try PlaybackResolverCredentialStore.authorizationToken()?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !token.isEmpty
        else {
            throw PlaybackResolverError.notConfigured
        }

        let approvedAddonIDs = values(in: defaults.string(forKey: approvedAddonIDsKey))
        guard !approvedAddonIDs.isEmpty else { throw PlaybackResolverError.noApprovedAddons }

        let approvedHosts = values(in: defaults.string(forKey: approvedStreamHostsKey))
            .compactMap(ApprovedStreamHost.init)
        guard !approvedHosts.isEmpty else { throw PlaybackResolverError.noApprovedStreamHosts }

        return .init(
            endpoint: endpoint,
            authorizationToken: token,
            approvedAddonIDs: approvedAddonIDs,
            approvedStreamHosts: Set(approvedHosts)
        )
    }

    private static func values(in text: String?) -> Set<String> {
        Set((text ?? "")
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
    }
}

struct AuthorizedPlaybackResolverConfiguration: Sendable {
    let endpoint: URL
    let authorizationToken: String
    let approvedAddonIDs: Set<String>
    let approvedStreamHosts: Set<ApprovedStreamHost>
}

/// Exact host names are intentionally used instead of broad wildcards. A
/// resolver may return an expiring CDN URL, but it must be on one of the
/// domains the user explicitly approved before AVPlayer can receive it.
struct ApprovedStreamHost: Hashable, Sendable {
    let value: String

    nonisolated init?(_ text: String) {
        let host = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard
            !host.isEmpty,
            !host.contains(":") && !host.contains("/"),
            host.range(of: "^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$", options: .regularExpression) != nil
        else { return nil }
        value = host
    }

    func matches(_ host: String?) -> Bool {
        host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) == value
    }
}

enum PlaybackResolverError: LocalizedError, Sendable {
    case notConfigured
    case noApprovedAddons
    case noApprovedStreamHosts
    case candidateNotApproved
    case invalidResolverResponse
    case finalURLNotApproved
    case server(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Configure the resolver endpoint and authorization token in Playback settings."
        case .noApprovedAddons:
            "Choose at least one approved add-on in Playback settings."
        case .noApprovedStreamHosts:
            "Add the resolver's approved HTTPS stream host in Playback settings."
        case .candidateNotApproved:
            "This add-on is not approved to use your resolver."
        case .invalidResolverResponse:
            "The resolver did not return a valid HTTPS media URL."
        case .finalURLNotApproved:
            "The resolver returned a host that is not in your approved stream hosts."
        case let .server(statusCode):
            "The resolver could not authorize this source (HTTP \(statusCode))."
        }
    }
}

/// The small resolver protocol keeps the boundary inspectable. Omnia sends a
/// torrent identifier only to the configured service after checking the add-on
/// allow-list, then accepts only an allow-listed HTTPS URL in return.
enum AuthorizedPlaybackResolver {
    private struct RequestBody: Encodable {
        let version = 1
        let addonID: String
        let streamIdentifier: String
        let infoHash: String
        let fileIndex: Int?
        let filename: String?

        enum CodingKeys: String, CodingKey {
            case version
            case addonID = "addon_id"
            case streamIdentifier = "stream_identifier"
            case infoHash = "info_hash"
            case fileIndex = "file_index"
            case filename
        }
    }

    private struct ResponseBody: Decodable {
        let url: String
    }

    static func resolve(
        _ candidate: AddonStreamCandidate,
        configuration: AuthorizedPlaybackResolverConfiguration,
        session: URLSession = .shared
    ) async throws -> PlaybackSource {
        guard case let .localTorrent(descriptor) = candidate.delivery else {
            throw PlaybackResolverError.candidateNotApproved
        }
        let infoHash = descriptor.infoHash
        let fileIndex = descriptor.fileIndex
        guard configuration.approvedAddonIDs.contains(candidate.addonID) else {
            throw PlaybackResolverError.candidateNotApproved
        }

        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpBody = try JSONEncoder().encode(RequestBody(
            addonID: candidate.addonID,
            streamIdentifier: candidate.streamIdentifier,
            infoHash: infoHash,
            fileIndex: fileIndex,
            filename: candidate.filename
        ))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(configuration.authorizationToken)", forHTTPHeaderField: "Authorization")

        let (data, urlResponse) = try await session.data(for: request)
        guard let response = urlResponse as? HTTPURLResponse else {
            throw PlaybackResolverError.invalidResolverResponse
        }
        guard 200 ..< 300 ~= response.statusCode else {
            throw PlaybackResolverError.server(statusCode: response.statusCode)
        }
        guard
            let payload = try? JSONDecoder().decode(ResponseBody.self, from: data),
            let url = URL.httpsURL(from: payload.url)
        else {
            throw PlaybackResolverError.invalidResolverResponse
        }
        guard configuration.approvedStreamHosts.contains(where: { $0.matches(url.host) }) else {
            throw PlaybackResolverError.finalURLNotApproved
        }
        return PlaybackSource(candidate: candidate, url: url)
    }
}

private extension URL {
    static func httpsURL(from text: String) -> URL? {
        guard
            let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
            url.scheme?.lowercased() == "https",
            url.host != nil,
            url.user == nil,
            url.password == nil
        else { return nil }
        return url
    }
}
