import SwiftUI
import UniformTypeIdentifiers

struct AddonsSettingsView: View {
    @Environment(OmniaStore.self) private var store
    @Environment(SettingsPreferencesStore.self) private var settings
    @State private var showsAddSheet = false
    @State private var addonToRemove: InstalledAddon?
    @State private var exportDocument: SettingsJSONDocument?
    @State private var showsExporter = false
    @State private var showsImporter = false
    @State private var importedDocument: AddonBackupDocument?
    @State private var statusMessage: String?

    var body: some View {
        @Bindable var store = store

        Form {
            Section {
                Picker("Request timeout", selection: settings.binding(\.addonTimeout)) {
                    ForEach(AddonTimeout.allCases, id: \.self) { timeout in
                        Text("\(timeout.rawValue) seconds").tag(timeout)
                    }
                }
            } footer: {
                Text("Omnia cancels an add-on request when this limit is reached.")
            }

            Section("Installed Add-ons") {
                if store.installedAddons.isEmpty {
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
                            )
                        )
                        .swipeActions {
                            Button("Remove", role: .destructive) { addonToRemove = addon }
                        }
                        .contextMenu {
                            Button("Move Earlier", systemImage: "arrow.up") {
                                move(addon, offset: -1)
                            }
                            .disabled(!canMove(addon, offset: -1))

                            Button("Move Later", systemImage: "arrow.down") {
                                move(addon, offset: 1)
                            }
                            .disabled(!canMove(addon, offset: 1))

                            Divider()
                            Button("Remove", role: .destructive) { addonToRemove = addon }
                        }
                        .accessibilityAction(named: "Move earlier") {
                            move(addon, offset: -1)
                        }
                        .accessibilityAction(named: "Move later") {
                            move(addon, offset: 1)
                        }
                    }
                    .onMove(perform: store.moveAddons)
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
        .navigationTitle("Add-ons")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Add-on", systemImage: "plus") { showsAddSheet = true }
            }
            #if os(iOS)
            ToolbarItem(placement: .secondaryAction) { EditButton() }
            #endif
        }
        .sheet(isPresented: $showsAddSheet) {
            AddManifestView(timeout: settings.preferences.addonTimeout)
        }
        .confirmationDialog(
            "Remove \(addonToRemove?.manifest.name ?? "add-on")?",
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

    private func canMove(_ addon: InstalledAddon, offset: Int) -> Bool {
        guard let index = store.installedAddons.firstIndex(where: { $0.id == addon.id }) else { return false }
        return store.installedAddons.indices.contains(index + offset)
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "puzzlepiece.extension.fill")
                .imageScale(.large)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(addon.manifest.name).font(.headline)
                Text("Version \(addon.manifest.version)").font(.caption).foregroundStyle(.secondary)
                Text(addon.manifest.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                Text(capabilities(for: addon)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Toggle("Enabled", isOn: $isEnabled).labelsHidden()
        }
        .padding(.vertical, 4)
    }

    private func capabilities(for addon: InstalledAddon) -> String {
        addon.manifest.resources.map(\.name).uniqued().sorted().joined(separator: " · ")
    }
}

private struct AddManifestView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(OmniaStore.self) private var store
    let timeout: AddonTimeout
    @State private var address = ""
    @State private var isInstalling = false
    @State private var errorMessage: String?

    private var manifestURL: URL? {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/manifest.json", text: $address)
                        .textContentType(.URL)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                } header: {
                    Text("Manifest URL")
                } footer: {
                    Text("HTTPS is required. Add only sources you trust.")
                }
                if isInstalling { ProgressView("Validating manifest…") }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Add Add-on")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { install() }.disabled(manifestURL == nil || isInstalling)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 240)
    }

    private func install() {
        guard let manifestURL else { return }
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
                dismiss()
            } catch {
                errorMessage = "Omnia could not validate this manifest. Check the address and try again."
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
