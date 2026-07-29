//
//  OmniaStore.swift
//  Omnia
//

import Observation
import SwiftUI

@Observable
@MainActor
final class OmniaStore {
    private static let addonsStorageKey = "installed-addons"
    private static let disabledCatalogsStorageKey = "disabled-addon-catalogs"
    private static let appearanceStorageKey = "app-appearance"
    private static let libraryStorageKey = "saved-library"
    private static let playbackCompletionThresholdKey = "playback-completion-threshold"

    var library: [MediaItem] {
        didSet { saveLibrary() }
    }
    var installedAddons: [InstalledAddon]
    private(set) var disabledAddonCatalogIDs: Set<String>
    var appearance: AppAppearance {
        didSet { saveAppearance() }
    }
    var accentColor: Color = .blue

    init(
        library: [MediaItem]? = nil,
        installedAddons: [InstalledAddon]? = nil,
        disabledAddonCatalogIDs: Set<String>? = nil,
        appearance: AppAppearance? = nil
    ) {
        self.library = library ?? Self.loadLibrary()
        self.installedAddons = installedAddons ?? Self.loadAddons()
        self.disabledAddonCatalogIDs = disabledAddonCatalogIDs ?? Self.loadDisabledCatalogIDs()
        self.appearance = appearance ?? Self.loadAppearance()
    }

    static let preview = OmniaStore(
        library: MediaItem.previewLibrary,
        installedAddons: [.preview]
    )

    func add(_ addon: InstalledAddon) {
        installedAddons.removeAll { $0.id == addon.id }
        installedAddons.append(addon)
        saveAddons()
    }

    func toggleAddon(id: String) {
        guard let index = installedAddons.firstIndex(where: { $0.id == id }) else { return }
        installedAddons[index].isEnabled.toggle()
        saveAddons()
    }

    func catalogID(for addon: InstalledAddon, catalog: AddonCatalog) -> String {
        "\(addon.id)::\(catalog.type)::\(catalog.id)"
    }

    func isCatalogEnabled(for addon: InstalledAddon, catalog: AddonCatalog) -> Bool {
        addon.isEnabled && !disabledAddonCatalogIDs.contains(catalogID(for: addon, catalog: catalog))
    }

    func toggleCatalog(for addon: InstalledAddon, catalog: AddonCatalog) {
        let id = catalogID(for: addon, catalog: catalog)
        if disabledAddonCatalogIDs.contains(id) {
            disabledAddonCatalogIDs.remove(id)
        } else {
            disabledAddonCatalogIDs.insert(id)
        }
        saveDisabledCatalogIDs()
    }

    var enabledAddonCatalogCount: Int {
        installedAddons.reduce(into: 0) { count, addon in
            count += addon.manifest.catalogs.filter { isCatalogEnabled(for: addon, catalog: $0) }.count
        }
    }

    func isSaved(_ item: MediaItem) -> Bool {
        library.contains { $0.id == item.id }
    }

    func toggleSaved(_ item: MediaItem) {
        if let index = library.firstIndex(where: { $0.id == item.id }) {
            library.remove(at: index)
        } else {
            library.insert(item, at: 0)
        }
    }

    /// Stores a durable local resume point. The title is added to the library
    /// when necessary so Continue Watching never depends on a remote catalog.
    func recordPlayback(for item: MediaItem, positionSeconds: Double, durationSeconds: Double?) {
        let position = max(positionSeconds, 0)
        let duration = durationSeconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let normalized = duration.map { min(max(position / $0, 0), 1) }
        let completed = normalized.map { $0 >= Self.playbackCompletionThreshold } ?? false

        var updated = item
        updated.positionSeconds = position
        updated.durationSeconds = duration
        updated.progress = completed ? nil : normalized

        if let index = library.firstIndex(where: { $0.id == item.id }) {
            library[index] = updated
        } else if !completed {
            library.insert(updated, at: 0)
        }
    }

    private static func loadAddons() -> [InstalledAddon] {
        guard let data = UserDefaults.standard.data(forKey: addonsStorageKey) else { return [] }
        return (try? JSONDecoder().decode([InstalledAddon].self, from: data)) ?? []
    }

    private static func loadDisabledCatalogIDs() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: disabledCatalogsStorageKey) else { return [] }
        return (try? JSONDecoder().decode(Set<String>.self, from: data)) ?? []
    }

    private static func loadAppearance() -> AppAppearance {
        guard let value = UserDefaults.standard.string(forKey: appearanceStorageKey) else { return .system }
        return AppAppearance(rawValue: value) ?? .system
    }

    private static func loadLibrary() -> [MediaItem] {
        guard let data = UserDefaults.standard.data(forKey: libraryStorageKey) else { return [] }
        return (try? JSONDecoder().decode([SavedMediaItem].self, from: data))?.map(\.mediaItem) ?? []
    }

    /// The point at which a title stops appearing in Continue Watching. The
    /// preference is intentionally read here, where completion is decided,
    /// rather than merely displayed in Settings.
    private static var playbackCompletionThreshold: Double {
        switch UserDefaults.standard.integer(forKey: playbackCompletionThresholdKey) {
        case 80, 90, 95:
            Double(UserDefaults.standard.integer(forKey: playbackCompletionThresholdKey)) / 100
        default:
            0.95
        }
    }

    private func saveAddons() {
        guard let data = try? JSONEncoder().encode(installedAddons) else { return }
        UserDefaults.standard.set(data, forKey: Self.addonsStorageKey)
    }

    private func saveDisabledCatalogIDs() {
        guard let data = try? JSONEncoder().encode(disabledAddonCatalogIDs) else { return }
        UserDefaults.standard.set(data, forKey: Self.disabledCatalogsStorageKey)
    }

    private func saveAppearance() {
        UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceStorageKey)
    }

    private func saveLibrary() {
        guard let data = try? JSONEncoder().encode(library.map(SavedMediaItem.init)) else { return }
        UserDefaults.standard.set(data, forKey: Self.libraryStorageKey)
    }
}
