import Foundation

nonisolated protocol DiscByteSource: Sendable {
    func bytes(for file: TorrentMediaFile) -> AsyncThrowingStream<Data, Error>
}

nonisolated struct MaterializedDisc: Equatable, Sendable {
    nonisolated enum KindHint: Equatable, Sendable {
        case iso
        case bluRayDirectory
    }

    let jobID: UUID
    let rootURL: URL
    let kindHint: KindHint
    let bytes: Int64
}

nonisolated enum DiscMaterializationEvent: Equatable, Sendable {
    case progress(completedBytes: Int64, totalBytes: Int64)
    case ready(MaterializedDisc)
}

nonisolated enum DiscMaterializationError: LocalizedError, Equatable, Sendable {
    case insufficientReservation
    case unsafeReservation
    case byteCountMismatch
    case storageFailure

    var errorDescription: String? {
        switch self {
        case .insufficientReservation:
            "There is not enough reserved cache space for this disc."
        case .unsafeReservation:
            "Omnia rejected an unsafe disc cache path."
        case .byteCountMismatch:
            "The disc source did not match its declared size."
        case .storageFailure:
            "Omnia could not store this disc in its local cache."
        }
    }
}

nonisolated struct DiscMaterializationManifest: Codable, Equatable, Sendable {
    let version: Int
    let jobID: UUID
    let kind: String
    let bytes: Int64
    let completedAt: Date
}

actor DiscMaterializer: LocalPlaybackCancellation {
    private let reservationRoot: URL
    private let reservedBytes: Int64
    private let retainsIncompleteJobs: Bool
    private let jobID: UUID
    private let fileManager: FileManager
    private var activeOperation: (id: UUID, task: Task<Void, Never>)?

    init(
        reservationRoot: URL,
        reservedBytes: Int64,
        retainsIncompleteJobs: Bool = false,
        jobID: UUID = UUID(),
        fileManager: FileManager = .default
    ) {
        self.reservationRoot = URL(
            fileURLWithPath: reservationRoot.standardizedFileURL.path,
            isDirectory: true
        )
        self.reservedBytes = reservedBytes
        self.retainsIncompleteJobs = retainsIncompleteJobs
        self.jobID = jobID
        self.fileManager = fileManager
    }

    func materialize(
        _ descriptor: DiscMediaDescriptor,
        source: any DiscByteSource
    ) -> AsyncThrowingStream<DiscMaterializationEvent, Error> {
        let operationID = UUID()
        var operationTask: Task<Void, Never>!
        let stream = AsyncThrowingStream<DiscMaterializationEvent, Error> { continuation in
            operationTask = Task {
                do {
                    try await self.run(
                        descriptor,
                        source: source,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    self.cleanUpAfterFailure()
                    continuation.finish(throwing: error)
                }
                self.clearActiveOperation(id: operationID)
            }
            continuation.onTermination = { [weak self] _ in
                Task.detached {
                    await self?.cancelOperation(id: operationID)
                }
            }
        }
        activeOperation?.task.cancel()
        activeOperation = (operationID, operationTask)
        return stream
    }

    func cancel() {
        activeOperation?.task.cancel()
    }

    func cancelAndWait() async {
        guard let operation = activeOperation else { return }
        operation.task.cancel()
        await operation.task.value
    }

    private func run(
        _ descriptor: DiscMediaDescriptor,
        source: any DiscByteSource,
        continuation: AsyncThrowingStream<DiscMaterializationEvent, Error>.Continuation
    ) async throws {
        let materialization = try plan(for: descriptor)
        guard reservedBytes >= materialization.totalBytes else {
            throw DiscMaterializationError.insufficientReservation
        }

        try prepareReservation()
        var completedBytes: Int64 = 0
        for item in materialization.items {
            try Task.checkCancellation()
            let finalURL = try confinedURL(for: item.relativeOutputPath)
            try ensureParentDirectories(for: finalURL)
            try rejectExistingItem(at: finalURL)

            let partialURL = finalURL.appendingPathExtension("partial")
            try rejectExistingItem(at: partialURL)
            guard fileManager.createFile(atPath: partialURL.path, contents: nil) else {
                throw DiscMaterializationError.storageFailure
            }

            var fileBytes: Int64 = 0
            do {
                let handle = try FileHandle(forWritingTo: partialURL)
                defer { try? handle.close() }
                for try await chunk in source.bytes(for: item.file) {
                    try Task.checkCancellation()
                    let chunkBytes = Int64(chunk.count)
                    let (nextFileBytes, fileOverflow) = fileBytes.addingReportingOverflow(chunkBytes)
                    let (nextCompletedBytes, totalOverflow) = completedBytes.addingReportingOverflow(nextFileBytes)
                    guard !fileOverflow,
                          !totalOverflow,
                          nextFileBytes <= item.file.size,
                          nextCompletedBytes <= materialization.totalBytes
                    else {
                        throw DiscMaterializationError.byteCountMismatch
                    }
                    try handle.write(contentsOf: chunk)
                    fileBytes = nextFileBytes
                    continuation.yield(
                        .progress(
                            completedBytes: nextCompletedBytes,
                            totalBytes: materialization.totalBytes
                        )
                    )
                }
                try Task.checkCancellation()
                guard fileBytes == item.file.size else {
                    throw DiscMaterializationError.byteCountMismatch
                }
                try handle.synchronize()
                try handle.close()
                try fileManager.moveItem(at: partialURL, to: finalURL)
            } catch {
                try? fileManager.removeItem(at: partialURL)
                throw error
            }
            completedBytes += fileBytes
        }

        guard completedBytes == materialization.totalBytes else {
            throw DiscMaterializationError.byteCountMismatch
        }
        try writeCompletionManifest(
            kind: materialization.kindHint,
            bytes: completedBytes
        )
        continuation.yield(
            .ready(
                MaterializedDisc(
                    jobID: jobID,
                    rootURL: materialization.resultURL,
                    kindHint: materialization.kindHint,
                    bytes: completedBytes
                )
            )
        )
    }

    private struct PlannedItem {
        let file: TorrentMediaFile
        let relativeOutputPath: String
    }

    private struct MaterializationPlan {
        let items: [PlannedItem]
        let totalBytes: Int64
        let resultURL: URL
        let kindHint: MaterializedDisc.KindHint
    }

    private func plan(for descriptor: DiscMediaDescriptor) throws -> MaterializationPlan {
        let mediaRoot = try confinedURL(for: "Media")
        let items: [PlannedItem]
        let resultURL: URL
        let kindHint: MaterializedDisc.KindHint

        switch descriptor {
        case let .iso(file):
            guard Self.isSafe(file: file) else {
                throw DiscMaterializationError.unsafeReservation
            }
            let name = URL(fileURLWithPath: file.relativePath).lastPathComponent
            items = [PlannedItem(file: file, relativeOutputPath: "Media/\(name)")]
            resultURL = try confinedURL(for: "Media/\(name)")
            kindHint = .iso

        case let .bluRayDirectory(root, files):
            let rootComponents = Self.components(in: root)
            guard files.allSatisfy(Self.isSafe) else {
                throw DiscMaterializationError.unsafeReservation
            }
            items = try files.map { file in
                let components = Self.components(in: file.relativePath)
                let fileRoot = components.prefix(rootComponents.count)
                guard fileRoot.map({ $0.lowercased() }) == rootComponents.map({ $0.lowercased() }),
                      components.count > rootComponents.count
                else {
                    throw DiscMaterializationError.unsafeReservation
                }
                let relative = components.dropFirst(rootComponents.count).joined(separator: "/")
                return PlannedItem(
                    file: file,
                    relativeOutputPath: "Media/\(relative)"
                )
            }
            resultURL = mediaRoot
            kindHint = .bluRayDirectory
        }

        var totalBytes: Int64 = 0
        for item in items {
            let (sum, overflow) = totalBytes.addingReportingOverflow(item.file.size)
            guard !overflow else { throw DiscMaterializationError.insufficientReservation }
            totalBytes = sum
        }
        guard totalBytes > 0 else {
            throw DiscMaterializationError.insufficientReservation
        }
        return MaterializationPlan(
            items: items,
            totalBytes: totalBytes,
            resultURL: resultURL,
            kindHint: kindHint
        )
    }

    private func prepareReservation() throws {
        guard reservationRoot.isFileURL else {
            throw DiscMaterializationError.unsafeReservation
        }
        if let attributes = try attributesIfPresent(at: reservationRoot) {
            guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                throw DiscMaterializationError.unsafeReservation
            }
        } else {
            do {
                try fileManager.createDirectory(
                    at: reservationRoot,
                    withIntermediateDirectories: true
                )
            } catch {
                throw DiscMaterializationError.storageFailure
            }
        }

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableRoot = reservationRoot
        do {
            try mutableRoot.setResourceValues(values)
        } catch {
            throw DiscMaterializationError.storageFailure
        }
    }

    private func confinedURL(for relativePath: String) throws -> URL {
        let components = Self.components(in: relativePath)
        guard !components.isEmpty,
              !relativePath.hasPrefix("/"),
              !components.contains("."),
              !components.contains("..")
        else {
            throw DiscMaterializationError.unsafeReservation
        }
        let url = components.reduce(reservationRoot) {
            $0.appendingPathComponent($1, isDirectory: false)
        }.standardizedFileURL
        guard url.path.hasPrefix(reservationRoot.path + "/") else {
            throw DiscMaterializationError.unsafeReservation
        }
        return url
    }

    private func ensureParentDirectories(for fileURL: URL) throws {
        let parent = fileURL.deletingLastPathComponent()
        let relative = String(parent.path.dropFirst(reservationRoot.path.count))
        let components = Self.components(in: relative)
        var cursor = reservationRoot
        for component in components {
            cursor.appendPathComponent(component, isDirectory: true)
            if let attributes = try attributesIfPresent(at: cursor) {
                guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                    throw DiscMaterializationError.unsafeReservation
                }
            } else {
                do {
                    try fileManager.createDirectory(at: cursor, withIntermediateDirectories: false)
                } catch {
                    throw DiscMaterializationError.storageFailure
                }
            }
        }
    }

    private func rejectExistingItem(at url: URL) throws {
        guard try attributesIfPresent(at: url) == nil else {
            throw DiscMaterializationError.unsafeReservation
        }
    }

    private func attributesIfPresent(
        at url: URL
    ) throws -> [FileAttributeKey: Any]? {
        do {
            return try fileManager.attributesOfItem(atPath: url.path)
        } catch {
            guard !fileManager.fileExists(atPath: url.path) else {
                throw DiscMaterializationError.storageFailure
            }
            return nil
        }
    }

    private func writeCompletionManifest(
        kind: MaterializedDisc.KindHint,
        bytes: Int64
    ) throws {
        let manifestURL = try confinedURL(for: "complete.plist")
        try rejectExistingItem(at: manifestURL)
        let manifest = DiscMaterializationManifest(
            version: 1,
            jobID: jobID,
            kind: kind == .iso ? "iso" : "bluRayDirectory",
            bytes: bytes,
            completedAt: Date()
        )
        do {
            let data = try PropertyListEncoder().encode(manifest)
            guard data.count <= 4_096 else {
                throw DiscMaterializationError.storageFailure
            }
            try data.write(to: manifestURL, options: [.atomic])
        } catch let error as DiscMaterializationError {
            throw error
        } catch {
            throw DiscMaterializationError.storageFailure
        }
    }

    private func cleanUpAfterFailure() {
        guard !retainsIncompleteJobs else { return }
        try? fileManager.removeItem(at: reservationRoot)
    }

    private func clearActiveOperation(id: UUID) {
        guard activeOperation?.id == id else { return }
        activeOperation = nil
    }

    private func cancelOperation(id: UUID) {
        guard activeOperation?.id == id else { return }
        activeOperation?.task.cancel()
    }

    private static func components(in path: String) -> [String] {
        path
            .replacingOccurrences(of: "\\", with: "/")
            .precomposedStringWithCanonicalMapping
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
    }

    private static func isSafe(file: TorrentMediaFile) -> Bool {
        let components = components(in: file.relativePath)
        return file.index >= 0
            && file.size >= 0
            && !file.isSymbolicLink
            && !file.relativePath.hasPrefix("/")
            && !components.isEmpty
            && !components.contains(".")
            && !components.contains("..")
    }
}

nonisolated enum TorrentDiscFinalizer {
    static func finalizeBluRayDirectory(
        _ sourceURL: URL,
        declaredBytes: Int64,
        cacheRoot: URL,
        jobID: UUID,
        fileManager: FileManager = .default
    ) throws -> MaterializedDisc {
        let cacheRoot = URL(
            fileURLWithPath: cacheRoot.standardizedFileURL.path,
            isDirectory: true
        )
        let sourceURL = URL(
            fileURLWithPath: sourceURL.standardizedFileURL.path,
            isDirectory: true
        )
        guard declaredBytes > 0,
              cacheRoot.isFileURL,
              sourceURL.isFileURL,
              sourceURL.path.hasPrefix(cacheRoot.path + "/")
        else {
            throw DiscMaterializationError.unsafeReservation
        }
        try rejectLinks(
            from: cacheRoot,
            through: sourceURL,
            fileManager: fileManager
        )

        let sourceValues = try sourceURL.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        guard sourceValues.isDirectory == true,
              sourceValues.isSymbolicLink != true,
              let bdmv = try child(named: "BDMV", at: sourceURL, fileManager: fileManager)
        else {
            throw DiscMaterializationError.unsafeReservation
        }
        let bdmvValues = try bdmv.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        guard bdmvValues.isDirectory == true,
              bdmvValues.isSymbolicLink != true,
              let marker = try child(
                named: "index.bdmv",
                at: bdmv,
                fileManager: fileManager
              )
        else {
            throw DiscMaterializationError.unsafeReservation
        }
        let markerValues = try marker.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard markerValues.isRegularFile == true,
              markerValues.isSymbolicLink != true
        else {
            throw DiscMaterializationError.unsafeReservation
        }

        guard let enumerator = fileManager.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
            ],
            options: []
        ) else {
            throw DiscMaterializationError.storageFailure
        }
        var fileCount = 0
        var actualBytes: Int64 = 0
        for case let itemURL as URL in enumerator {
            let values = try itemURL.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
            ])
            guard values.isSymbolicLink != true,
                  values.isDirectory == true || values.isRegularFile == true
            else {
                throw DiscMaterializationError.unsafeReservation
            }
            guard values.isRegularFile == true else { continue }
            fileCount += 1
            guard fileCount <= DiscDetectionPolicy.maximumMetadataFiles,
                  let size = values.fileSize,
                  size >= 0
            else {
                throw DiscMaterializationError.unsafeReservation
            }
            let (sum, overflow) = actualBytes.addingReportingOverflow(Int64(size))
            guard !overflow, sum <= declaredBytes else {
                throw DiscMaterializationError.byteCountMismatch
            }
            actualBytes = sum
        }
        guard actualBytes == declaredBytes else {
            throw DiscMaterializationError.byteCountMismatch
        }

        let manifestURL = sourceURL
            .deletingLastPathComponent()
            .appendingPathComponent("complete.plist")
        guard manifestURL.path.hasPrefix(cacheRoot.path + "/") else {
            throw DiscMaterializationError.unsafeReservation
        }
        if fileManager.fileExists(atPath: manifestURL.path) {
            let values = try manifestURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
            ])
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let size = values.fileSize,
                  (1...4_096).contains(size),
                  let data = try? Data(contentsOf: manifestURL, options: [.mappedIfSafe]),
                  let manifest = try? PropertyListDecoder().decode(
                    DiscMaterializationManifest.self,
                    from: data
                  ),
                  manifest.version == 1,
                  manifest.kind == "bluRayDirectory",
                  manifest.bytes == actualBytes
            else {
                throw DiscMaterializationError.unsafeReservation
            }
            return MaterializedDisc(
                jobID: manifest.jobID,
                rootURL: sourceURL,
                kindHint: .bluRayDirectory,
                bytes: actualBytes
            )
        }
        let manifest = DiscMaterializationManifest(
            version: 1,
            jobID: jobID,
            kind: "bluRayDirectory",
            bytes: actualBytes,
            completedAt: Date()
        )
        do {
            let data = try PropertyListEncoder().encode(manifest)
            guard data.count <= 4_096 else {
                throw DiscMaterializationError.storageFailure
            }
            try data.write(to: manifestURL, options: [.atomic])
        } catch let error as DiscMaterializationError {
            throw error
        } catch {
            throw DiscMaterializationError.storageFailure
        }
        return MaterializedDisc(
            jobID: jobID,
            rootURL: sourceURL,
            kindHint: .bluRayDirectory,
            bytes: actualBytes
        )
    }

    private static func child(
        named name: String,
        at directory: URL,
        fileManager: FileManager
    ) throws -> URL? {
        let children = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        let matches = children.filter {
            $0.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame
        }
        guard matches.count <= 1 else {
            throw DiscMaterializationError.unsafeReservation
        }
        return matches.first
    }

    private static func rejectLinks(
        from root: URL,
        through target: URL,
        fileManager: FileManager
    ) throws {
        var cursor = root
        let components = target.path
            .dropFirst(root.path.count)
            .split(separator: "/")
            .map(String.init)
        for component in components {
            cursor.appendPathComponent(component)
            let values = try cursor.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw DiscMaterializationError.unsafeReservation
            }
        }
    }
}
