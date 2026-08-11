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
}

@ModelActor
actor LocalMediaStore: LocalMediaStoring {
    static func live() throws -> LocalMediaStore {
        let container = try ModelContainer(for: LocalMediaRecord.self)
        return LocalMediaStore(modelContainer: container)
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
        if !record.isInWatchlist, record.progress == nil {
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
                record.resumeEpisodeStillURL = episode.stillURL
            }
        }

        if existing == nil, !completed { modelContext.insert(record) }
        if !record.isInWatchlist, record.progress == nil, existing != nil {
            modelContext.delete(record)
        }
        try saveOrRollback()
    }

    func clearProgress() throws {
        for record in try records() {
            clearProgress(on: record)
            if !record.isInWatchlist { modelContext.delete(record) }
        }
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
        record.resumeEpisodeStillURL = snapshot.item.resumeEpisodeStillURL
        if existing == nil { modelContext.insert(record) }
    }

    private func clearWatchlist() throws {
        for record in try records() {
            record.isInWatchlist = false
            record.savedAt = nil
            if record.progress == nil { modelContext.delete(record) }
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
        item.resumeEpisodeStillURL = record.resumeEpisodeStillURL
        return LocalMediaSnapshot(
            item: item,
            isInWatchlist: record.isInWatchlist,
            savedAt: record.savedAt,
            lastPlayedAt: record.lastPlayedAt
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
        record.resumeEpisodeStillURL = nil
        record.lastPlayedAt = nil
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
