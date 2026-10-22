import SwiftUI

/// Layout › Home Layout › Catalogs. Add-on catalogs and collections that can be Home rows are
/// listed in Home order: drag to reorder, switch on or off, rename. Pinned
/// collections stay at the top. Catalogs that only work in Discover (search,
/// or a required filter) and Omnia's built-in shelves follow below.
struct CatalogsSettingsView: View {
    /// Home Layout shows these rows inline, folded away until opened.
    var isEmbedded = false

    @Environment(OmniaStore.self) private var store
    @Environment(HomeLayoutStore.self) private var homeLayout
    @Environment(CollectionsStore.self) private var collections
    @AppStorage(HomeShelfPreferences.storageKey) private var disabledHomeShelfIDs = ""

    @State private var renamingCatalog: AddonHomeCatalog?
    @State private var renameDraft = ""
    @State private var showsResetConfirmation = false
    @State private var dropTargetKey: String?
    @State private var isExpanded = false
    @State private var servers = MediaServerStore.shared

    private var homeCatalogs: [AddonHomeCatalog] {
        homeLayout.ordered(AddonCatalogStore.catalogs(in: store))
    }

    /// Home rows in Home order, pinned collections first.
    private var homeEntries: [HomeRowEntry] {
        homeLayout.entries(catalogs: homeCatalogs, collections: collections.collections, servers: servers.homeRows)
    }

    /// The keys drag and drop and the Move commands reorder. Pinned
    /// collections aren't among them.
    private var movableKeys: [String] {
        homeEntries.filter { !$0.isPinned }.map(\.id)
    }

    private var catalogAddons: [InstalledAddon] {
        store.installedAddons.filter { !$0.manifest.catalogs.isEmpty }
    }

    /// Catalogs of each add-on that aren't Home rows: those needing a search
    /// or filter, types Omnia can't open, and every catalog of a disabled add-on.
    private func discoverOnlyCatalogs(of addon: InstalledAddon) -> [AddonCatalog] {
        let homeKeys = Set(homeCatalogs.map(\.key))
        return addon.manifest.catalogs.filter { !homeKeys.contains(store.catalogID(for: addon, catalog: $0)) }
    }

    var body: some View {
        if isEmbedded {
            withDialogs(
                Group {
                    foldedRowsSection
                    if isExpanded {
                        otherSections
                    }
                }
            )
        } else {
            withDialogs(
                OmniaSettingsForm {
                    if !homeCatalogs.isEmpty || !servers.homeRows.isEmpty {
                        homeRowsSection
                    }
                    otherSections
                }
                .omniaNavigationTitle("Catalogs")
            )
        }
    }

    /// Catalogs that aren't Home rows, and the built-in shelves.
    @ViewBuilder
    private var otherSections: some View {
        if catalogAddons.isEmpty {
            Section("Add-on Catalogs") {
                ContentUnavailableView(
                    "No Add-on Catalogs",
                    systemImage: "rectangle.stack.badge.plus",
                    description: Text("Catalogs declared by installed add-ons appear here for individual control.")
                )
            }
        }

        ForEach(catalogAddons) { addon in
            let catalogs = discoverOnlyCatalogs(of: addon)
            if !catalogs.isEmpty {
                Section {
                    ForEach(catalogs) { catalog in
                        Toggle(isOn: discoverBinding(addon: addon, catalog: catalog)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(catalog.name ?? catalog.id)
                                Text(discoverDetail(for: catalog))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(!addon.isEnabled)
                    }
                } header: {
                    Text(homeCatalogs.isEmpty ? addon.displayName : "\(addon.displayName) in Discover")
                } footer: {
                    if !addon.isEnabled {
                        Text("Enable this add-on before its catalogs can appear on Home and in Discover.")
                    }
                }
            }
        }

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
                .accessibilityHint("Show or hide this TMDB shelf")
            }
        } header: {
            Text("Built-in Discovery Shelves")
        } footer: {
            if homeCatalogs.isEmpty {
                Text("Choose which built-in TMDB rows appear on Home and Discover. Changes apply immediately.")
            } else {
                Text("These rows appear in Discover. Home uses your add-on catalogs while any are installed.")
            }
        }
    }

    /// Home Layout's Catalogs: one row that opens to the Home rows.
    private var foldedRowsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(homeEntries) { entry in
                    switch entry {
                    case let .catalog(catalog):
                        homeRow(catalog)
                    case let .collection(collection):
                        collectionRow(collection)
                    case let .server(row):
                        serverRow(row)
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(homeCatalogs.isEmpty ? "Built-in Rows" : "Home Rows")
                    Text(homeCatalogs.isEmpty ? "Omnia's TMDB shelves" : homeRowsSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            HStack {
                Text("Catalogs")
                Spacer()
                if !homeCatalogs.isEmpty {
                    Button("Reset to Default") { showsResetConfirmation = true }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
        } footer: {
            if homeCatalogs.isEmpty {
                Text("Home shows Omnia's built-in rows. Install an add-on that provides catalogs, such as Xperience or AIOMetadata, and its catalogs replace them.")
            } else if isExpanded {
                Text("Drag a row to change its place on Home.")
            }
        }
    }

    /// The rename alert and the reset confirmation, on either layout.
    private func withDialogs<V: View>(_ view: V) -> some View {
        view
            .alert("Rename Catalog", isPresented: isRenaming) {
                TextField("Name", text: $renameDraft)
                Button("Save") {
                    if let renamingCatalog {
                        homeLayout.rename(renamingCatalog, to: renameDraft)
                    }
                    renamingCatalog = nil
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) { renamingCatalog = nil }
            } message: {
                if let renamingCatalog {
                    Text("Leave the name empty to use “\(renamingCatalog.defaultTitle(showsCatalogType: homeLayout.preferences.showsCatalogType))”.")
                }
            }
            .confirmationDialog(
                "Reset Home Rows?",
                isPresented: $showsResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset to Default", role: .destructive) {
                    homeLayout.reset()
                    store.enableAllCatalogs()
                    collections.showAll()
                }
            } message: {
                Text("All catalogs and collections become visible in their default order, custom names are removed and the first two catalogs feed the hero.")
            }
    }

    // MARK: Home rows

    private var homeRowsSection: some View {
        Section {
            ForEach(homeEntries) { entry in
                switch entry {
                case let .catalog(catalog):
                    homeRow(catalog)
                case let .collection(collection):
                    collectionRow(collection)
                case let .server(row):
                    serverRow(row)
                }
            }
        } header: {
            HStack {
                Text("Home Rows")
                Spacer()
                Button("Reset to Default") { showsResetConfirmation = true }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        } footer: {
            Text(homeRowsFooter)
        }
    }

    private var homeRowsSummary: String {
        "\(homeCatalogs.filter(isVisible).count) of \(homeCatalogs.count) visible"
    }

    private var homeRowsFooter: String {
        let catalogsVisible = homeCatalogs.filter(isVisible).count
        var text = "\(catalogsVisible) of \(homeCatalogs.count) catalogs visible"
        let all = collections.collections
        if !all.isEmpty {
            text += ", \(all.filter { collections.isVisible($0) }.count) of \(all.count) collections"
        }
        return text + ". Drag a row to change its place on Home."
    }

    private func homeRow(_ catalog: AddonHomeCatalog) -> some View {
        let visible = isVisible(catalog)
        let title = homeLayout.title(for: catalog)

        return reorderableRow(key: catalog.key, title: title) {
            Toggle(isOn: visibilityBinding(for: catalog)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(visible ? .primary : .secondary)
                    Text("\(catalog.addon.displayName) • \(catalog.typeLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(TrailingSwitchToggleStyle())
        } extraMenuItems: {
            Button("Rename…", systemImage: "pencil") { beginRename(catalog) }
            Divider()
        }
        .contextMenu {
            Button("Rename…", systemImage: "pencil") { beginRename(catalog) }
        }
    }

    /// A media server library or Continue Watching row.
    private func serverRow(_ row: MediaServerHomeRow) -> some View {
        let visible = homeLayout.isVisible(row)
        return reorderableRow(key: row.key, title: row.title) {
            Toggle(isOn: Binding(
                get: { homeLayout.isVisible(row) },
                set: { homeLayout.setVisible($0, for: row) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .foregroundStyle(visible ? .primary : .secondary)
                    Text(row.library.map { "\(row.serverName) • \($0.kind.label)" } ?? "\(row.serverName) • Continue Watching")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(TrailingSwitchToggleStyle())
        } extraMenuItems: {
            EmptyView()
        }
    }

    @ViewBuilder
    private func collectionRow(_ collection: HomeCollection) -> some View {
        let visible = collections.isVisible(collection)
        let toggle = Toggle(isOn: collectionBinding(for: collection)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(collection.title)
                    .foregroundStyle(visible ? .primary : .secondary)
                Text(collectionDetail(collection))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(TrailingSwitchToggleStyle())

        if collection.pinToTop {
            HStack(spacing: 10) {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                toggle
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            reorderableRow(key: collection.layoutKey, title: collection.title) {
                toggle
            } extraMenuItems: {
                EmptyView()
            }
        }
    }

    /// A Home row with a drag handle, a Move menu and drop handling. The Mac
    /// settings cards aren't a List, so reordering is done with drag and
    /// drop: dropping a row takes the target row's place.
    private func reorderableRow<Content: View, MenuItems: View>(
        key: String,
        title: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder extraMenuItems: () -> MenuItems
    ) -> some View {
        let keys = movableKeys

        return HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .frame(width: 16)
                .accessibilityHidden(true)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                extraMenuItems()
                Button("Move to Top", systemImage: "arrow.up.to.line") {
                    homeLayout.move(key, by: -keys.count, in: keys)
                }
                .disabled(keys.first == key)
                Button("Move Up", systemImage: "arrow.up") {
                    homeLayout.move(key, by: -1, in: keys)
                }
                .disabled(keys.first == key)
                Button("Move Down", systemImage: "arrow.down") {
                    homeLayout.move(key, by: 1, in: keys)
                }
                .disabled(keys.last == key)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More options for \(title)")
        }
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            if dropTargetKey == key {
                Rectangle()
                    .fill(.tint)
                    .frame(height: 2)
                    .offset(y: -9)
            }
        }
        .draggable(key) {
            Text(title)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: .rect(cornerRadius: 8))
        }
        .dropDestination(for: String.self) { droppedKeys, _ in
            guard let dragged = droppedKeys.first, keys.contains(dragged) else { return false }
            homeLayout.move(dragged, onto: key, in: keys)
            return true
        } isTargeted: { isTargeted in
            if isTargeted {
                dropTargetKey = key
            } else if dropTargetKey == key {
                dropTargetKey = nil
            }
        }
    }

    // MARK: Helpers

    private func isVisible(_ catalog: AddonHomeCatalog) -> Bool {
        store.isCatalogEnabled(for: catalog.addon, catalog: catalog.catalog)
    }

    private func collectionDetail(_ collection: HomeCollection) -> String {
        let count = collection.folders.count
        let folders = count == 1 ? "1 folder" : "\(count) folders"
        return collection.pinToTop ? "Collection • \(folders) • Pinned" : "Collection • \(folders)"
    }

    private func collectionBinding(for collection: HomeCollection) -> Binding<Bool> {
        Binding(
            get: { collections.isVisible(collection) },
            set: { collections.setVisible($0, for: collection) }
        )
    }

    private func discoverDetail(for catalog: AddonCatalog) -> String {
        let type = AddonHomeCatalog.typeLabel(for: catalog.type)
        if catalog.supportsSearch && !catalog.canLoadWithoutExtra {
            return "\(type) • Search only"
        }
        if !catalog.canLoadWithoutExtra {
            return "\(type) • Needs a filter, shown in Discover"
        }
        return "\(type) catalog"
    }

    private func beginRename(_ catalog: AddonHomeCatalog) {
        renameDraft = homeLayout.title(for: catalog)
        renamingCatalog = catalog
    }

    private var isRenaming: Binding<Bool> {
        Binding(
            get: { renamingCatalog != nil },
            set: { if !$0 { renamingCatalog = nil } }
        )
    }

    private func visibilityBinding(for catalog: AddonHomeCatalog) -> Binding<Bool> {
        Binding(
            get: { isVisible(catalog) },
            set: { isOn in
                if isOn != isVisible(catalog) {
                    store.toggleCatalog(for: catalog.addon, catalog: catalog.catalog)
                }
            }
        )
    }

    private func discoverBinding(addon: InstalledAddon, catalog: AddonCatalog) -> Binding<Bool> {
        Binding(
            get: { store.isCatalogEnabled(for: addon, catalog: catalog) },
            set: { _ in store.toggleCatalog(for: addon, catalog: catalog) }
        )
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
