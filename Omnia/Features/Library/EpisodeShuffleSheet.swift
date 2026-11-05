//
//  EpisodeShuffleSheet.swift
//  Omnia
//

import SwiftUI

/// Nuvio's shuffle sheet: choose Unwatched or All episodes, preview the
/// random pick, then play it or shuffle again. Playing turns shuffle on for
/// the show, so its Play button and next episode stay random.
struct EpisodeShuffleSheet: View {
    let item: MediaItem
    let episodes: [MediaEpisode]
    let watchState: LocalMediaWatchState
    let play: (MediaEpisode) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayPreferences) private var display
    @State private var includeWatched = false
    @State private var preview: MediaEpisode?

    private var shuffle: EpisodeShuffleStore { .shared }
    private var current: EpisodeShuffleSettings { shuffle.settings(for: item.id) }

    private var allCount: Int {
        shuffle.candidates(episodes: episodes, watchState: watchState, includeWatched: true).count
    }

    private var unwatchedCount: Int {
        shuffle.candidates(episodes: episodes, watchState: watchState, includeWatched: false).count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let preview {
                        previewContent(preview)
                    } else {
                        chooser
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .navigationTitle("Shuffle")
            #if os(macOS)
            .navigationSubtitle(item.title)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if preview != nil {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            preview = nil
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 500, minHeight: 440)
        #endif
        .onAppear { includeWatched = current.includeWatched }
    }

    @ViewBuilder
    private var chooser: some View {
        Text("Choose which episodes to shuffle.")
            .font(.body)
        if allCount == 0 {
            Text("No episodes are available to shuffle.")
                .foregroundStyle(.secondary)
        } else {
            choiceButton("Unwatched episodes", includeWatched: false)
                .disabled(unwatchedCount == 0)
            choiceButton("All episodes", includeWatched: true)
            if unwatchedCount == 0 {
                Text("You have watched every episode. Choose All episodes to watch again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        if current.enabled {
            Divider()
            Text(current.includeWatched ? "Shuffle on · All episodes" : "Shuffle on · Unwatched episodes")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Stop Shuffle", role: .destructive) {
                shuffle.save(EpisodeShuffleSettings(enabled: false, includeWatched: current.includeWatched), for: item.id)
                dismiss()
            }
        }
    }

    private func choiceButton(_ title: String, includeWatched include: Bool) -> some View {
        Button {
            includeWatched = include
            preview = pick(include)
        } label: {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private func previewContent(_ episode: MediaEpisode) -> some View {
        let watched = watchState.isWatched(episode) == true
        let hidden = display.blurUnwatchedEpisodes && !watched

        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(.quaternary)
                .overlay {
                    if !hidden, let still = episode.stillURL {
                        GeometryReader { proxy in
                            CachedArtworkImage(url: still, size: proxy.size) { phase in
                                phase.image?.resizable().scaledToFill()
                            }
                            .frame(width: proxy.size.width, height: proxy.size.height)
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: hidden ? "eye.slash" : "shuffle")
                                .font(.title)
                            if hidden {
                                Text("Artwork hidden to avoid spoilers")
                                    .font(.caption)
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipped()

            Text(watched ? "Watched" : "Unwatched")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.black.opacity(0.8), in: .rect(cornerRadius: 6))
                .padding(12)
        }
        .clipShape(.rect(cornerRadius: 16, style: .continuous))

        Text(includeWatched ? "All episodes" : "Unwatched episodes")
            .font(.caption)
            .foregroundStyle(.secondary)
        Text("Your episode")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
        Text("S\(episode.seasonNumber) E\(episode.episodeNumber)")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
        Text(episode.title)
            .font(.title2.weight(.semibold))
            .lineLimit(2)
        if !episode.overview.isEmpty {
            Text(episode.overview)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }

        Button {
            shuffle.save(EpisodeShuffleSettings(enabled: true, includeWatched: includeWatched), for: item.id)
            dismiss()
            play(episode)
        } label: {
            Label("Play Episode", systemImage: "play.fill")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
        .omniaAccentForeground()

        if shuffle.candidates(episodes: episodes, watchState: watchState, includeWatched: includeWatched).count > 1 {
            Button {
                preview = pick(includeWatched, excluding: episode)
            } label: {
                Label("Shuffle Again", systemImage: "shuffle")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.bordered)
        } else {
            Text("This is the only episode in your selection.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func pick(_ include: Bool, excluding episode: MediaEpisode? = nil) -> MediaEpisode? {
        shuffle.pick(
            for: item.id,
            episodes: episodes,
            watchState: watchState,
            includeWatched: include,
            excluding: episode
        )
    }
}
