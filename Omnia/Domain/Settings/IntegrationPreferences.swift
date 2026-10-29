import Foundation

/// Settings › Integrations, laid out like Nuvio's: TMDB Enrichment, Anime
/// Enrichment and MDBList Ratings.
nonisolated struct IntegrationPreferences: Codable, Equatable, Sendable {
    var tmdb = TMDBEnrichmentPreferences()
    var tvdb = TVDBEnrichmentPreferences()
    var anime = AnimeEnrichmentPreferences()
    /// Nuvio's "Enable MDBList Ratings". On by default so ratings keep
    /// showing for anyone who already saved an MDBList key.
    var mdblistEnabled = true

    static let `default` = Self()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case tmdb, tvdb, anime, mdblistEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tmdb = (try? container.decodeIfPresent(TMDBEnrichmentPreferences.self, forKey: .tmdb)) ?? .init()
        tvdb = (try? container.decodeIfPresent(TVDBEnrichmentPreferences.self, forKey: .tvdb)) ?? .init()
        anime = (try? container.decodeIfPresent(AnimeEnrichmentPreferences.self, forKey: .anime)) ?? .init()
        mdblistEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .mdblistEnabled)) ?? true
    }
}

/// Which parts of a title's page TMDB may fill in when an add-on supplied
/// the title. Mirrors Nuvio's TMDB Enrichment modules.
///
/// Nuvio's enrichment is off by default; Omnia has always enriched add-on
/// titles, so it stays on here.
nonisolated struct TMDBEnrichmentPreferences: Codable, Equatable, Sendable {
    var enabled = true
    var useTrailers = true
    var useArtwork = true
    var useBasicInfo = true
    var useDetails = true
    var useCredits = true
    var useProductions = true
    var useEpisodes = true
    var useMoreLikeThis = true
    var useCollections = true

    init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled, useTrailers, useArtwork, useBasicInfo, useDetails, useCredits
        case useProductions, useEpisodes, useMoreLikeThis, useCollections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func flag(_ key: CodingKeys) -> Bool {
            (try? container.decodeIfPresent(Bool.self, forKey: key)) ?? true
        }
        enabled = flag(.enabled)
        useTrailers = flag(.useTrailers)
        useArtwork = flag(.useArtwork)
        useBasicInfo = flag(.useBasicInfo)
        useDetails = flag(.useDetails)
        useCredits = flag(.useCredits)
        useProductions = flag(.useProductions)
        useEpisodes = flag(.useEpisodes)
        useMoreLikeThis = flag(.useMoreLikeThis)
        useCollections = flag(.useCollections)
    }

    /// Number of modules turned on, for the Integrations summary.
    var enabledModuleCount: Int {
        [useTrailers, useArtwork, useBasicInfo, useDetails, useCredits,
         useProductions, useEpisodes, useMoreLikeThis, useCollections]
            .filter { $0 }.count
    }

    nonisolated var requestIdentity: String {
        [enabled, useTrailers, useArtwork, useBasicInfo, useDetails, useCredits,
         useProductions, useEpisodes, useMoreLikeThis, useCollections].map { $0 ? "1" : "0" }.joined()
    }

    static let moduleCount = 9
}

/// TVDB exposes only modules supported by its v4 extended records.
nonisolated struct TVDBEnrichmentPreferences: Codable, Equatable, Sendable {
    var enabled = false
    var modules = TMDBEnrichmentPreferences()

    init() {
        modules.useMoreLikeThis = false
        modules.useCollections = false
    }

    private enum CodingKeys: String, CodingKey { case enabled, modules }
    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? values.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false
        modules = (try? values.decodeIfPresent(TMDBEnrichmentPreferences.self, forKey: .modules)) ?? modules
        modules.useMoreLikeThis = false
        modules.useCollections = false
    }
}

/// What AniList, Kitsu and MyAnimeList may fill in on an anime title's page
/// when the add-on and TMDB left it out (Dafa, 2026-10-27). The anime
/// sources are asked in their Metadata Sources › Anime order.
nonisolated struct AnimeEnrichmentPreferences: Codable, Equatable, Sendable {
    var enabled = true
    var useBasicInfo = true
    var useArtwork = true

    init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled, useBasicInfo, useArtwork
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func flag(_ key: CodingKeys) -> Bool {
            (try? container.decodeIfPresent(Bool.self, forKey: key)) ?? true
        }
        enabled = flag(.enabled)
        useBasicInfo = flag(.useBasicInfo)
        useArtwork = flag(.useArtwork)
    }
}

extension MediaItem {
    /// An anime database's record with the fields a turned-off Anime
    /// Enrichment module covers removed.
    nonisolated func restricted(to modules: AnimeEnrichmentPreferences) -> MediaItem {
        MediaItem(
            id: id,
            title: title,
            year: modules.useBasicInfo ? year : "—",
            kind: kind,
            overview: modules.useBasicInfo ? overview : "",
            genres: modules.useBasicInfo ? genres : [],
            symbol: symbol,
            artworkColors: artworkColors,
            artworkURL: modules.useArtwork ? artworkURL : nil,
            backdropURL: modules.useArtwork ? backdropURL : nil,
            externalIDs: externalIDs,
            progress: progress
        )
    }

    /// The TMDB record with every field a turned-off module covers removed,
    /// so `fillingGaps(from:)` can't copy those fields onto an add-on title.
    nonisolated func restricted(to modules: TMDBEnrichmentPreferences) -> MediaItem {
        let details = self.details.map { details in
            MediaTitleDetails(
                ageRating: modules.useDetails ? details.ageRating : nil,
                runtimeMinutes: modules.useDetails ? details.runtimeMinutes : nil,
                status: modules.useDetails ? details.status : nil,
                budget: modules.useDetails ? details.budget : nil,
                revenue: modules.useDetails ? details.revenue : nil,
                studios: modules.useProductions ? details.studios : [],
                cast: modules.useCredits ? details.cast : [],
                crew: modules.useCredits ? details.crew : [],
                studioTitles: modules.useProductions ? details.studioTitles : [],
                collection: modules.useCollections ? details.collection : nil,
                recommendations: modules.useMoreLikeThis ? details.recommendations : [],
                seasons: modules.useEpisodes ? details.seasons : [],
                trailers: modules.useTrailers ? details.trailers : [],
                bonusContent: modules.useTrailers ? details.bonusContent : [],
                productionCompanies: modules.useProductions ? details.productionCompanies : [],
                networks: modules.useProductions ? details.networks : [],
                creators: modules.useCredits ? details.creators : [],
                originCountries: modules.useDetails ? details.originCountries : [],
                originalLanguage: modules.useDetails ? details.originalLanguage : nil,
                releaseDate: modules.useDetails ? details.releaseDate : nil,
                similar: modules.useMoreLikeThis ? details.similar : [],
                recommendationsHaveMore: modules.useMoreLikeThis && details.recommendationsHaveMore,
                similarHaveMore: modules.useMoreLikeThis && details.similarHaveMore,
                tmdbID: details.tmdbID
            )
        }

        return MediaItem(
            id: id,
            title: title,
            year: year,
            kind: kind,
            overview: modules.useBasicInfo ? overview : "",
            genres: modules.useBasicInfo ? genres : [],
            symbol: symbol,
            artworkColors: artworkColors,
            artworkURL: modules.useArtwork ? artworkURL : nil,
            backdropURL: modules.useArtwork ? backdropURL : nil,
            logoURL: modules.useArtwork ? logoURL : nil,
            metadataProvider: metadataProvider,
            metadataProviderID: metadataProviderID,
            metadataRecordID: metadataRecordID,
            externalIDs: externalIDs,
            details: details,
            progress: progress,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds,
            resumeEpisodeID: resumeEpisodeID,
            resumeSeasonNumber: resumeSeasonNumber,
            resumeEpisodeNumber: resumeEpisodeNumber,
            resumeEpisodeTitle: resumeEpisodeTitle,
            resumeEpisodeStillURL: resumeEpisodeStillURL
        )
    }
}

nonisolated extension MediaItem {
    /// Enabled, nonempty enrichment replaces source fields while preserving identity/history.
    /// Apply the highest-priority provider last. No rating payload is changed here.
    func mergingEnrichment(from provider: MediaItem, modules: TMDBEnrichmentPreferences) -> MediaItem {
        guard modules.enabled else { return self }
        let eligible = provider.restricted(to: modules)
        let preferred = eligible.fillingGaps(from: self)
        var enrichedDetails = MediaTitleDetails.enrichmentFilling(eligible.details, from: details)
        if let rich = enrichedDetails, let original = details {
            // The source release date remains authoritative for matching episodes.
            let incomingNumbers = Set(rich.seasons.map(\.seasonNumber))
            let seasons = rich.seasons.map { season in
                let source = original.seasons.first { $0.seasonNumber == season.seasonNumber }
                let incomingEpisodes = Set(season.episodes.map(\.episodeNumber))
                return MediaSeason(id: source?.id ?? season.id, seasonNumber: season.seasonNumber,
                    title: season.title.isEmpty ? source?.title ?? season.title : season.title,
                    overview: season.overview ?? source?.overview, posterURL: season.posterURL ?? source?.posterURL,
                    episodes: season.episodes.map { episode in
                        let sourceEpisode = source?.episodes.first { $0.episodeNumber == episode.episodeNumber }
                        return MediaEpisode(id: sourceEpisode?.id ?? episode.id, seasonNumber: episode.seasonNumber,
                            episodeNumber: episode.episodeNumber,
                            title: episode.title.isEmpty ? sourceEpisode?.title ?? episode.title : episode.title,
                            overview: episode.overview.isEmpty ? sourceEpisode?.overview ?? episode.overview : episode.overview,
                            runtimeMinutes: episode.runtimeMinutes ?? sourceEpisode?.runtimeMinutes,
                            stillURL: episode.stillURL ?? sourceEpisode?.stillURL,
                            airDate: sourceEpisode?.airDate ?? episode.airDate)
                    } + (source?.episodes.filter { !incomingEpisodes.contains($0.episodeNumber) } ?? []))
            } + original.seasons.filter { !incomingNumbers.contains($0.seasonNumber) }
            enrichedDetails = MediaTitleDetails(ageRating: rich.ageRating, runtimeMinutes: rich.runtimeMinutes,
                status: rich.status, budget: rich.budget, revenue: rich.revenue, studios: rich.studios,
                cast: rich.cast, crew: rich.crew, studioTitles: rich.studioTitles, collection: rich.collection,
                recommendations: rich.recommendations, seasons: seasons, trailers: rich.trailers,
                bonusContent: rich.bonusContent, productionCompanies: rich.productionCompanies,
                networks: rich.networks, creators: rich.creators, originCountries: rich.originCountries,
                originalLanguage: rich.originalLanguage, releaseDate: rich.releaseDate, similar: rich.similar,
                recommendationsHaveMore: rich.recommendationsHaveMore, similarHaveMore: rich.similarHaveMore,
                tmdbID: rich.tmdbID)
        }
        return MediaItem(id: id,
            title: modules.useBasicInfo && !provider.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? provider.title : title,
            year: modules.useBasicInfo && provider.year != "—" ? provider.year : year,
            kind: kind, overview: preferred.overview, genres: preferred.genres, symbol: symbol,
            artworkColors: artworkColors, artworkURL: preferred.artworkURL, backdropURL: preferred.backdropURL,
            logoURL: preferred.logoURL, metadataProvider: metadataProvider, metadataProviderID: metadataProviderID,
            metadataRecordID: metadataRecordID, externalIDs: externalIDs.merging(provider.externalIDs) { current, _ in current },
            details: enrichedDetails, progress: progress, positionSeconds: positionSeconds, durationSeconds: durationSeconds,
            resumeEpisodeID: resumeEpisodeID, resumeSeasonNumber: resumeSeasonNumber,
            resumeEpisodeNumber: resumeEpisodeNumber, resumeEpisodeTitle: resumeEpisodeTitle,
            resumeEpisodeStillURL: resumeEpisodeStillURL)
    }
}

nonisolated extension MediaTitleDetails {
    static func enrichmentFilling(_ primary: MediaTitleDetails?, from fallback: MediaTitleDetails?) -> MediaTitleDetails? {
        guard let primary else { return fallback }
        guard let fallback else { return primary }
        return MediaTitleDetails(
            ageRating: primary.ageRating ?? fallback.ageRating,
            runtimeMinutes: primary.runtimeMinutes ?? fallback.runtimeMinutes,
            status: primary.status ?? fallback.status,
            budget: primary.budget ?? fallback.budget,
            revenue: primary.revenue ?? fallback.revenue,
            studios: primary.studios.isEmpty ? fallback.studios : primary.studios,
            // Nonempty credits from the selected provider retain its priority.
            cast: primary.cast.isEmpty ? fallback.cast : primary.cast,
            crew: primary.crew.isEmpty ? fallback.crew : primary.crew,
            studioTitles: primary.studioTitles.isEmpty ? fallback.studioTitles : primary.studioTitles,
            collection: primary.collection ?? fallback.collection,
            recommendations: primary.recommendations.isEmpty ? fallback.recommendations : primary.recommendations,
            seasons: primary.seasons.isEmpty ? fallback.seasons : primary.seasons,
            trailers: primary.trailers.isEmpty ? fallback.trailers : primary.trailers,
            bonusContent: primary.bonusContent.isEmpty ? fallback.bonusContent : primary.bonusContent,
            productionCompanies: primary.productionCompanies.isEmpty ? fallback.productionCompanies : primary.productionCompanies,
            networks: primary.networks.isEmpty ? fallback.networks : primary.networks,
            creators: primary.creators.isEmpty ? fallback.creators : primary.creators,
            originCountries: primary.originCountries.isEmpty ? fallback.originCountries : primary.originCountries,
            originalLanguage: primary.originalLanguage ?? fallback.originalLanguage,
            releaseDate: primary.releaseDate ?? fallback.releaseDate,
            similar: primary.similar.isEmpty ? fallback.similar : primary.similar,
            // View All belongs to whichever list is shown.
            recommendationsHaveMore: primary.recommendations.isEmpty ? fallback.recommendationsHaveMore : primary.recommendationsHaveMore,
            similarHaveMore: primary.similar.isEmpty ? fallback.similarHaveMore : primary.similarHaveMore,
            tmdbID: primary.tmdbID ?? fallback.tmdbID
        )
    }
}
