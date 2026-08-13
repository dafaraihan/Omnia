import Foundation

nonisolated struct LocalTorrentPlaybackDescriptor: Hashable, Sendable {
    enum DescriptorError: LocalizedError, Equatable {
        case invalidInfoHash
        case invalidFileIndex
        case invalidExpectedSize
        case invalidMagnetURL

        var errorDescription: String? {
            switch self {
            case .invalidInfoHash:
                "The add-on returned an invalid torrent info hash."
            case .invalidFileIndex:
                "The add-on returned an invalid torrent file index."
            case .invalidExpectedSize:
                "The add-on returned an invalid media size."
            case .invalidMagnetURL:
                "Omnia could not create a local torrent descriptor."
            }
        }
    }

    static let maximumDisplayNameLength = 256
    static let maximumDeclaredByteCount: Int64 = 8 * 1_024 * 1_024 * 1_024 * 1_024

    let infoHash: String
    let fileIndex: Int?
    let displayName: String
    let expectedByteCount: Int64?
    let magnetURL: URL

    init(
        infoHash: String,
        fileIndex: Int?,
        displayName: String,
        expectedByteCount: Int64?
    ) throws {
        let hash = infoHash.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHash: String
        if hash.range(of: #"^[A-Fa-f0-9]{40}$"#, options: .regularExpression) != nil {
            normalizedHash = hash.lowercased()
        } else if hash.range(of: #"^[A-Za-z2-7]{32}$"#, options: .regularExpression) != nil {
            normalizedHash = hash.uppercased()
        } else {
            throw DescriptorError.invalidInfoHash
        }

        if let fileIndex, fileIndex < 0 {
            throw DescriptorError.invalidFileIndex
        }
        if let expectedByteCount,
           expectedByteCount < 0 || expectedByteCount > Self.maximumDeclaredByteCount {
            throw DescriptorError.invalidExpectedSize
        }

        let name = String(
            displayName
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(Self.maximumDisplayNameLength)
        )
        var components = URLComponents()
        components.scheme = "magnet"
        var queryItems = [URLQueryItem(name: "xt", value: "urn:btih:\(normalizedHash)")]
        if !name.isEmpty {
            queryItems.append(URLQueryItem(name: "dn", value: name))
        }
        components.queryItems = queryItems
        guard let magnetURL = components.url else {
            throw DescriptorError.invalidMagnetURL
        }

        self.infoHash = normalizedHash
        self.fileIndex = fileIndex
        self.displayName = name
        self.expectedByteCount = expectedByteCount
        self.magnetURL = magnetURL
    }

    var cacheKey: String {
        "\(infoHash)-\(fileIndex.map(String.init) ?? "auto")"
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
        maximumCacheBytes: 50 * 1_024 * 1_024 * 1_024,
        minimumFreeBytes: 5 * 1_024 * 1_024 * 1_024,
        maximumItemBytes: 100 * 1_024 * 1_024 * 1_024
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

nonisolated enum LocalTorrentConsent {
    static let disclosure = "Starting local torrent playback connects directly to peers. Your IP address can be visible to peers and trackers, Omnia may upload pieces while downloading, and the selected media is stored in a bounded local cache until it is removed. Only continue for media you are authorized to access and share."
}
