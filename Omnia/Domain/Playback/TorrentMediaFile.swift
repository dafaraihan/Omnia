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
