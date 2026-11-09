//
//  ResumeProgressPresentation.swift
//  Omnia
//

import SwiftUI

/// The complete launch decision for the title-level playback action. Source
/// selection must carry this decision unchanged so choosing a stream cannot
/// discard the selected episode or saved timestamp.
nonisolated struct MediaDetailPlaybackIntent: Equatable {
    let title: String
    let item: MediaItem
    let episode: MediaEpisode?
    let resumeAt: Double?

    init(
        displayItem: MediaItem,
        persistedItem: MediaItem?,
        episodes: [MediaEpisode]
    ) {
        item = displayItem

        let loadedFirstEpisode = episodes.sorted {
            ($0.seasonNumber, $0.episodeNumber) < ($1.seasonNumber, $1.episodeNumber)
        }.first
        let firstEpisode = loadedFirstEpisode ?? (displayItem.kind == .series
            ? MediaEpisode(
                id: "\(displayItem.id):1:1",
                seasonNumber: 1,
                episodeNumber: 1,
                title: "Episode 1",
                overview: "",
                runtimeMinutes: nil,
                stillURL: nil,
                airDate: nil
            )
            : nil)
        let savedProgress = persistedItem?.progress
        // A tracker can keep only a percentage (Trakt and Simkl without a
        // runtime). The title's runtime then gives the resume point, rather
        // than starting over (Dafa, 2026-11-09).
        let savedPosition = persistedItem?.positionSeconds ?? persistedItem.flatMap { persisted in
            Self.estimatedPosition(progress: savedProgress, persisted: persisted, display: displayItem, episodes: episodes)
        }
        let isResume = savedPosition.map { $0 > 0 } == true
            && savedProgress.map { $0 > 0 && $0 < 1 } == true

        if isResume, let persistedItem {
            title = "Resume"
            resumeAt = savedPosition
            if displayItem.kind == .series {
                episode = episodes.first(where: { candidate in
                    candidate.id == persistedItem.resumeEpisodeID
                        || (candidate.seasonNumber == persistedItem.resumeSeasonNumber
                            && candidate.episodeNumber == persistedItem.resumeEpisodeNumber)
                }) ?? persistedItem.resumeEpisode ?? firstEpisode
            } else {
                episode = nil
            }
        } else {
            title = savedPosition.map { $0 > 0 } == true ? "Rewatch" : "Play"
            resumeAt = nil
            episode = displayItem.kind == .series ? firstEpisode : nil
        }
    }
}

extension MediaDetailPlaybackIntent {
    static func estimatedPosition(
        progress: Double?,
        persisted: MediaItem,
        display: MediaItem,
        episodes: [MediaEpisode]
    ) -> Double? {
        guard let progress, progress > 0, progress < 1 else { return nil }
        let episodeMinutes = episodes.first { candidate in
            candidate.id == persisted.resumeEpisodeID
                || (candidate.seasonNumber == persisted.resumeSeasonNumber
                    && candidate.episodeNumber == persisted.resumeEpisodeNumber)
        }?.runtimeMinutes ?? persisted.resumeEpisode?.runtimeMinutes
        let minutes = display.kind == .series
            ? episodeMinutes ?? display.details?.runtimeMinutes
            : display.details?.runtimeMinutes ?? persisted.details?.runtimeMinutes
        guard let minutes, minutes > 0 else { return nil }
        return progress * Double(minutes) * 60
    }
}

/// One source of truth for partial-playback metadata across heroes, shelves,
/// and episode cards. Completed and untouched titles deliberately produce no
/// presentation so Play and Rewatch stay visually clean.
nonisolated struct ResumeProgressPresentation: Equatable {
    let progress: Double
    let remainingText: String
    let episodeIdentifier: String?
    let resumeEpisodeID: String?
    let resumeSeasonNumber: Int?
    let resumeEpisodeNumber: Int?

    init?(item: MediaItem) {
        guard let progress = item.progress, progress > 0, progress < 1 else { return nil }

        self.progress = min(max(progress, 0), 1)
        remainingText = item.progressText ?? "In progress"
        resumeEpisodeID = item.resumeEpisodeID
        resumeSeasonNumber = item.resumeSeasonNumber
        resumeEpisodeNumber = item.resumeEpisodeNumber

        if item.kind == .series,
           let season = item.resumeSeasonNumber,
           let episode = item.resumeEpisodeNumber {
            episodeIdentifier = "S\(season)E\(episode)"
        } else {
            episodeIdentifier = nil
        }
    }

    /// "S1 • E2" for a show, and "1h 12m left" for a movie.
    var heroMetadataText: String {
        if let resumeSeasonNumber, let resumeEpisodeNumber { return "S\(resumeSeasonNumber) • E\(resumeEpisodeNumber)" }
        return remainingText
    }

    func matches(_ episode: MediaEpisode) -> Bool {
        if let resumeEpisodeID, resumeEpisodeID == episode.id {
            return true
        }
        return resumeSeasonNumber == episode.seasonNumber
            && resumeEpisodeNumber == episode.episodeNumber
    }
}

nonisolated struct ContinueWatchingCardPresentation: Equatable {
    let primaryText: String
    let secondaryText: String
    let accessibilityValue: String

    init(item: MediaItem) {
        guard item.kind == .series,
              let season = item.resumeSeasonNumber,
              let episode = item.resumeEpisodeNumber else {
            primaryText = item.title
            secondaryText = item.year
            accessibilityValue = item.year
            return
        }

        primaryText = "\(item.title) · \(item.year)"
        let identifier = "S\(season) E\(episode)"
        let trimmedEpisodeTitle = item.resumeEpisodeTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let episodeTitle = trimmedEpisodeTitle.flatMap { $0.isEmpty ? nil : $0 }
        secondaryText = episodeTitle.map { "\(identifier) · \($0)" } ?? identifier
        accessibilityValue = [
            item.year,
            "season \(season)",
            "episode \(episode)",
            episodeTitle
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

/// White in dark appearance and black in light, as Apple's own bars are.
struct ResumeProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(.primary.opacity(0.25))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.primary)
                        .frame(width: geometry.size.width * min(max(progress, 0), 1))
                }
        }
        .frame(height: 5)
        .accessibilityLabel("Playback progress")
        .accessibilityValue("\(Int(min(max(progress, 0), 1) * 100)) percent")
    }
}
