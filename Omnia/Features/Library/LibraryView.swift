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
    @Environment(\.displayPreferences) private var display
    @Environment(OmniaStore.self) private var store
    @State private var selectedKind: MediaItem.Kind?
    @AppStorage("library-sort") private var savedSortOrder = LibrarySortOrder.recentAdded.rawValue
    /// Library from a tracker's watchlist and progress instead of Omnia's,
    /// like Nuvio's library source switch.
    @State private var trackerLibrary = TrackerLibraryStore.shared

    private var tracker: TrackerKind? {
        trackerLibrary.effectiveSource(trackerLibrary.watchlistSource).tracker
    }

    private var sections: [LibrarySection] {
        LibraryCollectionPresentation.sections(
            snapshots: tracker.map(trackerSnapshots) ?? store.localMediaSnapshots,
            kind: selectedKind,
            sort: sortOrder
        )
    }

    /// A tracker's lists in the shape Omnia's own library has: paused
    /// titles under Continue Watching, the watchlist under My List.
    private func trackerSnapshots(_ kind: TrackerKind) -> [LocalMediaSnapshot] {
        let progress = trackerLibrary.items(.progress, from: kind).map {
            LocalMediaSnapshot(item: $0, isInWatchlist: false, savedAt: nil, lastPlayedAt: nil)
        }
        let watchlist = trackerLibrary.items(.watchlist, from: kind).map { item in
            var item = item
            item.progress = nil
            return LocalMediaSnapshot(item: item, isInWatchlist: true, savedAt: nil, lastPlayedAt: nil)
        }
        return progress + watchlist
    }

    private var sortOrder: LibrarySortOrder {
        LibrarySortOrder(rawValue: savedSortOrder) ?? .recentAdded
    }

    /// One grid: what's in progress, saved or watched, each title once.
    private var items: [MediaItem] {
        var seen = Set<String>()
        return sections.flatMap(\.items).filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = MediaBrowseMetrics.posterGridLayout(containerWidth: proxy.size.width, display: display)
            ScrollView {
                VStack(spacing: 18) {
                    #if os(macOS)
                    Text("My Library")
                        .font(.largeTitle.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, MediaBrowseMetrics.pageInset)
                    #endif
                    kindPicker
                    if let tracker {
                        TrackerSyncStatusLine(kind: tracker)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, MediaBrowseMetrics.pageInset)
                    }
                    if items.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity, minHeight: 360)
                    } else {
                        LazyVGrid(columns: layout.columns, alignment: .leading, spacing: 18) {
                            ForEach(items) { item in
                                MediaPoster(item: item, fillsAvailableWidth: true, showsInfoOnArtwork: true)
                            }
                        }
                        .padding(.horizontal, MediaBrowseMetrics.pageInset)
                    }
                }
                .padding(.vertical, 12)
            }
            .modifier(TopBarScrollReporting(destination: .library))
        }
        #if os(macOS)
        .omniaNavigationTitle("", screen: .library)
        #else
        .omniaNavigationTitle("My Library", screen: .library)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                libraryFilterMenu
            }
        }
        .navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
        .task(id: tracker) {
            guard let tracker else { return }
            trackerLibrary.syncIfNeeded(tracker, addons: store.installedAddons)
        }
    }

    private var kindPicker: some View {
        Picker("Show", selection: $selectedKind) {
            Text("All").tag(MediaItem.Kind?.none)
            Text("Movies").tag(MediaItem.Kind?.some(.movie))
            Text("Series").tag(MediaItem.Kind?.some(.series))
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 420)
        .padding(.horizontal, MediaBrowseMetrics.pageInset)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var emptyState: some View {
        if let tracker, trackerLibrary.state(tracker) == .syncing {
            OmniaLoadingRow("Reading \(tracker.shortTitle)…")
        } else if let tracker {
            ContentUnavailableView(
                "Nothing on \(tracker.shortTitle)",
                systemImage: "rectangle.stack",
                description: Text("Titles on your \(tracker.title) watchlist or in progress there show here.")
            )
        } else {
            ContentUnavailableView(
                "Your Library Is Empty",
                systemImage: "rectangle.stack",
                description: Text("Add a title, start watching, or mark something as watched to see it here.")
            )
        }
    }

    private var libraryFilterMenu: some View {
        Menu {
            if trackerLibrary.availableWatchlistSources.count > 1 {
                Picker("Source", selection: $trackerLibrary.watchlistSource) {
                    ForEach(trackerLibrary.availableWatchlistSources) { source in
                        Text(source.title).tag(source)
                    }
                }
                if let tracker {
                    Button("Sync \(tracker.shortTitle) Now", systemImage: "arrow.triangle.2.circlepath") {
                        trackerLibrary.sync(tracker, addons: store.installedAddons)
                    }
                    .disabled(trackerLibrary.state(tracker) == .syncing)
                }
                Divider()
            }

            Picker("Sort", selection: $savedSortOrder) {
                ForEach(LibrarySortOrder.allCases) { order in
                    Text(order.title).tag(order.rawValue)
                }
            }
        } label: {
            Label("Filter and Sort", systemImage: "line.3.horizontal.decrease.circle")
        }
        .help("Choose the Library's source and how it's sorted")
    }
}

#Preview {
    NavigationStack { LibraryView() }
        .environment(OmniaStore.preview)
        .environment(LiveMetadataStore.preview)
        .environment(SettingsPreferencesStore())
}
