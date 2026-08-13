import Foundation

nonisolated protocol LocalPlaybackCancellation: Sendable {
    func cancelAndWait() async
}

nonisolated struct LocalTorrentPlaybackDescriptor: Hashable, Sendable {
    enum DescriptorError: LocalizedError, Equatable {
        case invalidInfoHash
        case invalidFileIndex
        case invalidDisplayName
        case invalidExpectedSize
        case invalidMagnetURL

        var errorDescription: String? {
            switch self {
            case .invalidInfoHash:
                "The add-on returned an invalid torrent info hash."
            case .invalidFileIndex:
                "The add-on returned an invalid torrent file index."
            case .invalidDisplayName:
                "The add-on returned an invalid torrent filename."
            case .invalidExpectedSize:
                "The add-on returned an invalid media size."
            case .invalidMagnetURL:
                "Omnia could not create a local torrent descriptor."
            }
        }
    }

    static let maximumFileIndex = 100_000
    static let maximumDisplayNameBytes = 512
    static let maximumTrackerCount = 16
    static let maximumTrackerLength = 2_048
    static let maximumDeclaredByteCount: Int64 = 8 * 1_024 * 1_024 * 1_024 * 1_024

    let infoHash: String
    let fileIndex: Int?
    let displayName: String
    let expectedByteCount: Int64?
    let trackers: [URL]
    let magnetURL: URL

    init(
        infoHash: String,
        fileIndex: Int?,
        displayName: String,
        expectedByteCount: Int64?,
        sources: [String] = []
    ) throws {
        let hash = infoHash.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHash: String
        if hash.range(of: #"^[A-Fa-f0-9]{40}$"#, options: .regularExpression) != nil {
            normalizedHash = hash.lowercased()
        } else if hash.range(of: #"^[A-Za-z2-7]{32}$"#, options: .regularExpression) != nil {
            normalizedHash = hash.uppercased()
        } else if hash.range(of: #"^[A-Fa-f0-9]{64}$"#, options: .regularExpression) != nil {
            normalizedHash = hash.lowercased()
        } else {
            throw DescriptorError.invalidInfoHash
        }

        if let fileIndex, !(0...Self.maximumFileIndex).contains(fileIndex) {
            throw DescriptorError.invalidFileIndex
        }
        if let expectedByteCount,
           expectedByteCount < 0 || expectedByteCount > Self.maximumDeclaredByteCount {
            throw DescriptorError.invalidExpectedSize
        }

        let name = displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        guard name.lengthOfBytes(using: .utf8) <= Self.maximumDisplayNameBytes else {
            throw DescriptorError.invalidDisplayName
        }
        let trackers = Self.validTrackers(in: sources)
        var components = URLComponents()
        components.scheme = "magnet"
        var queryItems = [URLQueryItem(name: "xt", value: "urn:btih:\(normalizedHash)")]
        if !name.isEmpty {
            queryItems.append(URLQueryItem(name: "dn", value: name))
        }
        queryItems.append(contentsOf: trackers.map {
            URLQueryItem(name: "tr", value: $0.absoluteString)
        })
        components.queryItems = queryItems
        guard let magnetURL = components.url else {
            throw DescriptorError.invalidMagnetURL
        }

        self.infoHash = normalizedHash
        self.fileIndex = fileIndex
        self.displayName = name
        self.expectedByteCount = expectedByteCount
        self.trackers = trackers
        self.magnetURL = magnetURL
    }

    var cacheKey: String {
        "\(infoHash)-\(fileIndex.map(String.init) ?? "auto")"
    }

    private static func validTrackers(in sources: [String]) -> [URL] {
        var seen = Set<String>()
        var trackers: [URL] = []
        for source in sources.prefix(64) where trackers.count < maximumTrackerCount {
            guard source.hasPrefix("tracker:") else { continue }
            let value = String(source.dropFirst("tracker:".count))
            guard value.utf8.count <= maximumTrackerLength,
                  let components = URLComponents(string: value),
                  ["https", "udp"].contains(components.scheme?.lowercased() ?? ""),
                  components.host?.isEmpty == false,
                  components.user == nil,
                  components.password == nil,
                  components.fragment == nil,
                  let url = components.url
            else { continue }

            let normalized = url.absoluteString
            guard seen.insert(normalized).inserted else { continue }
            trackers.append(url)
        }
        return trackers
    }
}

nonisolated struct LocalTorrentStoragePolicy: Equatable, Sendable {
    enum StorageError: LocalizedError, Equatable {
        case invalidPolicy
        case itemTooLarge
        case insufficientSpace

        var errorDescription: String? {
            switch self {
            case .invalidPolicy:
                "The torrent cache policy is invalid."
            case .itemTooLarge:
                "This source is larger than Omnia’s configured torrent item limit."
            case .insufficientSpace:
                "There is not enough local storage for this source and the required reserve."
            }
        }
    }

    struct Plan: Equatable, Sendable {
        let requiredEvictionBytes: Int64
        let requiredAvailableBytes: Int64
    }

    let maximumCacheBytes: Int64
    let minimumFreeBytes: Int64
    let maximumItemBytes: Int64

    static let `default` = LocalTorrentStoragePolicy(
        maximumCacheBytes: 20 * 1_024 * 1_024 * 1_024,
        minimumFreeBytes: 5 * 1_024 * 1_024 * 1_024,
        maximumItemBytes: 50 * 1_024 * 1_024 * 1_024
    )

    func plan(
        expectedItemBytes: Int64,
        currentCacheBytes: Int64,
        availableVolumeBytes: Int64,
        existingItemBytes: Int64 = 0
    ) throws -> Plan {
        guard maximumCacheBytes > 0,
              minimumFreeBytes >= 0,
              maximumItemBytes > 0,
              expectedItemBytes >= 0,
              currentCacheBytes >= 0,
              availableVolumeBytes >= 0,
              existingItemBytes >= 0,
              existingItemBytes <= currentCacheBytes else {
            throw StorageError.invalidPolicy
        }
        guard expectedItemBytes <= maximumItemBytes,
              expectedItemBytes <= maximumCacheBytes else {
            throw StorageError.itemTooLarge
        }

        let requiredEviction = max(
            currentCacheBytes - existingItemBytes
                + expectedItemBytes - maximumCacheBytes,
            0
        )
        let requiredAvailable = max(expectedItemBytes - existingItemBytes, 0)
            + minimumFreeBytes
        guard availableVolumeBytes + requiredEviction >= requiredAvailable else {
            throw StorageError.insufficientSpace
        }

        return Plan(
            requiredEvictionBytes: requiredEviction,
            requiredAvailableBytes: requiredAvailable
        )
    }
}

nonisolated enum LocalTorrentCacheManager {
    enum CacheError: LocalizedError, Equatable {
        case cacheUnavailable
        case unsafeCacheEntry
        case evictionFailed

        var errorDescription: String? {
            switch self {
            case .cacheUnavailable:
                "Omnia could not prepare its local torrent cache."
            case .unsafeCacheEntry:
                "Omnia found an unsafe entry in its local torrent cache."
            case .evictionFailed:
                "Omnia could not free enough space in its local torrent cache."
            }
        }
    }

    static func defaultRoot(fileManager: FileManager = .default) throws -> URL {
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw CacheError.cacheUnavailable
        }
        return caches
            .appendingPathComponent("PrimeDeca.Omnia", isDirectory: true)
            .appendingPathComponent("TorrentMedia", isDirectory: true)
    }

    static func prepare(
        descriptor: LocalTorrentPlaybackDescriptor,
        policy: LocalTorrentStoragePolicy = .default,
        root: URL? = nil,
        availableVolumeBytes: Int64? = nil,
        fileManager: FileManager = .default,
        protectedCacheKeys: Set<String> = [],
        cancellationCheck: () throws -> Void = { try Task.checkCancellation() }
    ) throws -> URL {
        try cancellationCheck()
        let selectedRoot: URL
        if let root {
            selectedRoot = root
        } else {
            selectedRoot = try defaultRoot(fileManager: fileManager)
        }
        let root = URL(
            fileURLWithPath: selectedRoot.standardizedFileURL.path,
            isDirectory: true
        )
        guard root.isFileURL else { throw CacheError.cacheUnavailable }
        try cancellationCheck()
        try ensureDirectory(root, fileManager: fileManager)
        try excludeFromBackup(root)

        let rootValues = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            throw CacheError.unsafeCacheEntry
        }

        let expectedItemDirectory = root
            .appendingPathComponent(descriptor.cacheKey, isDirectory: true)
            .standardizedFileURL
        guard expectedItemDirectory.deletingLastPathComponent() == root else {
            throw CacheError.unsafeCacheEntry
        }
        guard !protectedCacheKeys.contains(descriptor.cacheKey) else {
            throw CacheError.evictionFailed
        }
        try cancellationCheck()
        try migrateLegacyItemIfNeeded(
            at: expectedItemDirectory,
            fileManager: fileManager,
            cancellationCheck: cancellationCheck
        )

        let entries = try cacheEntries(
            at: root,
            fileManager: fileManager,
            cancellationCheck: cancellationCheck
        )
        let currentBytes = entries.reduce(Int64(0)) { $0 + $1.byteCount }
        let existingItemBytes = entries.first {
            $0.url.lastPathComponent == descriptor.cacheKey
        }?.byteCount ?? 0
        let volumeBytes: Int64
        if let availableVolumeBytes {
            volumeBytes = availableVolumeBytes
        } else {
            let values = try root.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey
            ])
            guard let capacity = values.volumeAvailableCapacityForImportantUsage else {
                throw CacheError.cacheUnavailable
            }
            volumeBytes = capacity
        }

        let reservedItemBytes = descriptor.expectedByteCount ?? policy.maximumItemBytes
        let plan = try policy.plan(
            expectedItemBytes: reservedItemBytes,
            currentCacheBytes: currentBytes,
            availableVolumeBytes: volumeBytes,
            existingItemBytes: existingItemBytes
        )

        var evictedBytes: Int64 = 0
        for entry in entries
            .filter({
                $0.url.lastPathComponent != descriptor.cacheKey
                    && !protectedCacheKeys.contains($0.url.lastPathComponent)
            })
            .sorted(by: { $0.modifiedAt < $1.modifiedAt })
        where evictedBytes < plan.requiredEvictionBytes {
            try cancellationCheck()
            do {
                try fileManager.removeItem(at: entry.url)
                evictedBytes += entry.byteCount
            } catch {
                throw CacheError.evictionFailed
            }
        }
        guard evictedBytes >= plan.requiredEvictionBytes else {
            throw CacheError.evictionFailed
        }

        let itemDirectory = expectedItemDirectory
        try cancellationCheck()
        let itemAlreadyExisted = fileManager.fileExists(atPath: itemDirectory.path)
        try ensureDirectory(itemDirectory, fileManager: fileManager)
        try excludeFromBackup(itemDirectory)
        let itemValues = try itemDirectory.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey
        ])
        guard itemValues.isDirectory == true, itemValues.isSymbolicLink != true else {
            throw CacheError.unsafeCacheEntry
        }
        do {
            try cancellationCheck()
        } catch {
            if !itemAlreadyExisted {
                try? fileManager.removeItem(at: itemDirectory)
            }
            throw error
        }
        return itemDirectory
    }

    private struct CacheEntry {
        let url: URL
        let byteCount: Int64
        let modifiedAt: Date
    }

    private static func ensureDirectory(_ url: URL, fileManager: FileManager) throws {
        if fileManager.fileExists(atPath: url.path) { return }
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw CacheError.cacheUnavailable
        }
    }

    private static func migrateLegacyItemIfNeeded(
        at itemDirectory: URL,
        fileManager: FileManager,
        cancellationCheck: () throws -> Void
    ) throws {
        guard fileManager.fileExists(atPath: itemDirectory.path) else { return }
        let values = try itemDirectory.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw CacheError.unsafeCacheEntry
        }
        let media = itemDirectory.appendingPathComponent("Media", isDirectory: true)
        guard fileManager.fileExists(atPath: media.path) else {
            try cancellationCheck()
            do {
                try fileManager.removeItem(at: itemDirectory)
            } catch {
                throw CacheError.evictionFailed
            }
            return
        }
        let mediaValues = try media.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        guard mediaValues.isDirectory == true, mediaValues.isSymbolicLink != true else {
            throw CacheError.unsafeCacheEntry
        }
        let allowedChildren = Set(["Media", "complete.plist"])
        let children = try fileManager.contentsOfDirectory(
            at: itemDirectory,
            includingPropertiesForKeys: nil
        )
        for child in children where !allowedChildren.contains(child.lastPathComponent) {
            try cancellationCheck()
            do {
                try fileManager.removeItem(at: child)
            } catch {
                throw CacheError.evictionFailed
            }
        }
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        do {
            try mutableURL.setResourceValues(values)
        } catch {
            throw CacheError.cacheUnavailable
        }
    }

    private static func cacheEntries(
        at root: URL,
        fileManager: FileManager,
        cancellationCheck: () throws -> Void
    ) throws -> [CacheEntry] {
        try cancellationCheck()
        let children = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .contentModificationDateKey
            ],
            options: [.skipsHiddenFiles]
        )

        return try children.map { child in
            try cancellationCheck()
            let child = child.standardizedFileURL
            guard child.deletingLastPathComponent() == root else {
                throw CacheError.unsafeCacheEntry
            }
            let values = try child.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .contentModificationDateKey
            ])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw CacheError.unsafeCacheEntry
            }
            return CacheEntry(
                url: child,
                byteCount: try allocatedBytes(
                    at: child,
                    fileManager: fileManager,
                    cancellationCheck: cancellationCheck
                ),
                modifiedAt: values.contentModificationDate ?? .distantPast
            )
        }
    }

    private static func allocatedBytes(
        at directory: URL,
        fileManager: FileManager,
        cancellationCheck: () throws -> Void
    ) throws -> Int64 {
        try cancellationCheck()
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileAllocatedSizeKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            throw CacheError.cacheUnavailable
        }

        var byteCount: Int64 = 0
        for case let fileURL as URL in enumerator {
            try cancellationCheck()
            let values = try fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileAllocatedSizeKey
            ])
            guard values.isSymbolicLink != true else {
                throw CacheError.unsafeCacheEntry
            }
            if values.isRegularFile == true {
                byteCount += Int64(values.fileAllocatedSize ?? 0)
            }
        }
        return byteCount
    }
}

actor LocalPlaybackJobCoordinator {
    nonisolated enum JobError: LocalizedError, Equatable, Sendable {
        case busy
        case invalidLease

        var errorDescription: String? {
            switch self {
            case .busy:
                "Another local playback source is already being prepared."
            case .invalidLease:
                "Omnia rejected an invalid local playback cache reservation."
            }
        }
    }

    nonisolated struct Reservation: Sendable {
        let cacheRoot: URL
        let itemDirectory: URL
    }

    nonisolated struct PlaybackProtection: Equatable, Sendable {
        fileprivate let id: UUID
        fileprivate let cacheKey: String
    }

    private struct ActiveJob {
        let lease: UUID
        var reservationURL: URL?
        var cacheKey: String?
        var removesReservationOnRelease: Bool
    }

    static let shared = LocalPlaybackJobCoordinator()

    private let root: URL?
    private let availableVolumeBytes: Int64?
    private let fileManager: FileManager
    private var activeJob: ActiveJob?
    private var playbackProtections: [UUID: String] = [:]

    init(
        root: URL? = nil,
        availableVolumeBytes: Int64? = nil,
        fileManager: FileManager = .default
    ) {
        self.root = root
        self.availableVolumeBytes = availableVolumeBytes
        self.fileManager = fileManager
    }

    func acquire() throws -> UUID {
        try Task.checkCancellation()
        guard activeJob == nil else { throw JobError.busy }
        let lease = UUID()
        activeJob = ActiveJob(
            lease: lease,
            reservationURL: nil,
            cacheKey: nil,
            removesReservationOnRelease: false
        )
        return lease
    }

    func prepare(
        descriptor: LocalTorrentPlaybackDescriptor,
        policy: LocalTorrentStoragePolicy,
        lease: UUID
    ) throws -> Reservation {
        try Task.checkCancellation()
        guard activeJob?.lease == lease else { throw JobError.invalidLease }
        let cacheRoot = try root ?? LocalTorrentCacheManager.defaultRoot(fileManager: fileManager)
        let expectedItemDirectory = cacheRoot
            .appendingPathComponent(descriptor.cacheKey, isDirectory: true)
            .standardizedFileURL
        let itemAlreadyExisted = fileManager.fileExists(
            atPath: expectedItemDirectory
                .appendingPathComponent("Media", isDirectory: true)
                .path
        )
        let itemDirectory: URL
        do {
            itemDirectory = try LocalTorrentCacheManager.prepare(
                descriptor: descriptor,
                policy: policy,
                root: cacheRoot,
                availableVolumeBytes: availableVolumeBytes,
                fileManager: fileManager,
                protectedCacheKeys: Set(playbackProtections.values)
            )
            guard activeJob?.lease == lease else { throw JobError.invalidLease }
            activeJob?.reservationURL = itemDirectory
            activeJob?.cacheKey = descriptor.cacheKey
            activeJob?.removesReservationOnRelease = !itemAlreadyExisted
            try Task.checkCancellation()
        } catch {
            if error is CancellationError, !itemAlreadyExisted {
                try? fileManager.removeItem(at: expectedItemDirectory)
            }
            throw error
        }
        guard activeJob?.lease == lease else { throw JobError.invalidLease }
        return Reservation(cacheRoot: cacheRoot, itemDirectory: itemDirectory)
    }

    func commitPreparation(_ lease: UUID) throws {
        try Task.checkCancellation()
        guard activeJob?.lease == lease,
              activeJob?.reservationURL != nil,
              activeJob?.cacheKey != nil
        else {
            throw JobError.invalidLease
        }
        activeJob?.removesReservationOnRelease = false
    }

    func discPlaybackRequest(
        disc: MaterializedDisc,
        cacheRoot: URL,
        lease: UUID
    ) throws -> DiscPlaybackRequest {
        try Task.checkCancellation()
        guard activeJob?.lease == lease else { throw JobError.invalidLease }
        let request = try DiscPlaybackRequest(disc: disc, cacheRoot: cacheRoot)
        try Task.checkCancellation()
        guard activeJob?.lease == lease else { throw JobError.invalidLease }
        return request
    }

    func protectForPlayback(_ lease: UUID) throws -> PlaybackProtection {
        try Task.checkCancellation()
        guard let job = activeJob,
              job.lease == lease,
              let cacheKey = job.cacheKey,
              !job.removesReservationOnRelease
        else {
            throw JobError.invalidLease
        }
        let protection = PlaybackProtection(id: UUID(), cacheKey: cacheKey)
        playbackProtections[protection.id] = protection.cacheKey
        activeJob = nil
        return protection
    }

    func unprotect(_ protection: PlaybackProtection) {
        guard playbackProtections[protection.id] == protection.cacheKey else { return }
        playbackProtections[protection.id] = nil
    }

    func cancelDiscPreparation(
        _ materializer: (any LocalPlaybackCancellation)?,
        lease: UUID
    ) async {
        guard activeJob?.lease == lease else { return }
        await materializer?.cancelAndWait()
        release(lease)
    }

    func release(_ lease: UUID) {
        guard let job = activeJob, job.lease == lease else { return }
        if job.removesReservationOnRelease, let reservationURL = job.reservationURL {
            try? fileManager.removeItem(at: reservationURL)
        }
        activeJob = nil
    }
}

nonisolated enum LocalTorrentConsent {
    static let disclosure = "Starting local torrent playback connects directly to peers. Your IP address can be visible to peers and trackers, Omnia may upload pieces while downloading, and the selected media is stored in a bounded local cache until it is removed. Only continue for media you are authorized to access and share."
}
