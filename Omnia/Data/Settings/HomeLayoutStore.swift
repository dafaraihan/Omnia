//
//  HomeLayoutStore.swift
//  Omnia
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class HomeLayoutStore {
    nonisolated static let storageKey = "home-layout-v1"

    private let defaults: UserDefaults
    private(set) var preferences: HomeLayoutPreferences

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(HomeLayoutPreferences.self, from: data) {
            preferences = saved
        } else {
            preferences = HomeLayoutPreferences()
        }
    }

    func update(_ transform: (inout HomeLayoutPreferences) -> Void) {
        var updated = preferences
        transform(&updated)
        guard updated != preferences else { return }
        preferences = updated
        if let data = try? JSONEncoder().encode(updated) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    func title(for catalog: AddonHomeCatalog) -> String {
        if let custom = preferences.customTitles[catalog.key]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty {
            return custom
        }
        return catalog.defaultTitle(showsCatalogType: preferences.showsCatalogType)
    }

    func ordered(_ catalogs: [AddonHomeCatalog]) -> [AddonHomeCatalog] {
        let byKey = Dictionary(catalogs.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        return preferences.ordered(catalogs.map(\.key)).compactMap { byKey[$0] }
    }

    /// Catalogs and collections in Home order, as in Nuvio: pinned
    /// collections first, then catalogs and the other collections in the
    /// order the user set. New collections start after the catalogs.
    func entries(
        catalogs: [AddonHomeCatalog],
        collections: [HomeCollection],
        servers: [MediaServerHomeRow] = []
    ) -> [HomeRowEntry] {
        let pinned = collections.filter(\.pinToTop).map(HomeRowEntry.collection)
        let movable = catalogs.map(HomeRowEntry.catalog)
            + servers.map(HomeRowEntry.server)
            + collections.filter { !$0.pinToTop }.map(HomeRowEntry.collection)
        let byKey = Dictionary(movable.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return pinned + preferences.ordered(movable.map(\.id)).compactMap { byKey[$0] }
    }

    func rename(_ catalog: AddonHomeCatalog, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        update {
            if trimmed.isEmpty || trimmed == catalog.defaultTitle(showsCatalogType: $0.showsCatalogType) {
                $0.customTitles[catalog.key] = nil
            } else {
                $0.customTitles[catalog.key] = trimmed
            }
        }
    }

    /// Reorders within the full ordered list, so hidden catalogs keep their
    /// slots relative to the ones being moved.
    func move(_ orderedKeys: [String], fromOffsets source: IndexSet, toOffset destination: Int) {
        var keys = orderedKeys
        keys.move(fromOffsets: source, toOffset: destination)
        update { $0.order = keys }
    }

    func move(_ key: String, by offset: Int, in orderedKeys: [String]) {
        guard let index = orderedKeys.firstIndex(of: key) else { return }
        let target = min(max(index + offset, 0), orderedKeys.count - 1)
        guard target != index else { return }
        var keys = orderedKeys
        keys.remove(at: index)
        keys.insert(key, at: target)
        update { $0.order = keys }
    }

    /// Drag and drop: `key` takes `target`'s place, pushing `target` down when
    /// dragged from above and up when dragged from below.
    func move(_ key: String, onto target: String, in orderedKeys: [String]) {
        guard key != target,
              let from = orderedKeys.firstIndex(of: key),
              let to = orderedKeys.firstIndex(of: target)
        else { return }
        var keys = orderedKeys
        keys.remove(at: from)
        keys.insert(key, at: to)
        update { $0.order = keys }
    }

    /// The hero mixes its catalogs in this order.
    func setHeroSourceOrder(_ keys: [String]) {
        update {
            $0.heroSourceKeys = Array(keys.prefix(HomeLayoutPreferences.heroSourceLimit))
            $0.hasCustomHeroSources = true
        }
    }

    /// Returns false when the limit is already reached.
    @discardableResult
    func setHeroSource(_ key: String, isEnabled: Bool, current: [String]) -> Bool {
        var sources = current
        if isEnabled {
            guard !sources.contains(key) else { return true }
            guard sources.count < HomeLayoutPreferences.heroSourceLimit else { return false }
            sources.append(key)
        } else {
            sources.removeAll { $0 == key }
        }
        update {
            $0.heroSourceKeys = sources
            $0.hasCustomHeroSources = true
        }
        return true
    }

    func isVisible(_ row: MediaServerHomeRow) -> Bool {
        !preferences.hiddenServerRowKeys.contains(row.key)
    }

    func setVisible(_ visible: Bool, for row: MediaServerHomeRow) {
        update { preferences in
            preferences.hiddenServerRowKeys.removeAll { $0 == row.key }
            if !visible { preferences.hiddenServerRowKeys.append(row.key) }
        }
    }

    func reset() {
        update { $0 = HomeLayoutPreferences() }
    }

    /// Switching profiles: another profile's layout, or the default one.
    func replace(with preferences: HomeLayoutPreferences?) {
        update { $0 = preferences ?? HomeLayoutPreferences() }
    }
}
