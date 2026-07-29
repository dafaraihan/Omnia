//
//  LibraryView.swift
//  Omnia
//

import SwiftUI

enum LibrarySortOrder: String, CaseIterable, Identifiable {
    case recentAdded
    case title
    case releaseYear
    case inProgress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentAdded: "Recently Added"
        case .title: "Title"
        case .releaseYear: "Release Year"
        case .inProgress: "In Progress"
        }
    }
}

struct LibraryView: View {
    @Environment(OmniaStore.self) private var store
    @State private var selectedKind: MediaItem.Kind?
    @AppStorage("library-sort") private var savedSortOrder = LibrarySortOrder.recentAdded.rawValue

    private var items: [MediaItem] {
        let filtered = selectedKind.map { kind in store.library.filter { $0.kind == kind } } ?? store.library
        return switch LibrarySortOrder(rawValue: savedSortOrder) ?? .recentAdded {
        case .recentAdded:
            filtered
        case .title:
            filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .releaseYear:
            filtered.sorted { $0.year > $1.year }
        case .inProgress:
            filtered.sorted { lhs, rhs in
                switch (lhs.progress, rhs.progress) {
                case (.some, .none): true
                case (.none, .some): false
                default: lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
            }
        }
    }

    #if os(iOS)
    private let columns = [
        GridItem(.flexible(minimum: 0), spacing: 16),
        GridItem(.flexible(minimum: 0), spacing: 16)
    ]
    #else
    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 190), spacing: 16)]
    #endif

    var body: some View {
        ScrollView {
            if items.isEmpty {
                ContentUnavailableView(
                    "Your Library Is Empty",
                    systemImage: "rectangle.stack",
                    description: Text("Save a title from Discover or Search to keep it here.")
                )
                .frame(maxWidth: .infinity, minHeight: 360)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                    ForEach(items) { item in
                        MediaPoster(item: item, fillsAvailableWidth: true)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Kind", selection: $selectedKind) {
                        Text("All Media").tag(MediaItem.Kind?.none)
                        ForEach(MediaItem.Kind.allCases, id: \.self) { kind in
                            Text(kind.rawValue).tag(Optional(kind))
                        }
                    }

                    Picker("Sort", selection: $savedSortOrder) {
                        ForEach(LibrarySortOrder.allCases) { order in
                            Text(order.title).tag(order.rawValue)
                        }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
    }
}

#Preview {
    NavigationStack { LibraryView() }
        .environment(OmniaStore.preview)
        .environment(LiveMetadataStore.preview)
}
