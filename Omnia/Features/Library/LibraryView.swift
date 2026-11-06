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

    /// Saved titles, each once. One that's in progress keeps its progress bar.
    private var items: [MediaItem] {
        LibraryCollectionPresentation.items(
            snapshots: tracker.map(trackerSnapshots) ?? store.localMediaSnapshots,
            kind: selectedKind,
            sort: sortOrder
        )
    }

    /// A tracker's watchlist, with progress from its paused titles.
    private func trackerSnapshots(_ kind: TrackerKind) -> [LocalMediaSnapshot] {
        let progress = trackerLibrary.items(.progress, from: kind)
        return trackerLibrary.items(.watchlist, from: kind).map { item in
            var item = item
            let paused = progress.first { $0.isSameTitle(as: item) }
            item.progress = paused?.progress
            item.positionSeconds = paused?.positionSeconds
            item.durationSeconds = paused?.durationSeconds
            return LocalMediaSnapshot(item: item, isInWatchlist: true, savedAt: nil, lastPlayedAt: nil)
        }
    }

    private var sortOrder: LibrarySortOrder {
        LibrarySortOrder(rawValue: savedSortOrder) ?? .recentAdded
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
        .omniaNavigationTitle("My Library", screen: .library)
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
        // Full width on iPhone, centred on iPad and Mac.
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
                description: Text("Titles you add to My List show here.")
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
