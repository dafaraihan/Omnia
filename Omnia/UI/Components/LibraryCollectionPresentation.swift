import Foundation

enum LibrarySectionKind: String, CaseIterable, Hashable, Identifiable, Sendable {
    case myList
    case continueWatching
    case rewatch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .myList: "My List"
        case .continueWatching: "Continue Watching"
        case .rewatch: "Rewatch"
        }
    }
}

struct LibrarySection: Equatable, Identifiable, Sendable {
    let kind: LibrarySectionKind
    let items: [MediaItem]

    var id: LibrarySectionKind { kind }
}

enum LibraryCollectionPresentation {
    static func sections(
        snapshots: [LocalMediaSnapshot],
        kind selectedKind: MediaItem.Kind?,
        sort: LibrarySortOrder
    ) -> [LibrarySection] {
        let filtered = snapshots.filter { selectedKind == nil || $0.item.kind == selectedKind }
        var values: [LibrarySectionKind: [LocalMediaSnapshot]] = Dictionary(
            uniqueKeysWithValues: LibrarySectionKind.allCases.map { ($0, []) }
        )

        for snapshot in filtered {
            if snapshot.progress != nil {
                values[.continueWatching, default: []].append(snapshot)
            } else if isCompleted(snapshot) {
                values[.rewatch, default: []].append(snapshot)
            } else if snapshot.isInWatchlist {
                values[.myList, default: []].append(snapshot)
            }
        }

        return LibrarySectionKind.allCases.map { sectionKind in
            LibrarySection(
                kind: sectionKind,
                items: sortSnapshots(values[sectionKind, default: []], by: sort).map(\.item)
            )
        }
    }

    static func isCompleted(_ snapshot: LocalMediaSnapshot) -> Bool {
        if snapshot.item.kind == .movie {
            return snapshot.watchState.movieWatched == true
        }
        let states = snapshot.watchState.episodeStates.values
        return !states.isEmpty && states.allSatisfy { $0 }
    }

    private static func sortSnapshots(
        _ snapshots: [LocalMediaSnapshot],
        by order: LibrarySortOrder
    ) -> [LocalMediaSnapshot] {
        snapshots.sorted { lhs, rhs in
            switch order {
            case .recentAdded:
                let leftDate = lhs.lastPlayedAt ?? lhs.savedAt ?? .distantPast
                let rightDate = rhs.lastPlayedAt ?? rhs.savedAt ?? .distantPast
                if leftDate != rightDate { return leftDate > rightDate }
            case .title:
                break
            case .releaseYear:
                let leftYear = Int(lhs.item.year) ?? 0
                let rightYear = Int(rhs.item.year) ?? 0
                if leftYear != rightYear { return leftYear > rightYear }
            case .inProgress:
                let leftProgress = lhs.progress ?? -1
                let rightProgress = rhs.progress ?? -1
                if leftProgress != rightProgress { return leftProgress > rightProgress }
            }
            return lhs.item.title.localizedStandardCompare(rhs.item.title) == .orderedAscending
        }
    }
}
