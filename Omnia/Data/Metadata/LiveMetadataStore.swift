//
//  LiveMetadataStore.swift
//  Omnia
//

import Foundation
import Observation
import SwiftUI

/// Read-only, provider-aggregated metadata for Omnia's built-in discovery.
/// The backing Edge Function accepts the project's verified publishable key;
/// it never exposes provider credentials or user-owned library data.
@Observable
@MainActor
final class LiveMetadataStore {
    private let client: SupabaseMetadataClient?

    var movieCatalog: [MediaItem] = []
    var seriesCatalog: [MediaItem] = []
    var homeCatalogs: [BuiltInHomeCatalog] = []
    var topMovies: [MediaItem] = []
    var topSeries: [MediaItem] = []
    var movieGenres: [MetadataGenre] = []
    var seriesGenres: [MetadataGenre] = []
    var searchResults: [MediaItem] = []
    var isLoadingCatalogs = false
    var isSearching = false
    var errorMessage: String?
    private var genreCatalogs: [String: [MediaItem]] = [:]

    init(configuration: SupabaseConfiguration? = nil, loadsBundleConfiguration: Bool = true) {
        let resolvedConfiguration = configuration ?? (loadsBundleConfiguration ? SupabaseConfiguration.load() : nil)
        client = resolvedConfiguration.map { SupabaseMetadataClient(configuration: $0) }
    }

    static let preview = LiveMetadataStore(loadsBundleConfiguration: false)

    func loadDefaultCatalogs() async {
        guard !isLoadingCatalogs, let client else { return }
        isLoadingCatalogs = true
        errorMessage = nil
        defer { isLoadingCatalogs = false }

        // Discovery requests are independent. One temporarily unavailable
        // provider route must not erase every already-working Home shelf.
        async let trendingMovies = safeExtendedCatalog(client, type: .movie, category: .trending)
        async let popularMovies = safeExtendedCatalog(client, type: .movie, category: .popular)
        async let nowPlaying = safeExtendedCatalog(client, type: .movie, category: .nowPlaying)
        async let upcoming = safeExtendedCatalog(client, type: .movie, category: .upcoming)
        async let trendingSeries = safeExtendedCatalog(client, type: .series, category: .trending)
        async let popularSeries = safeExtendedCatalog(client, type: .series, category: .popular)
        async let topRatedSeries = safeExtendedCatalog(client, type: .series, category: .topRated)
        async let airingToday = safeExtendedCatalog(client, type: .series, category: .airingToday)
        async let topRatedMovies = safeCatalogPage(client, type: .movie, category: .topRated)
        async let movieGenresResponse = safeGenres(client, type: .movie)
        async let seriesGenresResponse = safeGenres(client, type: .series)

        let responses = await (
                trendingMovies, popularMovies, nowPlaying, upcoming,
                trendingSeries, popularSeries, topRatedSeries, airingToday,
                topRatedMovies, movieGenresResponse, seriesGenresResponse
            )
        let rankedMovies = Array(responses.8.prefix(10))
            let rankedSeries = Array(responses.6.prefix(10))
            let shelves = Self.uniqueHomeCatalogs([
                BuiltInHomeCatalog(title: "Trending Now", kind: .movie, category: .trending, items: responses.0),
                BuiltInHomeCatalog(title: "Popular Movies", kind: .movie, category: .popular, items: responses.1),
                BuiltInHomeCatalog(title: "Popular Series", kind: .series, category: .popular, items: responses.5),
                BuiltInHomeCatalog(title: "In Theaters", kind: .movie, category: .nowPlaying, items: responses.2),
                BuiltInHomeCatalog(title: "Coming Soon", kind: .movie, category: .upcoming, items: responses.3),
                BuiltInHomeCatalog(title: "Series Worth Starting", kind: .series, category: .trending, items: responses.4),
                BuiltInHomeCatalog(title: "Top Rated Series", kind: .series, category: .topRated, items: responses.6),
                BuiltInHomeCatalog(title: "Airing Today", kind: .series, category: .airingToday, items: responses.7),
            ], excluding: rankedMovies + rankedSeries)

            movieCatalog = shelves.first(where: { $0.title == "Trending Now" })?.items ?? []
            seriesCatalog = shelves.first(where: { $0.title == "Series Worth Starting" })?.items ?? []
            topMovies = rankedMovies
            topSeries = rankedSeries
        movieGenres = responses.9
        seriesGenres = responses.10
        homeCatalogs = shelves

        if shelves.isEmpty, rankedMovies.isEmpty, rankedSeries.isEmpty {
            errorMessage = "Built-in discovery is temporarily unavailable."
        }
    }

    func search(_ text: String, type: MediaType) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2, let client else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            let response = try await client.search(query: query, type: type)
            guard query == text.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            searchResults = Self.rankedItems(from: response.results, matching: query)
        } catch is CancellationError {
            return
        } catch {
            guard query == text.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            searchResults = []
            errorMessage = "Metadata search is temporarily unavailable."
        }
    }

    func search(_ text: String) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2, let client else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            async let movies = client.search(query: query, type: .movie)
            async let series = client.search(query: query, type: .series)
            let (movieResponse, seriesResponse) = try await (movies, series)
            guard query == text.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            searchResults = Self.rankedItems(from: movieResponse.results + seriesResponse.results, matching: query)
        } catch is CancellationError {
            return
        } catch {
            guard query == text.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            searchResults = []
            errorMessage = "Metadata search is temporarily unavailable."
        }
    }

    func details(for item: MediaItem) async -> MediaItem {
        guard
            let client,
            let provider = item.metadataProvider,
            let identifier = item.metadataProviderID
        else { return item }

        do {
            let response = try await client.details(provider: provider, id: identifier, type: item.metadataType)
            return Self.item(
                from: response.item,
                progress: item.progress,
                positionSeconds: item.positionSeconds,
                durationSeconds: item.durationSeconds
            )
        } catch {
            return item
        }
    }

    func genreCatalog(for genre: MetadataGenre, type: MediaType) async -> [MediaItem] {
        let key = "\(type.rawValue):\(genre.id)"
        if let cached = genreCatalogs[key] {
            return cached
        }

        guard let client else { return [] }
        do {
            async let firstPage = client.catalog(type: type, category: .popular, genreID: genre.id, page: 1)
            async let secondPage = client.catalog(type: type, category: .popular, genreID: genre.id, page: 2)
            async let thirdPage = client.catalog(type: type, category: .popular, genreID: genre.id, page: 3)
            let responses = try await (firstPage, secondPage, thirdPage)
            let items = Self.items(from: responses.0.results + responses.1.results + responses.2.results)
            genreCatalogs[key] = items
            return items
        } catch {
            return []
        }
    }

    /// The catalog destination owns its own page state. This keeps Home and
    /// Discover light, while a user can keep scrolling without a small,
    /// hard-coded client-side title ceiling.
    func catalogPage(
        type: MediaType,
        category: MetadataCatalogCategory,
        genreID: Int? = nil,
        page: Int
    ) async -> [MediaItem] {
        guard let client, page > 0 else { return [] }
        do {
            let response = try await client.catalog(type: type, category: category, genreID: genreID, page: page)
            return Self.items(from: response.results)
        } catch {
            errorMessage = "Metadata discovery is temporarily unavailable."
            return []
        }
    }

    private static func items(from records: [OmniaMetadataRecord]) -> [MediaItem] {
        canonicalRecords(from: records).map { item(from: $0) }
    }

    /// Home shelves need replacement candidates after cross-shelf de-duplication.
    /// Two TMDB pages provide up to 40 candidates per category before that pass.
    private func extendedCatalog(
        _ client: SupabaseMetadataClient,
        type: MediaType,
        category: MetadataCatalogCategory
    ) async throws -> [MediaItem] {
        async let firstPage = client.catalog(type: type, category: category, page: 1)
        async let secondPage = client.catalog(type: type, category: category, page: 2)
        let responses = try await (firstPage, secondPage)
        return Self.items(from: responses.0.results + responses.1.results)
    }

    private func safeExtendedCatalog(
        _ client: SupabaseMetadataClient,
        type: MediaType,
        category: MetadataCatalogCategory
    ) async -> [MediaItem] {
        (try? await extendedCatalog(client, type: type, category: category)) ?? []
    }

    private func safeCatalogPage(
        _ client: SupabaseMetadataClient,
        type: MediaType,
        category: MetadataCatalogCategory
    ) async -> [MediaItem] {
        guard let response = try? await client.catalog(type: type, category: category) else { return [] }
        return Self.items(from: response.results)
    }

    private func safeGenres(_ client: SupabaseMetadataClient, type: MediaType) async -> [MetadataGenre] {
        (try? await client.genres(type: type).genres) ?? []
    }

    /// A title earns a single home-shelf placement. Ranked shelves reserve their
    /// titles first, then each subsequent shelf contributes only unseen items.
    private static func uniqueHomeCatalogs(
        _ catalogs: [BuiltInHomeCatalog],
        excluding reservedItems: [MediaItem]
    ) -> [BuiltInHomeCatalog] {
        var seen = Set(reservedItems.map(\.id))

        return catalogs.compactMap { catalog in
            let uniqueItems = catalog.items.filter { seen.insert($0.id).inserted }
            guard !uniqueItems.isEmpty else { return nil }
            return BuiltInHomeCatalog(title: catalog.title, kind: catalog.kind, category: catalog.category, items: uniqueItems)
        }
    }

    private static func rankedItems(from records: [OmniaMetadataRecord], matching query: String) -> [MediaItem] {
        let normalizedQuery = normalizedTitle(query)
        let queryTokens = normalizedQuery.split(separator: " ")

        return canonicalRecords(from: records)
            .filter { record in
                let title = normalizedTitle(record.title)
                return title.contains(normalizedQuery) || queryTokens.allSatisfy { title.contains($0) }
            }
            .sorted { lhs, rhs in
                searchScore(for: lhs, query: normalizedQuery) > searchScore(for: rhs, query: normalizedQuery)
            }
            .map { item(from: $0) }
    }

    /// Providers use different identifiers for the same title. The initial
    /// client only removed identical IDs, so a TMDB and TVDB result could both
    /// appear. Prefer TMDB where it has equivalent data, but retain TVDB when
    /// it has stronger artwork or a richer overview.
    private static func canonicalRecords(from records: [OmniaMetadataRecord]) -> [OmniaMetadataRecord] {
        var groups: [[OmniaMetadataRecord]] = []

        for record in records {
            let title = normalizedTitle(record.title)
            let year = releaseYear(record)
            if let index = groups.firstIndex(where: { group in
                guard let first = group.first,
                      first.type == record.type,
                      normalizedTitle(first.title) == title
                else { return false }

                let knownYears = Set(group.compactMap(releaseYear))
                return year == nil || knownYears.isEmpty || knownYears.contains(year!)
            }) {
                groups[index].append(record)
            } else {
                groups.append([record])
            }
        }

        return groups.compactMap { group in
            group.max { lhs, rhs in
                providerScore(for: lhs) < providerScore(for: rhs)
            }
        }
    }

    private static func searchScore(for record: OmniaMetadataRecord, query: String) -> Int {
        let title = normalizedTitle(record.title)
        var score = providerScore(for: record)
        if title == query { score += 1_000 }
        else if title.hasPrefix(query) { score += 650 }
        else if title.contains(query) { score += 400 }
        score += query.split(separator: " ").reduce(into: 0) { partial, token in
            if title.contains(token) { partial += 40 }
        }
        return score
    }

    private static func providerScore(for record: OmniaMetadataRecord) -> Int {
        var score = record.provider == MetadataProviderIdentifier.tmdb.rawValue ? 100 : 0
        if record.posterPath != nil { score += 30 }
        if record.backdropPath != nil { score += 20 }
        if let overview = record.overview { score += min(overview.count, 200) / 10 }
        if record.releaseDate != nil { score += 5 }
        return score
    }

    private static func normalizedTitle(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func releaseYear(_ record: OmniaMetadataRecord) -> String? {
        record.releaseDate.map { String($0.prefix(4)) }
    }

    private static func item(
        from record: OmniaMetadataRecord,
        progress: Double? = nil,
        positionSeconds: Double? = nil,
        durationSeconds: Double? = nil
    ) -> MediaItem {
        let type = record.type == MediaType.series.rawValue ? MediaItem.Kind.series : .movie
        return MediaItem(
            id: record.canonicalKey,
            title: record.title,
            year: record.releaseDate.map { String($0.prefix(4)) } ?? "—",
            kind: type,
            overview: record.overview ?? "No overview is available yet.",
            genres: record.genres ?? [],
            symbol: type == .movie ? "film.fill" : "tv.fill",
            artworkColors: type == .movie ? [.indigo, .black] : [.cyan, .indigo],
            artworkURL: artworkURL(for: record.posterPath, provider: record.provider, width: "w500"),
            backdropURL: artworkURL(for: record.backdropPath, provider: record.provider, width: "w1280"),
            logoURL: artworkURL(for: record.logoPath, provider: record.provider, width: "w500"),
            metadataProvider: MetadataProviderIdentifier(rawValue: record.provider),
            metadataProviderID: record.providerID,
            metadataRecordID: record.metadataRecordID,
            externalIDs: record.externalIDs,
            details: titleDetails(from: record.details),
            progress: progress,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds
        )
    }

    private static func titleDetails(from details: OmniaTitleDetails?) -> MediaTitleDetails? {
        guard let details else { return nil }
        return MediaTitleDetails(
            ageRating: details.ageRating,
            runtimeMinutes: details.runtimeMinutes,
            status: details.status,
            budget: details.budget,
            revenue: details.revenue,
            studios: details.studios.map { .init(id: $0.id, name: $0.name) },
            cast: credits(from: details.cast),
            crew: credits(from: details.crew),
            studioTitles: details.studioTitles.map { item(from: $0) },
            collection: details.collection.map {
                .init(id: $0.id, name: $0.name, members: $0.members.map { item(from: $0) })
            },
            recommendations: details.recommendations.map { item(from: $0) },
            seasons: details.seasons.map { season(from: $0) },
            trailers: details.trailers.compactMap { video(from: $0) },
            bonusContent: details.bonusContent.compactMap { video(from: $0) }
        )
    }

    private static func season(from record: OmniaMetadataSeason) -> MediaSeason {
        .init(
            id: record.id,
            seasonNumber: record.seasonNumber,
            title: record.title,
            overview: record.overview,
            posterURL: artworkURL(for: record.posterPath, provider: MetadataProviderIdentifier.tmdb.rawValue, width: "w500"),
            episodes: record.episodes.map { episode(from: $0) }
        )
    }

    private static func episode(from record: OmniaMetadataEpisode) -> MediaEpisode {
        .init(
            id: record.id,
            seasonNumber: record.seasonNumber,
            episodeNumber: record.episodeNumber,
            title: record.title,
            overview: record.overview ?? "No episode synopsis is available yet.",
            runtimeMinutes: record.runtimeMinutes,
            stillURL: artworkURL(for: record.stillPath, provider: MetadataProviderIdentifier.tmdb.rawValue, width: "w780"),
            airDate: record.airDate
        )
    }

    private static func video(from record: OmniaMetadataVideo) -> MediaVideo? {
        guard record.site.caseInsensitiveCompare("YouTube") == .orderedSame,
              let watchURL = URL(string: "https://www.youtube.com/watch?v=\(record.key)")
        else { return nil }

        return .init(
            id: record.id,
            title: record.title,
            type: record.type,
            thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(record.key)/hqdefault.jpg"),
            watchURL: watchURL,
            publishedAt: record.publishedAt
        )
    }

    private static func credits(from records: [OmniaMetadataCredit]) -> [MediaCredit] {
        records.map {
            .init(
                id: $0.id,
                name: $0.name,
                role: $0.role,
                character: $0.character,
                profileURL: artworkURL(for: $0.profilePath, provider: MetadataProviderIdentifier.tmdb.rawValue, width: "w185")
            )
        }
    }

    private static func artworkURL(for path: String?, provider: String, width: String) -> URL? {
        // TheTVDB supplies useful metadata, but its API terms require separate
        // image-display rights. Keep the app's artwork surface limited to the
        // licensed TMDB image service until those rights are in place.
        guard provider == MetadataProviderIdentifier.tmdb.rawValue,
              let path,
              !path.isEmpty
        else { return nil }

        if let url = URL(string: path), url.scheme != nil { return url }
        return URL(string: "https://image.tmdb.org/t/p/\(width)\(path)")
    }
}

struct BuiltInHomeCatalog: Identifiable, Sendable {
    let title: String
    let kind: MediaItem.Kind
    let category: MetadataCatalogCategory
    let items: [MediaItem]

    var id: String { title }
}

private extension MediaItem {
    var metadataType: MediaType {
        kind == .series ? .series : .movie
    }
}
