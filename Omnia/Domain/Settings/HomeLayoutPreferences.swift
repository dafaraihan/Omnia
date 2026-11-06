//
//  HomeLayoutPreferences.swift
//  Omnia
//

import Foundation

/// How add-on catalogs are arranged on Home: their order, custom titles and
/// which catalogs feed the hero. Whether a catalog is shown at all stays in
/// `OmniaStore.disabledAddonCatalogIDs`, so the Catalogs page and Home Layout
/// always agree.
nonisolated struct HomeLayoutPreferences: Codable, Equatable, Sendable {
    /// Nuvio caps hero sources at two catalogs; more sources dilute the
    /// eight-title carousel without adding variety.
    static let heroSourceLimit = 6
    static let heroItemLimit = 15

    /// Nuvio Enhanced's Hero Style.
    enum HeroStyle: String, Codable, CaseIterable, Identifiable, Sendable {
        case fullBleed, card
        var id: Self { self }
        var title: String {
            switch self {
            case .fullBleed: "Full-bleed"
            case .card: "Card"
            }
        }
        var detail: String {
            switch self {
            case .fullBleed: "Artwork fills the width of the window."
            case .card: "Artwork sits in a rounded card."
            }
        }
    }

    var showsHero = true
    var heroStyle: HeroStyle = .fullBleed
    /// Artwork-derived Home tint. New profiles opt in; decoded legacy layouts
    /// retain their previous default when the key predates this preference.
    var dynamicBackground = false
    var showsCatalogType = true
    var hidesUnreleasedContent = false
    /// Catalog keys in display order. Keys of add-ons that are temporarily
    /// missing are kept so they return to the same place.
    var order: [String] = []
    var customTitles: [String: String] = [:]
    var heroSourceKeys: [String] = []
    /// Until the user picks hero sources, the first two visible catalogs are
    /// used, as in Nuvio.
    var hasCustomHeroSources = false
    /// Media server rows turned off on Home. Server rows are shown unless
    /// they are listed here.
    var hiddenServerRowKeys: [String] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case showsHero, showsCatalogType, hidesUnreleasedContent, order, customTitles, heroSourceKeys, hasCustomHeroSources
        case heroStyle, dynamicBackground, hiddenServerRowKeys
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showsHero = try container.decodeIfPresent(Bool.self, forKey: .showsHero) ?? true
        showsCatalogType = try container.decodeIfPresent(Bool.self, forKey: .showsCatalogType) ?? true
        hidesUnreleasedContent = try container.decodeIfPresent(Bool.self, forKey: .hidesUnreleasedContent) ?? false
        order = try container.decodeIfPresent([String].self, forKey: .order) ?? []
        customTitles = try container.decodeIfPresent([String: String].self, forKey: .customTitles) ?? [:]
        heroSourceKeys = try container.decodeIfPresent([String].self, forKey: .heroSourceKeys) ?? []
        hasCustomHeroSources = try container.decodeIfPresent(Bool.self, forKey: .hasCustomHeroSources) ?? false
        heroStyle = (try? container.decodeIfPresent(HeroStyle.self, forKey: .heroStyle)) ?? .fullBleed
        dynamicBackground = (try? container.decodeIfPresent(Bool.self, forKey: .dynamicBackground)) ?? true
        hiddenServerRowKeys = (try? container.decodeIfPresent([String].self, forKey: .hiddenServerRowKeys)) ?? []
    }

    /// Known keys keep their saved position; catalogs that appeared since are
    /// appended in the order their add-ons declare them.
    func ordered(_ keys: [String]) -> [String] {
        let available = Set(keys)
        let saved = order.filter { available.contains($0) }
        let savedSet = Set(saved)
        return saved + keys.filter { !savedSet.contains($0) }
    }

    /// `orderedVisibleKeys` must already be in Home order.
    func heroSources(orderedVisibleKeys: [String], allKeys: [String]) -> [String] {
        if hasCustomHeroSources {
            let available = Set(allKeys)
            return Array(heroSourceKeys.filter { available.contains($0) }.prefix(Self.heroSourceLimit))
        }
        return Array(orderedVisibleKeys.prefix(Self.heroSourceLimit))
    }
}

/// A Home row: an add-on catalog, a collection or a media server row, in
/// Home order.
enum HomeRowEntry: Identifiable {
    case catalog(AddonHomeCatalog)
    case collection(HomeCollection)
    case server(MediaServerHomeRow)

    var id: String {
        switch self {
        case let .catalog(catalog): catalog.key
        case let .collection(collection): collection.layoutKey
        case let .server(row): row.key
        }
    }

    /// Pinned collections stay above everything and can't be moved.
    var isPinned: Bool {
        if case let .collection(collection) = self { return collection.pinToTop }
        return false
    }
}

/// One add-on catalog that can appear as a Home row.
struct AddonHomeCatalog: Identifiable, Hashable {
    let key: String
    let addon: InstalledAddon
    let catalog: AddonCatalog

    var id: String { key }
    var catalogName: String {
        let name = catalog.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? catalog.id : name
    }

    var typeLabel: String { Self.typeLabel(for: catalog.type) }

    /// "Popular - Movies" when the type is shown, otherwise "Popular".
    func defaultTitle(showsCatalogType: Bool) -> String {
        showsCatalogType ? "\(catalogName) - \(typeLabel)" : catalogName
    }

    var supportsPagination: Bool {
        catalog.supportsPagination
    }

    static func typeLabel(for type: String) -> String {
        switch type.lowercased() {
        case "movie": "Movies"
        case "series": "Series"
        case "anime": "Anime"
        case "tv": "TV"
        case "channel": "Channels"
        case "anime.movie": "Anime Movies"
        case "anime.series": "Anime Series"
        default: type.capitalized
        }
    }

    /// Catalog types are free-form (`Trakt`, `collection`, `anime.movie`), and
    /// each title carries its own type, so any catalog can be a row; titles
    /// Omnia can't open are dropped and an empty row stays hidden. People and
    /// live channels aren't titles.
    static func isSupportedType(_ type: String) -> Bool {
        !["person", "people", "channel", "events"].contains(type.lowercased())
    }
}
