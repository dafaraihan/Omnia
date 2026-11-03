//
//  CollectionEditorView.swift
//  Omnia
//

import SwiftUI

/// Nuvio's collection editor: name, backdrop, pin, folder layout, then the
/// folders. Changes are saved as they are made; a new collection is saved
/// once it has a name.
struct CollectionEditorView: View {
    @Environment(CollectionsStore.self) private var collections

    @State private var draft: HomeCollection
    @State private var backdropText: String
    @State private var folderToRemove: HomeCollectionFolder?

    init(collection: HomeCollection?) {
        let value = collection ?? HomeCollection()
        _draft = State(initialValue: value)
        _backdropText = State(initialValue: value.backdropImageUrl?.absoluteString ?? "")
    }

    var body: some View {
        OmniaSettingsForm {
            Section {
                TextField("Name", text: $draft.title, prompt: Text("Collection name"))
                TextField("Backdrop", text: $backdropText, prompt: Text("Backdrop image URL (optional)"))
                    .collectionURLField()
                Toggle(isOn: $draft.pinToTop) {
                    Text("Pin Above Catalogs")
                    Text("Shows this collection above every catalog on Home.")
                }
            } header: {
                Text("Basics")
            } footer: {
                if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Give the collection a name to save it.")
                } else if !backdropText.isEmpty, CollectionURLInput.url(from: backdropText) == nil {
                    Text("The backdrop needs an https image link.")
                }
            }

            Section {
                SettingsDropdown(
                    "View Mode",
                    subtitle: "How a folder's catalogs are shown when you open it.",
                    selection: $draft.layout,
                    options: HomeCollection.ViewMode.allCases
                ) { $0.title }
                if draft.layout == .tabs {
                    Toggle(isOn: $draft.showAllTab) {
                        Text("Show “All” Tab")
                        Text("Combines every catalog in a folder into one tab.")
                    }
                }
            } header: {
                Text("Appearance")
            }

            Section {
                if draft.folders.isEmpty {
                    Text("No folders yet. Add one to get started.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(draft.folders.enumerated()), id: \.element.id) { index, folder in
                    folderRow(folder, at: index)
                }
                Button("Add Folder", systemImage: "plus") {
                    draft.folders.append(HomeCollectionFolder())
                }
                .disabled(draft.folders.count >= HomeCollection.maximumFolders)
            } header: {
                Text("Folders")
            } footer: {
                Text("Each folder is a tile in the collection's row on Home and opens its catalogs.")
            }

            if !draft.folders.isEmpty {
                CollectionCatalogStatusSection(folders: draft.folders)
            }
        }
        .omniaNavigationTitle(draft.title.isEmpty ? "New Collection" : draft.title)
        .onChange(of: backdropText) { _, text in
            draft.backdropImageUrl = CollectionURLInput.url(from: text)
        }
        .onChange(of: draft) { _, collection in
            save(collection)
        }
        .confirmationDialog(
            "Remove \(folderToRemove?.title ?? "Folder")?",
            isPresented: Binding(get: { folderToRemove != nil }, set: { if !$0 { folderToRemove = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove Folder", role: .destructive) {
                if let folderToRemove {
                    draft.folders.removeAll { $0.id == folderToRemove.id }
                }
                folderToRemove = nil
            }
        }
    }

    private func folderRow(_ folder: HomeCollectionFolder, at index: Int) -> some View {
        HStack(spacing: 10) {
            NavigationLink {
                CollectionFolderEditorView(folder: folderBinding(id: folder.id))
            } label: {
                HStack(spacing: 10) {
                    if let emoji = folder.coverEmoji {
                        Text(emoji)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(folder.title)
                        Text("\(folder.sources.count) \(folder.sources.count == 1 ? "catalog" : "catalogs") · \(folder.tileShape.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                draft.folders.swapAt(index, index - 1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(index == 0)
            .help("Move Up")
            .accessibilityLabel("Move \(folder.title) up")

            Button {
                draft.folders.swapAt(index, index + 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(index == draft.folders.count - 1)
            .help("Move Down")
            .accessibilityLabel("Move \(folder.title) down")

            Button(role: .destructive) {
                folderToRemove = folder
            } label: {
                Image(systemName: "trash")
            }
            .help("Remove")
            .accessibilityLabel("Remove \(folder.title)")
        }
        .buttonStyle(.borderless)
    }

    private func folderBinding(id: String) -> Binding<HomeCollectionFolder> {
        Binding(
            get: { draft.folders.first { $0.id == id } ?? HomeCollectionFolder(id: id) },
            set: { folder in
                guard let index = draft.folders.firstIndex(where: { $0.id == id }) else { return }
                draft.folders[index] = folder
            }
        )
    }

    private func save(_ collection: HomeCollection) {
        var collection = collection
        collection.title = collection.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collection.title.isEmpty else { return }
        collections.save(collection)
    }
}

/// Nuvio's folder editor: name, cover, tile shape, then the add-on catalogs
/// the folder shows.
struct CollectionFolderEditorView: View {
    @Environment(OmniaStore.self) private var store
    @Binding var folder: HomeCollectionFolder

    @State private var coverKind: CoverKind
    @State private var coverURLText: String
    @State private var emojiText: String
    @State private var gifText: String

    enum CoverKind: String, CaseIterable, Hashable {
        case none, image, emoji

        var title: String {
            switch self {
            case .none: "None"
            case .image: "Image URL"
            case .emoji: "Emoji"
            }
        }
    }

    init(folder: Binding<HomeCollectionFolder>) {
        _folder = folder
        let value = folder.wrappedValue
        _coverKind = State(initialValue: value.coverImageUrl != nil ? .image : value.coverEmoji != nil ? .emoji : .none)
        _coverURLText = State(initialValue: value.coverImageUrl?.absoluteString ?? "")
        _emojiText = State(initialValue: value.coverEmoji ?? "")
        _gifText = State(initialValue: value.focusGifUrl?.absoluteString ?? "")
    }

    var body: some View {
        OmniaSettingsForm {
            Section {
                HStack {
                    Spacer()
                    CollectionFolderTile(folder: folder)
                        .allowsHitTesting(false)
                    Spacer()
                }
                .padding(.vertical, 6)
            } header: {
                Text("Preview")
            }

            Section {
                TextField("Name", text: $folder.title, prompt: Text("Folder name"))
                Toggle(isOn: $folder.hideTitle) {
                    Text("Hide Title")
                    Text("Only shows the cover image.")
                }
            } header: {
                Text("Basics")
            }

            Section {
                SettingsDropdown(
                    "Tile Shape",
                    selection: $folder.tileShape,
                    options: HomeCollectionFolder.TileShape.allCases
                ) { $0.title }
                SettingsDropdown(
                    "Cover",
                    selection: $coverKind,
                    options: CoverKind.allCases
                ) { $0.title }
                if coverKind == .image {
                    TextField("Image", text: $coverURLText, prompt: Text("https://…"))
                        .collectionURLField()
                } else if coverKind == .emoji {
                    TextField("Emoji", text: $emojiText, prompt: Text("🎬"))
                }
                TextField("Animated Cover", text: $gifText, prompt: Text("Animated GIF URL (optional)"))
                    .collectionURLField()
                if folder.focusGifUrl != nil {
                    Toggle(isOn: $folder.focusGifEnabled) {
                        Text("Show GIF When Configured")
                        Text("Plays the GIF in place of the still cover while the pointer is on the tile.")
                    }
                }
            } header: {
                Text("Appearance")
            } footer: {
                if hasInvalidLink {
                    Text("Covers need an https image link.")
                }
            }

            Section {
                if folder.sources.isEmpty {
                    Text("No catalog sources yet. Add catalogs from your installed add-ons to define what this folder shows.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(folder.sources.enumerated()), id: \.offset) { index, source in
                    sourceRow(source, at: index)
                }
                NavigationLink {
                    CollectionCatalogPickerView(folder: $folder)
                } label: {
                    LabeledContent("Add Catalog", value: "\(folder.sources.count) selected")
                }
                .settingsLinkRow()
            } header: {
                Text("Catalog Sources")
            }
        }
        .omniaNavigationTitle(folder.title.isEmpty ? "Folder" : folder.title)
        .onChange(of: coverKind) { applyCover() }
        .onChange(of: coverURLText) { applyCover() }
        .onChange(of: emojiText) { applyCover() }
        .onChange(of: gifText) { _, text in
            folder.focusGifUrl = CollectionURLInput.url(from: text)
        }
    }

    private var hasInvalidLink: Bool {
        (coverKind == .image && !coverURLText.isEmpty && CollectionURLInput.url(from: coverURLText) == nil)
            || (!gifText.isEmpty && CollectionURLInput.url(from: gifText) == nil)
    }

    /// An image cover replaces the emoji and the other way round, as in Nuvio.
    private func applyCover() {
        switch coverKind {
        case .none:
            folder.coverImageUrl = nil
            folder.coverEmoji = nil
        case .image:
            folder.coverImageUrl = CollectionURLInput.url(from: coverURLText)
            folder.coverEmoji = nil
        case .emoji:
            folder.coverImageUrl = nil
            folder.coverEmoji = emojiText.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init)
        }
    }

    @ViewBuilder
    private func sourceRow(_ source: HomeCollectionSource, at index: Int) -> some View {
        let resolved = HomeCollectionSourceResolver.resolve(source, in: store.installedAddons)
        let name = resolved?.catalog.name.flatMap { $0.isEmpty ? nil : $0 }
            ?? HomeCollectionSourceResolver.readableName(source.catalogId)
        let detail = resolved.map { "\($0.addon.displayName) · \(CollectionCatalogPickerView.typeTitle(source.type))" }
            ?? HomeCollectionSourceResolver.unavailableReason(for: source, in: store.installedAddons)
        let genres = resolved?.catalog.extra?.first { $0.name == "genre" }

        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(role: .destructive) {
                folder.sources.remove(at: index)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove")
            .accessibilityLabel("Remove \(name)")
        }

        if let options = genres?.options, !options.isEmpty {
            let isRequired = genres?.isRequired == true
            let genreChoices: [String?] = options.map { $0 }
            let choices: [String?] = isRequired ? genreChoices : [nil] + genreChoices
            SettingsDropdown(
                "Genre Filter",
                subtitle: name,
                selection: genreBinding(at: index, fallback: isRequired ? options.first : nil),
                options: choices
            ) { $0 ?? "All genres" }
        }
    }

    private func genreBinding(at index: Int, fallback: String?) -> Binding<String?> {
        Binding(
            get: { folder.sources.indices.contains(index) ? folder.sources[index].requestedGenre ?? fallback : fallback },
            set: { genre in
                guard folder.sources.indices.contains(index) else { return }
                folder.sources[index].genre = genre
            }
        )
    }
}

/// Nuvio's "Select Catalogs": every catalog the installed add-ons offer,
/// grouped by add-on, switched on or off for the folder.
struct CollectionCatalogPickerView: View {
    @Environment(OmniaStore.self) private var store
    @Binding var folder: HomeCollectionFolder

    var body: some View {
        OmniaSettingsForm {
            if catalogAddons.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Catalogs",
                        systemImage: "square.stack",
                        description: Text("Install an add-on that provides catalogs, then come back to add them to this folder.")
                    )
                }
            }
            ForEach(catalogAddons) { addon in
                Section {
                    ForEach(Self.catalogs(of: addon), id: \.self) { catalog in
                        Toggle(isOn: selection(addon: addon, catalog: catalog)) {
                            Text(catalog.name.flatMap { $0.isEmpty ? nil : $0 } ?? HomeCollectionSourceResolver.readableName(catalog.id))
                            Text(Self.typeTitle(catalog.type))
                        }
                    }
                } header: {
                    Text(addon.displayName)
                }
            }
        }
        .omniaNavigationTitle("Select Catalogs")
    }

    static func typeTitle(_ type: String) -> String {
        switch type.lowercased() {
        case "movie": "Movies"
        case "series": "Series"
        case "anime": "Anime"
        case "tv", "channel": "Channels"
        default: type.prefix(1).uppercased() + type.dropFirst()
        }
    }

    private var catalogAddons: [InstalledAddon] {
        store.installedAddons.filter { $0.isEnabled && !Self.catalogs(of: $0).isEmpty }
    }

    /// Catalogs that need a search query, or any value besides a genre,
    /// can't fill a folder on their own.
    private static func catalogs(of addon: InstalledAddon) -> [AddonCatalog] {
        addon.manifest.catalogs.filter { catalog in
            !(catalog.extra ?? []).contains { $0.isRequired == true && $0.name != "genre" }
        }
    }

    private func selection(addon: InstalledAddon, catalog: AddonCatalog) -> Binding<Bool> {
        let addonID = addon.manifest.id
        let matches: (HomeCollectionSource) -> Bool = {
            $0.isAddonSource && $0.addonId == addonID && $0.type == catalog.type && $0.catalogId == catalog.id
        }
        return Binding(
            get: { folder.sources.contains(where: matches) },
            set: { isOn in
                if isOn {
                    guard !folder.sources.contains(where: matches),
                          folder.sources.count < HomeCollectionFolder.maximumSources
                    else { return }
                    let genre = catalog.extra?.first { $0.name == "genre" && $0.isRequired == true }?.options?.first
                    folder.sources.append(
                        HomeCollectionSource(addonId: addonID, type: catalog.type, catalogId: catalog.id, genre: genre)
                    )
                } else {
                    folder.sources.removeAll(where: matches)
                }
            }
        )
    }
}

/// Collection images are https links only, as when a file is imported.
enum CollectionURLInput {
    static func url(from text: String) -> URL? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), url.scheme?.lowercased() == "https", url.host() != nil else { return nil }
        return url
    }
}

private extension View {
    func collectionURLField() -> some View {
        self
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            #endif
    }
}

/// Which catalogs of each folder can load, and why not, moved here from the
/// Collections list to keep that list to one row per collection.
private struct CollectionCatalogStatusSection: View {
    @Environment(OmniaStore.self) private var store
    let folders: [HomeCollectionFolder]

    var body: some View {
        Section("Catalog Status") {
            ForEach(folders) { folder in
                let available = folder.sources.filter {
                    HomeCollectionSourceResolver.resolve($0, in: store.installedAddons) != nil
                }.count
                let problems = sourceProblems(for: folder)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(folder.title)
                        Spacer()
                        Text("\(available) of \(folder.sources.count) catalogs")
                            .font(.caption)
                            .foregroundStyle(available == 0 ? .orange : .secondary)
                    }
                    ForEach(problems.prefix(3), id: \.self) { problem in
                        Text(problem)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if problems.count > 3 {
                        Text("And \(problems.count - 3) more.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    /// One line per catalog that won't load, or might not, saying why.
    private func sourceProblems(for folder: HomeCollectionFolder) -> [String] {
        let lines = folder.sources.compactMap { source -> String? in
            guard let resolved = HomeCollectionSourceResolver.resolve(source, in: store.installedAddons) else {
                let name = HomeCollectionSourceResolver.readableName(source.catalogId)
                return "\(name): \(HomeCollectionSourceResolver.unavailableReason(for: source, in: store.installedAddons))"
            }
            let name = resolved.catalog.name.flatMap { $0.isEmpty ? nil : $0 } ?? HomeCollectionSourceResolver.readableName(source.catalogId)
            if let failure = AddonDiagnostics.shared.catalogFailure(addon: resolved.addon, catalog: resolved.catalog) {
                return "\(name): \(failure.message)"
            }
            if !resolved.isListed {
                return "\(name): \(resolved.addon.displayName) doesn't list this catalog, so Omnia asks for it anyway."
            }
            return nil
        }
        var seen = Set<String>()
        return lines.filter { seen.insert($0).inserted }
    }
}
