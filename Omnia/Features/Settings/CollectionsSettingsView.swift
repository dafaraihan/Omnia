//
//  CollectionsSettingsView.swift
//  Omnia
//

import SwiftUI
import UniformTypeIdentifiers

/// Home › Collections: make collections, or import a Nuvio or Xperience
/// `collections.json`, then drag to reorder, and show, edit or remove each.
/// Folder sources are checked against the installed add-ons so a missing
/// add-on is visible here.
struct CollectionsSettingsView: View {
    @Environment(OmniaStore.self) private var store
    @Environment(CollectionsStore.self) private var collections
    @Environment(SettingsPreferencesStore.self) private var settings

    @State private var showsImporter = false
    @State private var showsExporter = false
    @State private var exportDocument: SettingsJSONDocument?
    @State private var collectionToRemove: HomeCollection?
    @State private var statusMessage: String?
    @State private var editingCollection: HomeCollection?
    @State private var draggedCollectionID: String?
    @State private var dragStartIndex = 0
    @State private var reorderRowHeight: CGFloat = 60

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
                Text("Make a collection here, or import a collections.json from Xperience or Nuvio. Importing replaces the collections in that file.")
            }

            Section {
                SettingsRouteLink(route: .landscapeCards, summary: nil)
                SettingsRouteLink(route: .posterCards, summary: nil)
            } header: {
                Text("Card Style")
            } footer: {
                Text("Landscape collections follow Landscape Card Style, and portrait ones follow Poster Card Style.")
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
                Section {
                    ForEach(collections.collections) { collection in
                        collectionRow(collection)
                    }
                } header: {
                    Text("Your Collections")
                } footer: {
                    Text("Drag to reorder. A missing catalog usually means its add-on isn't installed; open a collection to see which.")
                }
            }
        }
        .omniaNavigationTitle("Collections")
        .navigationDestination(item: $editingCollection) { collection in
            CollectionEditorView(collection: collection)
        }
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

    private func collectionRow(_ collection: HomeCollection) -> some View {
        let availability = sourceAvailability(for: collection)
        let isComplete = availability.available == availability.total
        let isVisible = visibilityBinding(for: collection)
        let folderCount = "\(collection.folders.count) \(collection.folders.count == 1 ? "folder" : "folders")"

        return HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(draggedCollectionID == collection.id ? .primary : .tertiary)
                .frame(width: 30, height: 44)
                .contentShape(Rectangle())
                .highPriorityGesture(reorderGesture(for: collection))
                .help("Drag to reorder")
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(collection.title)
                        .lineLimit(1)
                    if collection.pinToTop {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Pinned")
                    }
                }
                Text(isComplete ? folderCount : "\(folderCount) · \(availability.available) of \(availability.total) catalogs available")
                    .font(.caption)
                    .foregroundStyle(isComplete ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(isVisible.wrappedValue ? 1 : 0.5)

            HStack(spacing: 14) {
                Button {
                    isVisible.wrappedValue.toggle()
                } label: {
                    Image(systemName: isVisible.wrappedValue ? "eye" : "eye.slash")
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .help(isVisible.wrappedValue ? "Hide from Home" : "Show on Home")
                .accessibilityLabel(isVisible.wrappedValue ? "Hide \(collection.title) from Home" : "Show \(collection.title) on Home")

                Button {
                    editingCollection = collection
                } label: {
                    Image(systemName: "pencil")
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .help("Edit")
                .accessibilityLabel("Edit \(collection.title)")

                Button(role: .destructive) {
                    collectionToRemove = collection
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .help("Remove")
                .accessibilityLabel("Remove \(collection.title)")
            }
            .buttonStyle(.borderless)
        }
        .opacity(draggedCollectionID == collection.id ? 0.72 : 1)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { reorderRowHeight = $0 }
        .accessibilityAction(named: "Move Up") { step(collection, by: -1) }
        .accessibilityAction(named: "Move Down") { step(collection, by: 1) }
    }

    /// Dragging the handle moves the row a place for each row's height dragged.
    /// Held to the handle, so swiping anywhere else still scrolls the page.
    private func reorderGesture(for collection: HomeCollection) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                let all = collections.collections
                guard let current = all.firstIndex(where: { $0.id == collection.id }) else { return }
                if draggedCollectionID != collection.id {
                    draggedCollectionID = collection.id
                    dragStartIndex = current
                }
                let steps = Int((value.translation.height / max(reorderRowHeight, 1)).rounded())
                step(collection, to: min(max(dragStartIndex + steps, 0), all.count - 1))
            }
            .onEnded { _ in draggedCollectionID = nil }
    }

    private func step(_ collection: HomeCollection, by offset: Int) {
        guard let current = collections.collections.firstIndex(where: { $0.id == collection.id }) else { return }
        step(collection, to: min(max(current + offset, 0), collections.collections.count - 1))
    }

    private func step(_ collection: HomeCollection, to target: Int) {
        guard let current = collections.collections.firstIndex(where: { $0.id == collection.id }),
              let destination = AddonReorder.destination(from: current, over: target) else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            collections.move(fromOffsets: IndexSet(integer: current), toOffset: destination)
        }
    }

    // MARK: Helpers

    private func sourceAvailability(for folder: HomeCollectionFolder) -> (available: Int, total: Int) {
        let available = folder.sources.filter {
            HomeCollectionSourceResolver.resolve($0, in: store.installedAddons) != nil
        }.count
        return (available, folder.sources.count)
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

}

/// A few of your folders drawn as they'll look on Home, or a sample tile
/// before any collection exists. It updates as each option changes.
struct CollectionCardPreview: View {
    let folders: [HomeCollectionFolder]
    var sampleShape: HomeCollectionFolder.TileShape = .landscape
    @Environment(\.displayPreferences) private var display
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) {
                if folders.isEmpty {
                    sampleTile
                } else {
                    ForEach(folders) { folder in
                        CollectionFolderTile(folder: folder)
                            .allowsHitTesting(false)
                    }
                }
            }
            .padding(12)
        }
        .scrollIndicators(.hidden)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: display.collectionCard)
        .accessibilityHidden(true)
    }

    private var sampleTile: some View {
        let shape = sampleShape
        let radius = display.landscapeCornerRadius
        return ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [display.accentColor.opacity(0.85), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "folder.fill")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if display.collectionCard.titles != .never {
                Text("Preview")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(12)
            }
        }
        .frame(
            width: CollectionFolderTile.width(for: shape, display: display),
            height: CollectionFolderTile.height(for: shape, display: display)
        )
        .clipShape(.rect(cornerRadius: radius, style: .continuous))
        .cardDepth(.collections, cornerRadius: radius)
    }
}
