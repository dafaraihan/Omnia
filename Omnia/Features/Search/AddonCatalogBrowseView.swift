//
//  AddonCatalogBrowseView.swift
//  Omnia
//

import SwiftUI

/// A manifest-driven catalog browser. It only sends extras the add-on
/// advertised, including the documented `search` and `skip` controls.
struct AddonCatalogBrowseView: View {
    let addon: InstalledAddon
    let catalog: AddonCatalog

    @State private var items: [MediaItem] = []
    @State private var selectedExtras: [String: String] = [:]
    @State private var search = ""
    @State private var page = 0
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var title: String { catalog.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? catalog.id }
    private var supportsSearch: Bool { catalog.supportsSearch }
    private var supportsPagination: Bool { catalog.extra?.contains { $0.name == "skip" } == true }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if !filterExtras.isEmpty { filterControls }

                if isLoading && items.isEmpty {
                    ProgressView("Loading \(title)…")
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else if let errorMessage, items.isEmpty {
                    ContentUnavailableView("Catalog Unavailable", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else if items.isEmpty {
                    ContentUnavailableView("No Titles Found", systemImage: "film")
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    LazyVGrid(
                        columns: MediaBrowseMetrics.posterGridColumns,
                        alignment: .leading,
                        spacing: MediaBrowseMetrics.gridRowSpacing
                    ) {
                        ForEach(items) { item in
                            MediaPoster(item: item, fillsAvailableWidth: true)
                        }
                    }

                    if supportsPagination {
                        HStack {
                            Button("Previous") {
                                page -= 1
                                Task { await load() }
                            }
                            .disabled(page == 0 || isLoading)
                            Spacer()
                            Text("Page \(page + 1)")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Next") {
                                page += 1
                                Task { await load() }
                            }
                            .disabled(isLoading || items.isEmpty)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.horizontal, MediaBrowseMetrics.pageInset)
            .padding(.vertical, 24)
        }
        .omniaNavigationTitle(title)
        .searchable(text: $search, prompt: supportsSearch ? "Search \(title)" : "")
        .onChange(of: search) { _, _ in
            guard supportsSearch else { return }
            page = 0
        }
        .task(id: requestKey) { await load() }
        .navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
    }

    private var filterExtras: [AddonCatalogExtra] {
        (catalog.extra ?? []).filter { $0.name != "search" && $0.name != "skip" && !($0.options ?? []).isEmpty }
    }

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Filter")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(filterExtras) { extra in
                        Picker(extra.name.capitalized, selection: filterBinding(for: extra.name)) {
                            Text("All").tag("")
                            ForEach(extra.options ?? [], id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
        }
    }

    private func filterBinding(for name: String) -> Binding<String> {
        Binding(
            get: { selectedExtras[name] ?? "" },
            set: { value in
                if value.isEmpty { selectedExtras.removeValue(forKey: name) }
                else { selectedExtras[name] = value }
                page = 0
            }
        )
    }

    private var requestKey: String {
        "\(addon.manifestURL.absoluteString)|\(catalog.id)|\(search)|\(page)|\(selectedExtras.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&"))"
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        var extras = selectedExtras
        if supportsSearch, let value = search.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
            extras["search"] = value
        }
        if supportsPagination { extras["skip"] = String(page * 50) }
        do {
            let metas = try await StremioAddonClient.fetchCatalog(from: addon, catalog: catalog, extra: extras)
            guard !Task.isCancelled else { return }
            items = metas.compactMap { $0.mediaItem(addon: addon) }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "This add-on did not return a usable catalog response."
            items = []
        }
        isLoading = false
    }

}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
