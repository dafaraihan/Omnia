//
//  ProviderCredentialStore.swift
//  Omnia
//

import Foundation

/// Credentials that belong to one Omnia user rather than to the app. Values
/// are intentionally Keychain-only and are never included in a Supabase
/// request, app configuration, analytics event, or sync payload.
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
    }

    static func delete(_ credential: UserManagedProviderCredential) throws {
        try KeychainStore.delete(account: credential.keychainAccount)
    }

    static func isConfigured(_ credential: UserManagedProviderCredential) -> Bool {
        guard let value = try? value(for: credential) else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
