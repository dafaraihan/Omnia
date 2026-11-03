//
//  MediaServerHomeRowView.swift
//  Omnia
//

import SwiftUI

/// One media server row on Home: a selected library, newest first, or the
/// server's Continue Watching. Like add-on rows, an empty row is left out
/// and a failed one stays visible with Retry.
struct MediaServerHomeRowView: View {
    @Environment(\.displayPreferences) private var display
    let row: MediaServerHomeRow
    let items: [MediaItem]
    let state: MediaServerStore.RowState?
    let retry: () -> Void

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if row.library == nil {
                    SectionHeader(title: row.title)
                } else {
                    SectionHeaderLink(title: row.title) {
                        MediaServerLibraryBrowseView(row: row)
                    }
                }
                ShelfScrollView(
                    items: items,
                    itemSpan: MediaBrowseMetrics.posterItemSpan(display),
                    accessibilityLabel: row.title
                ) { item in
                    MediaPoster(item: item)
                }
            }
        } else if state == .loading || state == nil {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: row.title)
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Loading \(row.title)")
            }
        } else if state == .failed {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: row.title)
                Text("\(row.serverName) didn't respond.")
                    .foregroundStyle(.secondary)
                Button("Retry", systemImage: "arrow.clockwise", action: retry)
            }
        }
    }
}

/// A whole server library, loading more at the bottom on its own.
struct MediaServerLibraryBrowseView: View {
    @Environment(\.displayPreferences) private var display
    let row: MediaServerHomeRow

    @State private var servers = MediaServerStore.shared
    @State private var items: [MediaItem] = []
    @State private var hasReachedEnd = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var title: String { row.library?.name ?? row.title }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if isLoading && items.isEmpty {
                    OmniaLoadingRow("Loading \(title)…")
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else if let errorMessage, items.isEmpty {
                    ContentUnavailableView("Library Unavailable", systemImage: "server.rack", description: Text(errorMessage))
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

                    if !hasReachedEnd {
                        Color.clear
                            .frame(height: 1)
                            .task(id: items.count) {
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
        .task(id: row.key) {
            items = []
            hasReachedEnd = false
            errorMessage = nil
            isLoading = false
            await loadNextPage()
        }
        .navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
    }

    private func loadNextPage() async {
        guard !isLoading, !hasReachedEnd else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await servers.page(for: row, start: items.count)
            guard !Task.isCancelled else { return }
            let existing = Set(items.map(\.id))
            let fresh = page.items.filter { !existing.contains($0.id) }
            items.append(contentsOf: fresh)
            if !page.hasMore || fresh.isEmpty { hasReachedEnd = true }
        } catch is CancellationError {
            return
        } catch {
            if items.isEmpty {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(row.serverName) didn't respond."
            }
            hasReachedEnd = true
        }
    }
}
