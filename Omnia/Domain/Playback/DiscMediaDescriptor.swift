nonisolated enum DiscMediaDescriptor: Equatable, Sendable {
    case iso(TorrentMediaFile)
    case bluRayDirectory(root: String, files: [TorrentMediaFile])
}

nonisolated enum DiscDetectionResult: Equatable, Sendable {
    case supported(DiscMediaDescriptor)
    case unsupportedDVDDirectory(root: String)
    case notDisc
    case rejected(DiscDetectionFailure)
}

nonisolated enum DiscDetectionFailure: Equatable, Sendable {
    case metadataLimitExceeded
    case unsafePath
    case totalSizeExceeded
    case ambiguousLayout
}
