import Foundation

/// The one genre list Omnia shows: Browse by Genre cards, Discover's and
/// Search's Filter menus, and Settings › Content & Discovery all use it, so
/// every place offers the same genres (Dafa, 2026-10-22). Each genre also
/// lists the names add-ons, TMDB and TVDB use for it, such as TMDB's series
/// genre "Sci-Fi & Fantasy".
nonisolated enum BrowseGenre: String, CaseIterable, Identifiable, Sendable {
    case action, adventure, scienceFiction, drama, comedy, family, romance, horror, thriller
    case animation, crime, documentary, fantasy, mystery, history, war, western, music, reality

    var id: String { rawValue }

    var title: String {
        switch self {
        case .action: "Action"
        case .adventure: "Adventure"
        case .scienceFiction: "Sci-Fi"
        case .drama: "Drama"
        case .comedy: "Comedy"
        case .family: "Kids & Family"
        case .romance: "Romance"
        case .horror: "Horror"
        case .thriller: "Thriller"
        case .animation: "Animation"
        case .crime: "Crime"
        case .documentary: "Documentary"
        case .fantasy: "Fantasy"
        case .mystery: "Mystery"
        case .history: "History"
        case .war: "War"
        case .western: "Western"
        case .music: "Music"
        case .reality: "Reality"
        }
    }

    /// Names that mean this genre, compared without case or accents.
    var aliases: [String] {
        switch self {
        case .action: ["Action", "Action & Adventure"]
        case .adventure: ["Adventure", "Adventures", "Action & Adventure"]
        case .scienceFiction: ["Sci-Fi", "Science Fiction", "Science-Fiction", "SciFi", "Sci-Fi & Fantasy"]
        case .drama: ["Drama"]
        case .comedy: ["Comedy"]
        case .family: ["Family", "Kids", "Kids & Family", "Children"]
        case .romance: ["Romance"]
        case .horror: ["Horror"]
        case .thriller: ["Thriller", "Suspense"]
        case .animation: ["Animation"]
        case .crime: ["Crime"]
        case .documentary: ["Documentary"]
        case .fantasy: ["Fantasy", "Sci-Fi & Fantasy"]
        case .mystery: ["Mystery"]
        case .history: ["History"]
        case .war: ["War", "War & Politics"]
        case .western: ["Western"]
        case .music: ["Music", "Musical"]
        case .reality: ["Reality", "Reality-TV", "Reality TV"]
        }
    }

    func matches(_ name: String) -> Bool {
        let name = Self.normalized(name)
        return aliases.contains { Self.normalized($0) == name }
    }

    /// True when a title lists this genre under any of its names.
    func matches(genresOf item: MediaItem) -> Bool {
        item.genres.contains(where: matches)
    }

    /// The first option an add-on offers for this genre.
    func option(in options: [String]) -> String? {
        options.first(where: matches)
    }

    /// A stored genre name, which may be one of the titles above or an older
    /// provider name such as "Science Fiction".
    init?(name: String) {
        guard let genre = Self.allCases.first(where: { $0.title == name })
            ?? Self.allCases.first(where: { $0.matches(name) })
        else { return nil }
        self = genre
    }

    /// Keeps titles in `genreName`. Names outside this list, saved before
    /// it existed, still match exactly.
    static func keeps(_ item: MediaItem, genreName: String?) -> Bool {
        guard let genreName else { return true }
        if let genre = BrowseGenre(name: genreName) {
            return genre.matches(genresOf: item)
        }
        return item.genres.contains { normalized($0) == normalized(genreName) }
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
