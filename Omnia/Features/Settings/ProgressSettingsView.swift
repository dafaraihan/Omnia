import SwiftUI
import UniformTypeIdentifiers

struct ProgressSettingsView: View {
    @Environment(OmniaStore.self) private var store
    @Environment(SettingsPreferencesStore.self) private var settings
    @Environment(OmniaAccount.self) private var account
    @State private var exportDocument: SettingsJSONDocument?
    @State private var showsExporter = false
    @State private var showsImporter = false
    @State private var pendingImportData: Data?
    @State private var destructiveAction: LocalMediaDestructiveAction?
    @State private var importConfirmation = SettingsConfirmation<ImportAction>()
    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var trackerLibrary = TrackerLibraryStore.shared

    private enum ImportAction: Equatable {
        case replace
    }

    var body: some View {
        OmniaSettingsForm {
            Section {
                SettingsDropdown(
                    "Progress",
                    subtitle: storageDetail(trackerLibrary.continueWatchingSource),
                    selection: $trackerLibrary.continueWatchingSource,
                    options: storageOptions(trackerLibrary.availableSources, including: trackerLibrary.continueWatchingSource)
                ) { storageTitle($0) }
                SettingsDropdown(
                    "Watchlist",
                    subtitle: storageDetail(trackerLibrary.watchlistSource),
                    selection: $trackerLibrary.watchlistSource,
                    options: storageOptions(trackerLibrary.availableWatchlistSources, including: trackerLibrary.watchlistSource)
                ) { storageTitle($0) }
                ForEach(TrackerKind.allCases) { kind in
                    TrackerSyncStatusLine(kind: kind)
                }
                if account.user != nil {
                    Label("Omnia's own progress is synced for this profile on every device you sign in on", systemImage: "checkmark.icloud")
                        .foregroundStyle(.secondary)
                } else {
                    Label("Sign in under Account to keep Omnia's own progress in your Omnia account", systemImage: "laptopcomputer")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Storage")
            } footer: {
                Text("Choose where Continue Watching and the Library read from. A tracker's progress and watchlist come from your account there, and what you play is scrobbled back to it. Connect Trakt, Simkl or PublicMetaDB under Integrations to add them here. Omnia keeps its own progress either way.")
            }

            Section {
                SettingsDropdown(
                    "Continue Watching items",
                    selection: settings.binding(\.continueWatchingLimit),
                    options: Array(BoundedItemLimit.allCases)
                ) { limit in limit.title }
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

    /// Local plus every connected tracker, and the current choice even if
    /// its tracker was disconnected, so the menu always shows it.
    private func storageOptions(
        _ available: [TrackerLibrarySource],
        including current: TrackerLibrarySource
    ) -> [TrackerLibrarySource] {
        available.contains(current) ? available : available + [current]
    }

    private func storageTitle(_ source: TrackerLibrarySource) -> String {
        let local = account.user != nil ? "Omnia Account" : "This Device"
        switch source {
        case .local: return local
        case .localAniList: return "\(local) + AniList Anime"
        case .traktAniList: return source.title
        default: return source.tracker?.title ?? source.title
        }
    }

    private func storageDetail(_ source: TrackerLibrarySource) -> String {
        guard !source.trackers.isEmpty else { return account.storageSummary }
        guard trackerLibrary.effectiveSource(source) == source else {
            let missing = source.trackers.filter { !TrackerAccountStore.shared.isConnected($0) }.map(\.title)
            return "\(missing.formatted(.list(type: .and))) isn't connected, so Omnia's own is shown"
        }
        if source.addsAniListAnime {
            return "Anime from your AniList Watching list, the rest from \(source.tracker?.title ?? "Omnia")"
        }
        return "Read from your \(source.tracker?.title ?? "") account"
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
