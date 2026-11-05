//
//  LiveMetadataStore.swift
//  Omnia
//

import CryptoKit
import Foundation
import Observation
import Synchronization
import SwiftUI

/// Read-only, provider-aggregated metadata for Omnia's built-in discovery.
/// The backing Edge Function accepts the project's verified publishable key;
/// it never exposes provider credentials or user-owned library data.
@Observable
@MainActor
final class LiveMetadataStore {
    private let client: SupabaseMetadataClient?
    private let aniListClient = AniListMetadataClient()
    private let kitsuClient = KitsuMetadataClient()
    private let jikanClient = JikanMetadataClient()

    var movieCatalog: [MediaItem] = []
    var seriesCatalog: [MediaItem] = []
    var animeCatalogs: [BuiltInAnimeCatalog] = []
    var homeCatalogs: [BuiltInHomeCatalog] = []
    private var catalogsLoadedAt: Date?
    var topMovies: [MediaItem] = []
    var topSeries: [MediaItem] = []
    var movieGenres: [MetadataGenre] = []
    var seriesGenres: [MetadataGenre] = []
    var searchResults: [MediaItem] = []
    var isLoadingCatalogs = false
    var isSearching = false
    var errorMessage: String?
    private var genreCatalogs: [String: [MediaItem]] = [:]
    private(set) var metadataRouting = MetadataRoutingPreferences()
    /// Settings › Integrations › Anime Enrichment.
    var animeEnrichment = AnimeEnrichmentPreferences()
    /// Anime database records by source and title, so a title page and its
    /// hero don't each ask again.
    private var animeRecords: [String: MediaItem?] = [:]

    init(configuration: SupabaseConfiguration? = nil, loadsBundleConfiguration: Bool = true) {
        let resolvedConfiguration = configuration ?? (loadsBundleConfiguration ? SupabaseConfiguration.load() : nil)
        client = resolvedConfiguration.map { SupabaseMetadataClient(configuration: $0) }
    }

    static let preview = LiveMetadataStore(loadsBundleConfiguration: false)

    func configure(metadataRouting: MetadataRoutingPreferences) {
        guard self.metadataRouting != metadataRouting else { return }
        self.metadataRouting = metadataRouting
        genreCatalogs.removeAll()
    }

    /// TMDB's trending and popular lists move through the day. Reload Home's
    /// rows when the app comes back to the front after they've gone stale,
    /// instead of keeping the lists from launch for the whole session.
    func refreshCatalogsIfStale(maxAge: TimeInterval = 60 * 60) async {
        guard let catalogsLoadedAt, Date.now.timeIntervalSince(catalogsLoadedAt) > maxAge else { return }
        await loadDefaultCatalogs()
    }

    func loadDefaultCatalogs() async {
        guard !isLoadingCatalogs else { return }
        isLoadingCatalogs = true
        errorMessage = nil
        defer { isLoadingCatalogs = false }

        async let anime = loadAnimeDiscovery()

        guard let client else {
            animeCatalogs = await anime
            if animeCatalogs.isEmpty {
                errorMessage = "Built-in discovery is temporarily unavailable."
            }
            return
        }

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
                BuiltInHomeCatalog(shelf: .trendingMovies, items: responses.0),
                BuiltInHomeCatalog(shelf: .popularMovies, items: responses.1),
                BuiltInHomeCatalog(shelf: .popularSeries, items: responses.5),
                BuiltInHomeCatalog(shelf: .nowPlayingMovies, items: responses.2),
                BuiltInHomeCatalog(shelf: .upcomingMovies, items: responses.3),
                BuiltInHomeCatalog(shelf: .trendingSeries, items: responses.4),
                BuiltInHomeCatalog(shelf: .topRatedSeries, items: responses.6),
                BuiltInHomeCatalog(shelf: .airingToday, items: responses.7),
            ])

            movieCatalog = shelves.first(where: { $0.title == "Trending Now" })?.items ?? []
            seriesCatalog = shelves.first(where: { $0.title == "Series Worth Starting" })?.items ?? []
            topMovies = rankedMovies
            topSeries = rankedSeries
        movieGenres = responses.9
        seriesGenres = responses.10
        homeCatalogs = shelves
        animeCatalogs = await anime
        catalogsLoadedAt = .now

        if shelves.isEmpty, rankedMovies.isEmpty, rankedSeries.isEmpty, animeCatalogs.isEmpty {
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
            let response = try await client.search(query: query, type: type, routing: route(for: type))
            guard query == text.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            searchResults = Self.rankedItems(from: response.results, matching: query, preferredProvider: route(for: type).primary)
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
        guard query.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        async let anime = animeSearch(query)

        let providerItems: [MediaItem]
        if let client {
            async let movies = safeSearch(client, query: query, type: .movie)
            async let series = safeSearch(client, query: query, type: .series)
            let (movieRecords, seriesRecords, animeItems) = await (movies, series, anime)
            let movieItems = Self.rankedItems(
                from: movieRecords,
                matching: query,
                preferredProvider: route(for: .movie).primary
            )
            // A series search can also find an anime title. Keep the anime
            // route ahead of that general result before de-duplication so an
            // AniList/TMDB/TVDB anime preference remains authoritative.
            let seriesItems = Self.rankedItems(
                from: seriesRecords,
                matching: query,
                preferredProvider: route(for: .series).primary
            )
            providerItems = movieItems + animeItems + seriesItems
        } else {
            providerItems = await anime
        }

        guard query == text.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        searchResults = Self.uniqueItems(providerItems)
            .sorted { lhs, rhs in
                Self.crossTypeSearchScore(for: lhs, query: query)
                    > Self.crossTypeSearchScore(for: rhs, query: query)
            }
        if searchResults.isEmpty { errorMessage = "Metadata search is temporarily unavailable." }
    }

    func searchAnime(_ text: String) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        let items = await animeSearch(query)
        guard query == text.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        searchResults = items
        if items.isEmpty { errorMessage = "Anime search is temporarily unavailable." }
    }

    func details(for item: MediaItem) async -> MediaItem {
        await enrichedFromAnimeDatabases(await serviceDetails(for: item))
    }

    /// Includes module, routing, locale and credential revisions without exposing keys.
    func enrichmentRequestIdentity(integrations: IntegrationPreferences, language: String = "en-US") -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let encoded = (try? encoder.encode(integrations)) ?? Data()
        let routing = (try? encoder.encode(metadataRouting)) ?? Data()
        let identity = encoded + routing + Data((language + OnDeviceMetadataService.credentialIdentity("tmdb") + OnDeviceMetadataService.credentialIdentity("tvdb")).utf8)
        return SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
    }

    /// Add-on enrichment is deliberately separate from general metadata gap filling.
    func enrichedDetails(for source: MediaItem, integrations: IntegrationPreferences, language: String = "en-US") async -> MediaItem {
        guard let client else { return source }
        let route = Self.isExplicitlyAnime(source) ? metadataRouting.anime : route(for: source.metadataType)
        // A provider switched on here counts even when Metadata Sources doesn't
        // list it, at the lowest priority. Anime keeps its own source order.
        let listed = route.requestedProviders.filter(\.isServedByMetadataService)
        let unlisted: [MetadataProviderIdentifier] = Self.isExplicitlyAnime(source) ? [] : [
            integrations.tmdb.enabled ? .tmdb : nil,
            integrations.tvdb.enabled ? .tvdb : nil,
        ].compactMap { $0 }.filter { !listed.contains($0) }
        let providers = listed + unlisted
        var result = source
        // Applying preferred last gives its nonempty enabled values precedence.
        for provider in providers.reversed() {
            guard !Task.isCancelled else { return source }
            var modules = provider == .tmdb ? integrations.tmdb : integrations.tvdb.modules
            modules.enabled = provider == .tmdb ? integrations.tmdb.enabled : integrations.tvdb.enabled
            guard modules.enabled else { continue }
            let record: MediaItem?
            if provider == .tmdb {
                record = await tmdbCounterpart(for: source, client: client, language: language, modules: modules)
            } else {
                record = await tvdbCounterpart(for: source, client: client, language: language, modules: modules)
            }
            if let record { result = result.mergingEnrichment(from: record, modules: modules) }
        }
        return await enrichedFromAnimeDatabases(result)
    }

    private func tvdbCounterpart(for item: MediaItem, client: SupabaseMetadataClient, language: String, modules: TMDBEnrichmentPreferences? = nil) async -> MediaItem? {
        var identifier = item.externalIDs["tvdb"] ?? item.externalIDs["tvdb_id"]
            ?? (item.metadataProvider == .tvdb ? item.metadataProviderID : nil)
        let imdbID = item.externalIDs["imdb"] ?? item.externalIDs["imdb_id"] ?? (item.id.hasPrefix("tt") ? item.id : nil)
        if identifier == nil, let imdbID, let found = try? await client.findTVDB(imdbID: imdbID, type: item.metadataType),
           Set(found.results.map(\.providerID)).count == 1 {
            identifier = found.results.first?.providerID
        }
        if let identifier, let response = await detailsWithRetry(client, provider: .tvdb, id: identifier, type: item.metadataType, language: language, modules: modules) {
            return Self.item(from: response.item)
        }
        guard item.year.count == 4, Int(item.year) != nil,
              let search = try? await client.search(query: item.title, type: item.metadataType,
                routing: MetadataRoute(primary: .tvdb, fallbackEnabled: false), language: language) else { return nil }
        let matches = search.results.filter { Self.normalizedTitle($0.title) == Self.normalizedTitle(item.title) && Self.releaseYear($0) == item.year }
        guard Set(matches.map(\.providerID)).count == 1, let id = matches.first?.providerID,
              let response = await detailsWithRetry(client, provider: .tvdb, id: id, type: item.metadataType, language: language, modules: modules) else { return nil }
        return Self.item(from: response.item)
    }

    /// Anime Enrichment: AniList, Kitsu and MyAnimeList fill what TMDB,
    /// TVDB and the add-on left out of an anime title, as TMDB Enrichment
    /// does for other titles. Only titles with an anime database ID ask.
    private func enrichedFromAnimeDatabases(_ item: MediaItem) async -> MediaItem {
        guard animeEnrichment.enabled else { return item }
        var enriched = item
        let sources = metadataRouting.anime.requestedProviders.filter(\.isAnimeDatabase)
        for provider in sources {
            guard !Task.isCancelled else { break }
            let key = "\(provider.rawValue)|\(item.streamIdentifierCandidates.joined(separator: ","))"
            let record: MediaItem?
            if let cached = animeRecords[key] {
                record = cached
            } else {
                record = await AnimeMetadataSource.record(for: enriched, from: provider)
                if animeRecords.count > 300 { animeRecords.removeAll() }
                animeRecords[key] = record
            }
            if let record { enriched = enriched.fillingGaps(from: record.restricted(to: animeEnrichment)) }
        }
        return enriched
    }

    private func serviceDetails(for item: MediaItem) async -> MediaItem {
        guard let client else { return item }

        var resolvedItem = item
        // The metadata service only answers detail requests for TMDB and
        // TVDB. AniList and add-on titles go straight to the TMDB match below.
        if let provider = item.metadataProvider,
           provider.isServedByMetadataService,
           let identifier = item.metadataProviderID,
           let response = await detailsWithRetry(client, provider: provider, id: identifier, type: item.metadataType) {
            let providerItem = Self.item(
                from: response.item,
                progress: item.progress,
                positionSeconds: item.positionSeconds,
                durationSeconds: item.durationSeconds
            )
            resolvedItem = providerItem.mergingSourceIdentifiers(from: item)
        }

        guard resolvedItem.metadataProvider != .tmdb else { return resolvedItem }

        // Only TMDB records carry seasons, cast and full-size artwork. Without
        // this, TVDB, AniList and add-on titles open with no season or episode
        // pickers, no cast, and a poster stretched into a blurry hero.
        guard let counterpart = await tmdbCounterpart(for: resolvedItem, client: client) else {
            return resolvedItem
        }
        let enriched = resolvedItem.mergingEnrichment(from: counterpart, modules: .init())
        let selectedRoute = Self.isExplicitlyAnime(resolvedItem) ? metadataRouting.anime : route(for: resolvedItem.metadataType)
        return selectedRoute.primary == .tmdb
            ? enriched
            : enriched.mergingEnrichment(from: resolvedItem, modules: .init())
    }

    /// Title details answered recently, so a title page, its hero trailer
    /// and the player don't each ask the service again. Shared by every
    /// caller asking for the same title at once.
    private var detailsInFlight: [String: Task<MetadataDetailResponse?, Never>] = [:]

    /// Answers from `MetadataDetailCache` first, then the service.
    private func detailsWithRetry(
        _ client: SupabaseMetadataClient,
        provider: MetadataProviderIdentifier,
        id: String,
        type: MediaType,
        language: String = "en-US",
        modules: TMDBEnrichmentPreferences? = nil
    ) async -> MetadataDetailResponse? {
        let key = MetadataDetailCache.key(provider: provider, id: id, type: type, language: language) + (modules?.requestIdentity ?? "full")
        if let cached = await MetadataDetailCache.response(for: key) { return cached }
        if let running = detailsInFlight[key] { return await running.value }
        let task = Task { [weak self] () -> MetadataDetailResponse? in
            guard let self else { return nil }
            let response = await self.fetchDetailsWithRetry(client, provider: provider, id: id, type: type, language: language, modules: modules)
            if let response { await MetadataDetailCache.save(response, for: key) }
            return response
        }
        detailsInFlight[key] = task
        let response = await task.value
        detailsInFlight[key] = nil
        return response
    }

    /// One retry absorbs the transient failures seen while Home's catalog
    /// requests are still in flight, which otherwise leave a detail page bare.
    private func fetchDetailsWithRetry(
        _ client: SupabaseMetadataClient,
        provider: MetadataProviderIdentifier,
        id: String,
        type: MediaType,
        language: String = "en-US",
        modules: TMDBEnrichmentPreferences? = nil
    ) async -> MetadataDetailResponse? {
        for attempt in 0..<2 {
            if attempt > 0 {
                try? await Task.sleep(for: .milliseconds(600))
            }
            guard !Task.isCancelled else { return nil }
            if let response = try? await client.details(provider: provider, id: id, type: type, language: language, modules: modules) {
                return response
            }
        }
        return nil
    }

    private func tmdbCounterpart(for item: MediaItem, client: SupabaseMetadataClient, language: String = "en-US", modules: TMDBEnrichmentPreferences? = nil) async -> MediaItem? {
        let tmdbID = (item.externalIDs["tmdb"] ?? item.externalIDs["tmdb_id"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let tmdbID, !tmdbID.isEmpty,
           let response = await detailsWithRetry(client, provider: .tmdb, id: tmdbID, type: item.metadataType, language: language, modules: modules) {
            return Self.item(from: response.item)
        }
        let externalIDs = [(item.externalIDs["imdb"] ?? item.externalIDs["imdb_id"] ?? (item.id.hasPrefix("tt") ? item.id : nil), "imdb_id"),
            (item.metadataType == .series ? item.externalIDs["tvdb"] ?? item.externalIDs["tvdb_id"] ?? (item.metadataProvider == .tvdb ? item.metadataProviderID : nil) : nil, "tvdb_id")]
        for (externalID, source) in externalIDs {
            guard let externalID,
                  let found = try? await client.findTMDB(externalID: externalID, source: source, type: item.metadataType, language: language),
                  Set(found.results.map(\.providerID)).count == 1, let identifier = found.results.first?.providerID,
                  let response = await detailsWithRetry(client, provider: .tmdb, id: identifier, type: item.metadataType, language: language, modules: modules) else { continue }
            return Self.item(from: response.item)
        }
        return try? await exactTMDBFallback(for: item, client: client, language: language, modules: modules)
    }

    /// Older hosted TVDB records may not contain remote IDs even though the
    /// configured TMDB fallback can supply the IMDb identity expected by most
    /// Stremio stream add-ons. Resolve only an exact title/year match so source
    /// lookup never crosses from one production or remake to another.
    private func exactTMDBFallback(
        for item: MediaItem,
        client: SupabaseMetadataClient,
        language: String = "en-US",
        modules: TMDBEnrichmentPreferences? = nil
    ) async throws -> MediaItem? {
        guard item.year.count == 4, Int(item.year) != nil else { return nil }
        let tmdbOnly = MetadataRoute(primary: .tmdb, fallbackEnabled: false)
        let search = try await client.search(
            query: item.title,
            type: item.metadataType,
            routing: tmdbOnly,
            language: language
        )
        let matches = search.results.filter { record in
            guard record.provider == MetadataProviderIdentifier.tmdb.rawValue,
                  Self.normalizedTitle(record.title) == Self.normalizedTitle(item.title)
            else { return false }

            return Self.releaseYear(record) == item.year
        }
        let identifiers = Set(matches.map(\.providerID))
        guard identifiers.count == 1, let identifier = identifiers.first else { return nil }

        let response = try await client.details(
            provider: .tmdb,
            id: identifier,
            type: item.metadataType,
            language: language,
            modules: modules
        )
        let fallbackItem = Self.item(from: response.item)
        guard Self.normalizedTitle(fallbackItem.title) == Self.normalizedTitle(item.title),
              fallbackItem.year == item.year
        else { return nil }
        return fallbackItem
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
            let response = try await client.catalog(type: type, category: category, genreID: genreID, page: page, routing: route(for: type))
            return Self.items(from: response.results, preferredProvider: route(for: type).primary)
        } catch {
            errorMessage = "Metadata discovery is temporarily unavailable."
            return []
        }
    }

    /// A person's page (Nuvio's PersonDetailScreen). Throws so the page can
    /// offer Try Again.
    func person(id: String) async throws -> PersonPage {
        guard let client else { throw SupabaseMetadataError.invalidResponse }
        let person = try await client.person(id: id).person
        func credits(_ entries: [OmniaPersonDetails.Credit]) -> [PersonPage.Credit] {
            entries.compactMap { entry in
                Self.displayableItem(from: entry.item).map {
                    PersonPage.Credit(item: $0, role: entry.character ?? entry.job)
                }
            }
        }
        return PersonPage(
            id: person.id,
            name: person.name,
            biography: person.biography,
            birthday: person.birthday,
            deathday: person.deathday,
            placeOfBirth: person.placeOfBirth,
            knownForDepartment: person.knownForDepartment,
            profileURL: Self.artworkURL(for: person.profilePath, provider: MetadataProviderIdentifier.tmdb.rawValue, width: "h632"),
            cast: credits(person.cast),
            crew: credits(person.crew)
        )
    }

    /// One page of a company's or network's titles.
    func entityPage(
        kind: MetadataEntityKind,
        id: String,
        type: MediaType,
        page: Int
    ) async throws -> TitleListPage {
        guard let client else { throw SupabaseMetadataError.invalidResponse }
        let response = try await client.entity(kind: kind, id: id, type: type, page: page)
        return TitleListPage(
            items: response.results.compactMap(Self.displayableItem(from:)),
            hasMore: response.page < response.totalPages,
            entityName: response.entity?.name,
            entityLogoURL: Self.artworkURL(for: response.entity?.logoPath, provider: MetadataProviderIdentifier.tmdb.rawValue, width: "w500")
        )
    }

    /// One page behind More Like This or Similar's View All.
    func relatedPage(
        kind: MetadataRelatedKind,
        tmdbID: String,
        type: MediaType,
        page: Int
    ) async throws -> TitleListPage {
        guard let client else { throw SupabaseMetadataError.invalidResponse }
        let response = try await client.related(kind: kind, id: tmdbID, type: type, page: page)
        return TitleListPage(
            items: response.results.compactMap(Self.displayableItem(from:)),
            hasMore: response.page < response.totalPages
        )
    }

    /// Fetches a single browse page through the user's ordered anime route.
    /// Each provider is attempted in turn, so a primary outage or empty page
    /// naturally advances to the enabled fallback without mixing sources.
    func animeCatalogPage(
        category: MetadataCatalogCategory,
        genre: String? = nil,
        page: Int
    ) async -> [MediaItem] {
        await animeCatalogPage(category: category, genre: genre, page: page, route: metadataRouting.anime)
    }

    private static func items(
        from records: [OmniaMetadataRecord],
        preferredProvider: MetadataProviderIdentifier? = nil
    ) -> [MediaItem] {
        canonicalRecords(from: records, preferredProvider: preferredProvider).compactMap(displayableItem(from:))
    }

    /// Home shelves need replacement candidates after cross-shelf de-duplication.
    /// Two TMDB pages provide up to 40 candidates per category before that pass.
    private func extendedCatalog(
        _ client: SupabaseMetadataClient,
        type: MediaType,
        category: MetadataCatalogCategory
    ) async throws -> [MediaItem] {
        async let firstPage = client.catalog(type: type, category: category, page: 1, routing: route(for: type))
        async let secondPage = client.catalog(type: type, category: category, page: 2, routing: route(for: type))
        let responses = try await (firstPage, secondPage)
        return Self.items(
            from: responses.0.results + responses.1.results,
            preferredProvider: route(for: type).primary
        )
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
        guard let response = try? await client.catalog(type: type, category: category, routing: route(for: type)) else { return [] }
        return Self.items(from: response.results, preferredProvider: route(for: type).primary)
    }

    private func safeGenres(_ client: SupabaseMetadataClient, type: MediaType) async -> [MetadataGenre] {
        (try? await client.genres(type: type).genres) ?? []
    }

    private func safeSearch(
        _ client: SupabaseMetadataClient,
        query: String,
        type: MediaType
    ) async -> [OmniaMetadataRecord] {
        (try? await client.search(query: query, type: type, routing: route(for: type)).results) ?? []
    }

    private func loadAnimeDiscovery() async -> [BuiltInAnimeCatalog] {
        async let trending = animeCatalogPage(category: .trending, page: 1, route: metadataRouting.anime)
        async let popular = animeCatalogPage(category: .popular, page: 1, route: metadataRouting.anime)
        async let topRated = animeCatalogPage(category: .topRated, page: 1, route: metadataRouting.anime)
        async let airing = animeCatalogPage(category: .airingToday, page: 1, route: metadataRouting.anime)
        let shelves = await (trending, popular, topRated, airing)
        return [
            BuiltInAnimeCatalog(title: "Trending Anime", category: .trending, items: shelves.0),
            BuiltInAnimeCatalog(title: "Popular Anime", category: .popular, items: shelves.1),
            BuiltInAnimeCatalog(title: "Top Rated Anime", category: .topRated, items: shelves.2),
            BuiltInAnimeCatalog(title: "Airing Now", category: .airingToday, items: shelves.3),
        ].filter { !$0.items.isEmpty }
    }

    private func animeSearch(_ query: String) async -> [MediaItem] {
        for provider in metadataRouting.anime.requestedProviders {
            switch provider {
            case .anilist:
                if let items = try? await aniListClient.searchAnime(query: query), !items.isEmpty {
                    return items
                }
            case .kitsu:
                if let items = try? await kitsuClient.searchAnime(query: query), !items.isEmpty {
                    return items
                }
            case .myanimelist:
                if let items = try? await jikanClient.searchAnime(query: query), !items.isEmpty {
                    return items
                }
            case .tmdb, .tvdb:
                guard let client else { continue }
                let route = MetadataRoute(primary: provider, fallbackEnabled: false)
                if let response = try? await client.search(query: query, type: .series, routing: route) {
                    let items = Self.rankedItems(from: response.results, matching: query, preferredProvider: provider)
                    let animeItems = provider == .tvdb ? items.filter(Self.isExplicitlyAnime) : items
                    if !animeItems.isEmpty { return animeItems }
                }
            }
        }
        return []
    }

    private func animeCatalogPage(
        category: MetadataCatalogCategory,
        genre: String? = nil,
        page: Int,
        route: MetadataRoute
    ) async -> [MediaItem] {
        for provider in route.requestedProviders {
            switch provider {
            case .anilist:
                if let items = try? await aniListClient.catalogAnime(category: category, genre: genre, page: page), !items.isEmpty {
                    return items
                }
            case .kitsu:
                if let items = try? await kitsuClient.catalogAnime(category: category, genre: genre, page: page), !items.isEmpty {
                    return items
                }
            case .myanimelist:
                if let items = try? await jikanClient.catalogAnime(category: category, genre: genre, page: page), !items.isEmpty {
                    return items
                }
            case .tmdb, .tvdb:
                guard let client else { continue }
                let providerRoute = MetadataRoute(primary: provider, fallbackEnabled: false)
                // TMDB's Animation genre keeps its alternative anime surface
                // close to the user's intent. TVDB does not expose an
                // equivalent reliable genre filter, so its catalog remains
                // the provider's series browse result.
                let genreID = provider == .tmdb ? 16 : nil
                if let response = try? await client.catalog(
                    type: .series,
                    category: category,
                    genreID: genreID,
                    page: page,
                    routing: providerRoute
                ) {
                    let items = Self.items(from: response.results, preferredProvider: provider)
                    // TVDB's generic series endpoint also includes live
                    // action programming. Only retain records explicitly
                    // classified as Anime; an empty page correctly moves to
                    // the user's next fallback instead of relabeling random
                    // TV as anime.
                    let animeItems = provider == .tvdb ? items.filter(Self.isExplicitlyAnime) : items
                    if !animeItems.isEmpty { return animeItems }
                }
            }
        }
        return []
    }

    private func route(for type: MediaType) -> MetadataRoute {
        type == .movie ? metadataRouting.movies : metadataRouting.series
    }

    /// A title earns a single home-shelf placement. Ranked shelves reserve their
    /// titles first, then each subsequent shelf contributes only unseen items.
    private static func uniqueHomeCatalogs(
        _ catalogs: [BuiltInHomeCatalog]
    ) -> [BuiltInHomeCatalog] {
        // Each row mirrors its TMDB list in TMDB's order. Removing titles that
        // already appeared in an earlier row or the Top 10 made rows drift
        // from the real lists, so only duplicates within one row are dropped.
        catalogs.compactMap { catalog in
            var seen = Set<String>()
            let uniqueItems = catalog.items.filter { seen.insert($0.id).inserted }
            guard !uniqueItems.isEmpty else { return nil }
            return BuiltInHomeCatalog(shelf: catalog.shelf, items: uniqueItems)
        }
    }

    private static func rankedItems(
        from records: [OmniaMetadataRecord],
        matching query: String,
        preferredProvider: MetadataProviderIdentifier? = nil
    ) -> [MediaItem] {
        let normalizedQuery = normalizedTitle(query)
        let queryTokens = normalizedQuery.split(separator: " ")

        return canonicalRecords(from: records, preferredProvider: preferredProvider)
            .filter { record in
                let title = normalizedTitle(record.title)
                return title.contains(normalizedQuery) || queryTokens.allSatisfy { title.contains($0) }
            }
            .sorted { lhs, rhs in
                searchScore(for: lhs, query: normalizedQuery, preferredProvider: preferredProvider)
                    > searchScore(for: rhs, query: normalizedQuery, preferredProvider: preferredProvider)
            }
            .compactMap(displayableItem(from:))
    }

    private static func uniqueItems(_ items: [MediaItem]) -> [MediaItem] {
        var seen = Set<String>()
        return items.filter { item in
            let normalized = "\(item.kind.rawValue):\(normalizedTitle(item.title)): \(item.year)"
            return seen.insert(normalized).inserted
        }
    }

    private static func isExplicitlyAnime(_ item: MediaItem) -> Bool {
        item.genres.contains { $0.caseInsensitiveCompare("Anime") == .orderedSame }
            || item.externalIDs["anilist"] != nil
            || item.externalIDs["mal"] != nil
    }

    /// Providers use different identifiers for the same title. The initial
    /// client only removed identical IDs, so a TMDB and TVDB result could both
    /// appear. Prefer TMDB where it has equivalent data, but retain TVDB when
    /// it has stronger artwork or a richer overview.
    private static func canonicalRecords(
        from records: [OmniaMetadataRecord],
        preferredProvider: MetadataProviderIdentifier? = nil
    ) -> [OmniaMetadataRecord] {
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
            guard var selected = group.max(by: {
                providerScore(for: $0, preferredProvider: preferredProvider)
                    < providerScore(for: $1, preferredProvider: preferredProvider)
            }) else { return nil }

            // Metadata routing controls the selected record. A companion can
            // only fill fields that the selected provider did not return.
            // This keeps "TVDB primary" authoritative while retaining TMDB's
            // cross-ID, release date, or artwork where TVDB has a gap. In
            // particular, it prevents a valid TVDB search result from being
            // discarded merely because it has no displayable poster/date.
            let companion = group
                .filter { $0.provider != selected.provider }
                .max(by: {
                    providerScore(for: $0, preferredProvider: nil)
                        < providerScore(for: $1, preferredProvider: nil)
                })
            let mergedExternalIDs = group.reduce(into: selected.externalIDs) { identifiers, record in
                for (key, value) in record.externalIDs where identifiers[key] == nil {
                    identifiers[key] = value
                }
            }
            selected = OmniaMetadataRecord(
                canonicalKey: selected.canonicalKey,
                provider: selected.provider,
                providerID: selected.providerID,
                type: selected.type,
                title: selected.title,
                originalTitle: selected.originalTitle ?? companion?.originalTitle,
                overview: selected.overview ?? companion?.overview,
                releaseDate: selected.releaseDate ?? companion?.releaseDate,
                posterPath: mergedArtworkPath(
                    selected.posterPath,
                    companion: companion,
                    keyPath: \OmniaMetadataRecord.posterPath,
                    width: "w500"
                ),
                backdropPath: mergedArtworkPath(
                    selected.backdropPath,
                    companion: companion,
                    keyPath: \OmniaMetadataRecord.backdropPath,
                    width: "w1280"
                ),
                logoPath: mergedArtworkPath(
                    selected.logoPath,
                    companion: companion,
                    keyPath: \OmniaMetadataRecord.logoPath,
                    width: "w500"
                ),
                genres: selected.genres ?? companion?.genres,
                externalIDs: mergedExternalIDs,
                sourceURL: selected.sourceURL,
                metadataRecordID: selected.metadataRecordID,
                details: selected.details ?? companion?.details
            )
            return selected
        }
    }

    private static func searchScore(
        for record: OmniaMetadataRecord,
        query: String,
        preferredProvider: MetadataProviderIdentifier?
    ) -> Int {
        let title = normalizedTitle(record.title)
        var score = providerScore(for: record, preferredProvider: preferredProvider)
        if title == query { score += 1_000 }
        else if title.hasPrefix(query) { score += 650 }
        else if title.contains(query) { score += 400 }
        score += query.split(separator: " ").reduce(into: 0) { partial, token in
            if title.contains(token) { partial += 40 }
        }
        return score
    }

    /// A combined search contains movies, series, and anime from separate
    /// provider requests. Rank the final display items once more so an exact,
    /// current title is not hidden behind an unrelated older match simply
    /// because the movie request completed first.
    private static func crossTypeSearchScore(for item: MediaItem, query: String) -> Int {
        let title = normalizedTitle(item.title)
        let normalizedQuery = normalizedTitle(query)
        var score = 0
        if title == normalizedQuery { score += 1_000 }
        else if title.hasPrefix(normalizedQuery) { score += 650 }
        else if title.contains(normalizedQuery) { score += 400 }
        score += normalizedQuery.split(separator: " ").reduce(into: 0) { partial, token in
            if title.contains(token) { partial += 40 }
        }
        // Prefer the current incarnation of an exact title, while keeping
        // this a small tie-breaker rather than a substitute for title match.
        score += (Int(item.year) ?? 0) / 10
        return score
    }

    /// A relative TMDB image path needs its TMDB origin to be preserved after
    /// a TVDB-primary record is enriched. Persist it as an HTTPS URL so the
    /// later `MediaItem` conversion can render it without changing which
    /// provider remains the metadata authority.
    private static func mergedArtworkPath(
        _ selectedPath: String?,
        companion: OmniaMetadataRecord?,
        keyPath: KeyPath<OmniaMetadataRecord, String?>,
        width: String
    ) -> String? {
        guard selectedPath == nil, let companion else { return selectedPath }
        let path = companion[keyPath: keyPath]
        return artworkURL(for: path, provider: companion.provider, width: width)?.absoluteString
    }

    private static func providerScore(
        for record: OmniaMetadataRecord,
        preferredProvider: MetadataProviderIdentifier? = nil
    ) -> Int {
        var score = record.provider == preferredProvider?.rawValue ? 200 : 0
        if preferredProvider == nil, record.provider == MetadataProviderIdentifier.tmdb.rawValue { score += 100 }
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
            artworkColors: MediaItem.placeholderArtworkColors,
            artworkURL: artworkURL(for: record.posterPath, provider: record.provider, width: "w500"),
            backdropURL: artworkURL(for: record.backdropPath, provider: record.provider, width: "w1280"),
            logoURL: artworkURL(for: record.logoPath, provider: record.provider, width: "w500"),
            metadataProvider: MetadataProviderIdentifier(rawValue: record.provider),
            metadataProviderID: record.providerID,
            metadataRecordID: record.metadataRecordID,
            externalIDs: record.externalIDs,
            details: titleDetails(from: record.details, record: record),
            progress: progress,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds
        )
    }

    /// Catalog cards require real displayable artwork. Keeping a record with
    /// no artwork produces a fabricated placeholder and makes discovery look
    /// incomplete, so omit it until the selected provider supplies a usable
    /// poster.
    private static func displayableItem(from record: OmniaMetadataRecord) -> MediaItem? {
        let item = item(from: record)
        return item.artworkURL == nil ? nil : item
    }

    private static func titleDetails(from details: OmniaTitleDetails?, record: OmniaMetadataRecord) -> MediaTitleDetails? {
        guard let details else { return nil }
        return MediaTitleDetails(
            ageRating: details.ageRating,
            runtimeMinutes: details.runtimeMinutes,
            status: details.status,
            budget: details.budget,
            revenue: details.revenue,
            studios: details.studios.map(studio(from:)),
            cast: credits(from: details.cast),
            crew: credits(from: details.crew),
            studioTitles: details.studioTitles.compactMap(displayableItem(from:)),
            collection: details.collection.map {
                .init(id: $0.id, name: $0.name, members: $0.members.compactMap(displayableItem(from:)))
            },
            recommendations: details.recommendations.compactMap(displayableItem(from:)),
            seasons: details.seasons.map { season(from: $0) },
            trailers: details.trailers.compactMap { video(from: $0) },
            bonusContent: details.bonusContent.compactMap { video(from: $0) },
            productionCompanies: (details.productionCompanies ?? []).map(studio(from:)),
            networks: (details.networks ?? []).map(studio(from:)),
            creators: credits(from: details.creators ?? []),
            originCountries: details.originCountries ?? [],
            originalLanguage: details.originalLanguage,
            releaseDate: details.releaseDate,
            similar: (details.similar ?? []).compactMap(displayableItem(from:)),
            recommendationsHaveMore: details.recommendationsHaveMore ?? false,
            similarHaveMore: details.similarHaveMore ?? false,
            tmdbID: record.provider == MetadataProviderIdentifier.tmdb.rawValue ? record.providerID : nil
        )
    }

    private static func studio(from record: OmniaMetadataStudio) -> MediaStudio {
        MediaStudio(
            id: record.id,
            name: record.name,
            logoURL: artworkURL(for: record.logoPath, provider: MetadataProviderIdentifier.tmdb.rawValue, width: "w300")
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
        guard let path, !path.isEmpty else { return nil }

        // TVDB responses provide their artwork as fully-qualified HTTPS URLs;
        // TMDB provides a relative image path. Do not create a coloured
        // placeholder when either provider has supplied a real image.
        if let url = URL(string: path), url.scheme?.lowercased() == "https" { return url }
        guard provider == MetadataProviderIdentifier.tmdb.rawValue else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(width)\(path)")
    }
}

struct PersonPage: Sendable {
    struct Credit: Identifiable, Sendable {
        let item: MediaItem
        let role: String?
        var id: String { item.id }
    }

    let id: String
    let name: String
    let biography: String?
    let birthday: String?
    let deathday: String?
    let placeOfBirth: String?
    let knownForDepartment: String?
    let profileURL: URL?
    let cast: [Credit]
    let crew: [Credit]
}

struct TitleListPage: Sendable {
    let items: [MediaItem]
    let hasMore: Bool
    var entityName: String? = nil
    var entityLogoURL: URL? = nil
}

struct BuiltInHomeCatalog: Identifiable, Sendable {
    let shelf: BuiltInHomeShelf
    let items: [MediaItem]

    var id: String { shelf.id }
    var title: String { shelf.title }
    var kind: MediaItem.Kind { shelf.kind }
    var category: MetadataCatalogCategory { shelf.category }
}

/// A native anime shelf is kept separate from Home's movie/series catalog
/// model so it can preserve the selected anime route and its own browse UI.
struct BuiltInAnimeCatalog: Identifiable, Sendable {
    let title: String
    let category: MetadataCatalogCategory
    let items: [MediaItem]

    var id: String { category.rawValue }
}

private extension MediaItem {
    var metadataType: MediaType {
        kind == .series ? .series : .movie
    }
}

/// Title details kept in memory and in Caches, so a title opened again, or
/// after a relaunch, shows at once. Kept for a few hours: long enough to
/// skip repeat requests, short enough that new episodes still appear the
/// same day. Files are named by a hash of the title's provider ID.
private nonisolated enum MetadataDetailCache {
    static let maximumAge: TimeInterval = 4 * 60 * 60

    private struct Entry: Codable {
        var savedAt: Date
        var response: MetadataDetailResponse
    }

    private static let memory = Mutex<[String: Entry]>([:])
    private static let memoryLimit = 120

    private static let directory: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let directory = caches.appendingPathComponent("MetadataDetails", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    static func key(provider: MetadataProviderIdentifier, id: String, type: MediaType, language: String) -> String {
        let identity = ["v2", provider.rawValue, type.rawValue, id, language, OnDeviceMetadataService.credentialIdentity(provider.rawValue)].joined(separator: "|")
        return SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    @concurrent
    static func response(for key: String) async -> MetadataDetailResponse? {
        if let entry = memory.withLock({ $0[key] }) {
            return Date.now.timeIntervalSince(entry.savedAt) < maximumAge ? entry.response : nil
        }
        guard let directory,
              let data = try? Data(contentsOf: directory.appendingPathComponent(key)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              Date.now.timeIntervalSince(entry.savedAt) < maximumAge
        else { return nil }
        remember(entry, for: key)
        return entry.response
    }

    @concurrent
    static func save(_ response: MetadataDetailResponse, for key: String) async {
        let entry = Entry(savedAt: .now, response: response)
        remember(entry, for: key)
        guard let directory, let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: directory.appendingPathComponent(key), options: .atomic)
        pruneOnce(directory)
    }

    private static let didPrune = Mutex(false)

    /// Entries past their age are never read again, and earlier builds wrote
    /// keys no later launch could find. Clears them once per launch.
    private static func pruneOnce(_ directory: URL) {
        guard didPrune.withLock({ let first = !$0; $0 = true; return first }) else { return }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if Date.now.timeIntervalSince(modified ?? .distantPast) >= maximumAge {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private static func remember(_ entry: Entry, for key: String) {
        memory.withLock { entries in
            entries[key] = entry
            // Drop the oldest once full; the disk copy stays.
            if entries.count > memoryLimit,
               let oldest = entries.min(by: { $0.value.savedAt < $1.value.savedAt })?.key {
                entries[oldest] = nil
            }
        }
    }
}
