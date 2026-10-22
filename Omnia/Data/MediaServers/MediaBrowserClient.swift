//
//  MediaBrowserClient.swift
//  Omnia
//

import Foundation

/// Talks to a Jellyfin or Emby server, following Nuvio's MediaBrowser
/// provider: sign in by name, libraries, items, resume, search, episodes and
/// static streams. The token goes in the authorization header, never in a
/// URL, and requests only go to the server's own origin.
nonisolated struct MediaBrowserClient: Sendable {
    let kind: MediaServerKind
    let apiRoot: URL
    let token: String?

    init(kind: MediaServerKind, apiRoot: URL, token: String?) {
        self.kind = kind
        self.apiRoot = apiRoot
        self.token = token
    }

    init(connection: MediaServerConnection, token: String) {
        self.init(kind: connection.kind, apiRoot: connection.apiRoot, token: token)
    }

    // MARK: Sign in

    struct SignIn: Sendable {
        let address: URL
        let serverName: String
        let serverID: String
        let userID: String
        let userName: String
        let token: String
    }

    static func signIn(kind: MediaServerKind, address input: String, username: String, password: String) async throws -> SignIn {
        guard let address = MediaServerAddressPolicy.normalizedAddress(input, kind: kind) else {
            throw MediaServerFailure.invalidAddress
        }
        guard MediaServerAddressPolicy.permits(address) else { throw MediaServerFailure.insecureAddress }
        let anonymous = MediaBrowserClient(kind: kind, apiRoot: apiRoot(kind: kind, address: address), token: nil)
        let info: PublicInfo = try await anonymous.get("/System/Info/Public")
        guard info.isSupported(by: kind) else { throw MediaServerFailure.unsupportedVersion(kind) }

        let body = try JSONEncoder().encode(["Username": username, "Pw": password])
        let data = try await anonymous.send("POST", "/Users/AuthenticateByName", body: body)
        let result = try decode(AuthResult.self, from: data)
        guard let user = result.user, let token = result.accessToken?.nonEmptyValue else {
            throw MediaServerFailure.authenticationRequired
        }
        guard let serverID = result.serverID ?? info.id else { throw MediaServerFailure.failed }
        return SignIn(
            address: address,
            serverName: info.serverName?.nonEmptyValue ?? address.host ?? kind.displayName,
            serverID: serverID,
            userID: user.id,
            userName: user.name ?? username,
            token: token
        )
    }

    static func apiRoot(kind: MediaServerKind, address: URL) -> URL {
        kind.apiPath.isEmpty ? address : address.appending(path: String(kind.apiPath.dropFirst()))
    }

    func signOut() async {
        _ = try? await send("POST", "/Sessions/Logout")
    }

    // MARK: Browsing

    func libraries(userID: String) async throws -> [MediaServerLibrary] {
        let result: ItemsResult = try await get(viewsPath(userID: userID), query: itemsQuery(userID: userID))
        return result.items.compactMap { view in
            guard let kind = Self.libraryKind(collectionType: view.collectionType) else { return nil }
            return MediaServerLibrary(id: view.id, name: view.name ?? "Library", kind: kind)
        }
    }

    /// Newest first, as Nuvio's library rows.
    func libraryPage(userID: String, library: MediaServerLibrary, start: Int, limit: Int) async throws -> ItemsResult {
        let isCollection = library.kind == .collections
        return try await get(itemsPath(userID: userID), query: itemsQuery(userID: userID).merging([
            "parentId": library.id,
            "recursive": isCollection ? "false" : "true",
            "includeItemTypes": isCollection ? nil : library.kind.itemTypes,
            "sortBy": isCollection ? "SortName" : "DateCreated,SortName",
            "sortOrder": isCollection ? "Ascending" : "Descending",
            "startIndex": String(start),
            "limit": String(limit),
            "enableTotalRecordCount": "true",
            "fields": Self.listFields,
            "imageTypeLimit": "1",
            "enableImageTypes": "Primary,Backdrop,Logo"
        ]) { _, new in new })
    }

    func resumeItems(userID: String, limit: Int) async throws -> [BaseItem] {
        let result: ItemsResult = try await get(resumePath(userID: userID), query: itemsQuery(userID: userID).merging([
            "limit": String(limit),
            "mediaTypes": "Video",
            "fields": Self.listFields,
            "imageTypeLimit": "1",
            "enableImageTypes": "Primary,Backdrop,Logo,Thumb"
        ]) { _, new in new })
        return result.items
    }

    func search(userID: String, query text: String, itemTypes: String, parentID: String?, limit: Int) async throws -> [BaseItem] {
        let result: ItemsResult = try await get(itemsPath(userID: userID), query: itemsQuery(userID: userID).merging([
            "parentId": parentID,
            "recursive": "true",
            "includeItemTypes": itemTypes,
            "searchTerm": text,
            "limit": String(limit),
            "fields": Self.listFields,
            "imageTypeLimit": "1",
            "enableImageTypes": "Primary,Backdrop,Logo"
        ]) { _, new in new })
        return result.items
    }

    func item(userID: String, id: String, fields: String = "Overview,Genres,ProviderIds,PremiereDate,MediaSources") async throws -> BaseItem {
        try await get(itemPath(userID: userID, itemID: id), query: itemsQuery(userID: userID).merging(["fields": fields]) { _, new in new })
    }

    /// A page of every title's provider ids in a library, for matching
    /// titles from add-ons and TMDB to the server (Nuvio's external id index).
    func providerIndexPage(userID: String, library: MediaServerLibrary, start: Int, limit: Int) async throws -> ItemsResult {
        try await get(itemsPath(userID: userID), query: itemsQuery(userID: userID).merging([
            "parentId": library.id,
            "recursive": "true",
            "includeItemTypes": library.kind.itemTypes,
            "fields": "ProviderIds",
            "enableImages": "false",
            "enableUserData": "false",
            "startIndex": String(start),
            "limit": String(limit),
            "enableTotalRecordCount": "true"
        ]) { _, new in new })
    }

    func episodes(userID: String, seriesID: String, season: Int?) async throws -> [BaseItem] {
        let result: ItemsResult = try await get("/Shows/\(Self.pathSegment(seriesID))/Episodes", query: [
            "userId": userID,
            "season": season.map(String.init),
            "fields": "Overview,ProviderIds,PremiereDate,MediaSources",
            "enableUserData": "true"
        ])
        return result.items
    }

    // MARK: URLs

    func imageURL(itemID: String, type: String, tag: String?, maxWidth: Int) -> URL? {
        guard let tag else { return nil }
        let base = "/Items/\(Self.pathSegment(itemID))/Images/"
        return url(base + (type == "Backdrop" ? "Backdrop/0" : type), query: [
            "tag": tag,
            "maxWidth": String(maxWidth),
            "quality": "90"
        ])
    }

    /// A direct-play stream. The token travels in `requestHeaders`.
    func streamURL(itemID: String, mediaSourceID: String, tag: String?) -> URL? {
        url("/Videos/\(Self.pathSegment(itemID))/stream", query: [
            "static": "true",
            "mediaSourceId": mediaSourceID,
            "deviceId": Self.deviceID,
            "tag": tag
        ])
    }

    var requestHeaders: [String: String] {
        var headers = [kind.authorizationHeader: authorizationValue]
        if let token { headers["X-Emby-Token"] = token }
        return headers
    }

    // MARK: Requests

    private func get<Response: Decodable>(_ path: String, query: [String: String?] = [:]) async throws -> Response {
        try Self.decode(Response.self, from: try await send("GET", path, query: query))
    }

    @discardableResult
    private func send(_ method: String, _ path: String, query: [String: String?] = [:], body: Data? = nil) async throws -> Data {
        guard let url = url(path, query: query), MediaServerAddressPolicy.permits(url) else {
            throw MediaServerFailure.insecureAddress
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(authorizationValue, forHTTPHeaderField: kind.authorizationHeader)
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let response: URLResponse
        let data: Data
        do {
            (data, response) = try await Self.session.data(for: request, delegate: SameOriginRedirects(origin: url))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw MediaServerFailure.unreachable
        }
        guard let http = response as? HTTPURLResponse else { throw MediaServerFailure.invalidResponse }
        switch http.statusCode {
        case 200...299: break
        case 401: throw MediaServerFailure.authenticationRequired
        case 403: throw MediaServerFailure.forbidden
        case 404: throw MediaServerFailure.notFound
        case 500...599: throw MediaServerFailure.unreachable
        default: throw MediaServerFailure.failed
        }
        guard data.count <= Self.maximumResponseBytes else { throw MediaServerFailure.invalidResponse }
        return data
    }

    private func url(_ path: String, query: [String: String?]) -> URL? {
        guard var components = URLComponents(url: apiRoot, resolvingAgainstBaseURL: false) else { return nil }
        var basePath = components.percentEncodedPath
        while basePath.hasSuffix("/") { basePath.removeLast() }
        components.percentEncodedPath = basePath + path
        let items = query.compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
            .sorted { $0.name < $1.name }
        components.queryItems = items.isEmpty ? nil : items
        return components.url
    }

    private var authorizationValue: String {
        func clean(_ value: String) -> String { value.filter { $0 != "\"" && !$0.isNewline } }
        var value = "MediaBrowser Client=\"Omnia\", Device=\"\(clean(Self.deviceName))\", "
            + "DeviceId=\"\(clean(Self.deviceID))\", Version=\"\(clean(Self.appVersion))\""
        if let token { value += ", Token=\"\(clean(token))\"" }
        return value
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw MediaServerFailure.invalidResponse
        }
    }

    // MARK: Paths

    private func viewsPath(userID: String) -> String {
        kind == .jellyfin ? "/UserViews" : "/Users/\(Self.pathSegment(userID))/Views"
    }

    private func itemsPath(userID: String) -> String {
        kind == .jellyfin ? "/Items" : "/Users/\(Self.pathSegment(userID))/Items"
    }

    private func itemPath(userID: String, itemID: String) -> String {
        kind == .jellyfin
            ? "/Items/\(Self.pathSegment(itemID))"
            : "/Users/\(Self.pathSegment(userID))/Items/\(Self.pathSegment(itemID))"
    }

    private func resumePath(userID: String) -> String {
        kind == .jellyfin ? "/UserItems/Resume" : "/Users/\(Self.pathSegment(userID))/Items/Resume"
    }

    /// Jellyfin names the user in the query; Emby in the path.
    private func itemsQuery(userID: String) -> [String: String?] {
        kind == .jellyfin ? ["userId": userID] : [:]
    }

    private static func libraryKind(collectionType: String?) -> MediaServerLibraryKind? {
        switch collectionType?.lowercased() {
        case "movies": .movies
        case "tvshows": .series
        case "boxsets": .collections
        case "mixed", "homevideos": .mixed
        default: nil
        }
    }

    static func pathSegment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? value
    }

    // MARK: Shared

    static let listFields = "Overview,Genres,ProviderIds,PremiereDate"
    private static let maximumResponseBytes = 20 * 1_024 * 1_024

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: configuration)
    }()

    private static let deviceIDKey = "media-server-device-id"

    /// A random id for this install, as servers list each device once.
    static let deviceID: String = {
        if let saved = UserDefaults.standard.string(forKey: deviceIDKey), !saved.isEmpty { return saved }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: deviceIDKey)
        return created
    }()

    private static var deviceName: String {
        #if os(macOS)
        "Omnia for Mac"
        #else
        "Omnia for iOS"
        #endif
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

/// Redirects are followed only within the same scheme, host and port, so a
/// token never reaches another server.
private nonisolated final class SameOriginRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    private let origin: NormalizedOrigin?

    init(origin url: URL) {
        origin = NormalizedOrigin(url: url)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, let origin, origin.permits(url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

// MARK: Wire models

extension MediaBrowserClient {
    struct PublicInfo: Decodable, Sendable {
        let serverName: String?
        let version: String?
        let id: String?
        let productName: String?

        enum CodingKeys: String, CodingKey {
            case serverName = "ServerName", version = "Version", id = "Id", productName = "ProductName"
        }

        func isSupported(by kind: MediaServerKind) -> Bool {
            if kind == .emby, productName?.localizedCaseInsensitiveContains("jellyfin") == true { return false }
            let actual = (version ?? "").split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
            guard !actual.isEmpty else { return false }
            for (index, minimum) in kind.minimumVersion.split(separator: ".").compactMap({ Int($0) }).enumerated() {
                let part = index < actual.count ? actual[index] : 0
                if part != minimum { return part > minimum }
            }
            return true
        }
    }

    struct AuthResult: Decodable, Sendable {
        struct User: Decodable, Sendable {
            let id: String
            let name: String?
            enum CodingKeys: String, CodingKey { case id = "Id", name = "Name" }
        }

        let user: User?
        let accessToken: String?
        let serverID: String?

        enum CodingKeys: String, CodingKey {
            case user = "User", accessToken = "AccessToken", serverID = "ServerId"
        }
    }

    struct ItemsResult: Decodable, Sendable {
        let items: [BaseItem]
        let totalRecordCount: Int?

        enum CodingKeys: String, CodingKey { case items = "Items", totalRecordCount = "TotalRecordCount" }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            items = (try? container.decodeIfPresent([LossyItem].self, forKey: .items))?.compactMap(\.item) ?? []
            totalRecordCount = try? container.decodeIfPresent(Int.self, forKey: .totalRecordCount)
        }
    }

    /// One malformed item is skipped instead of failing the whole page.
    struct LossyItem: Decodable, Sendable {
        let item: BaseItem?
        init(from decoder: Decoder) throws { item = try? BaseItem(from: decoder) }
    }

    struct UserData: Decodable, Hashable, Sendable {
        let playbackPositionTicks: Int64?
        let played: Bool?
        let playedPercentage: Double?
        let lastPlayedDate: String?

        enum CodingKeys: String, CodingKey {
            case playbackPositionTicks = "PlaybackPositionTicks", played = "Played"
            case playedPercentage = "PlayedPercentage", lastPlayedDate = "LastPlayedDate"
        }
    }

    struct MediaStream: Decodable, Hashable, Sendable {
        let type: String?
        let codec: String?
        let height: Int?
        let displayTitle: String?
        let language: String?

        enum CodingKeys: String, CodingKey {
            case type = "Type", codec = "Codec", height = "Height", displayTitle = "DisplayTitle", language = "Language"
        }
    }

    struct MediaSource: Decodable, Hashable, Sendable {
        let id: String
        let name: String?
        let container: String?
        let size: Int64?
        let path: String?
        let eTag: String?
        let mediaStreams: [MediaStream]?

        enum CodingKeys: String, CodingKey {
            case id = "Id", name = "Name", container = "Container", size = "Size", path = "Path"
            case eTag = "ETag", mediaStreams = "MediaStreams"
        }
    }

    struct Person: Decodable, Hashable, Sendable {
        let id: String?
        let name: String?
        let role: String?
        let type: String?
        let primaryImageTag: String?

        enum CodingKeys: String, CodingKey {
            case id = "Id", name = "Name", role = "Role", type = "Type", primaryImageTag = "PrimaryImageTag"
        }
    }

    struct BaseItem: Decodable, Hashable, Sendable {
        let id: String
        let name: String?
        let type: String?
        let collectionType: String?
        let productionYear: Int?
        let overview: String?
        let genres: [String]?
        let providerIDs: [String: String]?
        let premiereDate: String?
        let imageTags: [String: String]?
        let backdropImageTags: [String]?
        let runTimeTicks: Int64?
        let userData: UserData?
        let seriesID: String?
        let seriesName: String?
        let seriesPrimaryImageTag: String?
        let parentIndexNumber: Int?
        let indexNumber: Int?
        let indexNumberEnd: Int?
        let locationType: String?
        let mediaSources: [MediaSource]?
        let people: [Person]?
        let officialRating: String?
        let studios: [Person]?

        enum CodingKeys: String, CodingKey {
            case id = "Id", name = "Name", type = "Type", collectionType = "CollectionType"
            case productionYear = "ProductionYear", overview = "Overview", genres = "Genres"
            case providerIDs = "ProviderIds", premiereDate = "PremiereDate", imageTags = "ImageTags"
            case backdropImageTags = "BackdropImageTags", runTimeTicks = "RunTimeTicks", userData = "UserData"
            case seriesID = "SeriesId", seriesName = "SeriesName", seriesPrimaryImageTag = "SeriesPrimaryImageTag"
            case parentIndexNumber = "ParentIndexNumber", indexNumber = "IndexNumber", indexNumberEnd = "IndexNumberEnd"
            case locationType = "LocationType", mediaSources = "MediaSources", people = "People"
            case officialRating = "OfficialRating", studios = "Studios"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = try? container.decodeIfPresent(String.self, forKey: .name)
            type = try? container.decodeIfPresent(String.self, forKey: .type)
            collectionType = try? container.decodeIfPresent(String.self, forKey: .collectionType)
            productionYear = try? container.decodeIfPresent(Int.self, forKey: .productionYear)
            overview = try? container.decodeIfPresent(String.self, forKey: .overview)
            genres = try? container.decodeIfPresent([String].self, forKey: .genres)
            providerIDs = try? container.decodeIfPresent([String: String].self, forKey: .providerIDs)
            premiereDate = try? container.decodeIfPresent(String.self, forKey: .premiereDate)
            imageTags = try? container.decodeIfPresent([String: String].self, forKey: .imageTags)
            backdropImageTags = try? container.decodeIfPresent([String].self, forKey: .backdropImageTags)
            runTimeTicks = try? container.decodeIfPresent(Int64.self, forKey: .runTimeTicks)
            userData = try? container.decodeIfPresent(UserData.self, forKey: .userData)
            seriesID = try? container.decodeIfPresent(String.self, forKey: .seriesID)
            seriesName = try? container.decodeIfPresent(String.self, forKey: .seriesName)
            seriesPrimaryImageTag = try? container.decodeIfPresent(String.self, forKey: .seriesPrimaryImageTag)
            parentIndexNumber = try? container.decodeIfPresent(Int.self, forKey: .parentIndexNumber)
            indexNumber = try? container.decodeIfPresent(Int.self, forKey: .indexNumber)
            indexNumberEnd = try? container.decodeIfPresent(Int.self, forKey: .indexNumberEnd)
            locationType = try? container.decodeIfPresent(String.self, forKey: .locationType)
            mediaSources = try? container.decodeIfPresent([MediaSource].self, forKey: .mediaSources)
            people = try? container.decodeIfPresent([Person].self, forKey: .people)
            officialRating = try? container.decodeIfPresent(String.self, forKey: .officialRating)
            studios = try? container.decodeIfPresent([Person].self, forKey: .studios)
        }

        /// Provider ids under Omnia's keys: imdb, tmdb, tvdb.
        var externalIDs: [String: String] {
            var ids: [String: String] = [:]
            for (key, value) in providerIDs ?? [:] {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                switch key.lowercased() {
                case "imdb": ids["imdb"] = trimmed
                case "tmdb": ids["tmdb"] = trimmed
                case "tvdb": ids["tvdb"] = trimmed
                default: break
                }
            }
            return ids
        }

        var isMissing: Bool { locationType?.caseInsensitiveCompare("Virtual") == .orderedSame }

        var mediaKind: MediaItem.Kind? {
            switch type?.lowercased() {
            case "movie": .movie
            case "series": .series
            case "episode": .episode
            default: nil
            }
        }

        var runtimeSeconds: Double? {
            runTimeTicks.map { Double($0) / 10_000_000 }
        }
    }
}

private extension String {
    nonisolated var nonEmptyValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
