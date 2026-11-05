//
//  MediaContextMenu.swift
//  Omnia
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

enum MediaContextPlacement: Equatable, Sendable {
    case browse
    case continueWatching
}

enum MediaContextCommand: Equatable, Sendable {
    case goToMovie
    case goToShow
    case markWatched
    case removeWatchProgress
    case addToWatchlist
    case removeFromWatchlist
}

enum MediaContextMenuSymbolTreatment: Equatable, Sendable {
    case white
}

enum MediaContextMenuSelectionTreatment: Equatable, Sendable {
    case nativeBlue
}

enum MediaContextMenuPresentation {
    static let symbolTreatment: MediaContextMenuSymbolTreatment = .white
    static let selectionTreatment: MediaContextMenuSelectionTreatment = .nativeBlue

    /// A browse card offers Add or Remove, whichever applies to the title.
    static func commands(
        kind: MediaItem.Kind,
        placement: MediaContextPlacement,
        isSaved: Bool = false
    ) -> [MediaContextCommand] {
        let watchlist: MediaContextCommand = isSaved ? .removeFromWatchlist : .addToWatchlist
        switch (kind, placement) {
        case (.movie, .continueWatching):
            return [.goToMovie, .markWatched, .removeWatchProgress]
        case (.series, .continueWatching), (.episode, .continueWatching):
            return [.goToShow, .markWatched, .removeWatchProgress]
        case (.movie, .browse):
            return [.goToMovie, watchlist]
        case (.series, .browse), (.episode, .browse):
            return [.goToShow, watchlist]
        }
    }
}

struct MediaDetailWatchAction: Equatable, Sendable {
    let systemImage: String
    let accessibilityLabel: String
    let command: LocalMediaWatchCommand
    /// Marking watched also takes the title out of Continue Watching.
    var leavesContinueWatching = false
}

enum MediaDetailWatchActionPresentation {
    static func action(
        kind: MediaItem.Kind,
        currentEpisode: MediaEpisode?,
        watchState: LocalMediaWatchState
    ) -> MediaDetailWatchAction? {
        let isWatched: Bool
        let command: LocalMediaWatchCommand

        switch kind {
        case .movie:
            isWatched = watchState.movieWatched == true
            command = .markMovie(watched: !isWatched)
        case .series, .episode:
            guard let currentEpisode else { return nil }
            isWatched = watchState.isWatched(currentEpisode) == true
            command = .markEpisode(currentEpisode, watched: !isWatched)
        }

        return MediaDetailWatchAction(
            systemImage: isWatched ? "eye.slash" : "eye",
            accessibilityLabel: isWatched ? "Mark as Unwatched" : "Mark as Watched",
            command: command,
            leavesContinueWatching: !isWatched
        )
    }
}

/// Right-click on the Mac, touch and hold on iPhone and iPad.
private struct MediaContextMenuModifier: ViewModifier {
    let item: MediaItem
    let placement: MediaContextPlacement
    #if os(iOS)
    @Environment(\.openMediaDetailFromMenu) private var openFromMenu
    #endif

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .contentShape(Rectangle())
            .contextMenu {
                MediaContextMenuItems(item: item, placement: placement)
            }
        #else
        // A link inside an iOS menu doesn't navigate, so Go to Movie / Show
        // opens the page through the stack's shared destination. Having one
        // on each card, inside a lazy list, slowed scrolling.
        content
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contextMenu {
                MediaContextMenuItems(item: item, placement: placement, openDetail: openFromMenu.map { open in { open(item) } })
            }
        #endif
    }
}

private struct OpenMediaDetailFromMenuKey: EnvironmentKey {
    static let defaultValue: (@MainActor (MediaItem) -> Void)? = nil
}

extension EnvironmentValues {
    var openMediaDetailFromMenu: (@MainActor (MediaItem) -> Void)? {
        get { self[OpenMediaDetailFromMenuKey.self] }
        set { self[OpenMediaDetailFromMenuKey.self] = newValue }
    }
}

/// One destination on the stack, for every card's Go to Movie / Show.
struct MediaDetailMenuDestination: ViewModifier {
    @State private var item: MediaItem?

    func body(content: Content) -> some View {
        content
            .environment(\.openMediaDetailFromMenu) { item = $0 }
            .navigationDestination(item: $item) { MediaDetailView(item: $0) }
    }
}

/// The three dots on a card: the same menu as a right-click or a long press.
struct MediaContextMenuButton: View {
    let item: MediaItem
    let placement: MediaContextPlacement
    @Environment(\.openMediaDetailFromMenu) private var openFromMenu

    var body: some View {
        Menu {
            MediaContextMenuItems(item: item, placement: placement, openDetail: openFromMenu.map { open in { open(item) } })
        } label: {
            MediaContextMenuDots()
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel("More for \(item.title)")
    }
}

struct MediaContextMenuDots: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 2)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

/// The menu's items, in their own view. `isSaved` scans the library and
/// watch history, and a menu's items are built with the card; here that
/// work and the library observation stay out of every poster's update, so
/// saving progress no longer redraws every card on screen.
private struct MediaContextMenuItems: View {
    let item: MediaItem
    let placement: MediaContextPlacement
    var openDetail: (() -> Void)?

    @Environment(OmniaStore.self) private var store
    @Environment(LiveMetadataStore.self) private var metadata

    var body: some View {
        ForEach(
            Array(MediaContextMenuPresentation.commands(
                kind: item.kind,
                placement: placement,
                isSaved: store.isSaved(item)
            ).enumerated()),
            id: \.offset
        ) { _, command in
            menuItem(for: command)
        }
        // iOS otherwise draws a menu's symbols in the accent color.
        .tint(.primary)
    }

    @ViewBuilder
    private func menuItem(for command: MediaContextCommand) -> some View {
        switch command {
        case .goToMovie:
            detailItem("Go to Movie", systemImage: "film")
        case .goToShow:
            detailItem("Go to Show", systemImage: "tv")
        case .markWatched:
            Button {
                Task { await markWatched() }
            } label: {
                menuLabel("Mark as Watched", systemImage: "checkmark.circle")
            }
        case .removeWatchProgress:
            Button {
                store.removeFromContinueWatching(item)
            } label: {
                menuLabel("Remove from Watchlist", systemImage: "minus.circle")
            }
        case .addToWatchlist:
            Button {
                store.setSaved(item, isIncluded: true)
            } label: {
                menuLabel("Add to Watchlist", systemImage: "plus")
            }
        case .removeFromWatchlist:
            Button {
                store.setSaved(item, isIncluded: false)
            } label: {
                menuLabel("Remove from Watchlist", systemImage: "minus")
            }
        }
    }

    @ViewBuilder
    private func detailItem(_ title: String, systemImage: String) -> some View {
        if let openDetail {
            Button(action: openDetail) {
                menuLabel(title, systemImage: systemImage)
            }
        } else {
            MediaDetailLink(item: item) {
                menuLabel(title, systemImage: systemImage)
            }
        }
    }

    private func menuLabel(_ title: String, systemImage: String) -> some View {
        // Template symbols let the system color them for each appearance and
        // the highlighted row. A Mac menu shows icons only when it's asked to.
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .symbolRenderingMode(.monochrome)
    }

    private func markWatched() async {
        if item.kind == .movie {
            store.applyWatchCommand(.markMovie(watched: true), to: item, episodes: [])
            return
        }
        let enrichedItem = await metadata.details(for: item)
        let episodes = enrichedItem.details?.seasons.flatMap(\.episodes)
            ?? item.details?.seasons.flatMap(\.episodes)
            ?? []
        guard let current = currentEpisode(in: episodes) else { return }
        store.applyWatchCommand(.markEpisode(current, watched: true), to: enrichedItem, episodes: episodes)
    }

    private func currentEpisode(in episodes: [MediaEpisode]) -> MediaEpisode? {
        guard let resumeEpisode = item.resumeEpisode else { return episodes.first }
        return episodes.first {
            $0.id == resumeEpisode.id
                || ($0.seasonNumber == resumeEpisode.seasonNumber
                    && $0.episodeNumber == resumeEpisode.episodeNumber)
        } ?? resumeEpisode
    }
}

extension View {
    @ViewBuilder
    func mediaContextMenu(
        for item: MediaItem,
        placement: MediaContextPlacement
    ) -> some View {
        modifier(MediaContextMenuModifier(item: item, placement: placement))
    }
}
