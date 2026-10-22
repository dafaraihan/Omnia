//
//  ProviderCredentialStore.swift
//  Omnia
//

import Foundation

/// Credentials that belong to one Omnia user rather than to the app. Values
/// stay in Keychain on device and are backed up only through the account vault.
enum UserManagedProviderCredential: String, CaseIterable, Identifiable, Sendable {
    case mdblist
    case anilist

    var id: String { rawValue }

    var providerName: String {
        switch self {
        case .mdblist: "MDBList"
        case .anilist: "AniList"
        }
    }

    var entryTitle: String {
        switch self {
        case .mdblist: "MDBList API Key"
        case .anilist: "AniList Access Token"
        }
    }

    var keychainAccount: String { "provider.\(rawValue).credential" }

    var guidance: String {
        switch self {
        case .mdblist:
            "MDBList uses a personal API key for ratings and curated lists."
        case .anilist:
            "AniList public anime metadata does not need a token. Add one only to connect your AniList account and lists."
        }
    }
}

enum ProviderCredentialStore {
    static func value(for credential: UserManagedProviderCredential) throws -> String? {
        try KeychainStore.value(account: credential.keychainAccount)
    }

    static func save(_ value: String, for credential: UserManagedProviderCredential) throws {
        try KeychainStore.save(value, account: credential.keychainAccount)
        NotificationCenter.default.post(name: .credentialVaultDidChange, object: nil)
    }

    static func delete(_ credential: UserManagedProviderCredential) throws {
        try KeychainStore.delete(account: credential.keychainAccount)
        NotificationCenter.default.post(name: .credentialVaultDidChange, object: nil)
    }

    static func isConfigured(_ credential: UserManagedProviderCredential) -> Bool {
        guard let value = try? value(for: credential) else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
