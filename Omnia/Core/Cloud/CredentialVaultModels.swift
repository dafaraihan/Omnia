import Foundation

extension Notification.Name {
    nonisolated static let credentialVaultDidChange = Notification.Name("Omnia.CredentialVaultDidChange")
}

nonisolated struct CredentialVaultEntry: Codable, Sendable {
    let id: String
    let revision: Int
    let deleted: Bool
    let payload: String?
}

nonisolated struct CredentialVaultAttachment: Codable, Sendable {
    let version: Int
    let uploadID: String
    let generation: String
    let byteCount: Int
    let sha256: String
    let chunkSize: Int
    let chunkCount: Int
}

nonisolated enum CredentialVaultError: Error, LocalizedError {
    case unavailable
    case invalidData
    case signedOut
    case persistence
    case conflict(CredentialVaultEntry)

    var errorDescription: String? {
        switch self {
        case .unavailable: "Credential sync is unavailable. Your local changes are saved for retry."
        case .invalidData: "Saved credentials could not be validated. Your existing data was kept."
        case .signedOut: "Sign in again to restore your saved credentials."
        case .persistence: "Credentials could not be saved securely on this device. Retry after unlocking Keychain."
        case .conflict: "These credentials changed on another device. Choose which copy to keep."
        }
    }
}
