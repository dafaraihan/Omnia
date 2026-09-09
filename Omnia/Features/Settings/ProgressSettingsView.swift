import SwiftUI
import UniformTypeIdentifiers

struct ProgressSettingsView: View {
    @Environment(OmniaStore.self) private var store
    @Environment(SettingsPreferencesStore.self) private var settings
    @State private var exportDocument: SettingsJSONDocument?
    @State private var showsExporter = false
    @State private var showsImporter = false
    @State private var pendingImportData: Data?
    @State private var destructiveAction: LocalMediaDestructiveAction?
    @State private var importConfirmation = SettingsConfirmation<ImportAction>()
    @State private var isWorking = false
    @State private var statusMessage: String?

    private enum ImportAction: Equatable {
        case replace
    }

    var body: some View {
        OmniaSettingsForm {
            Section("Storage") {
                LabeledContent("Progress", value: "On this device")
                LabeledContent("Watchlist", value: "On this device")
                Label("No account is required", systemImage: "iphone")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Continue Watching items", selection: settings.binding(\.continueWatchingLimit)) {
                    ForEach(BoundedItemLimit.allCases, id: \.self) { limit in
                        Text(limit.title).tag(limit)
                    }
                }
            } footer: {
                Text("Fewer items reduce the amount of Home content loaded at once.")
            }

            Section {
                Button("Export Local Data", systemImage: "square.and.arrow.up") { exportLocalData() }
                    .disabled(isWorking || store.localMediaSnapshots.isEmpty)
                Button("Import Local Data", systemImage: "square.and.arrow.down") { showsImporter = true }
                    .disabled(isWorking)
                if pendingImportData != nil {
                    Button("Merge Reviewed Import") { applyImport(replacingExisting: false) }
                    Button("Replace with Reviewed Import", role: .destructive) {
                        importConfirmation.request(.replace)
                    }
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("Backups contain local media identifiers, display metadata, watchlist membership, and resume state. They never include stream addresses or credentials.")
            }

            Section("Remove Local Data") {
                Button("Clear Progress", role: .destructive) { destructiveAction = .clearProgress }
                Button("Clear Watchlist", role: .destructive) { destructiveAction = .clearWatchlist }
            }

            if isWorking { ProgressView("Updating local data…") }
            if store.localMediaPersistenceFailed {
                Label("Local storage is unavailable. Try again after checking available disk space.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            if let statusMessage { Text(statusMessage).foregroundStyle(.secondary) }
        }
        .omniaNavigationTitle("Progress")
        .confirmationDialog(
            destructiveAction?.title ?? "Remove local data?",
            isPresented: Binding(get: { destructiveAction != nil }, set: { if !$0 { destructiveAction = nil } }),
            titleVisibility: .visible
        ) {
            Button(destructiveAction?.title ?? "Clear", role: .destructive) { performDestructiveAction() }
            Button("Cancel", role: .cancel) { destructiveAction = nil }
        } message: {
            Text(destructiveAction?.message ?? "")
        }
        .confirmationDialog(
            "Replace Existing Local Data?",
            isPresented: importConfirmationPresentation,
            titleVisibility: .visible
        ) {
            Button("Replace", role: .destructive) {
                guard importConfirmation.confirm() == .replace else { return }
                applyImport(replacingExisting: true)
            }
            Button("Cancel", role: .cancel) { importConfirmation.cancel() }
        } message: {
            Text("Existing local progress and watchlist data will be replaced by the reviewed backup.")
        }
        .fileExporter(
            isPresented: $showsExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Omnia Local Data"
        ) { result in
            if case .failure = result { statusMessage = "The local backup was not exported." }
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.json]) { result in
            reviewImport(result)
        }
    }

    private var importConfirmationPresentation: Binding<Bool> {
        Binding(
            get: { importConfirmation.pending != nil },
            set: { isPresented in
                if !isPresented { importConfirmation.cancel() }
            }
        )
    }

    private func exportLocalData() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                exportDocument = SettingsJSONDocument(data: try await store.exportLocalMedia())
                showsExporter = true
            } catch {
                statusMessage = "The local backup could not be prepared."
            }
        }
    }

    private func reviewImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            _ = try LocalMediaBackupDocument.decode(data)
            pendingImportData = data
            statusMessage = "Backup reviewed. Choose Merge or Replace."
        } catch {
            pendingImportData = nil
            statusMessage = "This local backup is invalid or cannot be read."
        }
    }

    private func applyImport(replacingExisting: Bool) {
        guard let pendingImportData else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await store.importLocalMedia(pendingImportData, replacingExisting: replacingExisting)
                self.pendingImportData = nil
                statusMessage = "Local data imported."
            } catch {
                statusMessage = "The reviewed backup could not be imported. Existing data was preserved."
            }
        }
    }

    private func performDestructiveAction() {
        guard let destructiveAction else { return }
        self.destructiveAction = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await store.clearLocalMedia(destructiveAction)
                statusMessage = "\(destructiveAction.title) completed."
            } catch {
                statusMessage = "Local data could not be updated."
            }
        }
    }
}

struct SettingsJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private extension BoundedItemLimit {
    var title: String {
        value.map(String.init) ?? "No limit"
    }
}

private extension LocalMediaDestructiveAction {
    var title: String {
        switch self {
        case .clearProgress: "Clear Progress"
        case .clearWatchlist: "Clear Watchlist"
        }
    }

    var message: String {
        switch self {
        case .clearProgress: "Resume positions will be removed. Your watchlist will remain."
        case .clearWatchlist: "Watchlist membership will be removed. Saved resume positions will remain."
        }
    }
}
