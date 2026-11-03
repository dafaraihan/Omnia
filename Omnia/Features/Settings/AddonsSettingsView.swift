import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum AddonContextMenuAction: Equatable {
    case refresh
    case configure
    case copyLink
    case rename
    case remove
}

enum AddonActionTextTreatment: Equatable {
    case white
}

enum AddonSettingsPresentation {
    static let usesLiquidGlassRows = false
    static let usesLiquidGlassAddModal = true
    static let actionTextTreatment = AddonActionTextTreatment.white

    static let contextMenuActions: [AddonContextMenuAction] = [
        .refresh,
        .copyLink,
        .rename,
        .configure,
        .remove
    ]

    static func configurationURL(from manifestURL: URL) -> URL? {
        guard var components = URLComponents(url: manifestURL, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host != nil,
              components.user == nil,
              components.password == nil else {
            return nil
        }

        let path = components.percentEncodedPath
        guard let separator = path.lastIndex(of: "/"),
              path[path.index(after: separator)...].lowercased() == "manifest.json" else {
            return nil
        }
        components.percentEncodedPath = "\(path[...separator])configure"
        components.fragment = nil
        return components.url
    }
}

enum AddonReorder {
    static func destination(from source: Int, over target: Int) -> Int? {
        guard source != target else { return nil }
        return target > source ? target + 1 : target
    }
}

struct AddonsSettingsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(OmniaStore.self) private var store
    @Environment(SettingsPreferencesStore.self) private var settings
    @State private var addonToRemove: InstalledAddon?
    @State private var addonToRename: InstalledAddon?
    @State private var renameDraft = ""
    @State private var draggedAddonID: String?
    @State private var refreshedLogoAddonIDs: Set<String> = []
    @State private var exportDocument: SettingsJSONDocument?
    @State private var showsExporter = false
    @State private var showsImporter = false
    @State private var importedDocument: AddonBackupDocument?
    @State private var statusMessage: String?
    @State private var detailAddonID: String?
    @State private var refreshingAddonIDs: Set<String> = []

    var body: some View {
        @Bindable var store = store

        OmniaSettingsForm {
            Section {
                SettingsDropdown(
                    "Request timeout",
                    selection: settings.binding(\.addonTimeout),
                    options: Array(AddonTimeout.allCases)
                ) { timeout in "\(timeout.rawValue) seconds" }
            } footer: {
                Text("Omnia cancels an add-on request when this limit is reached.")
            }

            AddAddonSection(timeout: settings.preferences.addonTimeout)

            if !store.installedAddonRestoreIssues.isEmpty {
                Section {
                    ForEach(store.installedAddonRestoreIssues) { issue in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.key.horizontal.fill")
                                .imageScale(.large)
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(issue.addonName)
                                    .font(.headline)
                                Text("Install this add-on again to repair its secure configuration.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Needs Attention")
                } footer: {
                    Text("Other installed add-ons remain available. Omnia never displays or reconstructs the missing private address.")
                }
            }

            Section("Installed Add-ons") {
                if store.installedAddonsAreLoading {
                    OmniaLoadingRow("Loading Add-ons…")
                } else if store.installedAddons.isEmpty {
                    ContentUnavailableView(
                        "No Add-ons",
                        systemImage: "puzzlepiece.extension",
                        description: Text("Add an HTTPS manifest from a source you trust.")
                    )
                } else {
                    ForEach(store.installedAddons) { addon in
                        AddonSettingsRow(
                            addon: addon,
                            isEnabled: Binding(
                                get: { addon.isEnabled },
                                set: { _ in store.toggleAddon(id: addon.id) }
                            ),
                            showDetails: { detailAddonID = addon.id }
                        )
                        .opacity(draggedAddonID == addon.id ? 0.72 : 1)
                        .onDrag {
                            draggedAddonID = addon.id
                            return NSItemProvider(object: addon.id as NSString)
                        }
                        .onDrop(
                            of: [.text],
                            delegate: AddonReorderDropDelegate(
                                targetID: addon.id,
                                addons: { store.installedAddons },
                                draggedAddonID: $draggedAddonID,
                                move: store.moveAddons
                            )
                        )
                        .contextMenu {
                            Button("Show Details", systemImage: "info.circle") {
                                detailAddonID = addon.id
                            }

                            Button("Refresh", systemImage: "arrow.clockwise") {
                                refreshAddon(addon.id)
                            }
                            .disabled(refreshingAddonIDs.contains(addon.id))

                            Button("Copy Link", systemImage: "doc.on.doc") {
                                copyManifestLink(addon.manifestURL)
                            }

                            Button("Rename", systemImage: "pencil") {
                                beginRename(addon)
                            }

                            Button("Configure", systemImage: "gearshape") {
                                if let url = AddonSettingsPresentation.configurationURL(from: addon.manifestURL) {
                                    openURL(url)
                                }
                            }
                            .disabled(AddonSettingsPresentation.configurationURL(from: addon.manifestURL) == nil)

                            Divider()
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                addonToRemove = addon
                            }
                        }
                        .accessibilityAction(named: "Move earlier") {
                            move(addon, offset: -1)
                        }
                        .accessibilityAction(named: "Move later") {
                            move(addon, offset: 1)
                        }
                    }
                }
            }

            Section {
                Button("Export Add-ons", systemImage: "square.and.arrow.up") { prepareExport() }
                    .disabled(store.installedAddons.isEmpty)
                Button("Import Add-ons", systemImage: "square.and.arrow.down") { showsImporter = true }
                if let importedDocument {
                    LabeledContent("Ready to import", value: "\(importedDocument.addons.count) add-ons")
                    Button("Install Reviewed Add-ons") { applyImport(importedDocument) }
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("Private configured manifest addresses are excluded from exports. Imports are reviewed before installation.")
            }

            if let statusMessage {
                Section { Text(statusMessage).foregroundStyle(.secondary) }
            }
        }
        .omniaNavigationTitle("Add-ons")
        .navigationDestination(item: $detailAddonID) { addonID in
            AddonDetailView(addonID: addonID)
        }
        .task(id: store.installedAddonsAreLoading) {
            await refreshMissingAddonLogos()
        }
        .confirmationDialog(
            "Remove \(addonToRemove?.displayName ?? "add-on")?",
            isPresented: Binding(get: { addonToRemove != nil }, set: { if !$0 { addonToRemove = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let addonToRemove { store.removeAddon(id: addonToRemove.id) }
                addonToRemove = nil
            }
            Button("Cancel", role: .cancel) { addonToRemove = nil }
        } message: {
            Text("Omnia will stop querying this add-on and remove its locally stored manifest address.")
        }
        .alert(
            "Rename Add-on",
            isPresented: Binding(
                get: { addonToRename != nil },
                set: { if !$0 { addonToRename = nil } }
            )
        ) {
            TextField("Add-on name", text: $renameDraft)
            Button("Cancel", role: .cancel) { addonToRename = nil }
            Button("Save") {
                if let addonToRename {
                    store.renameAddon(id: addonToRename.id, to: renameDraft)
                }
                addonToRename = nil
            }
            .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("This changes the name shown in Omnia. The add-on’s manifest and identity stay unchanged.")
        }
        .fileExporter(
            isPresented: $showsExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Omnia Add-ons"
        ) { result in
            if case .failure = result { statusMessage = "The add-on backup was not exported." }
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.json]) { result in
            reviewImport(result)
        }
    }

    private func move(_ addon: InstalledAddon, offset: Int) {
        guard let index = store.installedAddons.firstIndex(where: { $0.id == addon.id }) else { return }
        let destination = min(max(index + offset, 0), store.installedAddons.count - 1)
        guard destination != index else { return }
        store.moveAddons(from: IndexSet(integer: index), to: destination > index ? destination + 1 : destination)
    }

    private func beginRename(_ addon: InstalledAddon) {
        renameDraft = addon.displayName
        addonToRename = addon
    }

    private func refreshAddon(_ id: String) {
        guard !refreshingAddonIDs.contains(id) else { return }
        refreshingAddonIDs.insert(id)
        Task {
            let error = await store.refreshAddonManifest(id: id)
            refreshingAddonIDs.remove(id)
            let name = store.installedAddons.first { $0.id == id }?.displayName ?? "The add-on"
            statusMessage = error == nil
                ? "\(name) was refreshed."
                : "\(name) couldn't be refreshed. Its last manifest keeps working."
        }
    }

    private func copyManifestLink(_ url: URL) {
        OmniaPasteboard.copySensitive(url.absoluteString)
        statusMessage = "Add-on link copied."
    }

    private func refreshMissingAddonLogos() async {
        guard !store.installedAddonsAreLoading else { return }

        for addon in store.installedAddons where addon.manifest.presentationLogoURL == nil {
            guard !Task.isCancelled else { return }
            guard refreshedLogoAddonIDs.insert(addon.id).inserted else { continue }

            do {
                let manifest = try await StremioAddonClient.fetchManifest(
                    from: addon.manifestURL,
                    timeout: settings.preferences.addonTimeout,
                    transport: HTTPTransport()
                )
                guard manifest.id == addon.manifest.id else { continue }
                store.replaceAddon(id: addon.id, manifest: manifest, manifestURL: addon.manifestURL)
            } catch {
                // Logo loading is optional. Keep the installed manifest and
                // SF Symbol fallback when an add-on is offline or malformed.
            }
        }
    }

    private func prepareExport() {
        let result = AddonBackupDocument.exporting(store.installedAddons)
        guard let data = try? JSONEncoder().encode(result.document) else {
            statusMessage = "The add-on backup could not be prepared."
            return
        }
        exportDocument = SettingsJSONDocument(data: data)
        showsExporter = true
        statusMessage = result.excludedPrivateCount == 0
            ? nil
            : "\(result.excludedPrivateCount) private configured add-on(s) were excluded."
    }

    private func reviewImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            importedDocument = try AddonBackupDocument.decodeValidated(Data(contentsOf: url))
            statusMessage = nil
        } catch {
            importedDocument = nil
            statusMessage = "This add-on backup is invalid or cannot be read."
        }
    }

    private func applyImport(_ document: AddonBackupDocument) {
        statusMessage = "Installing reviewed add-ons…"
        Task {
            var failures = 0
            for record in document.addons {
                do {
                    let manifest = try await StremioAddonClient.fetchManifest(
                        from: record.manifestURL,
                        timeout: settings.preferences.addonTimeout,
                        transport: HTTPTransport()
                    )
                    store.add(InstalledAddon(
                        manifest: manifest,
                        manifestURL: record.manifestURL,
                        isEnabled: record.isEnabled,
                        addedAt: .now
                    ))
                } catch {
                    failures += 1
                }
            }
            importedDocument = nil
            statusMessage = failures == 0
                ? "Add-ons imported."
                : "Import completed with \(failures) add-on(s) unavailable. Existing add-ons were preserved."
        }
    }
}

private struct AddonSettingsRow: View {
    let addon: InstalledAddon
    @Binding var isEnabled: Bool
    let showDetails: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        HStack(alignment: .top, spacing: 12) {
            AddonLogoView(url: addon.manifest.presentationLogoURL)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(addon.displayName).font(.headline)
                    if hasProblem {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .help("Its last request failed. Open details to see why.")
                            .accessibilityLabel("Has errors")
                    }
                }
                Text("Version \(addon.manifest.version)").font(.caption).foregroundStyle(.secondary)
                Text(addon.manifest.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                Text(capabilities(for: addon)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            // An explicit switch, so the Settings row style doesn't draw the
            // label as text beside it.
            Toggle(isOn: $isEnabled) { EmptyView() }
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel("Enabled")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(shape)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(addon.displayName)
        .accessibilityHint("Click and hold, then drag to reorder. Right-click for add-on actions.")
    }

    private var hasProblem: Bool {
        addon.isEnabled && AddonDiagnostics.shared.report(for: addon).hasProblem
    }

    private func capabilities(for addon: InstalledAddon) -> String {
        addon.manifest.resources.map(\.name).uniqued().sorted().joined(separator: " · ")
    }
}

struct AddonLogoView: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                CachedArtworkImage(url: url, size: CGSize(width: 38, height: 38), contentMode: .fit) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: 38, height: 38)
        .padding(3)
        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .clipShape(.rect(cornerRadius: 9, style: .continuous))
    }

    private var fallback: some View {
        Image(systemName: "puzzlepiece.extension.fill")
            .resizable()
            .scaledToFit()
            .padding(8)
            .foregroundStyle(.black.opacity(0.78))
    }
}

private struct AddonReorderDropDelegate: DropDelegate {
    let targetID: String
    let addons: () -> [InstalledAddon]
    @Binding var draggedAddonID: String?
    let move: (IndexSet, Int) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedAddonID,
              draggedAddonID != targetID,
              let source = addons().firstIndex(where: { $0.id == draggedAddonID }),
              let target = addons().firstIndex(where: { $0.id == targetID }),
              let destination = AddonReorder.destination(from: source, over: target) else {
            return
        }
        withAnimation(.easeInOut(duration: 0.16)) {
            move(IndexSet(integer: source), destination)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedAddonID = nil
        return true
    }
}

/// Add an add-on by pasting its address, laid out like Plugins' Add
/// Repository field.
private struct AddAddonSection: View {
    @Environment(OmniaStore.self) private var store
    let timeout: AddonTimeout
    @State private var address = ""
    @State private var isInstalling = false
    @State private var errorMessage: String?

    /// Accepts `stremio://` links, Configure pages and addresses without
    /// `/manifest.json`, like Nuvio.
    private var manifestURL: URL? {
        AddonManifestAddress.manifestURL(from: address)
    }

    var body: some View {
        Section {
            HStack {
                // Verbatim, so the example address isn't styled as a link.
                TextField("Add-on URL", text: $address, prompt: Text(verbatim: "https://example.com/manifest.json"))
                    .labelsHidden()
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit(install)
                if isInstalling {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Add", action: install)
                        .disabled(manifestURL == nil)
                }
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Add Add-on")
        } footer: {
            Text("Paste an install link, a stremio:// link or the add-on's address. HTTPS is required. Add only sources you trust.")
        }
    }

    static func installErrorMessage(for error: Error) -> String {
        let reason = (error as? LocalizedError)?.errorDescription ?? "The add-on couldn't be reached."
        return "Omnia couldn't install this add-on. \(reason)"
    }

    private func install() {
        guard let manifestURL, !isInstalling else { return }
        isInstalling = true
        errorMessage = nil
        Task {
            defer { isInstalling = false }
            do {
                let manifest = try await StremioAddonClient.fetchManifest(
                    from: manifestURL,
                    timeout: timeout,
                    transport: HTTPTransport()
                )
                store.add(InstalledAddon(manifest: manifest, manifestURL: manifestURL, isEnabled: true, addedAt: .now))
                address = ""
            } catch {
                errorMessage = Self.installErrorMessage(for: error)
            }
        }
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
