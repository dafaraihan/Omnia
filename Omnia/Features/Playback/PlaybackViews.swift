//
//  PlaybackViews.swift
//  Omnia
//

import SwiftUI

struct PlaybackSourceSheet: View {
    let item: MediaItem
    var episode: MediaEpisode? = nil

    @Environment(OmniaStore.self) private var store
    @Environment(PlaybackSession.self) private var playback
    @Environment(\.dismiss) private var dismiss
    @AppStorage("resume-playback") private var resumePlayback = true
    @State private var sources: [PlaybackSource] = []
    @State private var isResolving = true
    @State private var showingPlayer = false

    var body: some View {
        NavigationStack {
            List {
                if isResolving {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Finding authorized sources…")
                        }
                    }
                } else if sources.isEmpty {
                    ContentUnavailableView(
                        "No Authorized Source",
                        systemImage: "play.slash",
                        description: Text(emptyStateDescription)
                    )
                } else {
                    Section("Available Sources") {
                        ForEach(sources) { source in
                            sourceButton(source)
                        }
                    }
                }

                Section("Playback Safety") {
                    Label("Direct HTTPS streams only", systemImage: "lock.shield")
                    Text("Omnia does not resolve torrents, magnets, or external handoff links. Only play media you are authorized to access.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Choose Source")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: item.id) {
                isResolving = true
                sources = await PlaybackSourceResolver.sources(for: item, addons: store.installedAddons)
                isResolving = false
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $showingPlayer) {
                PlaybackExperienceView(item: item)
            }
            #elseif os(macOS)
            .sheet(isPresented: $showingPlayer) {
                PlaybackExperienceView(item: item)
                    .frame(minWidth: 760, minHeight: 430)
            }
            #endif
        }
    }

    private var emptyStateDescription: String {
        if let episode {
            return "No add-on has supplied a direct HTTPS stream for S\(episode.seasonNumber), E\(episode.episodeNumber) yet. Enable a trusted add-on to make this episode available."
        }
        return "Enable a trusted add-on that supplies a direct HTTPS stream for this title."
    }

    private func sourceButton(_ source: PlaybackSource) -> some View {
        Button {
            playback.start(
                item: item,
                source: source,
                resumeAt: resumePlayback ? item.positionSeconds : nil
            ) { position, duration in
                store.recordPlayback(for: item, positionSeconds: position, durationSeconds: duration)
            }
            showingPlayer = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(source.detail ?? source.addonName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Starts native playback")
    }
}

struct PlaybackExperienceView: View {
    let item: MediaItem

    @Environment(PlaybackSession.self) private var playback
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let player = playback.player {
                NativePlayerView(player: player)
                    .ignoresSafeArea()
            } else {
                ContentUnavailableView("Playback Unavailable", systemImage: "play.slash")
                    .foregroundStyle(.white)
            }

            Button {
                playback.stop()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .padding(18)
            }
            .accessibilityLabel("Close player")
        }
        .onDisappear {
            playback.stop()
        }
    }
}
