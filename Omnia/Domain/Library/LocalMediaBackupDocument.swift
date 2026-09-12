import Foundation

nonisolated enum LocalMediaBackupError: Error, Equatable {
    case fileTooLarge
    case unsupportedVersion
    case tooManyRecords
    case duplicateMediaID
    case invalidRecord
}

nonisolated struct LocalMediaBackupRecord: Codable, Equatable, Sendable {
    let media: SavedMediaItem
    let isInWatchlist: Bool
    let savedAt: Date?
    let lastPlayedAt: Date?
    let watchState: LocalMediaWatchState?

    init(snapshot: LocalMediaSnapshot) throws {
        media = SavedMediaItem(snapshot.item)
        isInWatchlist = snapshot.isInWatchlist
        savedAt = snapshot.savedAt
        lastPlayedAt = snapshot.lastPlayedAt
        watchState = snapshot.watchState.isEmpty ? nil : snapshot.watchState
        try validate()
    }

    var snapshot: LocalMediaSnapshot {
        LocalMediaSnapshot(
            item: media.mediaItem,
            isInWatchlist: isInWatchlist,
            savedAt: savedAt,
            lastPlayedAt: lastPlayedAt,
            watchState: watchState ?? .empty
        )
    }

    func validate() throws {
        let item = media.mediaItem
        let textValues = [item.id, item.title, item.year, item.overview, item.symbol] + item.genres
        let displayURLs = [item.artworkURL, item.backdropURL, item.logoURL, item.resumeEpisodeStillURL]
            .compactMap { $0 }
        guard !item.id.isEmpty,
              textValues.allSatisfy({ $0.utf8.count <= 4_096 }),
              item.externalIDs.count <= 100,
              item.externalIDs.allSatisfy({ $0.key.utf8.count <= 4_096 && $0.value.utf8.count <= 4_096 }),
              isInWatchlist || item.progress != nil || watchState?.isEmpty == false,
              displayURLs.allSatisfy(Self.isSafeDisplayURL)
        else { throw LocalMediaBackupError.invalidRecord }
    }

    private static func isSafeDisplayURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.scheme?.lowercased() == "https"
            && components.host != nil
            && components.user == nil
            && components.password == nil
    }
}

nonisolated struct LocalMediaBackupDocument: Codable, Equatable, Sendable {
    static let maximumByteCount = 10 * 1_024 * 1_024
    static let maximumRecordCount = 10_000

    let version: Int
    let exportedAt: Date
    let records: [LocalMediaBackupRecord]

    init(
        version: Int = 1,
        exportedAt: Date = .now,
        records: [LocalMediaBackupRecord]
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.records = records
    }

    init(snapshots: [LocalMediaSnapshot], exportedAt: Date = .now) throws {
        self.init(
            exportedAt: exportedAt,
            records: try snapshots.sorted { $0.mediaID < $1.mediaID }.map(LocalMediaBackupRecord.init)
        )
        try validate()
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumByteCount else { throw LocalMediaBackupError.fileTooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> LocalMediaBackupDocument {
        guard data.count <= maximumByteCount else { throw LocalMediaBackupError.fileTooLarge }
        let document = try JSONDecoder().decode(LocalMediaBackupDocument.self, from: data)
        try document.validate()
        return document
    }

    func validate() throws {
        guard version == 1 else { throw LocalMediaBackupError.unsupportedVersion }
        guard records.count <= Self.maximumRecordCount else { throw LocalMediaBackupError.tooManyRecords }
        let identifiers = records.map(\.media.id)
        guard Set(identifiers).count == identifiers.count else { throw LocalMediaBackupError.duplicateMediaID }
        try records.forEach { try $0.validate() }
    }
}

nonisolated struct LocalMediaConfirmation: Hashable, Sendable {
    let rawValue: UUID
}

nonisolated struct LocalMediaImportReview: Sendable {
    let document: LocalMediaBackupDocument
    let conflictingMediaIDs: [String]
    let confirmation: LocalMediaConfirmation
}

nonisolated enum LocalMediaImportMode: Sendable {
    case merge
    case replace(LocalMediaConfirmation)
}

nonisolated enum LocalMediaDestructiveAction: String, Sendable {
    case clearProgress
    case clearWatchlist
}

nonisolated struct LocalMediaDestructiveConfirmation: Sendable {
    let action: LocalMediaDestructiveAction
    let rawValue: UUID
}
