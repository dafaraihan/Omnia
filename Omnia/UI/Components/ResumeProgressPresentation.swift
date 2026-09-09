//
//  ResumeProgressPresentation.swift
//  Omnia
//

import SwiftUI

/// The complete launch decision for the title-level playback action. Source
/// selection must carry this decision unchanged so choosing a stream cannot
/// discard the selected episode or saved timestamp.
struct MediaDetailPlaybackIntent: Equatable {
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
        let savedPosition = persistedItem?.positionSeconds
        let savedProgress = persistedItem?.progress
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

/// One source of truth for partial-playback metadata across heroes, shelves,
/// and episode cards. Completed and untouched titles deliberately produce no
/// presentation so Play and Rewatch stay visually clean.
struct ResumeProgressPresentation: Equatable {
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

    var heroMetadataText: String {
        episodeIdentifier ?? remainingText
    }

    var continueWatchingMetadataText: String {
        [episodeIdentifier, remainingText]
            .compactMap { $0 }
            .joined(separator: "  •  ")
    }

    func matches(_ episode: MediaEpisode) -> Bool {
        if let resumeEpisodeID, resumeEpisodeID == episode.id {
            return true
        }
        return resumeSeasonNumber == episode.seasonNumber
            && resumeEpisodeNumber == episode.episodeNumber
    }
}

struct ResumeProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(.white.opacity(0.28))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.92))
                        .frame(width: geometry.size.width * min(max(progress, 0), 1))
                }
        }
        .frame(height: 7)
        .accessibilityLabel("Playback progress")
        .accessibilityValue("\(Int(min(max(progress, 0), 1) * 100)) percent")
    }
}
