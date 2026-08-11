//
//  MetadataProvider.swift
//  Omnia
//

import Foundation

enum CredentialStrategy: String, Sendable {
    case backendManaged = "Protected by Omnia backend"
    case userManaged = "Your API key"
}

struct MetadataProvider: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let summary: String
    let credentialStrategy: CredentialStrategy

    static let supported: [MetadataProvider] = [
        .init(id: "tmdb", name: "TMDB", summary: "Titles, people, artwork, and discovery.", credentialStrategy: .backendManaged),
        .init(id: "tvdb", name: "TVDB", summary: "Series, seasons, episode ordering, and artwork.", credentialStrategy: .backendManaged),
        .init(id: "mdblist", name: "MDBList", summary: "Ratings aggregation and curated lists.", credentialStrategy: .userManaged),
        .init(id: "anilist", name: "AniList", summary: "Anime metadata and lists.", credentialStrategy: .userManaged)
    ]
}
