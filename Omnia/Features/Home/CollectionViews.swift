//
//  CollectionViews.swift
//  Omnia
//

import ImageIO
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// A collection on Home: its title over a row of folder tiles.
struct CollectionHomeRow: View {
    let collection: HomeCollection
    @Environment(\.displayPreferences) private var display

    var body: some View {
        if !collection.folders.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: collection.title)
                ShelfScrollView(
                    items: collection.folders,
                    itemSpan: CollectionFolderTile.width(for: tileShape, display: display) + MediaBrowseMetrics.shelfSpacing,
                    accessibilityLabel: collection.title
                ) { folder in
                    // Pushed by value, like titles, so a title opened inside
                    // the folder lands on top of it instead of underneath.
                    NavigationLink(value: CollectionFolderRoute(collection: collection, folder: folder)) {
                        CollectionFolderTile(folder: folder)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Rows keep one tile size, taken from the first folder.
    private var tileShape: HomeCollectionFolder.TileShape {
        collection.folders.first?.tileShape ?? .poster
    }
}

/// Opens a collection folder through the navigation path.
nonisolated struct CollectionFolderRoute: Hashable, Sendable {
    let collection: HomeCollection
    let folder: HomeCollectionFolder
}

/// A folder's cover. Xperience covers already carry the service or genre
/// artwork, so the title is drawn only when the folder asks for it or when
/// there's no cover image.
struct CollectionFolderTile: View {
    @Environment(\.displayPreferences) private var display
    let folder: HomeCollectionFolder
    @State private var isHovered = false

    /// The folder's shape and size after Settings › Layout › Collections ›
    /// Card Style.
    static func width(for folderShape: HomeCollectionFolder.TileShape, display: DisplayPreferences) -> CGFloat {
        let card = display.collectionCard
        let shape = card.shape.resolved(folderShape, landscapePosters: display.landscapePosters)
        let portrait = card.size == .matchPosters ? display.posterCardWidth : PosterWidthPreset.standard.width
        let base: CGFloat = switch shape {
        case .poster: portrait
        case .square: portrait * 1.25
        case .landscape, .wide:
            card.size == .matchPosters ? display.landscapePosterCardWidth : MediaBrowseMetrics.landscapeCardWidth
        }
        return (base * card.size.scale).rounded()
    }

    static func height(for folderShape: HomeCollectionFolder.TileShape, display: DisplayPreferences) -> CGFloat {
        let shape = display.collectionCard.shape.resolved(folderShape, landscapePosters: display.landscapePosters)
        return width(for: folderShape, display: display) / CGFloat(shape.aspectRatio)
    }

    #if os(iOS)
    @State private var isOnScreen = false
    @State private var animatedCovers = AnimatedCoverLimiter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PlaybackSession.self) private var playback
    #endif

    private var cornerRadius: CGFloat { display.collectionCard.corners.radius(for: display) }

    private var showsTitle: Bool {
        switch display.collectionCard.titles {
        case .automatic: !folder.hideTitle || folder.coverImageUrl == nil
        case .always: true
        case .never: folder.coverImageUrl == nil
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            fallback

            if let cover = folder.coverImageUrl {
                RemoteArtworkImage(url: cover)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // The animated cover plays over the still one: while the pointer
            // is on the tile, or on touch screens while it's on screen. It
            // loads ahead, so it starts at once; without a still cover its
            // first frame stays visible.
            if folder.focusGifEnabled, let animated = folder.focusGifUrl {
                AnimatedCoverImage(url: animated, isPlaying: playsAnimatedCover, staysDecoded: folder.coverImageUrl == nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(playsAnimatedCover || folder.coverImageUrl == nil ? 1 : 0)
            }

            if showsTitle {
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                Text(folder.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(12)
            }
        }
        .frame(width: Self.width(for: folder.tileShape, display: display), height: Self.height(for: folder.tileShape, display: display))
        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        // Settings › Appearance › Poster Cards draws the hover edge and lift.
        .cardDepth(.collections, cornerRadius: cornerRadius)
        .onHover { isHovered = $0 }
        #if os(iOS)
        .onScrollVisibilityChange(threshold: 0.6) { isOnScreen = $0 }
        .onChange(of: wantsAnimatedCover, initial: true) { _, wants in
            if wants { animatedCovers.request(folder.id) } else { animatedCovers.release(folder.id) }
        }
        .onDisappear { animatedCovers.release(folder.id) }
        #endif
        .contentShape(.rect(cornerRadius: cornerRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(folder.title)
        .accessibilityAddTraits(.isButton)
    }

    private var playsAnimatedCover: Bool {
        #if os(iOS)
        animatedCovers.playing.contains(folder.id)
        #else
        isHovered
        #endif
    }

    #if os(iOS)
    /// Motion stops for Reduce Motion, Low Power Mode, and whenever the tile
    /// can't be seen, such as behind the player.
    private var wantsAnimatedCover: Bool {
        folder.focusGifEnabled && folder.focusGifUrl != nil && isOnScreen
            && !reduceMotion && scenePhase == .active && !playback.isPresentingPlayer
            && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }
    #endif

    private var fallback: some View {
        ZStack {
            LinearGradient(colors: MediaItem.placeholderArtworkColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            if let emoji = folder.coverEmoji {
                Text(emoji)
                    .font(.system(size: 44))
            } else {
                Image(systemName: "folder.fill")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

/// A folder's page: its backdrop and logo, then its catalogs as tabs (with
/// an All tab that mixes them) or, for collections set to Rows, one row per
/// catalog.
struct CollectionFolderView: View {
    @Environment(\.displayPreferences) private var display
    let collection: HomeCollection
    let folder: HomeCollectionFolder

    @Environment(OmniaStore.self) private var store
    @State private var sections: [FolderSection] = []
    @State private var selectedTab = FolderSection.allID
    @State private var filters = DiscoverFilterState()
    @State private var isLoading = false
    /// The add-on catalog behind each section, for loading more titles.
    @State private var targets: [String: (source: HomeCollectionSource, target: HomeCollectionSourceResolver.Resolved)] = [:]

    struct FolderSection: Identifiable, Equatable {
        static let allID = "all"

        enum LoadState: Equatable {
            case loading
            case loaded([MediaItem])
            case failed
            case unavailable
        }

        let id: String
        let title: String
        var state: LoadState
        /// Where the next page starts: every title the add-on has sent so far.
        var nextSkip = 0
        var hasMore = false
        var isLoadingMore = false

        var items: [MediaItem] {
            if case let .loaded(items) = state { return items }
            return []
        }
    }

    private var allItems: [MediaItem] {
        var seen = Set<String>()
        // Interleave the catalogs so All doesn't open with one source's
        // whole list.
        let lists = sections.map(\.items)
        let longest = lists.map(\.count).max() ?? 0
        var merged: [MediaItem] = []
        for index in 0..<longest {
            for list in lists where index < list.count {
                let item = list[index]
                let key = item.externalIDs["imdb"] ?? item.id
                if seen.insert(key).inserted { merged.append(item) }
            }
        }
        return merged
    }

    struct FolderTab: Identifiable, Equatable {
        let id: String
        let title: String
    }

    /// Settings › Layout › Collections › Cards in Folders. By default titles
    /// keep the imported portrait posters, whatever shape the folder's tile is.
    private var cardDisplay: DisplayPreferences {
        var cardDisplay = display
        cardDisplay.landscapePosters = display.collectionCard.folderCards
            .usesLandscape(posterStyleIsLandscape: display.landscapePosters)
        return cardDisplay
    }

    private var tabs: [FolderTab] {
        let sourceTabs = sections.filter { $0.state != .unavailable }.map { FolderTab(id: $0.id, title: $0.title) }
        let allTab = collection.showAllTab && sourceTabs.count > 1 ? [FolderTab(id: FolderSection.allID, title: "All")] : []
        return allTab + sourceTabs
    }

    var body: some View {
        ScrollView {
            // Lazy, so the marker at the end of the grid only appears, and
            // loads the next page, when you reach the bottom.
            LazyVStack(alignment: .leading, spacing: 24) {
                header

                if sections.allSatisfy({ $0.state == .unavailable }) && !sections.isEmpty {
                    ContentUnavailableView(
                        "Catalogs Unavailable",
                        systemImage: "puzzlepiece.extension",
                        description: Text(unavailableReason)
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else if collection.showsSourcesAsRows {
                    ForEach(sections.filter { $0.state != .unavailable }) { section in
                        sourceRow(section)
                    }
                } else {
                    tabContent
                }
            }
            .padding(.horizontal, MediaBrowseMetrics.pageInset)
            .padding(.bottom, 32)
        }
        #if os(macOS)
        // Home's hero is drawn behind the whole window; a folder page covers
        // it so only the folder's own artwork shows.
        .background(OmniaPageBackground().ignoresSafeArea())
        #endif
        .omniaNavigationTitle(folder.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                filterMenu
            }
        }
        .task(id: loadKey) { await load() }
    }

    // MARK: Header

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(.quaternary)
            if let backdrop = folder.heroBackdropUrl ?? folder.coverImageUrl {
                RemoteArtworkImage(url: backdrop)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 6) {
                if let logo = folder.titleLogoUrl {
                    CachedArtworkImage(url: logo, size: CGSize(width: 320, height: 90), contentMode: .fit) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFit()
                        } else {
                            headerTitle
                        }
                    }
                    .frame(maxWidth: 320, maxHeight: 90, alignment: .bottomLeading)
                } else {
                    headerTitle
                }
                Text(collection.title)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(24)
        }
        .frame(height: 280)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: 20, style: .continuous))
        .padding(.top, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(folder.title), \(collection.title)")
    }

    private var headerTitle: some View {
        Text(folder.title)
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(.white)
    }

    // MARK: Filter

    /// The folder's catalogs, genres, kinds and order, in a toolbar menu
    /// built like Discover's.
    private var filterMenu: some View {
        Menu {
            if !collection.showsSourcesAsRows && tabs.count > 1 {
                // In a menu, a Picker is already its own submenu.
                Picker(selection: $selectedTab) {
                    ForEach(tabs) { tab in
                        Text(tab.title).tag(tab.id)
                    }
                } label: {
                    Label("Catalogs", systemImage: "rectangle.stack")
                }
                .pickerStyle(.menu)
            }
            Picker(selection: $filters.genre) {
                Text("All Genres").tag(String?.none)
                ForEach(availableGenres, id: \.self) { genre in
                    Text(genre).tag(Optional(genre))
                }
            } label: {
                Label("Genre", systemImage: "theatermasks")
            }
            .pickerStyle(.menu)
            Picker(selection: $filters.kind) {
                Text("All Kinds").tag(MediaItem.Kind?.none)
                Text("Movies").tag(Optional(MediaItem.Kind.movie))
                Text("Series").tag(Optional(MediaItem.Kind.series))
            } label: {
                Label("Kind", systemImage: "film.stack")
            }
            .pickerStyle(.menu)
            Menu("Sort", systemImage: "arrow.up.arrow.down") {
                Picker("Release Period", selection: $filters.releasePeriod) {
                    ForEach(DiscoverReleasePeriod.allCases) { period in
                        Text(period.title).tag(period)
                    }
                }
                .pickerStyle(.inline)
                if filters.releasePeriod == .chooseYear {
                    Picker("Year", selection: $filters.selectedYear) {
                        Text("Any Year").tag(Int?.none)
                        ForEach(availableYears, id: \.self) { year in
                            Text(String(year)).tag(Optional(year))
                        }
                    }
                    .pickerStyle(.menu)
                }
                Divider()
                Picker("Order", selection: $filters.sort) {
                    ForEach(DiscoverDateSort.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
                .pickerStyle(.inline)
            }
        } label: {
            Label("Filter and Sort", systemImage: "line.3.horizontal.decrease.circle")
        }
        .help("Filter and sort \(folder.title)")
    }

    private var loadedItems: [MediaItem] { sections.flatMap(\.items) }

    private var availableGenres: [String] {
        Set(loadedItems.flatMap(\.genres)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var availableYears: [Int] {
        Set(loadedItems.compactMap { Int($0.year) }).sorted(by: >)
    }

    @ViewBuilder
    private var tabContent: some View {
        if selectedTab == FolderSection.allID {
            if allItems.isEmpty {
                loadingOrEmpty(
                    isLoading: sections.contains { $0.state == .loading },
                    failed: sections.contains { $0.state == .failed },
                    reason: failureReason(sections.filter { $0.state == .failed }.map(\.id))
                )
            } else {
                grid(allItems, loadingMoreFor: sections.map(\.id))
            }
        } else if let section = sections.first(where: { $0.id == selectedTab }) {
            switch section.state {
            case .loading:
                loadingOrEmpty(isLoading: true, failed: false)
            case let .loaded(items) where !items.isEmpty:
                grid(items, loadingMoreFor: [section.id])
            case .failed:
                loadingOrEmpty(isLoading: false, failed: true, reason: failureReason([section.id]))
            default:
                loadingOrEmpty(isLoading: false, failed: false)
            }
        }
    }

    @ViewBuilder
    private func grid(_ loaded: [MediaItem], loadingMoreFor sectionIDs: [String]) -> some View {
        let pending = sections.filter { sectionIDs.contains($0.id) }
        let items = filtered(loaded)
        LazyVGrid(
            columns: MediaBrowseMetrics.posterGridColumns(cardDisplay),
            alignment: .leading,
            spacing: MediaBrowseMetrics.gridRowSpacing
        ) {
            ForEach(items) { item in
                MediaPoster(item: item, fillsAvailableWidth: true)
            }
        }
        .environment(\.displayPreferences, cardDisplay)

        // More titles load on their own at the bottom. The marker stays
        // put while a page loads: swapping it for the spinner cancelled
        // its task, and with it the request.
        if pending.contains(where: \.hasMore) {
            Color.clear
                .frame(height: 1)
                .task(id: loaded.count) {
                    // Not tied to the marker, so a section finishing
                    // early doesn't cancel the others' pages.
                    await Task { await loadMore(sectionIDs) }.value
                }
        }
        if pending.contains(where: \.isLoadingMore) {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        }
    }

    private func sourceRow(_ section: FolderSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: section.title)
            switch section.state {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
            case .failed:
                Text(failureReason([section.id]) ?? "This catalog didn't respond.")
                    .foregroundStyle(.secondary)
            default:
                if filtered(section.items).isEmpty {
                    Text("No titles.")
                        .foregroundStyle(.secondary)
                } else {
                    ShelfScrollView(
                        items: filtered(section.items),
                        itemSpan: MediaBrowseMetrics.posterItemSpan(cardDisplay),
                        accessibilityLabel: section.title
                    ) { item in
                        MediaPoster(item: item)
                    }
                    .environment(\.displayPreferences, cardDisplay)
                }
            }
        }
    }

    /// The last error the add-on gave for these sections' catalogs.
    private func failureReason(_ sectionIDs: [String]) -> String? {
        let messages = sectionIDs.compactMap { id in
            targets[id].flatMap { entry in
                AddonDiagnostics.shared.catalogFailure(addon: entry.target.addon, catalog: entry.target.catalog)?.message
            }
        }
        return messages.first
    }

    /// Why none of this folder's catalogs could be found.
    private var unavailableReason: String {
        let reasons = Set(folder.sources.map { HomeCollectionSourceResolver.unavailableReason(for: $0, in: store.installedAddons) })
        if reasons.count == 1, let reason = reasons.first {
            return "\(reason) Install or turn on the add-on, then try again."
        }
        return "This folder's catalogs come from an add-on that isn't installed or is turned off. Install the add-on this collection was made for, then try again."
    }

    private func filtered(_ items: [MediaItem]) -> [MediaItem] {
        DiscoverFilterPresentation.apply(filters, to: items)
    }

    @ViewBuilder
    private func loadingOrEmpty(isLoading: Bool, failed: Bool, reason: String? = nil) -> some View {
        if isLoading {
            OmniaLoadingRow("Loading \(folder.title)…")
                .frame(maxWidth: .infinity, minHeight: 220)
        } else if failed {
            ContentUnavailableView {
                Label("Catalog Unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text(reason ?? "The add-on didn't respond.")
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        } else {
            ContentUnavailableView("No Titles Found", systemImage: "film")
                .frame(maxWidth: .infinity, minHeight: 220)
        }
    }

    // MARK: Loading

    private var loadKey: String {
        // Includes catalog counts, so a refreshed manifest re-resolves the folder.
        folder.id + "|" + store.installedAddons.filter(\.isEnabled)
            .map { "\($0.id):\($0.manifest.catalogs.count)" }
            .joined(separator: ",")
    }

    private func load() async {
        let resolved = folder.sources.enumerated().map { index, source in
            (id: "\(index):\(source.type):\(source.catalogId)", source: source,
             target: HomeCollectionSourceResolver.resolve(source, in: store.installedAddons))
        }
        sections = resolved.map { entry in
            FolderSection(
                id: entry.id,
                title: Self.title(for: entry.source, catalog: entry.target?.catalog, folderTitle: folder.title),
                state: entry.target == nil ? .unavailable : .loading
            )
        }
        targets = resolved.reduce(into: [:]) { result, entry in
            if let target = entry.target { result[entry.id] = (entry.source, target) }
        }
        if !tabs.contains(where: { $0.id == selectedTab }) {
            selectedTab = tabs.first?.id ?? FolderSection.allID
        }
        isLoading = true
        defer { isLoading = false }

        // Show the copy saved last time straight away, then refresh it.
        let targets = resolved.compactMap { entry in
            entry.target.map { (id: entry.id, source: entry.source, target: $0) }
        }
        let cacheKeys = Dictionary(uniqueKeysWithValues: targets.map { entry in
            (entry.id, AddonCatalogCache.key(
                addon: entry.target.addon,
                catalog: entry.target.catalog,
                extra: Self.extra(for: entry.source, target: entry.target)
            ))
        })
        let saved = await AddonCatalogCache.previews(for: Array(cacheKeys.values))
        if Task.isCancelled { return }
        for entry in targets {
            guard let previews = cacheKeys[entry.id].flatMap({ saved[$0] }),
                  let index = sections.firstIndex(where: { $0.id == entry.id })
            else { continue }
            let items = Self.items(from: previews, addon: entry.target.addon)
            if !items.isEmpty {
                sections[index].state = .loaded(items)
                sections[index].nextSkip = previews.count
            }
        }

        await withTaskGroup(of: (String, [AddonMetaPreview]?).self) { group in
            for entry in targets {
                let id = entry.id
                let source = entry.source
                let target = entry.target
                group.addTask {
                    (id, await Self.fetch(source: source, target: target))
                }
            }
            for await (id, previews) in group {
                guard let index = sections.firstIndex(where: { $0.id == id }),
                      let entry = targets.first(where: { $0.id == id })
                else { continue }
                if let previews {
                    sections[index].state = .loaded(Self.items(from: previews, addon: entry.target.addon))
                    sections[index].nextSkip = previews.count
                    sections[index].hasMore = !previews.isEmpty
                    if let key = cacheKeys[id] {
                        Task { await AddonCatalogCache.save(previews, for: key) }
                    }
                } else if case .loaded = sections[index].state {
                    // Offline: keep the saved copy rather than an error.
                } else {
                    sections[index].state = .failed
                }
            }
        }
    }

    /// The next page of each section that has one, as Nuvio pages with `skip`.
    private func loadMore(_ sectionIDs: [String]) async {
        let ids = sectionIDs.filter { id in
            sections.first { $0.id == id }.map { $0.hasMore && !$0.isLoadingMore } ?? false
        }
        guard !ids.isEmpty else { return }
        for id in ids {
            guard let index = sections.firstIndex(where: { $0.id == id }) else { continue }
            sections[index].isLoadingMore = true
        }
        await withTaskGroup(of: (String, Int, [AddonMetaPreview]?).self) { group in
            for id in ids {
                guard let entry = targets[id],
                      let skip = sections.first(where: { $0.id == id })?.nextSkip
                else { continue }
                var extra = Self.extra(for: entry.source, target: entry.target)
                extra["skip"] = String(skip)
                group.addTask {
                    let previews = try? await StremioAddonClient.fetchCatalog(
                        from: entry.target.addon,
                        catalog: entry.target.catalog,
                        extra: extra,
                        allowsMissingRequiredExtras: true
                    )
                    return (id, skip, previews)
                }
            }
            for await (id, skip, previews) in group {
                guard let index = sections.firstIndex(where: { $0.id == id }),
                      let addon = targets[id]?.target.addon
                else { continue }
                sections[index].isLoadingMore = false
                let existing = Set(sections[index].items.map(\.id))
                let fresh = Self.items(from: previews ?? [], addon: addon).filter { !existing.contains($0.id) }
                // A failed page, an empty one, or the first page again
                // (an add-on that doesn't page) ends the list.
                guard let previews, !fresh.isEmpty else {
                    sections[index].hasMore = false
                    continue
                }
                sections[index].state = .loaded(sections[index].items + fresh)
                sections[index].nextSkip = skip + previews.count
            }
        }
        for id in ids {
            guard let index = sections.firstIndex(where: { $0.id == id }) else { continue }
            sections[index].isLoadingMore = false
        }
    }

    private static func extra(
        for source: HomeCollectionSource,
        target: HomeCollectionSourceResolver.Resolved
    ) -> [String: String] {
        var extra: [String: String] = [:]
        if let genre = source.requestedGenre,
           target.catalog.extra?.contains(where: { $0.name == "genre" }) == true {
            extra["genre"] = genre
        }
        return extra
    }

    private static func fetch(
        source: HomeCollectionSource,
        target: HomeCollectionSourceResolver.Resolved
    ) async -> [AddonMetaPreview]? {
        try? await StremioAddonClient.fetchCatalog(
            from: target.addon,
            catalog: target.catalog,
            extra: extra(for: source, target: target),
            allowsMissingRequiredExtras: true
        )
    }

    private static func items(from previews: [AddonMetaPreview], addon: InstalledAddon) -> [MediaItem] {
        previews.compactMap { preview in
            guard let item = preview.mediaItem(addon: addon) else { return nil }
            AddonItemProvenance.record(itemID: item.id, addonID: addon.id, stremioType: preview.type)
            return item
        }
    }

    /// Xperience names catalogs like "Apple TV+ Top 10 Movies"; inside the
    /// Apple TV folder the tab reads better as "Top 10 Movies".
    static func title(for source: HomeCollectionSource, catalog: AddonCatalog?, folderTitle: String) -> String {
        let name = catalog?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = (name?.isEmpty == false ? name : nil) ?? source.catalogId
        let trimmedFolder = folderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.count > trimmedFolder.count + 2,
           base.lowercased().hasPrefix(trimmedFolder.lowercased()) {
            let rest = base.dropFirst(trimmedFolder.count)
                .trimmingCharacters(in: CharacterSet(charactersIn: "+ -–:").union(.whitespaces))
            if !rest.isEmpty { return rest }
        }
        return base
    }
}

/// Fetches an animated cover through the shared cache. It comes from a
/// collection file, so only a bounded HTTPS response is accepted.
private enum AnimatedCoverData {
    static let maximumBytes = 32 * 1_024 * 1_024

    static func load(_ url: URL) async -> Data? {
        guard url.scheme?.lowercased() == "https",
              let (data, response) = try? await RemoteArtworkFetcher.session.data(from: url),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
              data.count <= maximumBytes
        else { return nil }
        return data
    }
}

#if os(iOS)
/// Touch screens have no hover, so covers play while on screen. A shelf of
/// GIFs would keep the CPU busy, so only a few play at once and the rest wait.
@MainActor
@Observable
final class AnimatedCoverLimiter {
    static let shared = AnimatedCoverLimiter()
    private static let limit = 3

    private(set) var playing: Set<String> = []
    private var waiting: [String] = []

    func request(_ id: String) {
        guard !playing.contains(id), !waiting.contains(id) else { return }
        if playing.count < Self.limit { playing.insert(id) } else { waiting.append(id) }
    }

    func release(_ id: String) {
        waiting.removeAll { $0 == id }
        guard playing.remove(id) != nil, !waiting.isEmpty else { return }
        playing.insert(waiting.removeFirst())
    }
}

/// An animated GIF filling its frame. ImageIO decodes one frame at a time, so
/// a long GIF doesn't sit in memory the way a frame array would.
struct AnimatedCoverImage: View {
    let url: URL
    var isPlaying = true
    var staysDecoded = true
    @State private var data: Data?

    var body: some View {
        AnimatedCoverLayerView(data: isPlaying || staysDecoded ? data : nil, isPlaying: isPlaying)
            .task(id: url) { data = await AnimatedCoverData.load(url) }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

private struct AnimatedCoverLayerView: UIViewRepresentable {
    let data: Data?
    let isPlaying: Bool

    func makeUIView(context: Context) -> CoverView {
        let view = CoverView()
        view.clipsToBounds = true
        view.layer.contentsGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: CoverView, context: Context) {
        view.update(data: data, isPlaying: isPlaying)
    }

    static func dismantleUIView(_ view: CoverView, coordinator: ()) {
        view.update(data: nil, isPlaying: false)
    }

    final class CoverView: UIView {
        private var current: Data?
        private var isAnimating = false
        /// Read by ImageIO's callback, which runs on the main queue.
        private var generation = 0

        func update(data: Data?, isPlaying: Bool) {
            guard data != current || isPlaying != isAnimating else { return }
            current = data
            isAnimating = isPlaying
            generation += 1
            guard let data else {
                layer.contents = nil
                return
            }
            let token = generation
            let playsOn = isPlaying
            CGAnimateImageDataWithBlock(data as CFData, nil) { [weak self] _, image, stop in
                guard let self, self.generation == token else {
                    stop.pointee = true
                    return
                }
                self.layer.contents = image
                // At rest, the first frame is all that's needed.
                if !playsOn { stop.pointee = true }
            }
        }
    }
}
#endif

#if os(macOS)
/// An animated GIF filling its frame like `scaledToFill()`. AsyncImage only
/// shows a GIF's first frame.
struct AnimatedCoverImage: View {
    let url: URL
    var isPlaying = true
    /// When the GIF is the tile's only cover, its first frame shows at rest.
    /// Otherwise it is decoded only while it plays: a Home with dozens of
    /// animated covers held every one in memory.
    var staysDecoded = true
    @State private var image: NSImage?

    private var isNeeded: Bool { staysDecoded || isPlaying }

    var body: some View {
        GeometryReader { proxy in
            if let image, image.size.width > 0, image.size.height > 0 {
                AnimatedImageView(image: image, isPlaying: isPlaying)
                    .aspectRatio(image.size.width / image.size.height, contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .transition(.opacity)
            }
        }
        .task(id: "\(url.absoluteString)|\(isNeeded)") {
            guard isNeeded else {
                image = nil
                // Download ahead into the disk cache, so hovering starts at once.
                await Self.prefetch(url)
                return
            }
            image = await Self.load(url)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private static var prefetched: Set<URL> = []

    private static func prefetch(_ url: URL) async {
        guard prefetched.insert(url).inserted else { return }
        _ = await AnimatedCoverData.load(url)
    }

    /// Loads through the shared cache, so covers don't download again.
    private static func load(_ url: URL) async -> NSImage? {
        guard let data = await AnimatedCoverData.load(url) else { return nil }
        return NSImage(data: data)
    }
}

private struct AnimatedImageView: NSViewRepresentable {
    let image: NSImage
    let isPlaying: Bool

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.animates = isPlaying
        view.imageScaling = .scaleAxesIndependently
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.image = image
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        if view.image !== image { view.image = image }
        if view.animates != isPlaying {
            view.animates = isPlaying
            // Start from the first frame on the next hover.
            if !isPlaying { view.image = nil; view.image = image }
        }
    }
}
#endif
