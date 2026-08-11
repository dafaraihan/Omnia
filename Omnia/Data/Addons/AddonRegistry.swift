import Foundation
import Observation

@MainActor
@Observable
final class AddonRegistry {
    static let defaultStorageKey = "installed-addons"

    private let defaults: UserDefaults?
    private let storageKey: String

    private(set) var addons: [InstalledAddon]

    init(
        addons: [InstalledAddon],
        defaults: UserDefaults? = nil,
        storageKey: String = AddonRegistry.defaultStorageKey
    ) {
        self.addons = addons
        self.defaults = defaults
        self.storageKey = storageKey
    }

    convenience init(
        defaults: UserDefaults = .standard,
        storageKey: String = AddonRegistry.defaultStorageKey
    ) {
        let addons: [InstalledAddon]
        if let data = defaults.data(forKey: storageKey) {
            addons = (try? JSONDecoder().decode([InstalledAddon].self, from: data)) ?? []
        } else {
            addons = []
        }
        self.init(addons: addons, defaults: defaults, storageKey: storageKey)
    }

    func add(_ addon: InstalledAddon) {
        if let index = addons.firstIndex(where: { $0.id == addon.id }) {
            addons[index] = addon
        } else {
            addons.append(addon)
        }
        persist()
    }

    func toggle(id: String) {
        guard let index = addons.firstIndex(where: { $0.id == id }) else { return }
        addons[index].isEnabled.toggle()
        persist()
    }

    func remove(id: String) {
        addons.first(where: { $0.id == id })?.removeSecureManifestURL()
        addons.removeAll { $0.id == id }
        persist()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let validOffsets = source.filter { addons.indices.contains($0) }.sorted()
        guard !validOffsets.isEmpty else { return }

        let moving = validOffsets.map { addons[$0] }
        for offset in validOffsets.reversed() {
            addons.remove(at: offset)
        }
        let removedBeforeDestination = validOffsets.filter { $0 < destination }.count
        let insertion = min(max(destination - removedBeforeDestination, 0), addons.count)
        addons.insert(contentsOf: moving, at: insertion)
        persist()
    }

    private func persist() {
        guard let defaults,
              let data = try? JSONEncoder().encode(addons) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }
}
