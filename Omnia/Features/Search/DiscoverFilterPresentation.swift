import Foundation

enum DiscoverFilterMenuSection: Equatable, Sendable {
    case catalogs
    case genre
    case kind
    case sort
}

enum DiscoverReleasePeriod: String, CaseIterable, Identifiable, Sendable {
    case anyDate
    case thisYear
    case lastYear
    case lastFiveYears
    case chooseYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anyDate: "Any Date"
        case .thisYear: "This Year"
        case .lastYear: "Last Year"
        case .lastFiveYears: "Last 5 Years"
        case .chooseYear: "Choose Year"
        }
    }
}

enum DiscoverDateSort: String, CaseIterable, Identifiable, Sendable {
    case catalogOrder
    case newestFirst
    case oldestFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .catalogOrder: "Catalog Order"
        case .newestFirst: "Newest First"
        case .oldestFirst: "Oldest First"
        }
    }
}

struct DiscoverFilterState: Equatable, Sendable {
    var genre: String?
    var selectedCatalogIDs: Set<String>
    var kind: MediaItem.Kind?
    var releasePeriod: DiscoverReleasePeriod
    var selectedYear: Int?
    var sort: DiscoverDateSort

    init(
        genre: String? = nil,
        selectedCatalogIDs: Set<String> = [],
        kind: MediaItem.Kind? = nil,
        releasePeriod: DiscoverReleasePeriod = .anyDate,
        selectedYear: Int? = nil,
        sort: DiscoverDateSort = .catalogOrder
    ) {
        self.genre = genre
        self.selectedCatalogIDs = selectedCatalogIDs
        self.kind = kind
        self.releasePeriod = releasePeriod
        self.selectedYear = selectedYear
        self.sort = sort
    }
}

enum DiscoverFilterPresentation {
    static let menuSections: [DiscoverFilterMenuSection] = [
        .catalogs,
        .genre,
        .kind,
        .sort
    ]

    static func apply(
        _ state: DiscoverFilterState,
        to items: [MediaItem],
        currentYear: Int = Calendar.current.component(.year, from: .now)
    ) -> [MediaItem] {
        let filtered = items.filter { item in
            guard state.kind == nil || item.kind == state.kind else { return false }
            guard BrowseGenre.keeps(item, genreName: state.genre) else { return false }
            guard let year = Int(item.year) else {
                return state.releasePeriod == .anyDate
            }
            switch state.releasePeriod {
            case .anyDate:
                return true
            case .thisYear:
                return year == currentYear
            case .lastYear:
                return year == currentYear - 1
            case .lastFiveYears:
                return (currentYear - 4...currentYear).contains(year)
            case .chooseYear:
                return state.selectedYear == nil || year == state.selectedYear
            }
        }

        switch state.sort {
        case .catalogOrder:
            return filtered
        case .newestFirst:
            return filtered.enumerated().sorted {
                let lhsYear = Int($0.element.year) ?? 0
                let rhsYear = Int($1.element.year) ?? 0
                return lhsYear == rhsYear ? $0.offset < $1.offset : lhsYear > rhsYear
            }.map(\.element)
        case .oldestFirst:
            return filtered.enumerated().sorted {
                let lhsYear = Int($0.element.year) ?? Int.max
                let rhsYear = Int($1.element.year) ?? Int.max
                return lhsYear == rhsYear ? $0.offset < $1.offset : lhsYear < rhsYear
            }.map(\.element)
        }
    }

    static func showsCatalog(
        id: String,
        kind: MediaItem.Kind,
        state: DiscoverFilterState,
        builtInShelf: BuiltInHomeShelf? = nil,
        preferences: HomeShelfPreferences
    ) -> Bool {
        if let builtInShelf, !preferences.isEnabled(builtInShelf) { return false }
        if let selectedKind = state.kind, selectedKind != kind { return false }
        return state.selectedCatalogIDs.isEmpty || state.selectedCatalogIDs.contains(id)
    }
}
