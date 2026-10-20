//
//  AddonCatalogBrowseView.swift
//  Omnia
//

import SwiftUI

/// A manifest-driven catalog browser. It only sends extras the add-on
/// advertised, including the documented `search` and `skip` controls.
struct AddonCatalogBrowseView: View {
    @Environment(\.displayPreferences) private var display
    let addon: InstalledAddon
    let catalog: AddonCatalog

    @State private var items: [MediaItem] = []
    @State private var selectedExtras: [String: String] = [:]
    @State private var search = ""
    /// The next page starts where the last one ended, counting every title
    /// the add-on sent, as Stremio and Nuvio do.
    @State private var nextSkip = 0
    @State private var hasReachedEnd = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var title: String { catalog.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? catalog.id }
    private var supportsSearch: Bool { catalog.supportsSearch }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
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
                        columns: MediaBrowseMetrics.posterGridColumns(display),
                        alignment: .leading,
                        spacing: MediaBrowseMetrics.gridRowSpacing
                    ) {
                        ForEach(items) { item in
                            MediaPoster(item: item, fillsAvailableWidth: true)
                        }
                    }

                    // More titles load on their own at the bottom. The
                    // marker stays put while a page loads: swapping it for
                    // the spinner cancelled its task, and with it the request.
                    if !hasReachedEnd {
                        Color.clear
                            .frame(height: 1)
                            .task(id: items.count) {
                                // Not tied to the marker, so scrolling away
                                // mid-request doesn't cancel the page.
                                await Task { await loadNextPage() }.value
                            }
                    }
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    }
                }
            }
            .padding(.horizontal, MediaBrowseMetrics.pageInset)
            .padding(.vertical, 24)
        }
        .omniaNavigationTitle(title)
        .modifier(CatalogSearchModifier(isEnabled: supportsSearch, text: $search, prompt: "Search \(title)"))
        .toolbar {
            if !filterExtras.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    filterMenu
                }
            }
        }
        .task(id: requestKey) {
            items = []
            nextSkip = 0
            hasReachedEnd = false
            errorMessage = nil
            isLoading = false
            await loadNextPage()
        }
        .navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
    }

    private var filterExtras: [AddonCatalogExtra] {
        (catalog.extra ?? []).filter { $0.name != "search" && $0.name != "skip" && !($0.options ?? []).isEmpty }
    }

    /// The add-on's own filters, in a toolbar menu like Discover's.
    private var filterMenu: some View {
        Menu {
            // In a menu, each Picker is already its own submenu.
            ForEach(filterExtras) { extra in
                Picker(selection: filterBinding(for: extra)) {
                    // A required filter has no "All": the add-on only
                    // answers with one chosen.
                    if extra.isRequired != true { Text("All").tag("") }
                    ForEach(extra.options ?? [], id: \.self) { option in
                        Text(option).tag(option)
                    }
                } label: {
                    Label(extra.name.capitalized, systemImage: extra.name == "genre" ? "theatermasks" : "line.3.horizontal.decrease")
                }
                .pickerStyle(.menu)
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
        .help("Filter \(title)")
    }

    private func filterBinding(for extra: AddonCatalogExtra) -> Binding<String> {
        Binding(
            get: {
                selectedExtras[extra.name]
                    ?? (extra.isRequired == true ? extra.options?.first ?? "" : "")
            },
            set: { value in
                if value.isEmpty { selectedExtras.removeValue(forKey: extra.name) }
                else { selectedExtras[extra.name] = value }
            }
        )
    }

    private var requestKey: String {
        "\(addon.manifestURL.absoluteString)|\(catalog.id)|\(supportsSearch ? search : "")|\(selectedExtras.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&"))"
    }

    private func loadNextPage() async {
        guard !isLoading, !hasReachedEnd else { return }
        let key = requestKey
        isLoading = true
        defer { if key == requestKey { isLoading = false } }
        var extras = selectedExtras
        if supportsSearch, let value = search.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
            extras["search"] = value
        }
        let start = nextSkip
        if start > 0 { extras["skip"] = String(start) }
        do {
            let metas = try await StremioAddonClient.fetchCatalog(from: addon, catalog: catalog, extra: extras)
            // A filter or search changed while this page was on its way.
            guard !Task.isCancelled, key == requestKey else { return }
            let existing = Set(items.map(\.id))
            let fresh = metas.compactMap { $0.mediaItem(addon: addon) }.filter { !existing.contains($0.id) }
            // An add-on that doesn't page sends the first page again.
            if metas.isEmpty || fresh.isEmpty {
                hasReachedEnd = true
            } else {
                items.append(contentsOf: fresh)
                nextSkip = start + metas.count
            }
        } catch is CancellationError {
            return
        } catch {
            guard key == requestKey else { return }
            if items.isEmpty { errorMessage = "This add-on did not return a usable catalog response." }
            hasReachedEnd = true
        }
    }

}

/// A search field only for catalogs that declare `search`; an empty one
/// sat in the toolbar of every other catalog.
private struct CatalogSearchModifier: ViewModifier {
    let isEnabled: Bool
    @Binding var text: String
    let prompt: String

    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(text: $text, prompt: prompt)
        } else {
            content
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
