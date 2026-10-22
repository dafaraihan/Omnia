//
//  MediaServerModels.swift
//  Omnia
//

import Foundation

/// Nuvio's media servers: Jellyfin 10.9+ and Emby 4.7+, which share the
/// MediaBrowser API and differ only in a few paths and the auth header.
nonisolated enum MediaServerKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case jellyfin
    case emby

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .jellyfin: "Jellyfin"
        case .emby: "Emby"
        }
    }

    var minimumVersion: String {
        switch self {
        case .jellyfin: "10.9"
        case .emby: "4.7"
        }
    }

    /// Emby serves its API below `/emby`; Jellyfin at the root.
    var apiPath: String {
        switch self {
        case .jellyfin: ""
        case .emby: "/emby"
        }
    }

    var authorizationHeader: String {
        switch self {
        case .jellyfin: "Authorization"
        case .emby: "X-Emby-Authorization"
        }
    }
}

nonisolated enum MediaServerLibraryKind: String, Codable, Sendable {
    case movies
    case series
    case mixed
    case collections

    func holds(_ kind: MediaItem.Kind) -> Bool {
        switch self {
        case .movies: kind == .movie
        case .series: kind == .series
        case .mixed: kind == .movie || kind == .series
        case .collections: false
        }
    }

    /// The MediaBrowser item types a library lists.
    var itemTypes: String {
        switch self {
        case .movies: "Movie"
        case .series: "Series"
        case .mixed: "Movie,Series"
        case .collections: "BoxSet"
        }
    }

    var label: String {
        switch self {
        case .movies: "Movies"
        case .series: "Series"
        case .mixed: "Movies and Series"
        case .collections: "Collections"
        }
    }
}

nonisolated struct MediaServerLibrary: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var name: String
    var kind: MediaServerLibraryKind
    var isSelected = true
}

/// One signed-in server. The access token is kept in the Keychain, never
/// here, so this can be saved in UserDefaults.
nonisolated struct MediaServerConnection: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let kind: MediaServerKind
    var name: String
    /// The server's base address, without the API path.
    var address: URL
    var serverID: String
    var userID: String
    var userName: String
    var libraries: [MediaServerLibrary] = []
    var isEnabled = true
    /// Nuvio's Use addon metadata: titles open with your add-ons' details
    /// and also list add-on streams. Off, they keep the server's own.
    var usesAddonMetadata = false
    /// Nuvio's Import watch progress: titles in progress on the server join
    /// Continue Watching.
    var importsWatchProgress = false

    var selectedLibraries: [MediaServerLibrary] { libraries.filter(\.isSelected) }

    var apiRoot: URL {
        kind.apiPath.isEmpty ? address : address.appending(path: String(kind.apiPath.dropFirst()))
    }

    var keychainAccount: String { "media-server.\(id)" }

    /// "Jellyfin · dafa"
    var identity: String { "\(kind.displayName) · \(userName)" }
}

nonisolated enum MediaServerFailure: Error, Equatable, LocalizedError, Sendable {
    case invalidAddress
    case insecureAddress
    case authenticationRequired
    case forbidden
    case unreachable
    case unsupportedVersion(MediaServerKind)
    case notFound
    case invalidResponse
    case failed

    var errorDescription: String? {
        switch self {
        case .invalidAddress: "Enter a valid server address."
        case .insecureAddress: "Use an https:// address. Plain http:// only works for servers on your local network."
        case .authenticationRequired: "Incorrect username or password."
        case .forbidden: "This user does not have access."
        case .unreachable: "Could not reach the server."
        case let .unsupportedVersion(kind): "\(kind.displayName) \(kind.minimumVersion) or later is required."
        case .notFound: "This item is no longer available on the server."
        case .invalidResponse: "The server returned something Omnia couldn't read."
        case .failed: "Could not connect to the server."
        }
    }

    /// The short status shown under a server in Settings.
    var status: String {
        switch self {
        case .authenticationRequired: "Sign in again"
        case .unreachable, .invalidResponse: "Server unavailable"
        default: errorDescription ?? "Unavailable"
        }
    }
}

/// Where server titles and streams come from in Omnia's ids.
nonisolated enum MediaServerIdentifier {
    static let itemPrefix = "mediaserver:"
    private static let sourcePrefix = "mediaserver-source:"

    /// `mediaserver:<connection>:<item>`
    static func itemID(connectionID: String, itemID: String) -> String {
        "\(itemPrefix)\(connectionID):\(itemID)"
    }

    static func parse(_ id: String) -> (connectionID: String, itemID: String)? {
        guard id.hasPrefix(itemPrefix) else { return nil }
        let body = id.dropFirst(itemPrefix.count)
        guard let separator = body.firstIndex(of: ":") else { return nil }
        let connection = String(body[..<separator])
        let item = String(body[body.index(after: separator)...])
        guard !connection.isEmpty, !item.isEmpty else { return nil }
        return (connection, item)
    }

    /// The source id a server's streams are listed under.
    static func sourceID(connectionID: String) -> String {
        sourcePrefix + connectionID
    }

    static func isServerSource(_ id: String) -> Bool {
        id.hasPrefix(sourcePrefix)
    }

    static func connectionID(fromSourceID id: String) -> String? {
        guard isServerSource(id) else { return nil }
        return String(id.dropFirst(sourcePrefix.count))
    }
}

/// Plain HTTP is allowed only for servers on the local network (Dafa's
/// choice, 2026-10-21): private and link-local IPs, Tailscale's 100.64/10,
/// localhost, `.local` names and single-label names. Everything else must be
/// HTTPS.
nonisolated enum MediaServerAddressPolicy {
    static func permits(_ url: URL) -> Bool {
        guard url.user == nil, url.password == nil, let host = url.host, !host.isEmpty else { return false }
        switch url.scheme?.lowercased() {
        case "https": return true
        case "http": return isLocalHost(host)
        default: return false
        }
    }

    static func isLocalHost(_ rawHost: String) -> Bool {
        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard !host.isEmpty else { return false }
        if host == "localhost" || host.hasSuffix(".local") { return true }
        if host.contains(":") { return isLocalIPv6(host) }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        let octets = parts.compactMap { UInt8($0) }
        if parts.count == 4, octets.count == 4 { return isLocalIPv4(octets) }
        // A single-label name such as `nas` only resolves on the local network.
        return parts.count == 1
    }

    private static func isLocalIPv4(_ octets: [UInt8]) -> Bool {
        switch (octets[0], octets[1]) {
        case (10, _), (127, _): true
        case (172, 16...31): true
        case (192, 168): true
        case (169, 254): true
        case (100, 64...127): true
        default: false
        }
    }

    private static func isLocalIPv6(_ host: String) -> Bool {
        host == "::1" || host.hasPrefix("fe80:") || host.hasPrefix("fc") || host.hasPrefix("fd")
    }

    /// Accepts what people paste: a bare host and port, a web UI address or
    /// an address ending in the API path. Returns the server's base address.
    static func normalizedAddress(_ input: String, kind: MediaServerKind) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty else { return nil }
        if !text.contains("://") {
            let hostAndPort = text.split(separator: "/").first.map(String.init) ?? text
            let host = hostAndPort.split(separator: ":").first.map(String.init) ?? hostAndPort
            text = (isLocalHost(host) ? "http://" : "https://") + text
        }
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil
        else { return nil }
        var path = components.percentEncodedPath
        for suffix in ["/web/index.html", "/web", "/index.html"] where path.lowercased().hasSuffix(suffix) {
            path.removeLast(suffix.count)
        }
        if !kind.apiPath.isEmpty, path.lowercased().hasSuffix(kind.apiPath) {
            path.removeLast(kind.apiPath.count)
        }
        while path.hasSuffix("/") { path.removeLast() }
        components.scheme = scheme
        components.percentEncodedPath = path
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
