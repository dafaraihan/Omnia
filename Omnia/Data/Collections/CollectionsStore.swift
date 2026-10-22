//
//  CollectionsStore.swift
//  Omnia
//

import Foundation
import Observation

/// The collections shown on Home. They are saved as Nuvio-format JSON in
/// Application Support, so an export is the same file Nuvio reads. Which
/// collections are hidden from Home is kept separately, because that isn't
/// part of Nuvio's format.
@MainActor
@Observable
final class CollectionsStore {
    nonisolated static let hiddenIDsKey = "home-collections-hidden-v1"

    private(set) var collections: [HomeCollection] = []
    private(set) var hiddenIDs: Set<String>
    private(set) var loadError: String?
    /// Goes up on every save, so profile sync notices changes.
    private(set) var revision = 0

    private let fileURL: URL?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, fileURL: URL? = CollectionsStore.defaultFileURL) {
        self.defaults = defaults
        self.fileURL = fileURL
        hiddenIDs = Set(defaults.stringArray(forKey: Self.hiddenIDsKey) ?? [])
        load()
    }

    nonisolated static var defaultFileURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "Omnia"
        return support
            .appending(path: bundleID, directoryHint: .isDirectory)
            .appending(path: "collections.json", directoryHint: .notDirectory)
    }

    func isVisible(_ collection: HomeCollection) -> Bool {
        !hiddenIDs.contains(collection.id)
    }

    /// Adds the file's collections. A collection with the same id as an
    /// existing one replaces it, so re-importing an updated Xperience export
    /// refreshes it in place. Returns how many were imported.
    @discardableResult
    func importCollections(from data: Data) throws -> Int {
        let imported = try HomeCollectionFile.collections(from: data)
        var merged = collections
        for collection in imported {
            if let index = merged.firstIndex(where: { $0.id == collection.id }) {
                merged[index] = collection
            } else {
                merged.append(collection)
            }
        }
        collections = Array(merged.prefix(HomeCollection.maximumCollections))
        save()
        return imported.count
    }

    func exportData() throws -> Data {
        try HomeCollectionFile.data(for: collections)
    }

    func remove(_ collection: HomeCollection) {
        collections.removeAll { $0.id == collection.id }
        hiddenIDs.remove(collection.id)
        saveHiddenIDs()
        save()
    }

    func removeAll() {
        collections = []
        hiddenIDs = []
        saveHiddenIDs()
        save()
    }

    func collection(id: String) -> HomeCollection? {
        collections.first { $0.id == id }
    }

    /// Saves a collection made or changed in the editor, keeping its place.
    func save(_ collection: HomeCollection) {
        if let index = collections.firstIndex(where: { $0.id == collection.id }) {
            guard collections[index] != collection else { return }
            collections[index] = collection
        } else {
            guard collections.count < HomeCollection.maximumCollections else { return }
            collections.append(collection)
        }
        save()
    }

    /// Nuvio's up and down arrows. Pinned collections keep this order too.
    func move(_ collection: HomeCollection, by offset: Int) {
        guard let index = collections.firstIndex(where: { $0.id == collection.id }) else { return }
        let target = index + offset
        guard collections.indices.contains(target) else { return }
        collections.swapAt(index, target)
        save()
    }

    func setPinned(_ isPinned: Bool, for collection: HomeCollection) {
        guard let index = collections.firstIndex(where: { $0.id == collection.id }) else { return }
        collections[index].pinToTop = isPinned
        save()
    }

    func setVisible(_ isVisible: Bool, for collection: HomeCollection) {
        if isVisible {
            hiddenIDs.remove(collection.id)
        } else {
            hiddenIDs.insert(collection.id)
        }
        saveHiddenIDs()
    }

    func showAll() {
        hiddenIDs = []
        saveHiddenIDs()
    }

    // MARK: Profiles

    /// A profile's collections, in Nuvio's file format, and which are hidden.
    nonisolated struct ProfileSnapshot: Codable, Sendable {
        var collections: Data?
        var hiddenIDs: [String]
    }

    func profileSnapshot() -> ProfileSnapshot {
        ProfileSnapshot(
            collections: collections.isEmpty ? nil : try? HomeCollectionFile.data(for: collections),
            hiddenIDs: hiddenIDs.sorted()
        )
    }

    /// Switching profiles: another profile's collections, or none.
    func restore(_ snapshot: ProfileSnapshot?) {
        collections = snapshot?.collections.flatMap { try? HomeCollectionFile.collections(from: $0) } ?? []
        hiddenIDs = Set(snapshot?.hiddenIDs ?? [])
        saveHiddenIDs()
        save()
    }

    // MARK: Storage

    private func load() {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            collections = try HomeCollectionFile.collections(from: data)
        } catch {
            loadError = "Saved collections couldn't be read. Import your collections file again."
        }
    }

    private func save() {
        revision &+= 1
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if collections.isEmpty {
                try? FileManager.default.removeItem(at: fileURL)
            } else {
                try HomeCollectionFile.data(for: collections).write(to: fileURL, options: .atomic)
            }
            loadError = nil
        } catch {
            loadError = "Collections couldn't be saved: \(error.localizedDescription)"
        }
    }

    private func saveHiddenIDs() {
        revision &+= 1
        defaults.set(hiddenIDs.sorted(), forKey: Self.hiddenIDsKey)
    }
}
