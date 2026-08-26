import Foundation

enum BuiltInHomeShelf: String, CaseIterable, Identifiable, Sendable {
    case trendingMovies = "trending-movies"
    case popularMovies = "popular-movies"
    case popularSeries = "popular-series"
    case nowPlayingMovies = "now-playing-movies"
    case upcomingMovies = "upcoming-movies"
    case trendingSeries = "trending-series"
    case topRatedSeries = "top-rated-series"
    case airingToday = "airing-today"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trendingMovies: "Trending Now"
        case .popularMovies: "Popular Movies"
        case .popularSeries: "Popular Series"
        case .nowPlayingMovies: "In Theaters"
        case .upcomingMovies: "Coming Soon"
        case .trendingSeries: "Series Worth Starting"
        case .topRatedSeries: "Top Rated Series"
        case .airingToday: "Airing Today"
        }
    }

    var kind: MediaItem.Kind {
        switch self {
        case .trendingMovies, .popularMovies, .nowPlayingMovies, .upcomingMovies: .movie
        case .popularSeries, .trendingSeries, .topRatedSeries, .airingToday: .series
        }
    }

    var category: MetadataCatalogCategory {
        switch self {
        case .trendingMovies, .trendingSeries: .trending
        case .popularMovies, .popularSeries: .popular
        case .nowPlayingMovies: .nowPlaying
        case .upcomingMovies: .upcoming
        case .topRatedSeries: .topRated
        case .airingToday: .airingToday
        }
    }
}

struct HomeShelfPreferences: Equatable, Sendable {
    static let storageKey = "home-disabled-built-in-shelves-v1"

    private var disabledShelfIDs: Set<String>

    init(rawValue: String) {
        let validIDs = Set(BuiltInHomeShelf.allCases.map(\.id))
        disabledShelfIDs = Set(rawValue.split(separator: "\n").map(String.init))
            .intersection(validIDs)
    }

    var rawValue: String {
        disabledShelfIDs.sorted().joined(separator: "\n")
    }

    func isEnabled(_ shelf: BuiltInHomeShelf) -> Bool {
        !disabledShelfIDs.contains(shelf.id)
    }

    mutating func setEnabled(_ isEnabled: Bool, for shelf: BuiltInHomeShelf) {
        if isEnabled {
            disabledShelfIDs.remove(shelf.id)
        } else {
            disabledShelfIDs.insert(shelf.id)
        }
    }
}
