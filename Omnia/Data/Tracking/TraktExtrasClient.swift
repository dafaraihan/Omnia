//
//  TraktExtrasClient.swift
//  Omnia
//
//  Trakt's More Like This and comments for a title page, after Nuvio's
//  Trakt features (More Like This source, Comments). Both are public Trakt
//  data, read with Omnia's Trakt app; no sign-in is needed.
//

import Foundation

/// One Trakt comment or review on a title.
nonisolated struct TraktComment: Identifiable, Equatable, Sendable {
    let id: Int
    let username: String
    let text: String
    let isSpoiler: Bool
    let isReview: Bool
    let likes: Int
    let rating: Int?
    let createdAt: Date?
}

nonisolated enum TraktExtrasClient {
    private static let base = URL(string: "https://api.trakt.tv")!

    /// The Trakt app to read with: Omnia's own, or the one an older
    /// connection was made with.
    @MainActor
    static var clientID: String? {
        if let app = TrackerAppCredentials.app(for: .trakt) { return app.clientID }
        let stored = TrackerAccountStore.shared.credentials[.trakt]?.clientID ?? ""
        return stored.isEmpty ? nil : stored
    }

    /// Titles Trakt relates to this one, as bare entries for the add-ons to
    /// draw.
    static func related(to item: MediaItem, clientID: String) async throws -> [TrackerLibraryEntry] {
        guard let path = try await titlePath(for: item, clientID: clientID) else { return [] }
        let (data, _) = try await TrackerClient.send(
            request("\(path)/related", clientID: clientID, query: ["limit": "20"]),
            accepting: [200]
        )
        let isMovie = item.kind == .movie
        return try TrackerClient.decode([RelatedTitle].self, from: data).compactMap { title in
            guard let ids = title.ids, ids.imdb != nil || ids.tmdb != nil || ids.tvdb != nil else { return nil }
            return TrackerLibraryEntry(
                kind: isMovie ? .movie : .series,
                title: title.title ?? "",
                year: title.year,
                imdb: ids.imdb,
                tmdb: ids.tmdb,
                tvdb: ids.tvdb
            )
        }
    }

    /// The most-liked comments and reviews on this title.
    static func comments(on item: MediaItem, clientID: String) async throws -> [TraktComment] {
        guard let path = try await titlePath(for: item, clientID: clientID) else { return [] }
        let (data, _) = try await TrackerClient.send(
            request("\(path)/comments/likes", clientID: clientID, query: ["limit": "20"]),
            accepting: [200]
        )
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return try TrackerClient.decode([CommentWire].self, from: data).compactMap { wire in
            let text = wire.comment?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let id = wire.id, !text.isEmpty else { return nil }
            return TraktComment(
                id: id,
                username: wire.user?.username ?? "Trakt user",
                text: String(text.prefix(4_000)),
                isSpoiler: wire.spoiler ?? false,
                isReview: wire.review ?? false,
                likes: wire.likes ?? 0,
                rating: wire.user_stats?.rating,
                createdAt: wire.created_at.flatMap(formatter.date(from:))
            )
        }
    }

    /// `movies/tt…` or `shows/tt…`; a title known only by TMDB or TVDB is
    /// looked up first.
    private static func titlePath(for item: MediaItem, clientID: String) async throws -> String? {
        let segment = item.kind == .movie ? "movies" : "shows"
        let ids = CustomPosterURLResolver.ids(for: item)
        if let imdb = ids.imdb, imdb.hasPrefix("tt"), imdb.dropFirst(2).allSatisfy(\.isNumber) {
            return "\(segment)/\(imdb)"
        }
        let lookup: (String, String)? = ids.tmdb.map { ("tmdb", $0) } ?? ids.tvdb.map { ("tvdb", $0) }
        guard let (source, value) = lookup, !value.isEmpty, value.allSatisfy(\.isNumber) else { return nil }
        let type = item.kind == .movie ? "movie" : "show"
        let (data, _) = try await TrackerClient.send(
            request("search/\(source)/\(value)", clientID: clientID, query: ["type": type]),
            accepting: [200]
        )
        let results = try TrackerClient.decode([SearchResult].self, from: data)
        guard let trakt = results.lazy.compactMap({ ($0.movie ?? $0.show)?.ids?.trakt }).first else { return nil }
        return "\(segment)/\(trakt)"
    }

    private static func request(_ path: String, clientID: String, query: [String: String]) -> URLRequest {
        var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        request.setValue(clientID, forHTTPHeaderField: "trakt-api-key")
        return request
    }

    private struct IDs: Decodable {
        let trakt: Int?
        let imdb: String?
        let tmdb: Int?
        let tvdb: Int?
    }

    private struct RelatedTitle: Decodable {
        let title: String?
        let year: Int?
        let ids: IDs?
    }

    private struct SearchResult: Decodable {
        struct Title: Decodable { let ids: IDs? }
        let movie: Title?
        let show: Title?
    }

    private struct CommentWire: Decodable {
        struct User: Decodable { let username: String? }
        struct Stats: Decodable { let rating: Int? }
        let id: Int?
        let comment: String?
        let spoiler: Bool?
        let review: Bool?
        let likes: Int?
        let created_at: String?
        let user: User?
        let user_stats: Stats?
    }
}
