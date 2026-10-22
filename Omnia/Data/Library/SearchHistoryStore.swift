//
//  SearchHistoryStore.swift
//  Omnia
//

import Foundation
import Observation

/// Nuvio's Recent Searches: the last ten searches that found something,
/// newest first, saved on this device. Shown while the search field is
/// empty. The switch is Settings › Content & Discovery › Recent Searches.
@Observable
final class SearchHistoryStore {
    static let shared = SearchHistoryStore()

    private static let searchesKey = "search-history-recent"
    private static let enabledKey = "search-history-enabled"
    private static let limit = 10

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    private var stored: [String]

    /// What the search page shows; empty while the feature is off.
    var recentSearches: [String] {
        isEnabled ? stored : []
    }

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        let saved = UserDefaults.standard.stringArray(forKey: Self.searchesKey) ?? []
        var seen = Set<String>()
        stored = saved
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 && seen.insert($0).inserted }
            .prefix(Self.limit)
            .map { $0 }
    }

    /// Records a search that returned results, as Nuvio does.
    func record(_ query: String) {
        guard isEnabled else { return }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { return }
        let updated = Array(([text] + stored.filter { $0 != text }).prefix(Self.limit))
        guard updated != stored else { return }
        stored = updated
        persist()
    }

    func remove(_ query: String) {
        let updated = stored.filter { $0 != query }
        guard updated != stored else { return }
        stored = updated
        persist()
    }

    func clear() {
        guard !stored.isEmpty else { return }
        stored = []
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(stored, forKey: Self.searchesKey)
    }
}
