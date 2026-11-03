//
//  AddonDetailView.swift
//  Omnia
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Settings › Add-ons › an add-on: whether each kind of request is working,
/// the last error in plain words, and the catalogs that failed. Opened from
/// the info button on an add-on's row.
struct AddonDetailView: View {
    let addonID: String

    @Environment(\.openURL) private var openURL
    @Environment(OmniaStore.self) private var store
    @State private var isChecking = false
    @State private var showsAllCatalogs = false
    @State private var statusMessage: String?

    private var diagnostics: AddonDiagnostics { .shared }
    private var addon: InstalledAddon? { store.installedAddons.first { $0.id == addonID } }

    var body: some View {
        OmniaSettingsForm {
            if let addon {
                overview(addon)
                status(addon)
                catalogs(addon)
                about(addon)
            } else {
                Section {
                    ContentUnavailableView("Add-on Removed", systemImage: "puzzlepiece.extension")
                }
            }
        }
        .omniaNavigationTitle(addon?.displayName ?? "Add-on")
    }

    // MARK: Sections

    private func overview(_ addon: InstalledAddon) -> some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                AddonLogoView(url: addon.manifest.presentationLogoURL)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(addon.displayName).font(.headline)
                    Text("Version \(addon.manifest.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !addon.manifest.description.isEmpty {
                        Text(addon.manifest.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
            if !addon.isEnabled {
                Label("Turned off. Omnia doesn't send it any requests.", systemImage: "pause.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func status(_ addon: InstalledAddon) -> some View {
        let report = diagnostics.report(for: addon)
        let resources = AddonDiagnostics.Resource.allCases.filter { resource in
            resource.manifestName.map { name in addon.manifest.resources.contains { $0.name == name } } ?? true
        }
        return Section {
            ForEach(resources) { resource in
                statusRow(resource.title, status: report.resources[resource])
            }
            Button {
                Task { await check(addon) }
            } label: {
                HStack {
                    Label("Check Now", systemImage: "arrow.clockwise")
                    if isChecking {
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(isChecking || !addon.isEnabled)
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Status")
        } footer: {
            Text("What happened the last time Omnia asked this add-on for each kind of content since Omnia opened. Check Now reloads its manifest and its first catalog.")
        }
    }

    private func statusRow(_ title: String, status: AddonDiagnostics.Status?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            statusIcon(status)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(statusDetail(status))
                    .font(.caption)
                    .foregroundStyle(status?.isFailing == true ? .orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func statusIcon(_ status: AddonDiagnostics.Status?) -> some View {
        if status?.isFailing == true {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        } else if status?.lastSuccess != nil {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        }
    }

    private func statusDetail(_ status: AddonDiagnostics.Status?) -> String {
        if let status, status.isFailing, let failure = status.lastFailure {
            return "\(failure.message) \(Self.relative(failure.date).capitalizedFirst)."
        }
        if let success = status?.lastSuccess {
            return "Working, last answered \(Self.relative(success))."
        }
        return "Not asked yet since Omnia opened."
    }

    @ViewBuilder
    private func catalogs(_ addon: InstalledAddon) -> some View {
        let report = diagnostics.report(for: addon)
        let catalogs = addon.manifest.catalogs
        let failing = catalogs.compactMap { catalog in
            report.failingCatalogs[AddonDiagnostics.catalogKey(catalog)].map { (key: AddonDiagnostics.catalogKey(catalog), catalog: catalog, failure: $0) }
        }

        if !failing.isEmpty {
            Section("Catalogs With Errors") {
                ForEach(failing, id: \.key) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(catalogTitle(entry.catalog))
                        Text("\(entry.failure.message) \(Self.relative(entry.failure.date).capitalizedFirst).")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }

        Section {
            LabeledContent("Catalogs", value: "\(catalogs.count)")
            if !catalogs.isEmpty {
                DisclosureGroup("All Catalogs", isExpanded: $showsAllCatalogs) {
                    // Ids repeat across types ("top" for movies and series).
                    ForEach(catalogs, id: \.self) { catalog in
                        HStack {
                            Text(catalogTitle(catalog))
                            Spacer()
                            if !catalog.canLoadWithDefaults {
                                Text("Search only")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if catalog.showInHome == false || !catalog.canLoadWithoutExtra {
                                Text("Not on Home")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Catalogs")
        } footer: {
            Text("Catalogs marked Not on Home need a filter or are kept off Home by the add-on. They still open in Discover.")
        }
    }

    private func about(_ addon: InstalledAddon) -> some View {
        Section {
            // Only the host: the rest of the address can hold a private key.
            LabeledContent("Server", value: addon.manifestURL.host() ?? "Unknown")
            LabeledContent("Add-on ID", value: addon.manifest.id)
            LabeledContent("Provides", value: Self.uniqued(addon.manifest.resources.map(\.name)).sorted().joined(separator: ", "))
            if !addon.manifest.types.isEmpty {
                LabeledContent("Types", value: addon.manifest.types.joined(separator: ", "))
            }
            Button("Copy Link", systemImage: "doc.on.doc") { copyLink(addon.manifestURL) }
            if let url = AddonSettingsPresentation.configurationURL(from: addon.manifestURL) {
                Button("Configure", systemImage: "gearshape") { openURL(url) }
            }
        } header: {
            Text("About")
        }
    }

    // MARK: Actions

    private func check(_ addon: InstalledAddon) async {
        isChecking = true
        statusMessage = nil
        defer { isChecking = false }
        do {
            let manifest = try await StremioAddonClient.fetchManifest(from: addon.manifestURL)
            AddonDiagnostics.shared.recordSuccess(.manifest, addon: addon)
            if manifest.id == addon.manifest.id, manifest != addon.manifest {
                store.replaceAddon(id: addon.id, manifest: manifest, manifestURL: addon.manifestURL)
            }
        } catch {
            AddonDiagnostics.shared.recordFailure(.manifest, addon: addon, error: error)
        }
        // The first catalog that opens without input shows whether the add-on
        // answers content requests, not just its manifest.
        guard let current = store.installedAddons.first(where: { $0.id == addon.id }),
              let catalog = current.manifest.catalogs.first(where: \.canLoadWithDefaults)
        else { return }
        if let metas = try? await StremioAddonClient.fetchCatalog(from: current, catalog: catalog) {
            statusMessage = "\(catalogTitle(catalog)) answered with \(metas.count) \(metas.count == 1 ? "title" : "titles")."
        }
    }

    private func copyLink(_ url: URL) {
        OmniaPasteboard.copySensitive(url.absoluteString)
        statusMessage = "Add-on link copied."
    }

    // MARK: Helpers

    private func catalogTitle(_ catalog: AddonCatalog) -> String {
        let name = catalog.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = (name?.isEmpty == false ? name : nil) ?? catalog.id
        return "\(base) · \(AddonHomeCatalog.typeLabel(for: catalog.type))"
    }

    private static func relative(_ date: Date) -> String {
        guard Date.now.timeIntervalSince(date) >= 5 else { return "just now" }
        return date.formatted(.relative(presentation: .named))
    }

    private static func uniqued(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
