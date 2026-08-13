import Foundation

nonisolated struct TorrentMediaFile: Identifiable, Equatable, Hashable, Sendable {
    var id: Int { index }

    let index: Int
    let relativePath: String
    let size: Int64
    let isSymbolicLink: Bool

    init(
        index: Int,
        relativePath: String,
        size: Int64,
        isSymbolicLink: Bool = false
    ) {
        self.index = index
        self.relativePath = relativePath
        self.size = size
        self.isSymbolicLink = isSymbolicLink
    }
}

nonisolated enum TorrentFileSelection: Equatable, Sendable {
    case selected(TorrentMediaFile)
    case requiresChoice([TorrentMediaFile])
    case unavailable(TorrentFileSelectionFailure)
}

nonisolated enum TorrentFileSelectionFailure: Equatable, Sendable {
    case noRegularFiles
    case metadataLimitExceeded
    case unsafePath
}

nonisolated struct TorrentFileSelectionPolicy: Sendable {
    static let maximumMetadataFiles = 10_000
    static let maximumChoices = 200

    private static let rankedMediaExtensions = Set([
        "mkv", "mp4", "m4v", "mov", "webm", "avi", "ts", "m2ts",
        "mts", "mpg", "mpeg", "vob", "iso",
    ])

    func select(
        _ files: [TorrentMediaFile],
        preferredIndex: Int?,
        preferredFilename: String?
    ) -> TorrentFileSelection {
        guard files.count <= Self.maximumMetadataFiles else {
            return .unavailable(.metadataLimitExceeded)
        }
        guard files.allSatisfy(Self.isSafe) else {
            return .unavailable(.unsafePath)
        }

        let regularFiles = files.filter { $0.size > 0 && !$0.isSymbolicLink }
        guard !regularFiles.isEmpty else { return .unavailable(.noRegularFiles) }

        if let preferredIndex,
           let indexed = regularFiles.first(where: { $0.index == preferredIndex }) {
            return .selected(indexed)
        }

        if let preferredFilename {
            let normalizedPreference = preferredFilename
                .precomposedStringWithCanonicalMapping
                .lowercased()
            if let named = regularFiles.first(where: {
                URL(fileURLWithPath: $0.relativePath).lastPathComponent
                    .precomposedStringWithCanonicalMapping
                    .lowercased() == normalizedPreference
            }) {
                return .selected(named)
            }
        }

        let ranked = regularFiles.filter {
            Self.rankedMediaExtensions.contains(
                URL(fileURLWithPath: $0.relativePath).pathExtension.lowercased()
            )
        }
        guard !ranked.isEmpty else {
            return .requiresChoice(Self.sortedChoices(regularFiles))
        }

        let sorted = Self.sortedChoices(ranked)
        guard let largest = sorted.first else { return .unavailable(.noRegularFiles) }
        let similarlySized = sorted.filter {
            Double($0.size) >= Double(largest.size) * 0.80
        }
        if similarlySized.count == 1 {
            return .selected(largest)
        }
        return .requiresChoice(Array(sorted.prefix(Self.maximumChoices)))
    }

    private static func sortedChoices(_ files: [TorrentMediaFile]) -> [TorrentMediaFile] {
        Array(files.sorted {
            if $0.size != $1.size { return $0.size > $1.size }
            return $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }.prefix(maximumChoices))
    }

    private static func isSafe(_ file: TorrentMediaFile) -> Bool {
        guard file.index >= 0, file.size >= 0, !file.isSymbolicLink else { return false }
        let path = file.relativePath
            .replacingOccurrences(of: "\\", with: "/")
            .precomposedStringWithCanonicalMapping
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              URL(fileURLWithPath: path).path != "/",
              !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
        else { return false }
        return true
    }
}
