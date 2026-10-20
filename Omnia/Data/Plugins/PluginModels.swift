//
//  PluginModels.swift
//  Omnia
//

import Foundation

/// A plugin repository's `manifest.json`, in the format Nuvio reads: a name,
/// a version, and the scrapers it offers, each a JavaScript file that exports
/// `getStreams(tmdbId, mediaType, season, episode)`.
nonisolated struct PluginRepositoryManifest: Decodable, Sendable {
    let name: String
    let version: String
    let description: String?
    let author: String?
    let scrapers: [Scraper]

    nonisolated struct Scraper: Decodable, Sendable {
        let id: String
        let name: String
        let description: String?
        let version: String
        let filename: String
        let supportedTypes: [String]
        let enabled: Bool
        let hasSettings: Bool
        let logo: String?
        let contentLanguage: [String]
        let formats: [String]?
        let supportedPlatforms: [String]?
        let disabledPlatforms: [String]?

        private enum CodingKeys: String, CodingKey {
            case id, name, description, version, filename, supportedTypes, enabled, hasSettings, logo
            case contentLanguage, formats, supportedFormats, supportedPlatforms, disabledPlatforms
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = (try? container.decode(String.self, forKey: .name)) ?? id
            description = try? container.decode(String.self, forKey: .description)
            version = (try? container.decode(String.self, forKey: .version)) ?? "1.0.0"
            filename = try container.decode(String.self, forKey: .filename)
            supportedTypes = (try? container.decode([String].self, forKey: .supportedTypes)) ?? ["movie", "tv"]
            enabled = (try? container.decode(Bool.self, forKey: .enabled)) ?? true
            hasSettings = (try? container.decode(Bool.self, forKey: .hasSettings)) ?? false
            logo = try? container.decode(String.self, forKey: .logo)
            contentLanguage = (try? container.decode([String].self, forKey: .contentLanguage)) ?? []
            formats = (try? container.decode([String].self, forKey: .formats))
                ?? (try? container.decode([String].self, forKey: .supportedFormats))
            supportedPlatforms = try? container.decode([String].self, forKey: .supportedPlatforms)
            disabledPlatforms = try? container.decode([String].self, forKey: .disabledPlatforms)
        }

        /// Scrapers can be limited to, or kept off, some platforms.
        var runsOnThisPlatform: Bool {
            let tags = Set(PluginPlatform.tags)
            let supported = Set((supportedPlatforms ?? []).map { $0.lowercased() })
            let disabled = Set((disabledPlatforms ?? []).map { $0.lowercased() })
            if !supported.isEmpty, supported.isDisjoint(with: tags) { return false }
            return disabled.isDisjoint(with: tags)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case name, version, description, author, scrapers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        version = (try? container.decode(String.self, forKey: .version)) ?? ""
        description = try? container.decode(String.self, forKey: .description)
        author = try? container.decode(String.self, forKey: .author)
        // One malformed entry shouldn't hide the repository's other scrapers.
        scrapers = ((try? container.decode([LossyScraper].self, forKey: .scrapers)) ?? []).compactMap(\.value)
    }

    private struct LossyScraper: Decodable {
        let value: Scraper?
        init(from decoder: Decoder) throws {
            value = try? Scraper(from: decoder)
        }
    }
}

nonisolated enum PluginPlatform {
    static var tags: [String] {
        #if os(macOS)
        ["macos", "desktop"]
        #else
        ["ios"]
        #endif
    }
}

/// An installed plugin repository.
nonisolated struct PluginRepository: Codable, Hashable, Identifiable, Sendable {
    let manifestURL: URL
    var name: String
    var description: String?
    var version: String?
    var author: String?
    var scraperCount: Int
    var lastUpdated: Date?

    var id: String { manifestURL.absoluteString }

    /// Nuvio refreshes repositories every six hours.
    static let refreshInterval: TimeInterval = 6 * 60 * 60

    func isRefreshDue(now: Date = .now) -> Bool {
        guard let lastUpdated else { return true }
        return now.timeIntervalSince(lastUpdated) >= Self.refreshInterval
    }
}

/// One scraper from a repository. Its code is kept in its own file.
nonisolated struct PluginScraper: Codable, Hashable, Identifiable, Sendable {
    /// `<repository manifest URL, lowercased>:<scraper id>`, as Nuvio keys them.
    let id: String
    let repositoryURL: URL
    var name: String
    var description: String
    var version: String
    var filename: String
    var supportedTypes: [String]
    var isEnabled: Bool
    /// False when the repository ships it turned off; it then stays off.
    var manifestEnabled: Bool
    var hasSettings: Bool
    var logo: URL?
    var contentLanguage: [String]
    var formats: [String]?

    func supports(type: String) -> Bool {
        let wanted = Self.normalizedType(type)
        return supportedTypes.contains { Self.normalizedType($0) == wanted }
    }

    /// Plugins name series "tv", as TMDB does.
    static func normalizedType(_ type: String) -> String {
        switch type.lowercased() {
        case "series", "show", "other", "anime": "tv"
        default: type.lowercased()
        }
    }
}

/// One stream a scraper returned.
nonisolated struct PluginStreamResult: Hashable, Sendable {
    let title: String
    let name: String?
    let url: String
    let quality: String?
    let size: String?
    let language: String?
    let provider: String?
    let type: String?
    let seeders: Int?
    let peers: Int?
    let infoHash: String?
    let headers: [String: String]
    let subtitles: [Subtitle]

    nonisolated struct Subtitle: Hashable, Sendable {
        let url: String
        let language: String
        let name: String?
    }

    /// Reads the array `getStreams` resolved with. Entries without a URL are
    /// dropped, and so are "[object Object]" strings from careless plugins.
    static func results(fromJSON json: String) -> [PluginStreamResult] {
        guard let data = json.data(using: .utf8),
              let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any]
        else { return [] }

        return array.compactMap { element in
            guard let item = element as? [String: Any] else { return nil }
            let url: String? = switch item["url"] {
            case let value as String: value
            case let value as [String: Any]: value["url"] as? String
            default: nil
            }
            guard let url = url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty else { return nil }

            let subtitles = (item["subtitles"] as? [[String: Any]] ?? []).compactMap { subtitle -> Subtitle? in
                guard let url = string(subtitle["url"]) else { return nil }
                return Subtitle(url: url, language: string(subtitle["language"]) ?? "Unknown", name: string(subtitle["name"]))
            }
            return PluginStreamResult(
                title: string(item["title"]) ?? string(item["name"]) ?? "Unknown",
                name: string(item["name"]),
                url: url,
                quality: string(item["quality"]),
                size: string(item["size"]),
                language: string(item["language"]),
                provider: string(item["provider"]),
                type: string(item["type"]),
                seeders: int(item["seeders"]),
                peers: int(item["peers"]),
                infoHash: string(item["infoHash"]),
                headers: headers(item["headers"]),
                subtitles: subtitles
            )
        }
    }

    private static func string(_ value: Any?) -> String? {
        let text: String? = switch value {
        case let value as String: value
        case let value as NSNumber: value.stringValue
        default: nil
        }
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, !text.contains("[object")
        else { return nil }
        return text
    }

    private static func int(_ value: Any?) -> Int? {
        switch value {
        case let value as NSNumber: value.intValue
        case let value as String: Int(value)
        default: nil
        }
    }

    private static func headers(_ value: Any?) -> [String: String] {
        guard let object = value as? [String: Any] else { return [:] }
        return object.reduce(into: [:]) { result, entry in
            if let text = string(entry.value) { result[entry.key] = text }
        }
    }
}

/// A field from a plugin's `onSettings()` layout: a header, a note, a text
/// field, a menu or a switch, as Nuvio draws them.
nonisolated struct PluginSettingsField: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case header
        case info
        case text(placeholder: String?, isSecure: Bool)
        case select(options: [Option])
        case toggle
    }

    nonisolated struct Option: Hashable, Sendable {
        let value: String
        let label: String
    }

    let id: Int
    let kind: Kind
    let key: String
    let label: String
    let detail: String?
    let defaultText: String?
    let defaultBool: Bool?

    static func fields(fromJSON json: String) -> [PluginSettingsField] {
        guard let data = json.data(using: .utf8),
              let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
        else { return [] }

        return array.enumerated().compactMap { index, field in
            let key = field["key"] as? String ?? ""
            let type = (field["type"] as? String ?? "info").lowercased()
            let label = field["label"] as? String ?? field["title"] as? String ?? key
            let detail = field["description"] as? String ?? field["text"] as? String
            let kind: Kind
            switch type {
            case "header": kind = .header
            case "text", "input", "password":
                kind = .text(
                    placeholder: field["placeholder"] as? String,
                    isSecure: type == "password" || (field["secure"] as? Bool ?? false)
                )
            case "select":
                let options = (field["options"] as? [Any] ?? []).compactMap { option -> Option? in
                    if let option = option as? [String: Any] {
                        let value = (option["value"] as? String) ?? (option["value"] as? NSNumber)?.stringValue
                        guard let value else { return nil }
                        return Option(value: value, label: option["label"] as? String ?? value)
                    }
                    if let option = option as? String { return Option(value: option, label: option) }
                    return nil
                }
                kind = .select(options: options)
            case "toggle", "switch", "boolean": kind = .toggle
            default: kind = .info
            }
            switch kind {
            case .text, .select, .toggle: if key.isEmpty { return nil }
            case .header, .info: break
            }
            let defaultValue = field["defaultValue"] ?? field["default"]
            return PluginSettingsField(
                id: index,
                kind: kind,
                key: key,
                label: label,
                detail: detail,
                defaultText: (defaultValue as? String) ?? (defaultValue as? NSNumber).flatMap { CFGetTypeID($0) == CFBooleanGetTypeID() ? nil : $0.stringValue },
                defaultBool: (defaultValue as? NSNumber).flatMap { CFGetTypeID($0) == CFBooleanGetTypeID() ? $0.boolValue : nil }
            )
        }
    }
}
