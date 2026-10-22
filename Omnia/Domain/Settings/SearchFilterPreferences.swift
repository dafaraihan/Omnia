import Foundation

/// Settings › Content & Discovery › Search, and the Search page's Filter
/// menu: where Search looks, and which kinds and genre it keeps. Choosing
/// one add-on shows only that add-on's own results, with its posters, so
/// one title isn't listed again from other sources (Dafa, 2026-10-22).
nonisolated struct SearchFilterPreferences: Codable, Equatable, Sendable {
    enum Source: Codable, Hashable, Sendable {
        /// Every add-on search catalog, the metadata service and media servers.
        case all
        /// The metadata service alone (TMDB, TVDB or AniList, as routed).
        case metadata
        /// Connected Jellyfin or Emby servers alone.
        case mediaServers
        /// One installed add-on's search catalogs, by install id.
        case addon(String)
    }

    var source: Source = .all
    var kind: MediaItem.Kind?
    var genre: String?

    static let `default` = Self()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case source, kind, genre
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = (try? container.decodeIfPresent(Source.self, forKey: .source)) ?? .all
        kind = try? container.decodeIfPresent(MediaItem.Kind.self, forKey: .kind)
        genre = try? container.decodeIfPresent(String.self, forKey: .genre)
    }

    var isFiltered: Bool { self != .default }

    /// Kind and genre, applied to results from any source. A chosen genre
    /// keeps only titles that list it.
    func keeps(_ item: MediaItem) -> Bool {
        if let kind, item.kind != kind { return false }
        if let genre {
            return item.genres.contains { $0.compare(genre, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        }
        return true
    }
}
