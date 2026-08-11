import Foundation

struct AddonBackupDocument: Codable, Equatable, Sendable {
    struct Record: Codable, Equatable, Sendable {
        let manifestURL: URL
        let isEnabled: Bool
    }

    let version: Int
    let addons: [Record]

    static func exporting(_ addons: [InstalledAddon]) -> AddonBackupExportResult {
        var records: [Record] = []
        var excludedPrivateCount = 0

        for addon in addons {
            guard addon.isPubliclyExportable else {
                excludedPrivateCount += 1
                continue
            }
            records.append(Record(
                manifestURL: addon.manifestURL,
                isEnabled: addon.isEnabled
            ))
        }

        return AddonBackupExportResult(
            document: AddonBackupDocument(version: 1, addons: records),
            excludedPrivateCount: excludedPrivateCount
        )
    }

    static func decodeValidated(_ data: Data) throws -> AddonBackupDocument {
        guard data.count <= 1_048_576 else {
            throw AddonBackupError.documentTooLarge
        }

        let document: AddonBackupDocument
        do {
            document = try JSONDecoder().decode(AddonBackupDocument.self, from: data)
        } catch {
            throw AddonBackupError.invalidDocument
        }

        guard document.version == 1 else {
            throw AddonBackupError.unsupportedVersion
        }
        guard document.addons.count <= 1_000 else {
            throw AddonBackupError.tooManyAddons
        }

        var seen = Set<String>()
        for record in document.addons {
            guard record.manifestURL.isSafePublicManifestReference else {
                throw AddonBackupError.privateManifest
            }
            guard seen.insert(record.manifestURL.absoluteString).inserted else {
                throw AddonBackupError.duplicateManifest
            }
        }
        return document
    }
}

struct AddonBackupExportResult: Equatable, Sendable {
    let document: AddonBackupDocument
    let excludedPrivateCount: Int
}

enum AddonBackupError: Error, Equatable, LocalizedError {
    case documentTooLarge
    case invalidDocument
    case unsupportedVersion
    case tooManyAddons
    case privateManifest
    case duplicateManifest

    var errorDescription: String? {
        switch self {
        case .documentTooLarge:
            "The add-on backup is too large."
        case .invalidDocument:
            "The add-on backup is not valid."
        case .unsupportedVersion:
            "This add-on backup version is not supported."
        case .tooManyAddons:
            "The add-on backup contains too many entries."
        case .privateManifest:
            "The add-on backup contains a private manifest address."
        case .duplicateManifest:
            "The add-on backup contains duplicate manifest addresses."
        }
    }
}

private extension InstalledAddon {
    var isPubliclyExportable: Bool {
        manifest.behaviorHints?.configurable != true
            && manifest.behaviorHints?.configurationRequired != true
            && manifestURL.isSafePublicManifestReference
    }
}

private extension URL {
    var isSafePublicManifestReference: Bool {
        guard scheme?.lowercased() == "https",
              host != nil,
              user == nil,
              password == nil,
              query == nil,
              fragment == nil else {
            return false
        }
        return true
    }
}
