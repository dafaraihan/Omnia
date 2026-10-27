//
//  MetadataRouting.swift
//  Omnia
//

import Foundation

/// The content class whose metadata routing the user controls.
nonisolated enum MetadataContentClass: String, CaseIterable, Codable, Identifiable, Sendable {
    case movies
    case series
    case anime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .movies: "Movies"
        case .series: "TV Shows"
        case .anime: "Anime"
        }
    }

    var availableSources: [MetadataProviderIdentifier] {
        switch self {
        case .movies, .series: [.tmdb, .tvdb]
        case .anime: [.anilist, .kitsu, .myanimelist, .tvdb, .tmdb]
        }
    }
}

/// Sources Omnia can route metadata requests through. This is intentionally
/// distinct from credential configuration: a source can be selectable only
/// when its server-side or user-managed connection is available.
nonisolated enum MetadataProviderIdentifier: String, Codable, CaseIterable, Identifiable, Sendable {
    case tmdb
    case tvdb
    case anilist
    /// Kitsu and MyAnimeList (through Jikan) were added 2026-10-27; both
    /// are public, like AniList.
    case kitsu
    case myanimelist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tmdb: "TMDB"
        case .tvdb: "TVDB"
        case .anilist: "AniList"
        case .kitsu: "Kitsu"
        case .myanimelist: "MyAnimeList"
        }
    }

    /// TMDB and TVDB go through Omnia's metadata service; the anime
    /// databases are asked directly.
    var isServedByMetadataService: Bool { self == .tmdb || self == .tvdb }

    /// Sources that look a title up by its anime database ID, for Anime
    /// Enrichment.
    var isAnimeDatabase: Bool { !isServedByMetadataService }
}

nonisolated enum MetadataFallbackMoveDirection: Equatable, Sendable {
    case earlier
    case later
}

nonisolated struct MetadataRoute: Codable, Equatable, Sendable {
    var primary: MetadataProviderIdentifier
    var fallbackEnabled: Bool
    var fallbackOrder: [MetadataProviderIdentifier]

    init(
        primary: MetadataProviderIdentifier,
        fallbackEnabled: Bool = true,
        fallbackOrder: [MetadataProviderIdentifier] = []
    ) {
        self.primary = primary
        self.fallbackEnabled = fallbackEnabled
        self.fallbackOrder = fallbackOrder
    }

    mutating func setPrimary(_ provider: MetadataProviderIdentifier, allowed: [MetadataProviderIdentifier]) {
        primary = provider
        fallbackOrder.removeAll { $0 == provider || !allowed.contains($0) }
        fallbackOrder = Self.completeFallbackOrder(fallbackOrder, primary: provider, allowed: allowed)
    }

    mutating func setFallback(_ provider: MetadataProviderIdentifier, enabled: Bool, allowed: [MetadataProviderIdentifier]) {
        guard provider != primary, allowed.contains(provider) else { return }
        if enabled {
            if !fallbackOrder.contains(provider) { fallbackOrder.append(provider) }
        } else {
            fallbackOrder.removeAll { $0 == provider }
        }
        fallbackOrder = Self.completeFallbackOrder(fallbackOrder, primary: primary, allowed: allowed, includeAll: false)
    }

    mutating func moveFallback(from source: IndexSet, to destination: Int) {
        let moving = source.sorted().map { fallbackOrder[$0] }
        for index in source.sorted(by: >) {
            fallbackOrder.remove(at: index)
        }
        let removedBeforeDestination = source.filter { $0 < destination }.count
        let insertionIndex = max(0, min(destination - removedBeforeDestination, fallbackOrder.count))
        fallbackOrder.insert(contentsOf: moving, at: insertionIndex)
    }

    @discardableResult
    mutating func moveFallback(
        _ provider: MetadataProviderIdentifier,
        direction: MetadataFallbackMoveDirection
    ) -> Bool {
        guard let source = fallbackOrder.firstIndex(of: provider) else { return false }
        let destination = direction == .earlier ? source - 1 : source + 1
        guard fallbackOrder.indices.contains(destination) else { return false }

        fallbackOrder.swapAt(source, destination)
        return true
    }

    /// The ordered provider list sent to the metadata service. The primary is
    /// always first; fallbacks are included only when the user enables them.
    var requestedProviders: [MetadataProviderIdentifier] {
        [primary] + (fallbackEnabled ? fallbackOrder : [])
    }

    // MARK: One ordered list

    /// Settings shows a type's sources as one list: those in use in the
    /// order they're asked (the first is the primary), then the rest
    /// (Dafa, 2026-10-26).
    func orderedSources(allowed: [MetadataProviderIdentifier]) -> [MetadataProviderIdentifier] {
        let inUse = requestedProviders.filter(allowed.contains)
        return inUse + allowed.filter { !inUse.contains($0) }
    }

    func isInUse(_ provider: MetadataProviderIdentifier) -> Bool {
        requestedProviders.contains(provider)
    }

    /// Uses exactly `order`, first to last: the first is the primary and
    /// the rest fill in what it's missing. Ignored when nothing is left on.
    mutating func setSources(inUseOrder order: [MetadataProviderIdentifier], allowed: [MetadataProviderIdentifier]) {
        var seen = Set<MetadataProviderIdentifier>()
        let sources = order.filter { allowed.contains($0) && seen.insert($0).inserted }
        guard let first = sources.first else { return }
        primary = first
        fallbackOrder = Array(sources.dropFirst())
        fallbackEnabled = true
    }

    private static func completeFallbackOrder(
        _ order: [MetadataProviderIdentifier],
        primary: MetadataProviderIdentifier,
        allowed: [MetadataProviderIdentifier],
        includeAll: Bool = true
    ) -> [MetadataProviderIdentifier] {
        let permitted = allowed.filter { $0 != primary }
        var result = order.filter { permitted.contains($0) }
        if includeAll {
            result.append(contentsOf: permitted.filter { !result.contains($0) })
        }
        return result
    }
}

nonisolated struct MetadataRoutingPreferences: Codable, Equatable, Sendable {
    var movies = MetadataRoute(primary: .tmdb, fallbackOrder: [.tvdb])
    var series = MetadataRoute(primary: .tvdb, fallbackOrder: [.tmdb])
    var anime = MetadataRoute(primary: .anilist, fallbackOrder: [.tvdb, .tmdb])

    subscript(_ contentClass: MetadataContentClass) -> MetadataRoute {
        get {
            switch contentClass {
            case .movies: movies
            case .series: series
            case .anime: anime
            }
        }
        set {
            switch contentClass {
            case .movies: movies = newValue
            case .series: series = newValue
            case .anime: anime = newValue
            }
        }
    }
}
