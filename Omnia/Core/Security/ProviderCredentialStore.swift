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
    case tmdb
    case tvdb
    case fanart

    var id: String { rawValue }

    var providerName: String {
        switch self {
        case .mdblist: "MDBList"
        case .anilist: "AniList"
        case .tmdb: "TMDB"
        case .tvdb: "TVDB"
        case .fanart: "fanart.tv"
        }
    }

    var entryTitle: String {
        switch self {
        case .mdblist: "MDBList API Key"
        case .anilist: "AniList Access Token"
        case .tmdb: "TMDB API Read Access Token or API Key"
        case .tvdb: "TVDB API Key"
        case .fanart: "fanart.tv Personal API Key"
        }
    }

    var keychainAccount: String { "provider.\(rawValue).credential" }

    var guidance: String {
        switch self {
        case .mdblist:
            "MDBList uses a personal API key for ratings and curated lists."
        case .anilist:
            "AniList public anime metadata does not need a token. Add one only to connect your AniList account and lists."
        case .tmdb:
            "Omnia uses your own TMDB key for catalogs, search, details, trailers and cast. Create one free at themoviedb.org › Settings › API; the API Read Access Token or the API Key both work."
        case .tvdb:
            "Omnia uses your own TVDB key for series, seasons and episode order. Create one at thetvdb.com › Dashboard › API Keys. For a user-supported key, add your subscriber PIN after a space."
        case .fanart:
            "On iPhone, Omnia uses fanart.tv for textless posters TMDB doesn't have. Get a free personal API key at fanart.tv › your profile › API Key."
        }
    }
}

extension Notification.Name {
    static let providerCredentialDidChange = Notification.Name("omnia.provider-credential-did-change")
}

enum ProviderCredentialStore {
    static func value(for credential: UserManagedProviderCredential) throws -> String? {
        try KeychainStore.value(account: credential.keychainAccount)
    }

    static func save(_ value: String, for credential: UserManagedProviderCredential) throws {
        try KeychainStore.save(value, account: credential.keychainAccount)
        NotificationCenter.default.post(name: .credentialVaultDidChange, object: nil)
        NotificationCenter.default.post(name: .providerCredentialDidChange, object: credential.rawValue)
    }

    static func delete(_ credential: UserManagedProviderCredential) throws {
        try KeychainStore.delete(account: credential.keychainAccount)
        NotificationCenter.default.post(name: .credentialVaultDidChange, object: nil)
        NotificationCenter.default.post(name: .providerCredentialDidChange, object: credential.rawValue)
    }

    static func isConfigured(_ credential: UserManagedProviderCredential) -> Bool {
        guard let value = try? value(for: credential) else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
