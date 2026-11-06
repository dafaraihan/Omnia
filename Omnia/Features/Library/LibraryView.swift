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
            // Only what's saved to the library. Continue Watching has its own row on Home.
            snapshots: (tracker.map(trackerSnapshots) ?? store.localMediaSnapshots).filter(\.isInWatchlist),
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

    /// One grid, each title once, even when two sources list it.
    private var items: [MediaItem] {
        var kept: [MediaItem] = []
        for item in sections.flatMap(\.items) where !kept.contains(where: { $0.id == item.id || $0.isSameTitle(as: item) }) {
            kept.append(item)
        }
        return kept
    }

    /// Columns that share the width evenly, so a row never ends in a gap.
    private func gridColumns(width: CGFloat) -> [GridItem] {
        let spacing = MediaBrowseMetrics.gridSpacing
        let available = max(0, width - MediaBrowseMetrics.pageInset * 2)
        let minimum = display.landscapePosters ? display.landscapePosterCardWidth * 0.85 : display.posterCardWidth * 0.85
        let count = max(OmniaDevice.isPhone && !display.landscapePosters ? 3 : 2, Int((available + spacing) / (minimum + spacing)))
        return Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: count)
    }

    var body: some View {
        GeometryReader { proxy in
            let columns = gridColumns(width: proxy.size.width)
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
                        LazyVGrid(columns: columns, alignment: .center, spacing: 18) {
                            ForEach(items) { item in
                                MediaPoster(item: item, fillsAvailableWidth: true, showsTitleOnly: true)
                                    .modifier(OmniaScrollEdgeEffect(axis: .vertical))
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
                OmniaToolbarSymbol {
                libraryFilterMenu
                }
            }
        }
        .navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
        .task(id: tracker) {
            guard let tracker else { return }
            trackerLibrary.syncIfNeeded(tracker, addons: store.installedAddons)
        }
    }

    private var kindPicker: some View {
        OmniaSegmentedControl(
            selection: $selectedKind,
            options: [(nil, "All"), (.movie, "Movies"), (.series, "Series")]
        )
        .frame(maxWidth: OmniaDevice.isPhone ? .infinity : 420)
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
