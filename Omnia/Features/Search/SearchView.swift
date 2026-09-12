//
//  SearchView.swift
//  Omnia
//

import SwiftUI

enum SearchViewPresentation {
    case fullPage
    #if os(macOS)
    case popover
    #endif
}

struct SearchView: View {
    @Environment(OmniaStore.self) private var store
    @Environment(LiveMetadataStore.self) private var metadata
    @State private var query = ""
    @State private var addonResults: [MediaItem] = []
    @State private var isSearchingAddons = false
    #if os(macOS)
    @FocusState private var isPopoverSearchFocused: Bool
    #endif

    let presentation: SearchViewPresentation

    init(presentation: SearchViewPresentation = .fullPage) {
        self.presentation = presentation
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var results: [MediaItem] {
        unique(metadata.searchResults + addonResults)
    }

    var body: some View {
        presentedContent
        .task(id: query) {
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 2 else {
                metadata.searchResults = []
                addonResults = []
                isSearchingAddons = false
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            isSearchingAddons = true
            async let metadataSearch: Void = metadata.search(query)
            let addonMatches = await StremioAddonClient.searchCatalogs(
                addons: store.installedAddons,
                query: text
            )
            await metadataSearch
            guard !Task.isCancelled,
                  text == query.trimmingCharacters(in: .whitespacesAndNewlines)
            else { return }
            addonResults = unique(addonMatches.map(\.item))
            isSearchingAddons = false
        }
        .navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
    }

    @ViewBuilder
    private var presentedContent: some View {
        switch presentation {
        case .fullPage:
            searchContent
                .omniaNavigationTitle("Search", screen: .search)
                .searchable(text: $query, prompt: "Titles, people, or genres")
                .searchSuggestions {
                    ForEach(store.library.prefix(3)) { item in
                        Text(item.title).searchCompletion(item.title)
                    }
                }
        #if os(macOS)
        case .popover:
            VStack(spacing: 0) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    TextField("Titles, people, or genres", text: $query)
                        .textFieldStyle(.plain)
                        .focused($isPopoverSearchFocused)

                    if !query.isEmpty {
                        Button("Clear Search", systemImage: "xmark.circle.fill") {
                            query = ""
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .labelStyle(.iconOnly)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(.regularMaterial, in: Capsule())
                .padding(16)

                Divider()

                searchContent
            }
            .frame(width: 760, height: 620)
            .background(.black.opacity(0.18))
            .onAppear {
                isPopoverSearchFocused = true
            }
        #endif
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        Group {
            if trimmedQuery.count < 2 {
                SearchBrowseDirectoryView(genres: metadata.movieGenres)
            } else if metadata.isSearching || isSearchingAddons {
                ContentUnavailableView("Searching Omnia", systemImage: "magnifyingglass")
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                GeometryReader { proxy in
                    let layout = MediaBrowseMetrics.posterGridLayout(containerWidth: proxy.size.width)

                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(
                            columns: layout.columns,
                            alignment: .leading,
                            spacing: 18
                        ) {
                            ForEach(results) { item in
                                MediaPoster(item: item, fillsAvailableWidth: true)
                            }
                        }
                        .padding(.horizontal, MediaBrowseMetrics.pageInset)
                        .padding(.vertical, 24)
                    }
                }
            }
        }
    }

    private func unique(_ items: [MediaItem]) -> [MediaItem] {
        var seen = Set<String>()
        return items.filter { item in
            let identity = item.externalIDs["imdb"] ?? item.metadataProviderID ?? item.id
            return seen.insert(identity).inserted
        }
    }
}

#Preview {
    NavigationStack { SearchView() }
        .environment(OmniaStore.preview)
        .environment(LiveMetadataStore.preview)
}
