import Foundation

nonisolated struct NativePlaybackLegalNotice: Identifiable, Hashable, Sendable {
    let name: String
    let version: String
    let licenseExpression: String
    let text: String

    var id: String { name }
}

nonisolated enum NativePlaybackLegalCatalog {
    static let maximumSBOMBytes = 2 * 1_024 * 1_024
    static let maximumNoticeBytes = 1 * 1_024 * 1_024

    enum CatalogError: LocalizedError, Equatable {
        case unavailable
        case unsafePackageName
        case duplicatePackage
        case oversizedFile
        case symbolicLink
        case missingNotice
        case malformedSBOM

        var errorDescription: String? {
            switch self {
            case .unavailable:
                "Bundled native playback notices are unavailable in this build."
            case .unsafePackageName:
                "A bundled native package has an unsafe name."
            case .duplicatePackage:
                "The native playback SBOM contains a duplicate package."
            case .oversizedFile:
                "A bundled native playback notice exceeds the allowed size."
            case .symbolicLink:
                "Bundled native playback notices cannot be symbolic links."
            case .missingNotice:
                "A bundled native playback license notice is missing."
            case .malformedSBOM:
                "The bundled native playback SBOM is malformed."
            }
        }
    }

    static func bundledRoot(in bundle: Bundle = .main) -> URL? {
        bundle.resourceURL?.appendingPathComponent(
            "NativePlayback",
            isDirectory: true
        )
    }

    static func notices(at root: URL) throws -> [NativePlaybackLegalNotice] {
        let root = root.standardizedFileURL
        let sbomURL = root.appendingPathComponent("native-playback.spdx.json")
        let sbomData = try boundedData(
            at: sbomURL,
            maximumBytes: maximumSBOMBytes,
            missingError: .unavailable
        )

        let document: SPDXDocument
        do {
            document = try JSONDecoder().decode(SPDXDocument.self, from: sbomData)
        } catch {
            throw CatalogError.malformedSBOM
        }

        var seenNames = Set<String>()
        let notices = try document.packages.map { package in
            guard package.name.range(
                of: #"^[A-Za-z0-9][A-Za-z0-9+._-]*$"#,
                options: .regularExpression
            ) != nil else {
                throw CatalogError.unsafePackageName
            }
            guard seenNames.insert(package.name).inserted else {
                throw CatalogError.duplicatePackage
            }
            guard !package.versionInfo.isEmpty,
                  !package.licenseDeclared.isEmpty,
                  package.licenseDeclared != "NOASSERTION" else {
                throw CatalogError.malformedSBOM
            }

            let licenseDirectory = root
                .appendingPathComponent("Licenses", isDirectory: true)
                .standardizedFileURL
            let noticeURL = licenseDirectory
                .appendingPathComponent("\(package.name).txt")
                .standardizedFileURL
            guard noticeURL.deletingLastPathComponent() == licenseDirectory else {
                throw CatalogError.unsafePackageName
            }

            let noticeData = try boundedData(
                at: noticeURL,
                maximumBytes: maximumNoticeBytes,
                missingError: .missingNotice
            )
            guard let text = String(data: noticeData, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CatalogError.missingNotice
            }

            return NativePlaybackLegalNotice(
                name: package.name,
                version: package.versionInfo,
                licenseExpression: package.licenseDeclared,
                text: text
            )
        }

        return notices.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func boundedData(
        at url: URL,
        maximumBytes: Int,
        missingError: CatalogError
    ) throws -> Data {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey
            ])
        } catch {
            throw missingError
        }

        guard values.isSymbolicLink != true else {
            throw CatalogError.symbolicLink
        }
        guard values.isRegularFile == true else {
            throw missingError
        }
        guard let fileSize = values.fileSize, fileSize <= maximumBytes else {
            throw CatalogError.oversizedFile
        }

        do {
            return try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw missingError
        }
    }

    private struct SPDXDocument: Decodable {
        let packages: [SPDXPackage]
    }

    private struct SPDXPackage: Decodable {
        let name: String
        let versionInfo: String
        let licenseDeclared: String
    }
}
