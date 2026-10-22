import Foundation
import SwiftData

enum LocalMediaStoreError: Error, Equatable {
    case invalidPlaybackState
    case invalidCompletionThreshold
    case corruptStoredMedia
    case verificationFailed
    case confirmationRequired
}

protocol LocalMediaStoring: Sendable {
    func snapshot() async throws -> [LocalMediaSnapshot]
    func continueWatching(limit: Int?) async throws -> [LocalMediaSnapshot]
    func setWatchlist(_ item: MediaItem, isIncluded: Bool, at date: Date) async throws
    func recordPlayback(
        for item: MediaItem,
        episode: MediaEpisode?,
        positionSeconds: Double,
        durationSeconds: Double?,
        completionThreshold: Double,
        at date: Date
    ) async throws
    func clearProgress() async throws
    func clearProgress(for mediaID: String) async throws
    func applyWatchCommand(
        _ command: LocalMediaWatchCommand,
        to item: MediaItem,
        episodes: [MediaEpisode],
        at date: Date
    ) async throws
}

@ModelActor
actor LocalMediaStore: LocalMediaStoring {
    static func live() throws -> LocalMediaStore {
        let container = try ModelContainer(for: LocalMediaRecord.self)
        return LocalMediaStore(modelContainer: container)
    }

    /// A profile's own library. The profile that owns this Mac's library
    /// from before profiles keeps using `live()`.
    static func live(profileID: UUID) throws -> LocalMediaStore {
        guard let url = profileStoreURL(for: profileID) else { return try live() }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let configuration = ModelConfiguration(url: url)
        let container = try ModelContainer(for: LocalMediaRecord.self, configurations: configuration)
        return LocalMediaStore(modelContainer: container)
    }

    nonisolated static func profileStoreURL(for profileID: UUID) -> URL? {
        ProfileStore.defaultDirectory?.appending(path: "\(profileID.uuidString).store")
    }

    static func inMemory() throws -> LocalMediaStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: LocalMediaRecord.self, configurations: configuration)
        return LocalMediaStore(modelContainer: container)
    }

    func snapshot() throws -> [LocalMediaSnapshot] {
        try records()
            .map(makeSnapshot)
            .sorted(by: snapshotOrder)
    }

    func continueWatching(limit: Int?) throws -> [LocalMediaSnapshot] {
        let boundedLimit = limit.map { min(max($0, 0), 500) }
        let values = try records()
            .filter { $0.progress != nil }
            .map(makeSnapshot)
            .sorted { lhs, rhs in
                let left = lhs.lastPlayedAt ?? .distantPast
                let right = rhs.lastPlayedAt ?? .distantPast
                return left == right ? lhs.mediaID < rhs.mediaID : left > right
            }
        return boundedLimit.map { Array(values.prefix($0)) } ?? values
    }

    func setWatchlist(_ item: MediaItem, isIncluded: Bool, at date: Date) throws {
        guard !item.id.isEmpty, item.id.count <= 512 else {
            throw LocalMediaStoreError.corruptStoredMedia
        }
        let existing = try record(id: item.id)
        guard isIncluded || existing != nil else { return }
        let record = try existing ?? makeRecord(for: item)
        record.mediaData = try encodedBaseItem(item)
        record.isInWatchlist = isIncluded
        record.savedAt = isIncluded ? (record.savedAt ?? date) : nil
        if existing == nil { modelContext.insert(record) }
        if !record.isInWatchlist,
           record.progress == nil,
           try decodedWatchState(from: record).isEmpty {
            modelContext.delete(record)
        }
        try saveOrRollback()
    }

    func recordPlayback(
        for item: MediaItem,
        episode: MediaEpisode?,
        positionSeconds: Double,
        durationSeconds: Double?,
        completionThreshold: Double,
        at date: Date
    ) throws {
        guard positionSeconds.isFinite, positionSeconds >= 0,
              completionThreshold.isFinite,
              (0 ... 1).contains(completionThreshold)
        else { throw LocalMediaStoreError.invalidPlaybackState }
        guard durationSeconds == nil || (durationSeconds!.isFinite && durationSeconds! > 0) else {
            throw LocalMediaStoreError.invalidPlaybackState
        }

        let existing = try record(id: item.id)
        let record = try existing ?? makeRecord(for: item)
        let normalized = durationSeconds.map { min(max(positionSeconds / $0, 0), 1) }
        let completed = normalized.map { $0 >= completionThreshold } ?? false

        record.mediaData = try encodedBaseItem(item)
        if completed {
            clearProgress(on: record)
        } else {
            record.positionSeconds = positionSeconds
            record.durationSeconds = durationSeconds
            record.progress = normalized
            record.lastPlayedAt = date
            if let episode {
                record.resumeEpisodeID = episode.id
                record.resumeSeasonNumber = episode.seasonNumber
                record.resumeEpisodeNumber = episode.episodeNumber
                record.resumeEpisodeTitle = episode.title
                record.resumeEpisodeStillURL = episode.stillURL
            }
        }

        if existing == nil, !completed { modelContext.insert(record) }
        if !record.isInWatchlist,
           record.progress == nil,
           try decodedWatchState(from: record).isEmpty,
           existing != nil {
            modelContext.delete(record)
        }
        try saveOrRollback()
    }

    func clearProgress() throws {
        for record in try records() {
            clearProgress(on: record)
            if !record.isInWatchlist, try decodedWatchState(from: record).isEmpty {
                modelContext.delete(record)
            }
        }
        try saveOrRollback()
    }

    func clearProgress(for mediaID: String) throws {
        guard !mediaID.isEmpty, mediaID.count <= 512 else {
            throw LocalMediaStoreError.corruptStoredMedia
        }
        guard let record = try record(id: mediaID) else { return }
        clearProgress(on: record)
        if !record.isInWatchlist, try decodedWatchState(from: record).isEmpty {
            modelContext.delete(record)
        }
        try saveOrRollback()
    }

    func applyWatchCommand(
        _ command: LocalMediaWatchCommand,
        to item: MediaItem,
        episodes: [MediaEpisode],
        at date: Date
    ) throws {
        guard !item.id.isEmpty, item.id.count <= 512 else {
            throw LocalMediaStoreError.corruptStoredMedia
        }

        let existing = try record(id: item.id)
        let record = try existing ?? makeRecord(for: item)
        var watchState = try decodedWatchState(from: record)
        let orderedEpisodes = episodes.sorted {
            ($0.seasonNumber, $0.episodeNumber, $0.id)
                < ($1.seasonNumber, $1.episodeNumber, $1.id)
        }

        switch command {
        case let .markMovie(watched):
            guard item.kind == .movie else { throw LocalMediaStoreError.invalidPlaybackState }
            watchState.movieWatched = watched
            clearProgress(on: record)

        case let .markEpisode(episode, watched):
            guard item.kind == .series else { throw LocalMediaStoreError.invalidPlaybackState }
            watchState.setWatched(watched, for: episode)
            if watched {
                setResumeTarget(after: episode, in: orderedEpisodes, on: record, at: date)
            } else {
                setResumeTarget(episode, on: record, at: date)
            }

        case let .markSeason(current, watched):
            guard item.kind == .series else { throw LocalMediaStoreError.invalidPlaybackState }
            let seasonEpisodes = orderedEpisodes.filter { $0.seasonNumber == current.seasonNumber }
            guard !seasonEpisodes.isEmpty else { throw LocalMediaStoreError.invalidPlaybackState }
            seasonEpisodes.forEach { watchState.setWatched(watched, for: $0) }
            if watched {
                setResumeTarget(
                    orderedEpisodes.first { $0.seasonNumber > current.seasonNumber },
                    on: record,
                    at: date
                )
            } else {
                setResumeTarget(seasonEpisodes.first, on: record, at: date)
            }

        case let .markThrough(current, watched):
            guard item.kind == .series,
                  let currentIndex = orderedEpisodes.firstIndex(where: { matches($0, current) })
            else { throw LocalMediaStoreError.invalidPlaybackState }
            let affected = Array(orderedEpisodes.prefix(through: currentIndex))
            affected.forEach { watchState.setWatched(watched, for: $0) }
            if watched {
                let target = orderedEpisodes.indices.contains(currentIndex + 1)
                    ? orderedEpisodes[currentIndex + 1]
                    : nil
                setResumeTarget(target, on: record, at: date)
            } else {
                setResumeTarget(affected.first, on: record, at: date)
            }

        case let .revertToPrevious(current):
            guard item.kind == .series,
                  let currentIndex = orderedEpisodes.firstIndex(where: { matches($0, current) }),
                  currentIndex > orderedEpisodes.startIndex
            else { throw LocalMediaStoreError.invalidPlaybackState }
            let previous = orderedEpisodes[currentIndex - 1]
            watchState.setWatched(false, for: previous)
            setResumeTarget(previous, on: record, at: date)

        case let .finishEpisode(finished, nextUp):
            guard item.kind == .series else { throw LocalMediaStoreError.invalidPlaybackState }
            watchState.setWatched(true, for: finished)
            setResumeTarget(nextUp, on: record, at: date)
        }

        record.mediaData = try encodedBaseItem(item)
        record.watchStateData = try JSONEncoder().encode(watchState)
        if existing == nil { modelContext.insert(record) }
        try saveOrRollback()
    }

    func exportDocument(at date: Date = .now) throws -> LocalMediaBackupDocument {
        try LocalMediaBackupDocument(snapshots: snapshot(), exportedAt: date)
    }

    func reviewImport(_ data: Data) throws -> LocalMediaImportReview {
        let document = try LocalMediaBackupDocument.decode(data)
        let existing = Set(try records().map(\.mediaID))
        return LocalMediaImportReview(
            document: document,
            conflictingMediaIDs: document.records.map(\.media.id).filter(existing.contains).sorted(),
            confirmation: LocalMediaConfirmation(rawValue: UUID())
        )
    }

    func applyImport(_ review: LocalMediaImportReview, mode: LocalMediaImportMode) throws {
        switch mode {
        case .merge:
            break
        case let .replace(confirmation):
            guard confirmation == review.confirmation else {
                throw LocalMediaStoreError.confirmationRequired
            }
            try records().forEach(modelContext.delete)
        }

        for backup in review.document.records {
            try apply(backup)
        }
        try saveOrRollback()
    }

    func confirmation(for action: LocalMediaDestructiveAction) -> LocalMediaDestructiveConfirmation {
        LocalMediaDestructiveConfirmation(action: action, rawValue: UUID())
    }

    func perform(
        _ action: LocalMediaDestructiveAction,
        confirmation: LocalMediaDestructiveConfirmation
    ) throws {
        guard confirmation.action == action else {
            throw LocalMediaStoreError.confirmationRequired
        }
        switch action {
        case .clearProgress:
            try clearProgress()
        case .clearWatchlist:
            try clearWatchlist()
        }
    }

    func importLegacy(_ items: [SavedMediaItem], startingAt date: Date = .distantPast) throws {
        let identifiers = items.map(\.id)
        guard Set(identifiers).count == identifiers.count else {
            throw LocalMediaStoreError.verificationFailed
        }
        for (index, saved) in items.enumerated() {
            let item = saved.mediaItem
            let existing = try record(id: item.id)
            let record = try existing ?? makeRecord(for: item)
            record.mediaData = try encodedBaseItem(item)
            record.isInWatchlist = true
            record.savedAt = date.addingTimeInterval(Double(index))
            record.progress = item.progress
            record.positionSeconds = item.positionSeconds
            record.durationSeconds = item.durationSeconds
            record.resumeEpisodeID = item.resumeEpisodeID
            record.resumeSeasonNumber = item.resumeSeasonNumber
            record.resumeEpisodeNumber = item.resumeEpisodeNumber
            record.resumeEpisodeTitle = item.resumeEpisodeTitle
            record.resumeEpisodeStillURL = item.resumeEpisodeStillURL
            record.lastPlayedAt = item.progress == nil ? nil : date.addingTimeInterval(Double(index))
            if existing == nil { modelContext.insert(record) }
        }
        try saveOrRollback()
    }

    private func records() throws -> [LocalMediaRecord] {
        try modelContext.fetch(FetchDescriptor<LocalMediaRecord>())
    }

    private func apply(_ backup: LocalMediaBackupRecord) throws {
        let snapshot = backup.snapshot
        let existing = try record(id: snapshot.mediaID)
        let record = try existing ?? makeRecord(for: snapshot.item)
        record.mediaData = try encodedBaseItem(snapshot.item)
        record.isInWatchlist = snapshot.isInWatchlist
        record.savedAt = snapshot.savedAt
        record.lastPlayedAt = snapshot.lastPlayedAt
        record.progress = snapshot.item.progress
        record.positionSeconds = snapshot.item.positionSeconds
        record.durationSeconds = snapshot.item.durationSeconds
        record.resumeEpisodeID = snapshot.item.resumeEpisodeID
        record.resumeSeasonNumber = snapshot.item.resumeSeasonNumber
        record.resumeEpisodeNumber = snapshot.item.resumeEpisodeNumber
        record.resumeEpisodeTitle = snapshot.item.resumeEpisodeTitle
        record.resumeEpisodeStillURL = snapshot.item.resumeEpisodeStillURL
        record.watchStateData = snapshot.watchState.isEmpty
            ? nil
            : try JSONEncoder().encode(snapshot.watchState)
        if existing == nil { modelContext.insert(record) }
    }

    private func clearWatchlist() throws {
        for record in try records() {
            record.isInWatchlist = false
            record.savedAt = nil
            if record.progress == nil, try decodedWatchState(from: record).isEmpty {
                modelContext.delete(record)
            }
        }
        try saveOrRollback()
    }

    private func record(id: String) throws -> LocalMediaRecord? {
        try records().first { $0.mediaID == id }
    }

    private func makeRecord(for item: MediaItem) throws -> LocalMediaRecord {
        LocalMediaRecord(mediaID: item.id, mediaData: try encodedBaseItem(item))
    }

    private func encodedBaseItem(_ item: MediaItem) throws -> Data {
        var base = item
        base.progress = nil
        base.positionSeconds = nil
        base.durationSeconds = nil
        base.resumeEpisodeID = nil
        base.resumeSeasonNumber = nil
        base.resumeEpisodeNumber = nil
        base.resumeEpisodeTitle = nil
        base.resumeEpisodeStillURL = nil
        return try JSONEncoder().encode(SavedMediaItem(base))
    }

    private func makeSnapshot(_ record: LocalMediaRecord) throws -> LocalMediaSnapshot {
        var item = try JSONDecoder().decode(SavedMediaItem.self, from: record.mediaData).mediaItem
        item.progress = record.progress
        item.positionSeconds = record.positionSeconds
        item.durationSeconds = record.durationSeconds
        item.resumeEpisodeID = record.resumeEpisodeID
        item.resumeSeasonNumber = record.resumeSeasonNumber
        item.resumeEpisodeNumber = record.resumeEpisodeNumber
        item.resumeEpisodeTitle = record.resumeEpisodeTitle
        item.resumeEpisodeStillURL = record.resumeEpisodeStillURL
        return LocalMediaSnapshot(
            item: item,
            isInWatchlist: record.isInWatchlist,
            savedAt: record.savedAt,
            lastPlayedAt: record.lastPlayedAt,
            watchState: try decodedWatchState(from: record)
        )
    }

    private func snapshotOrder(_ lhs: LocalMediaSnapshot, _ rhs: LocalMediaSnapshot) -> Bool {
        let left = lhs.savedAt ?? lhs.lastPlayedAt ?? .distantPast
        let right = rhs.savedAt ?? rhs.lastPlayedAt ?? .distantPast
        return left == right ? lhs.mediaID < rhs.mediaID : left > right
    }

    private func clearProgress(on record: LocalMediaRecord) {
        record.progress = nil
        record.positionSeconds = nil
        record.durationSeconds = nil
        record.resumeEpisodeID = nil
        record.resumeSeasonNumber = nil
        record.resumeEpisodeNumber = nil
        record.resumeEpisodeTitle = nil
        record.resumeEpisodeStillURL = nil
        record.lastPlayedAt = nil
    }

    private func decodedWatchState(from record: LocalMediaRecord) throws -> LocalMediaWatchState {
        guard let data = record.watchStateData else { return .empty }
        do {
            return try JSONDecoder().decode(LocalMediaWatchState.self, from: data)
        } catch {
            throw LocalMediaStoreError.corruptStoredMedia
        }
    }

    private func matches(_ lhs: MediaEpisode, _ rhs: MediaEpisode) -> Bool {
        lhs.id == rhs.id
            || (lhs.seasonNumber == rhs.seasonNumber && lhs.episodeNumber == rhs.episodeNumber)
    }

    private func setResumeTarget(
        after episode: MediaEpisode,
        in episodes: [MediaEpisode],
        on record: LocalMediaRecord,
        at date: Date
    ) {
        guard let index = episodes.firstIndex(where: { matches($0, episode) }),
              episodes.indices.contains(index + 1)
        else {
            clearProgress(on: record)
            return
        }
        setResumeTarget(episodes[index + 1], on: record, at: date)
    }

    private func setResumeTarget(
        _ episode: MediaEpisode?,
        on record: LocalMediaRecord,
        at date: Date
    ) {
        guard let episode else {
            clearProgress(on: record)
            return
        }
        record.progress = 0
        record.positionSeconds = 0
        record.durationSeconds = episode.runtimeMinutes.map { Double($0 * 60) }
        record.resumeEpisodeID = episode.id
        record.resumeSeasonNumber = episode.seasonNumber
        record.resumeEpisodeNumber = episode.episodeNumber
        record.resumeEpisodeTitle = episode.title
        record.resumeEpisodeStillURL = episode.stillURL
        record.lastPlayedAt = date
    }

    private func saveOrRollback() throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
