import Foundation

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
        availableVolumeBytes: Int64
    ) throws -> Plan {
        guard maximumCacheBytes > 0,
              minimumFreeBytes >= 0,
              maximumItemBytes > 0,
              expectedItemBytes >= 0,
              currentCacheBytes >= 0,
              availableVolumeBytes >= 0 else {
            throw StorageError.invalidPolicy
        }
        guard expectedItemBytes <= maximumItemBytes,
              expectedItemBytes <= maximumCacheBytes else {
            throw StorageError.itemTooLarge
        }

        let requiredEviction = max(
            currentCacheBytes + expectedItemBytes - maximumCacheBytes,
            0
        )
        let requiredAvailable = expectedItemBytes + minimumFreeBytes
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
        fileManager: FileManager = .default
    ) throws -> URL {
        let selectedRoot: URL
        if let root {
            selectedRoot = root
        } else {
            selectedRoot = try defaultRoot(fileManager: fileManager)
        }
        let root = selectedRoot.standardizedFileURL
        guard root.isFileURL else { throw CacheError.cacheUnavailable }
        try ensureDirectory(root, fileManager: fileManager)

        let rootValues = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            throw CacheError.unsafeCacheEntry
        }

        let entries = try cacheEntries(at: root, fileManager: fileManager)
        let currentBytes = entries.reduce(Int64(0)) { $0 + $1.byteCount }
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
            availableVolumeBytes: volumeBytes
        )

        var evictedBytes: Int64 = 0
        for entry in entries
            .filter({ $0.url.lastPathComponent != descriptor.cacheKey })
            .sorted(by: { $0.modifiedAt < $1.modifiedAt })
        where evictedBytes < plan.requiredEvictionBytes {
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

        let itemDirectory = root
            .appendingPathComponent(descriptor.cacheKey, isDirectory: true)
            .standardizedFileURL
        guard itemDirectory.deletingLastPathComponent() == root else {
            throw CacheError.unsafeCacheEntry
        }
        try ensureDirectory(itemDirectory, fileManager: fileManager)
        let itemValues = try itemDirectory.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey
        ])
        guard itemValues.isDirectory == true, itemValues.isSymbolicLink != true else {
            throw CacheError.unsafeCacheEntry
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

    private static func cacheEntries(
        at root: URL,
        fileManager: FileManager
    ) throws -> [CacheEntry] {
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
                byteCount: try allocatedBytes(at: child, fileManager: fileManager),
                modifiedAt: values.contentModificationDate ?? .distantPast
            )
        }
    }

    private static func allocatedBytes(at directory: URL, fileManager: FileManager) throws -> Int64 {
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

nonisolated enum LocalTorrentConsent {
    static let disclosure = "Starting local torrent playback connects directly to peers. Your IP address can be visible to peers and trackers, Omnia may upload pieces while downloading, and the selected media is stored in a bounded local cache until it is removed. Only continue for media you are authorized to access and share."
}
