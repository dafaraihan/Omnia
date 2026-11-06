import Foundation

/// Library is what's saved to it, each title once. Continue Watching and
/// finished titles have their own places, so they aren't listed here.
enum LibraryCollectionPresentation {
    static func items(
        snapshots: [LocalMediaSnapshot],
        kind selectedKind: MediaItem.Kind?,
        sort: LibrarySortOrder
    ) -> [MediaItem] {
        var kept: [LocalMediaSnapshot] = []
        for snapshot in snapshots where snapshot.isInWatchlist && (selectedKind == nil || snapshot.item.kind == selectedKind) {
            // A title saved twice under different IDs shows once.
            if !kept.contains(where: { $0.item.isSameTitle(as: snapshot.item) }) {
                kept.append(snapshot)
            }
        }
        return sortSnapshots(kept, by: sort).map(\.item)
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
