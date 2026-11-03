//
//  LiveTVView.swift
//  Omnia
//

import ImageIO
import SwiftUI

/// Nuvio Enhanced's Live TV page: the last watched channel, then every
/// channel with what's on now and next. Favorites, categories, sources and
/// sorting are in the toolbar's Filter and Sort menu.
struct LiveTVView: View {
    @Environment(PlaybackSession.self) private var playback
    @Environment(SettingsPreferencesStore.self) private var settings
    @State private var live = LiveTVStore.shared
    @State private var searchText = ""
    @State private var filters = LiveTVFilters()
    @State private var guideChannel: LiveTVChannel?
    @State private var startingChannelID: String?
    @State private var playbackError: String?

    var body: some View {
        content
            .omniaNavigationTitle("Live TV", screen: .liveTV)
            #if os(macOS)
            // The Filter button just before the search field, each its own
            // toolbar item, as on Search (Dafa, 2026-10-22).
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    filterMenu
                }
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) {
                    MacSettingsSearchField(text: $searchText, prompt: "Search channels")
                        .frame(width: 260)
                }
            }
            #else
            .searchable(text: $searchText, prompt: "Search channels")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    filterMenu
                }
            }
            #endif
            .task { await live.loadIfNeeded() }
            .sheet(item: $guideChannel) { channel in
                LiveTVGuideSheet(channel: channel, play: { play(channel) })
            }
            .alert(
                "Couldn't Play This Channel",
                isPresented: Binding(get: { playbackError != nil }, set: { if !$0 { playbackError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(playbackError ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        if !live.hasSources {
            ContentUnavailableView {
                Label("No Playlist Configured", systemImage: "play.tv")
            } description: {
                Text("Add an M3U playlist, an Xtream account or a Stalker portal in Settings › Content & Discovery › Live TV.")
            } actions: {
                NavigationLink("Set Up Live TV") {
                    SettingsDestinationView(route: .liveTV)
                }
            }
        } else if live.channels.isEmpty {
            switch live.channelState {
            case .idle, .loading:
                OmniaLoadingRow("Loading channels…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ContentUnavailableView {
                    Label("Playlist Could Not Be Loaded", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again", systemImage: "arrow.clockwise") {
                        Task { await live.reloadChannels() }
                    }
                }
            case .loaded:
                ContentUnavailableView("No Channels Found", systemImage: "play.tv")
            }
        } else {
            channelList
        }
    }

    private var channelList: some View {
        let channels = visibleChannels
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if searchText.isEmpty, filters.isDefault, let last = live.lastWatchedChannel {
                    LastWatchedChannelCard(
                        channel: last,
                        programs: live.programs(for: last),
                        isStarting: startingChannelID == last.id,
                        play: { play(last) }
                    )
                    .padding(.bottom, 14)
                }
                if channels.isEmpty {
                    if searchText.isEmpty {
                        ContentUnavailableView("No Channels Found", systemImage: "play.tv")
                            .frame(maxWidth: .infinity, minHeight: 240)
                    } else {
                        ContentUnavailableView.search(text: searchText)
                            .frame(maxWidth: .infinity, minHeight: 240)
                    }
                }
                ForEach(channels) { channel in
                    LiveTVChannelRow(
                        channel: channel,
                        programs: live.programs(for: channel),
                        isFavorite: live.isFavorite(channel),
                        isStarting: startingChannelID == channel.id,
                        play: { play(channel) },
                        toggleFavorite: { live.toggleFavorite(channel) },
                        showGuide: { guideChannel = channel }
                    )
                }
            }
            .padding(.horizontal, MediaBrowseMetrics.pageInset)
            .padding(.vertical, 24)
        }
    }

    private var visibleChannels: [LiveTVChannel] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let favorites = Set(live.configuration.favoriteChannelIDs)
        var channels = live.channels.filter { channel in
            if filters.favoritesOnly, !favorites.contains(channel.id) { return false }
            switch filters.category {
            case .all: break
            case .uncategorized: if channel.group != nil { return false }
            case let .named(group): if channel.group != group { return false }
            }
            if let source = filters.sourceID, channel.sourceID != source { return false }
            guard !query.isEmpty else { return true }
            return channel.name.localizedCaseInsensitiveContains(query)
                || channel.group?.localizedCaseInsensitiveContains(query) == true
        }
        if filters.sort == .source {
            var order: [String: Int] = [:]
            for (index, source) in sources.enumerated() where order[source.id] == nil {
                order[source.id] = index
            }
            channels.sort { (order[$0.sourceID] ?? .max) < (order[$1.sourceID] ?? .max) }
        }
        return channels
    }

    private var sources: [(id: String, name: String)] {
        var seen = Set<String>()
        return live.channels.compactMap { channel in
            seen.insert(channel.sourceID).inserted ? (channel.sourceID, channel.sourceName) : nil
        }
    }

    // MARK: Filter and Sort

    private var filterMenu: some View {
        Menu {
            Toggle("Favorites Only", systemImage: "star", isOn: $filters.favoritesOnly)
            Picker(selection: $filters.category) {
                Text("All Categories").tag(LiveTVFilters.Category.all)
                if live.hasUncategorizedChannels {
                    Text("Uncategorized").tag(LiveTVFilters.Category.uncategorized)
                }
                ForEach(live.groups, id: \.self) { group in
                    Text(group).tag(LiveTVFilters.Category.named(group))
                }
            } label: {
                Label("Category", systemImage: "square.grid.2x2")
            }
            .pickerStyle(.menu)
            if sources.count > 1 {
                Picker(selection: $filters.sourceID) {
                    Text("All Sources").tag(String?.none)
                    ForEach(sources, id: \.id) { source in
                        Text(source.name).tag(Optional(source.id))
                    }
                } label: {
                    Label("Source", systemImage: "list.bullet.rectangle")
                }
                .pickerStyle(.menu)
            }
            Picker(selection: $filters.sort) {
                ForEach(LiveTVFilters.Sort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .pickerStyle(.menu)
            Divider()
            Button("Reload Channels", systemImage: "arrow.clockwise") {
                Task {
                    await live.reloadChannels()
                    await live.reloadGuide()
                }
            }
            .disabled(live.channelState == .loading)
            NavigationLink {
                SettingsDestinationView(route: .liveTV)
            } label: {
                Label("Live TV Settings", systemImage: "gearshape")
            }
        } label: {
            Label("Filter and Sort", systemImage: "line.3.horizontal.decrease.circle")
        }
        .help("Filter and sort channels")
    }

    // MARK: Playback

    private func play(_ channel: LiveTVChannel) {
        guard startingChannelID == nil else { return }
        startingChannelID = channel.id
        Task {
            defer { startingChannelID = nil }
            do {
                try await live.play(channel, in: playback, preferences: settings.preferences)
                guideChannel = nil
            } catch {
                playbackError = (error as? LocalizedError)?.errorDescription ?? "The channel couldn't be started."
            }
        }
    }
}

struct LiveTVFilters: Equatable {
    enum Category: Hashable {
        case all
        case uncategorized
        case named(String)
    }

    enum Sort: String, CaseIterable, Identifiable {
        case name
        case source

        var id: String { rawValue }

        var title: String {
            switch self {
            case .name: "Name"
            case .source: "Source"
            }
        }
    }

    var favoritesOnly = false
    var category: Category = .all
    var sourceID: String?
    var sort: Sort = .name

    var isDefault: Bool { self == LiveTVFilters() }
}

// MARK: Rows

private struct LiveTVChannelRow: View {
    let channel: LiveTVChannel
    let programs: [LiveTVProgram]
    let isFavorite: Bool
    let isStarting: Bool
    let play: () -> Void
    let toggleFavorite: () -> Void
    let showGuide: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 14) {
            Button(action: play) {
                HStack(spacing: 14) {
                    LiveTVChannelLogo(channel: channel, side: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(channel.name)
                            .font(.headline)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 6, height: 6)
                            Text([channel.group ?? "Uncategorized", channel.sourceName].joined(separator: " · "))
                                .lineLimit(1)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        LiveTVNowNext(programs: programs)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")

            if !programs.isEmpty {
                Button(action: showGuide) {
                    Image(systemName: "list.bullet.rectangle")
                }
                .buttonStyle(.borderless)
                .help("TV Guide")
            }

            Button(action: play) {
                if isStarting {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "play.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .help("Play")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.09 : 0.05))
        )
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Play", systemImage: "play", action: play)
            Button(
                isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: isFavorite ? "star.slash" : "star",
                action: toggleFavorite
            )
            if !programs.isEmpty {
                Button("TV Guide", systemImage: "list.bullet.rectangle", action: showGuide)
            }
        }
    }
}

/// What's on now, with its progress, and what's next. Redrawn each minute.
private struct LiveTVNowNext: View {
    let programs: [LiveTVProgram]

    var body: some View {
        if !programs.isEmpty {
            TimelineView(.everyMinute) { context in
                let entries = LiveTVGuideMatcher.nowAndNext(in: programs, at: context.date)
                VStack(alignment: .leading, spacing: 3) {
                    if let now = entries.now {
                        HStack(spacing: 8) {
                            Text("Now")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                            Text(now.title)
                                .font(.caption)
                                .lineLimit(1)
                            ProgressView(value: now.progress(at: context.date))
                                .frame(maxWidth: 120)
                        }
                    }
                    if let next = entries.next {
                        Text("Next  \(next.start.formatted(date: .omitted, time: .shortened))  \(next.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

private struct LastWatchedChannelCard: View {
    let channel: LiveTVChannel
    let programs: [LiveTVProgram]
    let isStarting: Bool
    let play: () -> Void

    var body: some View {
        // One row where it fits; on an iPhone, Continue gets its own row
        // instead of wrapping letter by letter.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                LiveTVChannelLogo(channel: channel, side: 84)
                details
                Spacer(minLength: 12)
                continueButton(fullWidth: false)
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    LiveTVChannelLogo(channel: channel, side: 64)
                    details
                    Spacer(minLength: 0)
                }
                continueButton(fullWidth: true)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
        )
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last Watched Channel")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(channel.name)
                .font(.title2.weight(.semibold))
                .lineLimit(2)
            LiveTVNowNext(programs: programs)
        }
    }

    private func continueButton(fullWidth: Bool) -> some View {
        Button(action: play) {
            Group {
                if isStarting {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Continue", systemImage: "play.fill")
                        .fixedSize()
                }
            }
            .frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}

private struct LiveTVChannelLogo: View {
    let channel: LiveTVChannel
    let side: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.2, style: .continuous)
                .fill(Color.primary.opacity(0.06))
            if let url = channel.logoURL {
                LiveTVLogoImage(url: url, size: CGSize(width: side - 12, height: side - 12)) {
                    initials
                }
                .padding(6)
            } else {
                initials
            }
        }
        .frame(width: side, height: side)
    }

    private var initials: some View {
        Text(String(channel.name.prefix(2)).uppercased())
            .font(.system(size: side * 0.3, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
    }
}

/// A channel logo. https:// logos use the app's artwork cache; plain http://
/// ones, which App Transport Security blocks, are fetched through Live TV's
/// own downloader (2 MB at most) and kept in a small memory cache.
struct LiveTVLogoImage<Placeholder: View>: View {
    let url: URL
    let size: CGSize
    @ViewBuilder let placeholder: () -> Placeholder
    @Environment(\.displayScale) private var displayScale
    @State private var plainImage: CGImage?

    var body: some View {
        if LiveTVAddressPolicy.needsPlainHTTP(url) {
            Group {
                if let plainImage {
                    Image(decorative: plainImage, scale: max(displayScale, 1))
                        .resizable()
                        .scaledToFit()
                } else {
                    placeholder()
                }
            }
            .task(id: url) {
                plainImage = await LiveTVLogoCache.image(
                    for: url,
                    maximumPixels: Int(max(size.width, size.height) * max(displayScale, 1))
                )
            }
        } else {
            CachedArtworkImage(url: url, size: size, contentMode: .fit) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFit()
                } else {
                    placeholder()
                }
            }
        }
    }
}

enum LiveTVLogoCache {
    private static let images = NSCache<NSURL, CGImageBox>()
    private static var failed = Set<URL>()

    final class CGImageBox {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    static func image(for url: URL, maximumPixels: Int) async -> CGImage? {
        if let cached = images.object(forKey: url as NSURL) { return cached.image }
        guard !failed.contains(url) else { return nil }
        let data = try? await LiveTVHTTP.data(
            from: url,
            headers: ["Accept": "image/*", "User-Agent": "Omnia/1.0"],
            maximumBytes: 2 * 1_024 * 1_024,
            timeout: 20
        )
        guard let data, let image = await decode(data, maximumPixels: max(maximumPixels, 64))?.image else {
            failed.insert(url)
            return nil
        }
        images.setObject(CGImageBox(image), forKey: url as NSURL)
        return image
    }

    nonisolated private struct DecodedLogo: @unchecked Sendable {
        let image: CGImage
    }

    @concurrent
    private static func decode(_ data: Data, maximumPixels: Int) async -> DecodedLogo? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixels,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map(DecodedLogo.init)
    }
}

// MARK: TV Guide

private struct LiveTVGuideSheet: View {
    let channel: LiveTVChannel
    let play: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var live = LiveTVStore.shared

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                let programs = live.programs(for: channel).filter { $0.end > context.date }
                List(programs, id: \.start) { program in
                    let isAiring = program.isAiring(at: context.date)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(timeRange(program))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(isAiring ? Color.accentColor : Color.secondary)
                            if isAiring {
                                Text("Now")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        Text(program.title)
                            .font(.headline)
                        if let category = program.category {
                            Text(category)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let detail = program.detail {
                            Text(detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        if isAiring {
                            ProgressView(value: program.progress(at: context.date))
                        }
                    }
                    .padding(.vertical, 4)
                }
                .overlay {
                    if programs.isEmpty {
                        ContentUnavailableView("No Guide for This Channel", systemImage: "list.bullet.rectangle")
                    }
                }
            }
            .navigationTitle("TV Guide · \(channel.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Play", systemImage: "play.fill", action: play)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 520)
        #endif
    }

    private func timeRange(_ program: LiveTVProgram) -> String {
        let day: Date.FormatStyle.DateStyle = Calendar.current.isDateInToday(program.start) ? .omitted : .abbreviated
        return "\(program.start.formatted(date: day, time: .shortened)) – \(program.end.formatted(date: .omitted, time: .shortened))"
    }
}
