//
//  CustomPosterURLResolver.swift
//  Omnia
//
//  Settings › Layout › Poster Cards › Custom Poster Source, after Nuvio's
//  CustomPosterUrlResolver (NuvioMedia/NuvioMobile, GPL-3.0; Dafa,
//  2026-10-27). A URL pattern from an external poster service, filled with
//  each title's IDs. When a placeholder has no value, or the image fails to
//  load, the title's own poster is used.
//

import Foundation

/// Fills a custom poster URL pattern with a title's IDs.
///
/// Placeholders: `{id}` (the full ID, such as `tt0137523`, `tmdb:1396`),
/// `{id_type}`, `{typed_id}` (RPDB style: `tt…`, or `movie-1396`),
/// `{type}` (`movie` or `series`), `{shape}` (`poster`, `landscape`,
/// `square`), and `{imdb_id}`, `{tmdb_id}`, `{tvdb_id}`, `{kitsu_id}`,
/// `{anilist_id}`, `{mal_id}`, `{anidb_id}`. `{imdb_id?}` is optional (empty
/// when missing); `{imdb_id|tmdb_id}` uses the first that has a value. A
/// required placeholder without a value means no custom poster.
nonisolated enum CustomPosterURLResolver {
    struct ContentIDs: Equatable, Sendable {
        var id: String
        var imdb: String?
        var tmdb: String?
        var tvdb: String?
        var kitsu: String?
        var anilist: String?
        var mal: String?
        var anidb: String?
    }

    static func url(for item: MediaItem, pattern: String, shape: String = "poster") -> URL? {
        let pattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty,
              let resolved = resolve(pattern, ids: ids(for: item), type: item.kind == .movie ? "movie" : "series", shape: shape),
              let url = URL(string: resolved),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http"
        else { return nil }
        return url
    }

    /// Whether `pattern` can be used at all: an http(s) address.
    static func isValidPattern(_ pattern: String) -> Bool {
        let decoded = decodePlaceholders(pattern.trimmingCharacters(in: .whitespacesAndNewlines))
        let probe = decoded
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .replacingOccurrences(of: "|", with: "")
        guard let url = URL(string: probe), let scheme = url.scheme?.lowercased(), url.host != nil else { return false }
        return scheme == "https" || scheme == "http"
    }

    static func ids(for item: MediaItem) -> ContentIDs {
        func value(_ keys: [String]) -> String? {
            keys.lazy.compactMap { item.externalIDs[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        }
        // Add-on titles carry the add-on's own meta ID after `stremio:<addon>:`.
        var metaID = item.id
        if metaID.hasPrefix("stremio:") {
            let parts = metaID.split(separator: ":", maxSplits: 2)
            if parts.count == 3 { metaID = String(parts[2]) }
        }
        var ids = ContentIDs(id: metaID)
        let parts = metaID.split(separator: ":")
        let prefix = parts.first.map { String($0).lowercased() } ?? ""
        let raw = parts.dropFirst().first.map(String.init)
        if metaID.hasPrefix("tt") { ids.imdb = parts.first.map(String.init) }
        switch prefix {
        case "tmdb": ids.tmdb = raw
        case "tvdb": ids.tvdb = raw
        case "kitsu": ids.kitsu = raw
        case "anilist": ids.anilist = raw
        case "mal": ids.mal = raw
        case "anidb": ids.anidb = raw
        default: break
        }
        ids.imdb = ids.imdb ?? value(["imdb", "imdb_id"])
        ids.tmdb = ids.tmdb ?? value(["tmdb", "tmdb_id"])
        ids.tvdb = ids.tvdb ?? value(["tvdb", "tvdb_id"])
        ids.kitsu = ids.kitsu ?? value(["kitsu", "kitsu_id"])
        ids.anilist = ids.anilist ?? value(["anilist", "anilist_id"])
        ids.mal = ids.mal ?? value(["mal", "mal_id", "myanimelist"])
        ids.anidb = ids.anidb ?? value(["anidb", "anidb_id"])
        // A title known only by an Omnia metadata record.
        if let providerID = item.metadataProviderID {
            switch item.metadataProvider {
            case .tmdb: ids.tmdb = ids.tmdb ?? providerID
            case .tvdb: ids.tvdb = ids.tvdb ?? providerID
            case .anilist: ids.anilist = ids.anilist ?? providerID
            case .kitsu: ids.kitsu = ids.kitsu ?? providerID
            case .myanimelist: ids.mal = ids.mal ?? providerID
            case .none: break
            }
        }
        return ids
    }

    static func resolve(_ pattern: String, ids: ContentIDs, type: String, shape: String) -> String? {
        let decoded = decodePlaceholders(pattern)
        let tokens = scanTokens(decoded)
        guard !tokens.isEmpty else { return decoded }
        if let direct = fill(decoded, tokens: tokens, ids: ids, type: type, shape: shape) { return direct }
        guard isRPDBFamily(decoded) else { return nil }
        // RPDB-style services also take TMDB or TVDB IDs when IMDb's is missing.
        let typePrefix = type == "movie" ? "movie" : "series"
        var fallbacks: [String] = []
        if decoded.contains("{imdb_id}") {
            if let tmdb = ids.tmdb {
                fallbacks.append(decoded.replacingOccurrences(of: "/imdb/", with: "/tmdb/")
                    .replacingOccurrences(of: "{imdb_id}", with: "\(typePrefix)-\(tmdb)"))
            }
            if let tvdb = ids.tvdb {
                fallbacks.append(decoded.replacingOccurrences(of: "/imdb/", with: "/tvdb/")
                    .replacingOccurrences(of: "{imdb_id}", with: "\(typePrefix)-\(tvdb)"))
            }
        } else if decoded.contains("{tmdb_id}") {
            if let imdb = ids.imdb {
                fallbacks.append(decoded.replacingOccurrences(of: "/tmdb/", with: "/imdb/")
                    .replacingOccurrences(of: "\(typePrefix)-{tmdb_id}", with: imdb)
                    .replacingOccurrences(of: "{tmdb_id}", with: imdb))
            }
            if let tvdb = ids.tvdb {
                fallbacks.append(decoded.replacingOccurrences(of: "/tmdb/", with: "/tvdb/")
                    .replacingOccurrences(of: "{tmdb_id}", with: tvdb))
            }
        } else if decoded.contains("{tvdb_id}") {
            if let imdb = ids.imdb {
                fallbacks.append(decoded.replacingOccurrences(of: "/tvdb/", with: "/imdb/")
                    .replacingOccurrences(of: "\(typePrefix)-{tvdb_id}", with: imdb)
                    .replacingOccurrences(of: "{tvdb_id}", with: imdb))
            }
            if let tmdb = ids.tmdb {
                fallbacks.append(decoded.replacingOccurrences(of: "/tvdb/", with: "/tmdb/")
                    .replacingOccurrences(of: "{tvdb_id}", with: tmdb))
            }
        }
        for fallback in fallbacks {
            if let resolved = fill(fallback, tokens: scanTokens(fallback), ids: ids, type: type, shape: shape) {
                return resolved
            }
        }
        return nil
    }

    // MARK: Internals

    private struct Token {
        let range: Range<String.Index>
        let optional: Bool
        let keys: [String]
    }

    private static func decodePlaceholders(_ pattern: String) -> String {
        guard pattern.contains("%") else { return pattern }
        return pattern
            .replacingOccurrences(of: "%7B", with: "{", options: .caseInsensitive)
            .replacingOccurrences(of: "%7D", with: "}", options: .caseInsensitive)
            .replacingOccurrences(of: "%7C", with: "|", options: .caseInsensitive)
    }

    private static func isRPDBFamily(_ pattern: String) -> Bool {
        ["ratingposterdb.com", "aioratings.com", "top-posters.com", "btttr.cc"].contains { pattern.contains($0) }
    }

    private static func scanTokens(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var index = text.startIndex
        while let open = text[index...].firstIndex(of: "{") {
            guard let close = text[text.index(after: open)...].firstIndex(of: "}") else { break }
            var body = String(text[text.index(after: open)..<close])
            let optional = body.hasSuffix("?")
            if optional { body.removeLast() }
            let keys = body.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let valid = !keys.isEmpty && keys.allSatisfy { key in
                !key.isEmpty && key.allSatisfy { ($0 >= "a" && $0 <= "z") || $0 == "_" }
            }
            if valid {
                tokens.append(Token(range: open..<text.index(after: close), optional: optional, keys: keys))
                index = text.index(after: close)
            } else {
                index = text.index(after: open)
            }
        }
        return tokens
    }

    private static func fill(_ text: String, tokens: [Token], ids: ContentIDs, type: String, shape: String) -> String? {
        let (rawID, idType) = rawIDAndType(ids.id)
        let typedID = idType == "tmdb" || idType == "tvdb" ? "\(type == "movie" ? "movie" : "series")-\(rawID)" : rawID
        func lookup(_ key: String) -> String? {
            switch key {
            case "id": ids.id
            case "id_type": idType
            case "typed_id": typedID
            case "type": type
            case "shape": shape
            case "imdb_id": ids.imdb ?? ""
            case "tmdb_id": ids.tmdb ?? ""
            case "tvdb_id": ids.tvdb ?? ""
            case "kitsu_id": ids.kitsu ?? ""
            case "anilist_id": ids.anilist ?? ""
            case "mal_id": ids.mal ?? ""
            case "anidb_id": ids.anidb ?? ""
            default: nil
            }
        }
        // IDs go in as written, as Nuvio does; only characters a URL can't
        // hold are escaped.
        func encoded(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.union(.urlPathAllowed)) ?? value
        }
        var output = ""
        var cursor = text.startIndex
        for token in tokens {
            output += text[cursor..<token.range.lowerBound]
            if token.keys.count > 1 {
                guard let value = token.keys.lazy.compactMap(lookup).first(where: { !$0.isEmpty }) else { return nil }
                output += encoded(value)
            } else if let value = lookup(token.keys[0]) {
                if value.isEmpty && !token.optional { return nil }
                output += encoded(value)
            } else {
                // Not a placeholder Omnia knows: left as written.
                output += text[token.range]
            }
            cursor = token.range.upperBound
        }
        output += text[cursor...]
        return output
    }

    private static func rawIDAndType(_ id: String) -> (String, String) {
        if id.hasPrefix("tt") { return (id, "imdb") }
        if let colon = id.firstIndex(of: ":") {
            return (String(id[id.index(after: colon)...]), String(id[..<colon]))
        }
        return (id, "unknown")
    }
}
