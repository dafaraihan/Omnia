import SwiftUI

struct CatalogsSettingsView: View {
    @Environment(OmniaStore.self) private var store

    private var catalogAddons: [InstalledAddon] {
        store.installedAddons.filter { !$0.manifest.catalogs.isEmpty }
    }

    var body: some View {
        Form {
            Section("Built-in") {
                LabeledContent("TMDB + TVDB", value: "Default")
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
        .navigationTitle("Catalogs")
    }
}
