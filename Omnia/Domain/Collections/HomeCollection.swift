//
//  HomeCollection.swift
//  Omnia
//

import Foundation

/// A Nuvio collection: a titled row of folders on Home. The JSON format is
/// Nuvio's `collections.json`, which Xperience also exports, so files move
/// between the apps unchanged.
nonisolated struct HomeCollection: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var pinToTop: Bool
    /// Nuvio's `TABBED_GRID`, `ROWS` or `FOLLOW_LAYOUT`.
    var viewMode: String
    var showAllTab: Bool
    var backdropImageUrl: URL?
    var folders: [HomeCollectionFolder]

    static let maximumCollections = 64
    static let maximumFolders = 256

    var layoutKey: String { Self.layoutKey(for: id) }

    static func layoutKey(for id: String) -> String { "collection:\(id)" }

    /// Folder pages show one row per source instead of tabs.
    var showsSourcesAsRows: Bool { viewMode.uppercased() == "ROWS" }

    private enum CodingKeys: String, CodingKey {
        case id, title, pinToTop, viewMode, showAllTab, backdropImageUrl, folders
    }

    /// A new, empty collection, as Nuvio's editor starts one.
    init(
        id: String = UUID().uuidString.lowercased(),
        title: String = "",
        pinToTop: Bool = false,
        viewMode: String = ViewMode.tabs.rawValue,
        showAllTab: Bool = true,
        backdropImageUrl: URL? = nil,
        folders: [HomeCollectionFolder] = []
    ) {
        self.id = id
        self.title = title
        self.pinToTop = pinToTop
        self.viewMode = viewMode
        self.showAllTab = showAllTab
        self.backdropImageUrl = backdropImageUrl
        self.folders = folders
    }

    /// Nuvio's folder page layouts. Files may also hold `FOLLOW_LAYOUT`,
    /// which Omnia shows as tabs.
    enum ViewMode: String, CaseIterable, Sendable {
        case tabs = "TABBED_GRID"
        case rows = "ROWS"

        var title: String {
            switch self {
            case .tabs: "Tabs"
            case .rows: "Rows"
            }
        }
    }

    var layout: ViewMode {
        get { showsSourcesAsRows ? .rows : .tabs }
        set { viewMode = newValue.rawValue }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = container.manifestString(forKey: .id), !id.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "A collection needs an id.")
        }
        self.id = id
        title = container.manifestString(forKey: .title)?.collectionTrimmed ?? "Collection"
        pinToTop = container.manifestBool(forKey: .pinToTop) ?? false
        viewMode = container.manifestString(forKey: .viewMode) ?? "FOLLOW_LAYOUT"
        showAllTab = container.manifestBool(forKey: .showAllTab) ?? true
        backdropImageUrl = container.collectionImageURL(forKey: .backdropImageUrl)
        folders = Array((container.manifestArray(HomeCollectionFolder.self, forKey: .folders) ?? []).prefix(Self.maximumFolders))
    }
}

nonisolated struct HomeCollectionFolder: Codable, Hashable, Sendable, Identifiable {
    enum TileShape: String, Codable, Sendable {
        case poster = "POSTER"
        case landscape = "LANDSCAPE"
        case wide = "WIDE"
        case square = "SQUARE"

        static let allCases: [TileShape] = [.poster, .landscape, .wide, .square]

        var title: String {
            switch self {
            case .poster: "Poster"
            case .landscape: "Landscape"
            case .wide: "Wide"
            case .square: "Square"
            }
        }

        /// Width divided by height.
        var aspectRatio: Double {
            switch self {
            case .poster: 2.0 / 3.0
            case .landscape: 16.0 / 9.0
            case .wide: 21.0 / 9.0
            case .square: 1
            }
        }
    }

    var id: String
    var title: String
    var hideTitle: Bool
    var coverImageUrl: URL?
    var coverEmoji: String?
    var heroBackdropUrl: URL?
    var titleLogoUrl: URL?
    /// Xperience's animated cover, shown in place of the still one as Nuvio does.
    var focusGifUrl: URL?
    var focusGifEnabled: Bool
    var tileShape: TileShape
    var sources: [HomeCollectionSource]

    static let maximumSources = 64

    private enum CodingKeys: String, CodingKey {
        case id, title, hideTitle, coverImageUrl, coverEmoji, heroBackdropUrl, titleLogoUrl, focusGifUrl, focusGifEnabled, tileShape, sources, catalogSources
    }

    /// A new folder, as Nuvio's editor adds one.
    init(id: String = UUID().uuidString.lowercased(), title: String = "New Folder") {
        self.id = id
        self.title = title
        hideTitle = false
        coverImageUrl = nil
        coverEmoji = nil
        heroBackdropUrl = nil
        titleLogoUrl = nil
        focusGifUrl = nil
        focusGifEnabled = true
        tileShape = .poster
        sources = []
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = container.manifestString(forKey: .id), !id.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "A folder needs an id.")
        }
        self.id = id
        title = container.manifestString(forKey: .title)?.collectionTrimmed ?? "Folder"
        hideTitle = container.manifestBool(forKey: .hideTitle) ?? false
        coverImageUrl = container.collectionImageURL(forKey: .coverImageUrl)
        coverEmoji = container.manifestString(forKey: .coverEmoji)?.collectionTrimmed
        heroBackdropUrl = container.collectionImageURL(forKey: .heroBackdropUrl)
        titleLogoUrl = container.collectionImageURL(forKey: .titleLogoUrl)
        focusGifUrl = container.collectionImageURL(forKey: .focusGifUrl)
        focusGifEnabled = container.manifestBool(forKey: .focusGifEnabled) ?? true
        tileShape = container.manifestString(forKey: .tileShape)
            .flatMap { TileShape(rawValue: $0.uppercased()) } ?? .poster
        // Newer files use `sources`; older ones only `catalogSources`.
        let decoded = container.manifestArray(HomeCollectionSource.self, forKey: .sources)
            ?? container.manifestArray(HomeCollectionSource.self, forKey: .catalogSources)
            ?? []
        sources = Array(decoded.prefix(Self.maximumSources))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(hideTitle, forKey: .hideTitle)
        try container.encodeIfPresent(coverImageUrl, forKey: .coverImageUrl)
        try container.encodeIfPresent(coverEmoji, forKey: .coverEmoji)
        try container.encodeIfPresent(heroBackdropUrl, forKey: .heroBackdropUrl)
        try container.encodeIfPresent(titleLogoUrl, forKey: .titleLogoUrl)
        try container.encodeIfPresent(focusGifUrl, forKey: .focusGifUrl)
        try container.encode(focusGifEnabled, forKey: .focusGifEnabled)
        try container.encode(tileShape, forKey: .tileShape)
        // Written under both keys so older Nuvio builds can read the export.
        try container.encode(sources, forKey: .sources)
        try container.encode(sources.filter(\.isAddonSource), forKey: .catalogSources)
    }
}

/// One catalog shown inside a folder. Only add-on catalogs are supported;
/// Nuvio's TMDB and Trakt list sources need those integrations first.
nonisolated struct HomeCollectionSource: Codable, Hashable, Sendable {
    var provider: String
    var addonId: String
    var type: String
    var catalogId: String
    /// Nuvio writes "None" for "no genre".
    var genre: String?

    var isAddonSource: Bool { provider.lowercased() == "addon" }

    /// The genre to request, or nil for none.
    var requestedGenre: String? {
        guard let genre = genre?.collectionTrimmed, genre.lowercased() != "none" else { return nil }
        return genre
    }

    private enum CodingKeys: String, CodingKey {
        case provider, addonId, type, catalogId, genre
    }

    /// An installed add-on's catalog, picked in the folder editor.
    init(addonId: String, type: String, catalogId: String, genre: String? = nil) {
        provider = "addon"
        self.addonId = addonId
        self.type = type
        self.catalogId = catalogId
        self.genre = genre
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let catalogId = container.manifestString(forKey: .catalogId), !catalogId.isEmpty,
              let type = container.manifestString(forKey: .type), !type.isEmpty
        else {
            throw DecodingError.dataCorruptedError(forKey: .catalogId, in: container, debugDescription: "A source needs a catalog.")
        }
        self.catalogId = catalogId
        self.type = type
        provider = container.manifestString(forKey: .provider) ?? "addon"
        addonId = container.manifestString(forKey: .addonId) ?? ""
        genre = container.manifestString(forKey: .genre)
    }
}

/// Reads a `collections.json` file: a bare array, or an object with a
/// `collections` array. Broken entries are skipped.
nonisolated enum HomeCollectionFile {
    static let maximumBytes = 10 * 1_024 * 1_024

    enum ImportError: LocalizedError {
        case tooLarge
        case unreadable
        case empty

        var errorDescription: String? {
            switch self {
            case .tooLarge: "The file is larger than 10 MB."
            case .unreadable: "The file isn't a Nuvio or Xperience collections file."
            case .empty: "The file doesn't contain any collections."
            }
        }
    }

    private struct LossyCollection: Decodable {
        let value: HomeCollection?
        init(from decoder: Decoder) throws { value = try? HomeCollection(from: decoder) }
    }

    private struct Wrapper: Decodable {
        let collections: [LossyCollection]
    }

    static func collections(from data: Data) throws -> [HomeCollection] {
        guard data.count <= maximumBytes else { throw ImportError.tooLarge }
        let decoder = JSONDecoder()
        let entries: [LossyCollection]
        if let array = try? decoder.decode([LossyCollection].self, from: data) {
            entries = array
        } else if let wrapper = try? decoder.decode(Wrapper.self, from: data) {
            entries = wrapper.collections
        } else {
            throw ImportError.unreadable
        }
        let collections = entries.compactMap(\.value)
        guard !collections.isEmpty else { throw ImportError.empty }
        return Array(collections.prefix(HomeCollection.maximumCollections))
    }

    static func data(for collections: [HomeCollection]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(collections)
    }
}

/// Finds the installed add-on catalog a folder source points at, the way
/// Nuvio does: the exact add-on first, then any add-on with that catalog,
/// then the catalog id before its first comma.
///
/// Xperience lists only the catalogs picked in its configuration, while its
/// collection files point at many more that the same add-on still serves.
/// When the folder's own add-on is installed but doesn't list the catalog,
/// it is requested from that add-on anyway; a catalog the add-on really
/// lacks then fails on its own tab.
nonisolated enum HomeCollectionSourceResolver {
    struct Resolved: Hashable, Sendable {
        let addon: InstalledAddon
        let catalog: AddonCatalog
        /// False when the add-on's manifest doesn't list this catalog.
        var isListed = true
    }

    static func resolve(_ source: HomeCollectionSource, in addons: [InstalledAddon]) -> Resolved? {
        guard source.isAddonSource else { return nil }
        let enabled = addons.filter(\.isEnabled)
        let baseID = source.catalogId.split(separator: ",").first.map(String.init) ?? source.catalogId

        for catalogID in [source.catalogId, baseID] {
            // Several configurations of one add-on can be installed; the
            // first that lists the catalog wins.
            for addon in enabled where addon.manifest.id == source.addonId {
                if let catalog = addon.manifest.catalogs.first(where: { $0.id == catalogID && $0.type == source.type }) {
                    return Resolved(addon: addon, catalog: catalog)
                }
            }
            for addon in enabled {
                if let catalog = addon.manifest.catalogs.first(where: { $0.id == catalogID && $0.type == source.type }) {
                    return Resolved(addon: addon, catalog: catalog)
                }
            }
        }

        guard let addon = declaredAddon(for: source, in: enabled), addon.manifest.supportsCatalogs else { return nil }
        let genre = source.requestedGenre.map { _ in
            [AddonCatalogExtra(name: "genre", isRequired: false, options: nil, optionsLimit: nil)]
        }
        return Resolved(
            addon: addon,
            catalog: AddonCatalog(type: source.type, id: source.catalogId, name: readableName(source.catalogId), extra: genre),
            isListed: false
        )
    }

    /// Why `resolve` found nothing for a source, in words a person can act on.
    static func unavailableReason(for source: HomeCollectionSource, in addons: [InstalledAddon]) -> String {
        guard source.isAddonSource else {
            return "Omnia can't load catalogs from \(source.provider) yet."
        }
        if let addon = declaredAddon(for: source, in: addons) {
            if !addon.isEnabled { return "\(addon.displayName) is turned off." }
            if !addon.manifest.supportsCatalogs { return "\(addon.displayName) doesn't provide catalogs." }
        }
        return "The add-on this collection was made for isn't installed."
    }

    /// The add-on the file names, or, since each Xperience configuration
    /// has its own id (`app.xperience.<uuid>`), another configuration of it.
    private static func declaredAddon(for source: HomeCollectionSource, in addons: [InstalledAddon]) -> InstalledAddon? {
        if let exact = addons.first(where: { $0.manifest.id == source.addonId }) { return exact }
        // Needs at least `vendor.name.config`, so a bare id never matches widely.
        let parts = source.addonId.split(separator: ".")
        guard parts.count >= 3 else { return nil }
        let family = parts.dropLast().joined(separator: ".") + "."
        return addons.first { $0.manifest.id.hasPrefix(family) }
    }

    /// `genre_action_latest_movies` reads as "Genre Action Latest Movies".
    static func readableName(_ id: String) -> String {
        id.split(whereSeparator: { $0 == "_" || $0 == "-" || $0 == "." })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}


extension KeyedDecodingContainer {
    /// HTTPS images only, so a collection file can't trigger cleartext loads.
    nonisolated func collectionImageURL(forKey key: Key) -> URL? {
        guard let value = manifestString(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              url.host != nil
        else { return nil }
        return url
    }
}

private extension String {
    nonisolated var collectionTrimmed: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
