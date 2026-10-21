//
//  CollectionsSettingsView.swift
//  Omnia
//

import SwiftUI
import UniformTypeIdentifiers

/// Home › Collections: make collections, or import a Nuvio or Xperience
/// `collections.json`, then edit, show, hide, pin, reorder or remove each.
/// Folder sources are checked against the installed add-ons so a missing
/// add-on is visible here.
struct CollectionsSettingsView: View {
    @Environment(OmniaStore.self) private var store
    @Environment(CollectionsStore.self) private var collections

    @State private var showsImporter = false
    @State private var showsExporter = false
    @State private var exportDocument: SettingsJSONDocument?
    @State private var collectionToRemove: HomeCollection?
    @State private var statusMessage: String?
    @State private var expandedCollectionIDs: Set<String> = []

    var body: some View {
        OmniaSettingsForm {
            Section {
                NavigationLink {
                    CollectionEditorView(collection: nil)
                } label: {
                    Label("New Collection", systemImage: "plus")
                }
                .settingsLinkRow()
                .disabled(collections.collections.count >= HomeCollection.maximumCollections)
                Button("Import Collections…", systemImage: "square.and.arrow.down") {
                    showsImporter = true
                }
                Button("Export Collections…", systemImage: "square.and.arrow.up") {
                    export()
                }
                .disabled(collections.collections.isEmpty)
                if let message = statusMessage ?? collections.loadError {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Collections")
            } footer: {
                Text("Make a collection here, or import the collections.json that Xperience or Nuvio exports. Importing an updated file replaces the collections it already contains.")
            }

            if collections.collections.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Collections",
                        systemImage: "square.stack",
                        description: Text("Collections group catalogs into folders, such as streaming services or genres, and appear as rows on Home.")
                    )
                }
            } else {
                ForEach(collections.collections) { collection in
                    collectionSection(collection)
                }
            }
        }
        .omniaNavigationTitle("Collections")
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.json]) { result in
            importFile(result)
        }
        .fileExporter(
            isPresented: $showsExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "collections"
        ) { result in
            if case .failure = result { statusMessage = "The collections weren't exported." }
        }
        .confirmationDialog(
            "Remove \(collectionToRemove?.title ?? "Collection")?",
            isPresented: removalBinding,
            titleVisibility: .visible
        ) {
            Button("Remove Collection", role: .destructive) {
                if let collectionToRemove {
                    collections.remove(collectionToRemove)
                }
                collectionToRemove = nil
            }
        } message: {
            Text("Its folders disappear from Home. Export your collections first to keep a copy.")
        }
    }

    private func collectionSection(_ collection: HomeCollection) -> some View {
        let availability = sourceAvailability(for: collection)

        let index = collections.collections.firstIndex { $0.id == collection.id } ?? 0

        return Section {
            NavigationLink {
                CollectionEditorView(collection: collection)
            } label: {
                Label("Edit Collection", systemImage: "pencil")
            }
            .settingsLinkRow()
            Toggle(isOn: visibilityBinding(for: collection)) {
                rowLabel("Show on Home", detail: "\(collection.folders.count) \(collection.folders.count == 1 ? "folder" : "folders")")
            }
            Toggle(isOn: pinBinding(for: collection)) {
                rowLabel("Pin to Top", detail: "Keep this collection above every catalog on Home.")
            }
            HStack {
                rowLabel(
                    availability.available == availability.total ? "All Catalogs Available" : "Some Catalogs Unavailable",
                    detail: "\(availability.available) of \(availability.total) folder catalogs come from installed add-ons."
                )
                Spacer()
                Image(systemName: availability.available == availability.total ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(availability.available == availability.total ? .green : .orange)
                    .accessibilityHidden(true)
            }
            DisclosureGroup(isExpanded: expansionBinding(for: collection)) {
                ForEach(collection.folders) { folder in
                    let folderAvailability = sourceAvailability(for: folder)
                    let problems = sourceProblems(for: folder)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(folder.title)
                            Spacer()
                            Text("\(folderAvailability.available) of \(folderAvailability.total) catalogs")
                                .font(.caption)
                                .foregroundStyle(folderAvailability.available == 0 ? .orange : .secondary)
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
            } label: {
                Text("Folders")
            }
            if collections.collections.count > 1 {
                HStack(spacing: 16) {
                    Button("Move Up", systemImage: "chevron.up") {
                        collections.move(collection, by: -1)
                    }
                    .disabled(index == 0)
                    Button("Move Down", systemImage: "chevron.down") {
                        collections.move(collection, by: 1)
                    }
                    .disabled(index == collections.collections.count - 1)
                }
                .buttonStyle(.borderless)
            }
            Button("Remove Collection…", systemImage: "trash", role: .destructive) {
                collectionToRemove = collection
            }
        } header: {
            Text(collection.title)
        }
    }

    // MARK: Helpers

    private func rowLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func sourceAvailability(for folder: HomeCollectionFolder) -> (available: Int, total: Int) {
        let available = folder.sources.filter {
            HomeCollectionSourceResolver.resolve($0, in: store.installedAddons) != nil
        }.count
        return (available, folder.sources.count)
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

    private func sourceAvailability(for collection: HomeCollection) -> (available: Int, total: Int) {
        collection.folders.map(sourceAvailability(for:)).reduce((0, 0)) { ($0.0 + $1.available, $0.1 + $1.total) }
    }

    private func importFile(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                guard size <= HomeCollectionFile.maximumBytes else { throw HomeCollectionFile.ImportError.tooLarge }
                let data = try Data(contentsOf: url)
                let count = try collections.importCollections(from: data)
                statusMessage = "Imported \(count) \(count == 1 ? "collection" : "collections")."
            } catch {
                statusMessage = "Import failed. \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
            }
        case .failure:
            statusMessage = "The file couldn't be opened."
        }
    }

    private func export() {
        do {
            exportDocument = SettingsJSONDocument(data: try collections.exportData())
            showsExporter = true
        } catch {
            statusMessage = "The collections couldn't be exported."
        }
    }

    private var removalBinding: Binding<Bool> {
        Binding(
            get: { collectionToRemove != nil },
            set: { if !$0 { collectionToRemove = nil } }
        )
    }

    private func visibilityBinding(for collection: HomeCollection) -> Binding<Bool> {
        Binding(
            get: { collections.isVisible(collection) },
            set: { collections.setVisible($0, for: collection) }
        )
    }

    private func pinBinding(for collection: HomeCollection) -> Binding<Bool> {
        Binding(
            get: { collections.collections.first { $0.id == collection.id }?.pinToTop ?? false },
            set: { collections.setPinned($0, for: collection) }
        )
    }

    private func expansionBinding(for collection: HomeCollection) -> Binding<Bool> {
        Binding(
            get: { expandedCollectionIDs.contains(collection.id) },
            set: { isExpanded in
                if isExpanded {
                    expandedCollectionIDs.insert(collection.id)
                } else {
                    expandedCollectionIDs.remove(collection.id)
                }
            }
        )
    }
}
