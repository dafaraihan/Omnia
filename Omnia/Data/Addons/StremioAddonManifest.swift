//
//  StremioAddonManifest.swift
//  Omnia
//

import Foundation

/// A compatible subset of the documented Stremio add-on manifest protocol.
/// Omnia intentionally accepts only declarative HTTP(S) manifests; it never executes add-on code.
nonisolated struct StremioAddonManifest: Codable, Hashable, Sendable {
    let id: String
    let version: String
    let name: String
    let description: String
    let resources: [AddonResource]
    let types: [String]
    let catalogs: [AddonCatalog]
    let addonCatalogs: [AddonCatalog]?
    let idPrefixes: [String]?
    let behaviorHints: AddonBehaviorHints?

    var supportsCatalogs: Bool { resources.contains { $0.name == "catalog" } }
    var supportsStreams: Bool { resources.contains { $0.name == "stream" } }
    var supportsMeta: Bool { resources.contains { $0.name == "meta" } }
    var supportsSubtitles: Bool { resources.contains { $0.name == "subtitles" } }
    var supportsAddonCatalogs: Bool { resources.contains { $0.name == "addon_catalog" } }

    /// Applies Stremio's manifest routing rules before an add-on is contacted.
    /// Catalogs are selected from their explicit declarations; the other
    /// resources additionally match content type and optional ID prefixes.
    func supports(resource name: String, type: String, identifier: String? = nil) -> Bool {
        guard name != "catalog" else { return catalogs.contains { $0.type == type } }

        // Manifests are allowed to declare the same resource more than once
        // for distinct types or identifier namespaces. Looking only at the
        // first declaration silently hides valid streams from many real-world
        // add-ons (including media and anime aggregators).
        return resources.contains { resource in
            guard resource.name == name else { return false }
            let resourceTypes = resource.types ?? types
            guard resourceTypes.contains(type) else { return false }

            guard let identifier else { return true }
            let prefixes = resource.idPrefixes ?? idPrefixes
            return prefixes?.isEmpty != false || prefixes?.contains(where: { identifier.hasPrefix($0) }) == true
        }
    }
}

nonisolated enum AddonResource: Codable, Hashable, Sendable {
    case name(String)
    case detailed(AddonResourceDetail)

    var name: String {
        switch self {
        case let .name(value): value
        case let .detailed(value): value.name
        }
    }

    var types: [String]? {
        if case let .detailed(value) = self { return value.types }
        return nil
    }

    var idPrefixes: [String]? {
        if case let .detailed(value) = self { return value.idPrefixes }
        return nil
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

nonisolated struct AddonResourceDetail: Codable, Hashable, Sendable {
    let name: String
    let types: [String]?
    let idPrefixes: [String]?
}

nonisolated struct AddonCatalog: Codable, Hashable, Sendable, Identifiable {
    let type: String
    let id: String
    let name: String?
    let extra: [AddonCatalogExtra]?
}

nonisolated struct AddonCatalogExtra: Codable, Hashable, Sendable, Identifiable {
    let name: String
    let isRequired: Bool?
    let options: [String]?
    let optionsLimit: Int?

    var id: String { name }
}

extension AddonCatalog {
    var supportsSearch: Bool { extra?.contains { $0.name == "search" } == true }

    /// Board/Discover catalog requests must not be made when the add-on marks
    /// an extra as required; the caller needs an explicit user choice first.
    var canLoadWithoutExtra: Bool { !(extra?.contains { $0.isRequired == true } ?? false) }
}

nonisolated struct AddonBehaviorHints: Codable, Hashable, Sendable {
    let configurable: Bool?
    let configurationRequired: Bool?
}

nonisolated struct InstalledAddon: Identifiable, Codable, Hashable, Sendable {
    let manifest: StremioAddonManifest
    let manifestURL: URL
    var isEnabled: Bool
    var addedAt: Date

    /// The manifest endpoint can contain an add-on's private configuration
    /// token. Persist its value in Keychain only; UserDefaults retains merely
    /// this stable Keychain account name alongside non-sensitive manifest
    /// metadata and enabled state.
    private let manifestURLKeychainAccount: String

    private enum CodingKeys: String, CodingKey {
        case manifest
        case manifestURL // legacy migration only; never written again
        case manifestURLKeychainAccount
        case isEnabled
        case addedAt
    }

    init(
        manifest: StremioAddonManifest,
        manifestURL: URL,
        isEnabled: Bool,
        addedAt: Date
    ) {
        self.manifest = manifest
        self.manifestURL = manifestURL
        self.isEnabled = isEnabled
        self.addedAt = addedAt
        manifestURLKeychainAccount = Self.keychainAccount(for: manifest.id)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        manifest = try container.decode(StremioAddonManifest.self, forKey: .manifest)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        addedAt = try container.decode(Date.self, forKey: .addedAt)
        manifestURLKeychainAccount = try container.decodeIfPresent(String.self, forKey: .manifestURLKeychainAccount)
            ?? Self.keychainAccount(for: manifest.id)

        if let storedURL = try KeychainStore.value(account: manifestURLKeychainAccount),
           let url = URL(string: storedURL) {
            manifestURL = url
            return
        }

        // One-time migration from the prior UserDefaults representation.
        // The next successful save intentionally omits this legacy key.
        if let legacyURL = try container.decodeIfPresent(URL.self, forKey: .manifestURL) {
            manifestURL = legacyURL
            try? KeychainStore.save(legacyURL.absoluteString, account: manifestURLKeychainAccount)
            return
        }

        throw DecodingError.dataCorruptedError(
            forKey: .manifestURLKeychainAccount,
            in: container,
            debugDescription: "The add-on manifest endpoint is missing from Keychain."
        )
    }

    func encode(to encoder: Encoder) throws {
        // A failed Keychain write must not produce an ordinary persisted copy
        // that could later erase the only usable endpoint from storage.
        try KeychainStore.save(manifestURL.absoluteString, account: manifestURLKeychainAccount)

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(manifest, forKey: .manifest)
        try container.encode(manifestURLKeychainAccount, forKey: .manifestURLKeychainAccount)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(addedAt, forKey: .addedAt)
    }

    nonisolated func removeSecureManifestURL() {
        try? KeychainStore.delete(account: manifestURLKeychainAccount)
    }

    private static func keychainAccount(for addonID: String) -> String {
        "addon.manifest-url.\(addonID)"
    }

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
            addonCatalogs: nil,
            idPrefixes: ["tt"],
            behaviorHints: nil
        ),
        manifestURL: URL(string: "https://example.invalid/manifest.json")!,
        isEnabled: true,
        addedAt: .now
    )
}
