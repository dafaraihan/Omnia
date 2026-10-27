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
    @State private var sourcePlaybackItem: MediaItem?
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

    var body: some View {
        ScrollView {
            if let tracker {
                TrackerSyncStatusLine(kind: tracker)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, MediaBrowseMetrics.pageInset)
                    .padding(.top, 12)
            }
            if sections.allSatisfy(\.items.isEmpty), let tracker, trackerLibrary.state(tracker) == .syncing {
                ProgressView("Reading \(tracker.shortTitle)…")
                    .frame(maxWidth: .infinity, minHeight: 360)
            } else if sections.allSatisfy(\.items.isEmpty), let tracker {
                ContentUnavailableView(
                    "Nothing on \(tracker.shortTitle)",
                    systemImage: "rectangle.stack",
                    description: Text("Titles on your \(tracker.title) watchlist or in progress there show here.")
                )
                .frame(maxWidth: .infinity, minHeight: 360)
            } else if sections.allSatisfy(\.items.isEmpty) {
                ContentUnavailableView(
                    "Your Library Is Empty",
                    systemImage: "rectangle.stack",
                    description: Text("Add a title, start watching, or mark something as watched to see it here.")
                )
                .frame(maxWidth: .infinity, minHeight: 360)
            } else {
                LazyVStack(alignment: .leading, spacing: 34) {
                    ForEach(sections) { section in
                        if !section.items.isEmpty {
                            libraryShelf(section)
                        }
                    }
                }
                .padding(.horizontal, MediaBrowseMetrics.pageInset)
                .padding(.vertical, 24)
            }
        }
        .omniaNavigationTitle("Library", screen: .library)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                libraryFilterMenu
            }
        }
        .navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
        .omniaStreamsPage(isPresented: showsSourcePicker) {
            if let sourcePlaybackItem {
                PlaybackSourceSheet(
                    item: sourcePlaybackItem,
                    episode: sourcePlaybackItem.resumeEpisode,
                    resumeAt: sourcePlaybackItem.positionSeconds,
                    onClose: { self.sourcePlaybackItem = nil }
                )
            }
        }
        .task(id: tracker) {
            guard let tracker else { return }
            trackerLibrary.syncIfNeeded(tracker, addons: store.installedAddons)
        }
    }

    @ViewBuilder
    private func libraryShelf(_ section: LibrarySection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderLink(title: section.kind.title) {
                LibrarySectionGridView(kind: section.kind, items: section.items)
            }

            switch section.kind {
            case .continueWatching:
                ShelfScrollView(
                    items: section.items,
                    itemSpan: ContinueWatchingCard.itemSpan(for: display),
                    accessibilityLabel: section.kind.title
                ) { item in
                    ContinueWatchingCard(item: item) {
                        sourcePlaybackItem = item
                    }
                }
            case .myList, .rewatch:
                ShelfScrollView(
                    items: section.items,
                    itemSpan: MediaBrowseMetrics.posterItemSpan(display),
                    accessibilityLabel: section.kind.title
                ) { item in
                    MediaPoster(item: item)
                }
            }
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
            Label("Filter and Sort", systemImage: "line.3.horizontal.decrease.circle")
        }
        .help("Choose the Library's source, and filter and sort every shelf")
    }

    private var showsSourcePicker: Binding<Bool> {
        Binding(
            get: { sourcePlaybackItem != nil },
            set: { if !$0 { sourcePlaybackItem = nil } }
        )
    }
}

private struct LibrarySectionGridView: View {
    @Environment(\.displayPreferences) private var display
    let kind: LibrarySectionKind
    let items: [MediaItem]
    @State private var sourcePlaybackItem: MediaItem?

    var body: some View {
        GeometryReader { proxy in
            let layout = kind == .continueWatching && display.continueWatchingStyle.isLandscape
                ? MediaBrowseMetrics.landscapeGridLayout(containerWidth: proxy.size.width)
                : MediaBrowseMetrics.posterGridLayout(containerWidth: proxy.size.width, display: display)
            ScrollView {
                LazyVGrid(columns: layout.columns, alignment: .leading, spacing: 18) {
                    ForEach(items) { item in
                        if kind == .continueWatching {
                            ContinueWatchingCard(item: item) {
                                sourcePlaybackItem = item
                            }
                        } else {
                            MediaPoster(item: item, fillsAvailableWidth: true)
                        }
                    }
                }
                .padding(.horizontal, MediaBrowseMetrics.pageInset)
                .padding(.vertical, 24)
            }
        }
        .omniaNavigationTitle(kind.title)
        .navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
        .omniaStreamsPage(isPresented: showsSourcePicker) {
            if let sourcePlaybackItem {
                PlaybackSourceSheet(
                    item: sourcePlaybackItem,
                    episode: sourcePlaybackItem.resumeEpisode,
                    resumeAt: sourcePlaybackItem.positionSeconds,
                    onClose: { self.sourcePlaybackItem = nil }
                )
            }
        }
    }

    private var showsSourcePicker: Binding<Bool> {
        Binding(
            get: { sourcePlaybackItem != nil },
            set: { if !$0 { sourcePlaybackItem = nil } }
        )
    }
}

#Preview {
    NavigationStack { LibraryView() }
        .environment(OmniaStore.preview)
        .environment(LiveMetadataStore.preview)
        .environment(SettingsPreferencesStore())
}
