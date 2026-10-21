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
    let logo: String?
    let behaviorHints: AddonBehaviorHints?

    private enum CodingKeys: String, CodingKey {
        case id, version, name, description, resources, types, catalogs, addonCatalogs, idPrefixes, logo, behaviorHints
    }

    var supportsCatalogs: Bool { resources.contains { $0.name == "catalog" } }
    var supportsStreams: Bool { resources.contains { $0.name == "stream" } }
    var supportsMeta: Bool { resources.contains { $0.name == "meta" } }
    var supportsSubtitles: Bool { resources.contains { $0.name == "subtitles" } }
    var supportsAddonCatalogs: Bool { resources.contains { $0.name == "addon_catalog" } }

    /// Add-on manifests are untrusted. A malformed or insecure optional logo
    /// must not prevent the add-on from working or trigger a cleartext load.
    var presentationLogoURL: URL? {
        guard let logo,
              let url = URL(string: logo),
              url.scheme?.lowercased() == "https",
              url.host != nil,
              url.user == nil,
              url.password == nil else {
            return nil
        }
        return url
    }

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
            guard !string.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "A resource needs a name.")
            }
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

    private enum CodingKeys: String, CodingKey {
        case name, types, idPrefixes
    }

    init(name: String, types: [String]?, idPrefixes: [String]?) {
        self.name = name
        self.types = types
        self.idPrefixes = idPrefixes
    }

    /// Empty `types` or `idPrefixes` fall back to the manifest's own lists,
    /// as in Stremio and Nuvio.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        types = container.manifestStrings(forKey: .types).flatMap { $0.isEmpty ? nil : $0 }
        idPrefixes = container.manifestStrings(forKey: .idPrefixes).flatMap { $0.isEmpty ? nil : $0 }
    }
}

nonisolated struct AddonCatalog: Codable, Hashable, Sendable, Identifiable {
    let type: String
    let id: String
    let name: String?
    let extra: [AddonCatalogExtra]?
    /// AIOMetadata and Xperience mark catalogs that should stay off Home.
    var showInHome: Bool? = nil

    private enum CodingKeys: String, CodingKey {
        case type, id, name, extra, showInHome
    }

    /// Stremio's older manifest format lists extras as plain names.
    private enum LegacyCodingKeys: String, CodingKey {
        case extraSupported, extraRequired
    }

    init(type: String, id: String, name: String?, extra: [AddonCatalogExtra]?, showInHome: Bool? = nil) {
        self.type = type
        self.id = id
        self.name = name
        self.extra = extra
        self.showInHome = showInHome
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let type = container.manifestString(forKey: .type), !type.isEmpty,
              let id = container.manifestString(forKey: .id), !id.isEmpty
        else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "A catalog needs a type and an id.")
        }
        self.type = type
        self.id = id
        name = container.manifestString(forKey: .name)
        showInHome = container.manifestBool(forKey: .showInHome)

        var extras = container.manifestArray(AddonCatalogExtra.self, forKey: .extra) ?? []
        let legacy = try? decoder.container(keyedBy: LegacyCodingKeys.self)
        let required = Set(legacy?.manifestStrings(forKey: .extraRequired) ?? [])
        let supported = (legacy?.manifestStrings(forKey: .extraSupported) ?? []) + Array(required)
        for name in supported where !extras.contains(where: { $0.name == name }) {
            extras.append(AddonCatalogExtra(name: name, isRequired: required.contains(name), options: nil, optionsLimit: nil))
        }
        extra = extras.isEmpty ? nil : extras
    }
}

nonisolated struct AddonCatalogExtra: Codable, Hashable, Sendable, Identifiable {
    let name: String
    let isRequired: Bool?
    let options: [String]?
    let optionsLimit: Int?

    var id: String { name }

    private enum CodingKeys: String, CodingKey {
        case name, isRequired, options, optionsLimit
    }

    init(name: String, isRequired: Bool?, options: [String]?, optionsLimit: Int?) {
        self.name = name
        self.isRequired = isRequired
        self.options = options
        self.optionsLimit = optionsLimit
    }

    /// Add-ons send `isRequired` as a Bool, "true" or 1, and genre options can
    /// include numbers such as years.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let name = container.manifestString(forKey: .name), !name.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .name, in: container, debugDescription: "An extra needs a name.")
        }
        self.name = name
        isRequired = container.manifestBool(forKey: .isRequired)
        options = container.manifestStrings(forKey: .options)
        optionsLimit = container.manifestString(forKey: .optionsLimit).flatMap { Int($0) }
    }
}

nonisolated extension AddonCatalog {
    var supportsSearch: Bool { extra?.contains { $0.name == "search" } == true }

    /// Home rows leave out catalogs with a required extra, as Stremio's
    /// board does; AIOMetadata and Xperience use that to keep catalogs off Home.
    var canLoadWithoutExtra: Bool { !(extra?.contains { $0.isRequired == true } ?? false) }

    /// Discover and Browse open these catalogs on the first option of each
    /// required extra, the way Stremio does. Only a required extra with no
    /// options, such as `search`, needs the user's input first.
    var canLoadWithDefaults: Bool { resolvingExtras([:]) != nil }

    /// Declares `skip`. Callers also page a catalog whose first answer is a
    /// full page of 100 titles, as Nuvio does.
    var supportsPagination: Bool { extra?.contains { $0.name == "skip" } == true }

    /// `extra` with each missing required value set to its first option.
    /// Nil when a required extra has neither a value nor any options.
    func resolvingExtras(_ extra: [String: String]) -> [String: String]? {
        var resolved = extra
        for item in self.extra ?? [] where item.isRequired == true && resolved[item.name]?.isEmpty != false {
            guard let first = item.options?.first(where: { !$0.isEmpty }) else { return nil }
            resolved[item.name] = first
        }
        return resolved
    }
}

nonisolated extension StremioAddonManifest {
    /// Real manifests vary a lot. Only `id` and `name` are required; anything
    /// malformed or unknown (for example AIOMetadata's `watch_state` resource
    /// or a catalog without an id) is skipped instead of failing the install.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = container.manifestString(forKey: .id), !id.isEmpty,
              let name = container.manifestString(forKey: .name), !name.isEmpty
        else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "A manifest needs an id and a name.")
        }
        self.init(
            id: id,
            version: container.manifestString(forKey: .version) ?? "",
            name: name,
            description: container.manifestString(forKey: .description) ?? "",
            resources: container.manifestArray(AddonResource.self, forKey: .resources) ?? [],
            types: container.manifestStrings(forKey: .types) ?? [],
            catalogs: container.manifestArray(AddonCatalog.self, forKey: .catalogs) ?? [],
            addonCatalogs: container.manifestArray(AddonCatalog.self, forKey: .addonCatalogs),
            idPrefixes: container.manifestStrings(forKey: .idPrefixes),
            logo: container.manifestString(forKey: .logo),
            behaviorHints: try? container.decodeIfPresent(AddonBehaviorHints.self, forKey: .behaviorHints)
        )
    }
}

/// Turns whatever someone pastes (a `stremio://` link, an add-on's Configure
/// page, a URL without `/manifest.json`) into the manifest address, the same
/// way Nuvio does. The path keeps its case because many add-ons put a
/// private configuration token there.
nonisolated enum AddonManifestAddress {
    static func manifestURL(from input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let range = text.range(of: "stremio://", options: [.caseInsensitive, .anchored]) {
            text.replaceSubrange(range, with: "https://")
        } else if text.range(of: "://") == nil {
            text = "https://" + text
        }
        if let fragment = text.firstIndex(of: "#") {
            text = String(text[..<fragment])
        }

        // Encode characters URL(string:) refuses, such as `|` and spaces in
        // configuration segments, without touching existing escapes.
        let unsafe = CharacterSet(charactersIn: " \"<>\\^`{|}")
        text = text.unicodeScalars.map { unsafe.contains($0) ? String(format: "%%%02X", $0.value) : String($0) }.joined()

        guard var components = URLComponents(string: text),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil
        else { return nil }

        var path = components.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        if path.lowercased().hasSuffix("/configure") {
            path.removeLast("/configure".count)
        }
        if !path.lowercased().hasSuffix("/manifest.json") {
            path += "/manifest.json"
        }
        components.percentEncodedPath = path
        components.fragment = nil
        return components.url
    }
}

extension KeyedDecodingContainer {
    /// A string, number or Bool as text; anything else is nil.
    nonisolated func manifestString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return String(value) }
        return nil
    }

    nonisolated func manifestBool(forKey key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value != 0 }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            switch value.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        }
        return nil
    }

    /// Text elements of an array, skipping anything that isn't text or a
    /// number. nil when the key is missing or isn't an array.
    nonisolated func manifestStrings(forKey key: Key) -> [String]? {
        guard let values = try? decodeIfPresent([ManifestLossyText].self, forKey: key) else { return nil }
        return values.compactMap(\.value)
    }

    /// Elements that decode, skipping the ones that don't.
    nonisolated func manifestArray<Element: Decodable>(_ type: Element.Type, forKey key: Key) -> [Element]? {
        guard let values = try? decodeIfPresent([ManifestLossyElement<Element>].self, forKey: key) else { return nil }
        return values.compactMap(\.value)
    }
}

private nonisolated struct ManifestLossyText: Decodable {
    let value: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let number = try? container.decode(Int.self) {
            value = String(number)
        } else if let number = try? container.decode(Double.self) {
            value = String(number)
        } else {
            value = nil
        }
    }
}

private nonisolated struct ManifestLossyElement<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
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
    private(set) var customName: String?
    /// Identifies this install. It is the manifest id, so titles saved in the
    /// library keep their ids, except for a second configuration of an
    /// add-on already installed from another address, which gets a suffix
    /// so the two can live side by side, as in Stremio and Nuvio.
    let installID: String

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
        case customName
        case installID
    }

    init(
        manifest: StremioAddonManifest,
        manifestURL: URL,
        isEnabled: Bool,
        addedAt: Date,
        customName: String? = nil,
        installID: String? = nil
    ) {
        self.manifest = manifest
        self.manifestURL = manifestURL
        self.isEnabled = isEnabled
        self.addedAt = addedAt
        self.customName = Self.normalizedName(customName)
        let installID = installID ?? manifest.id
        self.installID = installID
        manifestURLKeychainAccount = Self.keychainAccount(for: installID)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        manifest = try container.decode(StremioAddonManifest.self, forKey: .manifest)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        addedAt = try container.decode(Date.self, forKey: .addedAt)
        customName = Self.normalizedName(
            try container.decodeIfPresent(String.self, forKey: .customName)
        )
        installID = try container.decodeIfPresent(String.self, forKey: .installID) ?? manifest.id
        manifestURLKeychainAccount = try container.decodeIfPresent(String.self, forKey: .manifestURLKeychainAccount)
            ?? Self.keychainAccount(for: installID)

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
        try container.encodeIfPresent(customName, forKey: .customName)
        try container.encode(installID, forKey: .installID)
    }

    var displayName: String { customName ?? manifest.name }

    mutating func rename(to name: String) {
        customName = Self.normalizedName(name)
    }

    nonisolated func removeSecureManifestURL() {
        try? KeychainStore.delete(account: manifestURLKeychainAccount)
    }

    private static func keychainAccount(for addonID: String) -> String {
        "addon.manifest-url.\(addonID)"
    }

    private static func normalizedName(_ name: String?) -> String? {
        guard let value = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    var id: String { installID }

    /// The install id for another configuration of `manifest.id` at
    /// `manifestURL`: a short, stable suffix derived from the address.
    static func secondaryInstallID(manifestID: String, manifestURL: URL) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in manifestURL.absoluteString.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return "\(manifestID)~\(String(hash, radix: 36).prefix(6))"
    }

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
            logo: nil,
            behaviorHints: nil
        ),
        manifestURL: URL(string: "https://example.invalid/manifest.json")!,
        isEnabled: true,
        addedAt: .now
    )
}
