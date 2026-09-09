import SwiftUI

struct CatalogsSettingsView: View {
    @Environment(OmniaStore.self) private var store
    @AppStorage(HomeShelfPreferences.storageKey) private var disabledHomeShelfIDs = ""

    private var catalogAddons: [InstalledAddon] {
        store.installedAddons.filter { !$0.manifest.catalogs.isEmpty }
    }

    var body: some View {
        OmniaSettingsForm {
            Section {
                ForEach(BuiltInHomeShelf.allCases) { shelf in
                    Toggle(isOn: homeShelfBinding(for: shelf)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shelf.title)
                            Text("TMDB \(shelf.kind.rawValue.lowercased()) shelf")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel(shelf.title)
                    .accessibilityHint("Show or hide this TMDB shelf in Home and Discover")
                }
            } header: {
                Text("Built-in Discovery Shelves")
            } footer: {
                Text("Choose which built-in TMDB rows appear on Home and Discover. Changes apply immediately.")
            }

            if catalogAddons.isEmpty {
                Section("Add-on Catalogs") {
                    ContentUnavailableView(
                        "No Add-on Catalogs",
                        systemImage: "rectangle.stack.badge.plus",
                        description: Text("Catalogs declared by installed add-ons appear here for individual control.")
                    )
                }
            } else {
                ForEach(catalogAddons) { addon in
                    Section {
                        ForEach(addon.manifest.catalogs) { catalog in
                            Toggle(
                                isOn: Binding(
                                    get: { store.isCatalogEnabled(for: addon, catalog: catalog) },
                                    set: { _ in store.toggleCatalog(for: addon, catalog: catalog) }
                                )
                            ) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(catalog.name ?? catalog.id)
                                    Text("\(catalog.type.capitalized) catalog")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .disabled(!addon.isEnabled)
                        }
                    } header: {
                        Text(addon.manifest.name)
                    } footer: {
                        if !addon.isEnabled {
                            Text("Enable this add-on before its catalogs can appear in Discover.")
                        }
                    }
                }
            }
        }
        .omniaNavigationTitle("Catalogs")
    }

    private func homeShelfBinding(for shelf: BuiltInHomeShelf) -> Binding<Bool> {
        Binding(
            get: { HomeShelfPreferences(rawValue: disabledHomeShelfIDs).isEnabled(shelf) },
            set: { isEnabled in
                var preferences = HomeShelfPreferences(rawValue: disabledHomeShelfIDs)
                preferences.setEnabled(isEnabled, for: shelf)
                disabledHomeShelfIDs = preferences.rawValue
            }
        )
    }
}
