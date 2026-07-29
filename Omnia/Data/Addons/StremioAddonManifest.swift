//
//  StremioAddonManifest.swift
//  Omnia
//

import Foundation

/// A compatible subset of the documented Stremio add-on manifest protocol.
/// Omnia intentionally accepts only declarative HTTP(S) manifests; it never executes add-on code.
struct StremioAddonManifest: Codable, Hashable, Sendable {
    let id: String
    let version: String
    let name: String
    let description: String
    let resources: [AddonResource]
    let types: [String]
    let catalogs: [AddonCatalog]
    let idPrefixes: [String]?
    let behaviorHints: AddonBehaviorHints?

    var supportsCatalogs: Bool { resources.contains { $0.name == "catalog" } }
    var supportsStreams: Bool { resources.contains { $0.name == "stream" } }
}

enum AddonResource: Codable, Hashable, Sendable {
    case name(String)
    case detailed(AddonResourceDetail)

    var name: String {
        switch self {
        case let .name(value): value
        case let .detailed(value): value.name
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .name(string)
        } else {
            self = .detailed(try container.decode(AddonResourceDetail.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .name(value): try container.encode(value)
        case let .detailed(value): try container.encode(value)
        }
    }
}

struct AddonResourceDetail: Codable, Hashable, Sendable {
    let name: String
    let types: [String]?
    let idPrefixes: [String]?
}

struct AddonCatalog: Codable, Hashable, Sendable, Identifiable {
    let type: String
    let id: String
    let name: String?
    let extra: [AddonCatalogExtra]?
}

struct AddonCatalogExtra: Codable, Hashable, Sendable {
    let name: String
    let isRequired: Bool?
    let options: [String]?
    let optionsLimit: Int?
}

struct AddonBehaviorHints: Codable, Hashable, Sendable {
    let configurable: Bool?
    let configurationRequired: Bool?
}

struct InstalledAddon: Identifiable, Codable, Hashable, Sendable {
    let manifest: StremioAddonManifest
    let manifestURL: URL
    var isEnabled: Bool
    var addedAt: Date

    var id: String { manifest.id }

    static let preview = InstalledAddon(
        manifest: .init(
            id: "org.omnia.preview",
            version: "1.0.0",
            name: "Omnia Sample Library",
            description: "Local design data for the Omnia preview.",
            resources: [.name("catalog"), .name("meta")],
            types: ["movie", "series"],
            catalogs: [.init(type: "movie", id: "recent", name: "Recently Added", extra: nil)],
            idPrefixes: ["tt"],
            behaviorHints: nil
        ),
        manifestURL: URL(string: "https://example.invalid/manifest.json")!,
        isEnabled: true,
        addedAt: .now
    )
}
