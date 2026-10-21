import Foundation

/// Settings › Integrations, laid out like Nuvio's: TMDB Enrichment and
/// MDBList Ratings.
nonisolated struct IntegrationPreferences: Codable, Equatable, Sendable {
    var tmdb = TMDBEnrichmentPreferences()
    /// Nuvio's "Enable MDBList Ratings". On by default so ratings keep
    /// showing for anyone who already saved an MDBList key.
    var mdblistEnabled = true

    static let `default` = Self()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case tmdb, mdblistEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tmdb = (try? container.decodeIfPresent(TMDBEnrichmentPreferences.self, forKey: .tmdb)) ?? .init()
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

    static let moduleCount = 9
}

extension MediaItem {
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
                bonusContent: modules.useTrailers ? details.bonusContent : []
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
            artworkURL: artworkURL,
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
