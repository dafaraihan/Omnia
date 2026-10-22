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
    case separator
    case markWatched
    case markUnwatched
    case seasonWatched
    case seasonUnwatched
    case revertToPreviousEpisode
    case episodesThroughHereWatched
    case episodesThroughHereUnwatched
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
            return [
                .goToMovie,
                .separator,
                .markWatched,
                .markUnwatched,
                .removeWatchProgress,
            ]
        case (.series, .continueWatching), (.episode, .continueWatching):
            return [
                .goToShow,
                .separator,
                .markWatched,
                .markUnwatched,
                .seasonWatched,
                .seasonUnwatched,
                .revertToPreviousEpisode,
                .episodesThroughHereWatched,
                .episodesThroughHereUnwatched,
            ]
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

#if os(macOS)
private struct MediaContextMenuModifier: ViewModifier {
    let item: MediaItem
    let placement: MediaContextPlacement

    @Environment(OmniaStore.self) private var store
    @Environment(LiveMetadataStore.self) private var metadata

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .contextMenu {
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
            }
    }

    @ViewBuilder
    private func menuItem(for command: MediaContextCommand) -> some View {
        switch command {
        case .goToMovie:
            MediaDetailLink(item: item) {
                menuLabel("Go to Movie", systemImage: "info.circle")
            }
        case .goToShow:
            MediaDetailLink(item: item) {
                menuLabel("Go to Show", systemImage: "info.circle")
            }
        case .separator:
            Divider()
        case .markWatched:
            actionButton("Mark as Watched", systemImage: "checkmark.rectangle", command: command)
        case .markUnwatched:
            actionButton("Mark as Unwatched", systemImage: "rectangle", command: command)
        case .seasonWatched:
            actionButton("Season Watched", systemImage: "checkmark.rectangle.stack", command: command)
        case .seasonUnwatched:
            actionButton("Season Unwatched", systemImage: "rectangle.stack", command: command)
        case .revertToPreviousEpisode:
            actionButton("Revert to Previous Episode", systemImage: "backward.end", command: command)
        case .episodesThroughHereWatched:
            actionButton("All Episodes up to Here Watched", systemImage: "checkmark.circle", command: command)
        case .episodesThroughHereUnwatched:
            actionButton("All Episodes up to Here Unwatched", systemImage: "circle", command: command)
        case .removeWatchProgress:
            Button(role: .destructive) {
                store.removeFromContinueWatching(item)
            } label: {
                menuLabel("Remove Watch Progress", systemImage: "minus.circle")
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

    private func actionButton(
        _ title: String,
        systemImage: String,
        command: MediaContextCommand
    ) -> some View {
        Button {
            Task { await perform(command) }
        } label: {
            menuLabel(title, systemImage: systemImage)
        }
    }

    private func menuLabel(_ title: String, systemImage: String) -> some View {
        // Template symbols let NSMenu color icons for light and dark menus and
        // for the highlighted row. Forced white icons vanished in light mode.
        Label(title, systemImage: systemImage)
    }

    private func perform(_ command: MediaContextCommand) async {
        if item.kind == .movie {
            switch command {
            case .markWatched:
                store.applyWatchCommand(.markMovie(watched: true), to: item, episodes: [])
            case .markUnwatched:
                store.applyWatchCommand(.markMovie(watched: false), to: item, episodes: [])
            default:
                break
            }
            return
        }

        let enrichedItem = await metadata.details(for: item)
        let episodes = enrichedItem.details?.seasons.flatMap(\.episodes)
            ?? item.details?.seasons.flatMap(\.episodes)
            ?? []
        guard let current = currentEpisode(in: episodes) else { return }

        let watchCommand: LocalMediaWatchCommand?
        switch command {
        case .markWatched:
            watchCommand = .markEpisode(current, watched: true)
        case .markUnwatched:
            watchCommand = .markEpisode(current, watched: false)
        case .seasonWatched:
            watchCommand = .markSeason(containing: current, watched: true)
        case .seasonUnwatched:
            watchCommand = .markSeason(containing: current, watched: false)
        case .revertToPreviousEpisode:
            watchCommand = .revertToPrevious(current)
        case .episodesThroughHereWatched:
            watchCommand = .markThrough(current, watched: true)
        case .episodesThroughHereUnwatched:
            watchCommand = .markThrough(current, watched: false)
        default:
            watchCommand = nil
        }
        if let watchCommand {
            store.applyWatchCommand(watchCommand, to: enrichedItem, episodes: episodes)
        }
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
#endif

extension View {
    @ViewBuilder
    func mediaContextMenu(
        for item: MediaItem,
        placement: MediaContextPlacement
    ) -> some View {
        #if os(macOS)
        modifier(MediaContextMenuModifier(item: item, placement: placement))
        #else
        self
        #endif
    }
}
