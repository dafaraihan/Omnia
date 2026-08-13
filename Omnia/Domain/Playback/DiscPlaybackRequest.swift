import Foundation

nonisolated enum DiscPlaybackRequestError: LocalizedError, Equatable, Sendable {
    case outsideCache
    case incompleteMaterialization
    case unsafeDevice
    case unsupportedDisc

    var errorDescription: String? {
        switch self {
        case .outsideCache:
            "Omnia rejected a disc outside its resolver cache."
        case .incompleteMaterialization:
            "This disc has not finished preparing."
        case .unsafeDevice:
            "Omnia rejected an unsafe disc cache path."
        case .unsupportedDisc:
            "This is not a supported unencrypted Blu-ray disc."
        }
    }
}

nonisolated struct DiscPlaybackRequest: Equatable, Sendable {
    let playbackURL: URL
    let deviceURL: URL
    let requestHeaders: [String: String]

    init(
        disc: MaterializedDisc,
        cacheRoot: URL,
        fileManager: FileManager = .default
    ) throws {
        let cacheRoot = URL(
            fileURLWithPath: cacheRoot.standardizedFileURL.path,
            isDirectory: true
        )
        let deviceURL = disc.rootURL.standardizedFileURL
        guard cacheRoot.isFileURL,
              deviceURL.isFileURL,
              deviceURL.path.hasPrefix(cacheRoot.path + "/")
        else {
            throw DiscPlaybackRequestError.outsideCache
        }
        try Self.requireDirectoryWithoutLink(cacheRoot, fileManager: fileManager)
        try Self.rejectLinks(
            from: cacheRoot,
            through: deviceURL,
            fileManager: fileManager
        )

        let jobRoot: URL
        switch disc.kindHint {
        case .iso:
            jobRoot = deviceURL.deletingLastPathComponent().deletingLastPathComponent()
        case .bluRayDirectory:
            jobRoot = deviceURL.deletingLastPathComponent()
        }
        guard jobRoot.path.hasPrefix(cacheRoot.path + "/") else {
            throw DiscPlaybackRequestError.outsideCache
        }
        try Self.verifyManifest(
            at: jobRoot.appendingPathComponent("complete.plist"),
            disc: disc,
            fileManager: fileManager
        )

        switch disc.kindHint {
        case .iso:
            let attributes = try Self.attributes(at: deviceURL, fileManager: fileManager)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.size] as? NSNumber)?.int64Value == disc.bytes,
                  disc.bytes > 0
            else {
                throw DiscPlaybackRequestError.unsupportedDisc
            }
        case .bluRayDirectory:
            try Self.requireDirectoryWithoutLink(deviceURL, fileManager: fileManager)
            try Self.rejectUnsafeTree(at: deviceURL, fileManager: fileManager)
            guard let bdmv = try Self.child(named: "BDMV", at: deviceURL, fileManager: fileManager),
                  let index = try Self.child(named: "index.bdmv", at: bdmv, fileManager: fileManager)
            else {
                throw DiscPlaybackRequestError.unsupportedDisc
            }
            let markerAttributes = try Self.attributes(at: index, fileManager: fileManager)
            guard markerAttributes[.type] as? FileAttributeType == .typeRegular else {
                throw DiscPlaybackRequestError.unsupportedDisc
            }
        }

        guard let playbackURL = URL(string: "bd://longest") else {
            throw DiscPlaybackRequestError.unsupportedDisc
        }
        self.playbackURL = playbackURL
        self.deviceURL = deviceURL
        requestHeaders = [:]
    }

    private static func verifyManifest(
        at url: URL,
        disc: MaterializedDisc,
        fileManager: FileManager
    ) throws {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try Self.attributes(at: url, fileManager: fileManager)
        } catch {
            throw DiscPlaybackRequestError.incompleteMaterialization
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.intValue,
              (1...4_096).contains(size),
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              let manifest = try? PropertyListDecoder().decode(
                DiscMaterializationManifest.self,
                from: data
              ),
              manifest.version == 1,
              manifest.jobID == disc.jobID,
              manifest.bytes == disc.bytes,
              manifest.kind == (disc.kindHint == .iso ? "iso" : "bluRayDirectory")
        else {
            throw DiscPlaybackRequestError.incompleteMaterialization
        }
    }

    private static func rejectLinks(
        from root: URL,
        through target: URL,
        fileManager: FileManager
    ) throws {
        let relative = String(target.path.dropFirst(root.path.count))
        let components = relative.split(separator: "/").map(String.init)
        var cursor = root
        for component in components {
            cursor.appendPathComponent(component)
            let attributes = try Self.attributes(at: cursor, fileManager: fileManager)
            guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
                throw DiscPlaybackRequestError.unsafeDevice
            }
        }
    }

    private static func rejectUnsafeTree(
        at root: URL,
        fileManager: FileManager
    ) throws {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            throw DiscPlaybackRequestError.unsafeDevice
        }
        var count = 0
        for case let url as URL in enumerator {
            count += 1
            guard count <= DiscDetectionPolicy.maximumMetadataFiles else {
                throw DiscPlaybackRequestError.unsafeDevice
            }
            let attributes = try Self.attributes(at: url, fileManager: fileManager)
            guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
                throw DiscPlaybackRequestError.unsafeDevice
            }
        }
    }

    private static func child(
        named name: String,
        at directory: URL,
        fileManager: FileManager
    ) throws -> URL? {
        try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).first { $0.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame }
    }

    private static func requireDirectoryWithoutLink(
        _ url: URL,
        fileManager: FileManager
    ) throws {
        let attributes = try Self.attributes(at: url, fileManager: fileManager)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw DiscPlaybackRequestError.unsafeDevice
        }
    }

    private static func attributes(
        at url: URL,
        fileManager: FileManager
    ) throws -> [FileAttributeKey: Any] {
        do {
            return try fileManager.attributesOfItem(atPath: url.path)
        } catch {
            throw DiscPlaybackRequestError.unsafeDevice
        }
    }
}
