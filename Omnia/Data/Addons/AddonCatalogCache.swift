//
//  AddonCatalogCache.swift
//  Omnia
//

import CryptoKit
import Foundation
import Synchronization

/// The last answer from each add-on catalog, kept in memory and in Caches,
/// so Home and collection folders draw at once and refresh behind the
/// scenes. Files are named by a hash and hold only the public listing,
/// never the add-on's address, which can carry a personal token.
nonisolated enum AddonCatalogCache {
    /// Older copies are ignored rather than shown.
    static let maximumAge: TimeInterval = 14 * 24 * 60 * 60

    private struct Entry: Codable {
        var savedAt: Date
        var previews: [AddonMetaPreview]
    }

    private static let memory = Mutex<[String: [AddonMetaPreview]]>([:])

    private static let directory: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let directory = caches.appendingPathComponent("AddonCatalogs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    static func key(addon: InstalledAddon, catalog: AddonCatalog, extra: [String: String] = [:]) -> String {
        let extras = extra.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        let identity = [addon.manifestURL.absoluteString, catalog.type, catalog.id, extras].joined(separator: "|")
        return SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Answers from memory first, then from disk.
    @concurrent
    static func previews(for keys: [String]) async -> [String: [AddonMetaPreview]] {
        var found = memory.withLock { cached in
            keys.reduce(into: [String: [AddonMetaPreview]]()) { result, key in
                result[key] = cached[key]
            }
        }
        guard let directory else { return found }
        let decoder = JSONDecoder()
        var loaded: [String: [AddonMetaPreview]] = [:]
        for key in keys where found[key] == nil {
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(key)),
                  let entry = try? decoder.decode(Entry.self, from: data),
                  Date.now.timeIntervalSince(entry.savedAt) < maximumAge,
                  !entry.previews.isEmpty
            else { continue }
            loaded[key] = entry.previews
        }
        if !loaded.isEmpty {
            memory.withLock { $0.merge(loaded) { _, new in new } }
            found.merge(loaded) { _, new in new }
        }
        return found
    }

    @concurrent
    static func save(_ previews: [AddonMetaPreview], for key: String) async {
        guard !previews.isEmpty else { return }
        memory.withLock { $0[key] = previews }
        guard let directory,
              let data = try? JSONEncoder().encode(Entry(savedAt: .now, previews: previews))
        else { return }
        try? data.write(to: directory.appendingPathComponent(key), options: .atomic)
    }
}
