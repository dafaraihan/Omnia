import Foundation

nonisolated struct DiscDetectionPolicy: Sendable {
    static let maximumMetadataFiles = 10_000

    let maximumBytes: Int64

    init(maximumBytes: Int64) {
        self.maximumBytes = maximumBytes
    }

    func detect(files: [TorrentMediaFile]) -> DiscDetectionResult {
        guard files.count <= Self.maximumMetadataFiles else {
            return .rejected(.metadataLimitExceeded)
        }
        guard maximumBytes > 0, files.allSatisfy(Self.isSafe) else {
            return .rejected(.unsafePath)
        }

        var totalBytes: Int64 = 0
        for file in files {
            let (sum, overflow) = totalBytes.addingReportingOverflow(file.size)
            guard !overflow, sum <= maximumBytes else {
                return .rejected(.totalSizeExceeded)
            }
            totalBytes = sum
        }
        guard totalBytes > 0 else { return .notDisc }

        let bluRayRoots = Set(files.compactMap { Self.root(before: ["bdmv", "index.bdmv"], in: $0.relativePath) })
        let dvdRoots = Set(files.compactMap { Self.root(before: ["video_ts", "video_ts.ifo"], in: $0.relativePath) })
        let isoFiles = files.filter {
            URL(fileURLWithPath: $0.relativePath).pathExtension.lowercased() == "iso"
        }

        let detectedKinds = (bluRayRoots.isEmpty ? 0 : 1)
            + (dvdRoots.isEmpty ? 0 : 1)
            + (isoFiles.isEmpty ? 0 : 1)
        guard detectedKinds <= 1 else { return .rejected(.ambiguousLayout) }

        if !bluRayRoots.isEmpty {
            guard bluRayRoots.count == 1, let root = bluRayRoots.first else {
                return .rejected(.ambiguousLayout)
            }
            let discFiles = files.filter { Self.belongsToBluRayRoot($0.relativePath, root: root) }
            guard discFiles.count == files.count else { return .rejected(.ambiguousLayout) }
            return .supported(.bluRayDirectory(root: root, files: discFiles))
        }

        if !dvdRoots.isEmpty {
            guard dvdRoots.count == 1, let root = dvdRoots.first,
                  files.allSatisfy({ Self.belongsToRoot($0.relativePath, root: root) })
            else { return .rejected(.ambiguousLayout) }
            return .unsupportedDVDDirectory(root: root)
        }

        if !isoFiles.isEmpty {
            guard isoFiles.count == 1, files.count == 1, let iso = isoFiles.first else {
                return .rejected(.ambiguousLayout)
            }
            return .supported(.iso(iso))
        }
        return .notDisc
    }

    private static func root(before suffix: [String], in path: String) -> String? {
        let components = normalizedComponents(path)
        guard components.count >= suffix.count,
              Array(components.suffix(suffix.count)).map({ $0.lowercased() }) == suffix
        else { return nil }
        return components.dropLast(suffix.count).joined(separator: "/")
    }

    private static func belongsToBluRayRoot(_ path: String, root: String) -> Bool {
        let relative = normalizedComponents(path).joined(separator: "/").lowercased()
        let prefix = root.isEmpty ? "bdmv/" : "\(root.lowercased())/bdmv/"
        return relative.hasPrefix(prefix)
    }

    private static func belongsToRoot(_ path: String, root: String) -> Bool {
        let relative = normalizedComponents(path).joined(separator: "/").lowercased()
        return root.isEmpty || relative.hasPrefix("\(root.lowercased())/")
    }

    private static func normalizedComponents(_ path: String) -> [String] {
        path
            .replacingOccurrences(of: "\\", with: "/")
            .precomposedStringWithCanonicalMapping
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
    }

    private static func isSafe(_ file: TorrentMediaFile) -> Bool {
        let components = normalizedComponents(file.relativePath)
        return file.index >= 0
            && file.size >= 0
            && !file.isSymbolicLink
            && !file.relativePath.hasPrefix("/")
            && !components.isEmpty
            && !components.contains("")
            && !components.contains("..")
            && !components.contains(".")
    }
}
