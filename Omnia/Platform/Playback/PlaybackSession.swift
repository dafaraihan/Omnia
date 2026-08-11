//
//  PlaybackSession.swift
//  Omnia
//

import Foundation
import Observation

#if os(macOS)
import AppKit
#else
import AVFoundation
#endif

/// One shared player session keeps playback independent from the transient
/// source picker. macOS is backed by libmpv; iOS retains an AVFoundation
/// fallback because libmpv is not bundled for Apple's mobile platforms.
@Observable
@MainActor
final class PlaybackSession {
    #if os(macOS)
    private(set) var player: OMMpvPlayerController?
    #else
    private(set) var player: AVPlayer?
    #endif

    private(set) var source: PlaybackSource?
    private(set) var mediaItem: MediaItem?
    private(set) var episode: MediaEpisode?
    private(set) var positionSeconds: Double = 0
    private(set) var durationSeconds: Double?
    private(set) var isPaused = false
    private(set) var volume: Double = 1
    private(set) var playbackRate: Double = 1
    private(set) var playbackError: String?
    private(set) var audioTracks: [PlaybackTrack] = []
    private(set) var subtitleTracks: [PlaybackTrack] = []
    private(set) var areTracksLoading = false
    var isPresentingPlayer = false

    @ObservationIgnored private var progressHandler: (@MainActor (Double, Double?) -> Void)?
    @ObservationIgnored private var stateTask: Task<Void, Never>?
    #if !os(macOS)
    @ObservationIgnored private var mediaSelectionTask: Task<Void, Never>?
    #endif
    @ObservationIgnored private var lastPersistedPosition: Double = 0

    func start(
        item: MediaItem,
        episode: MediaEpisode? = nil,
        source: PlaybackSource,
        resumeAt position: Double?,
        preferences: SettingsPreferences,
        onProgress: @escaping @MainActor (Double, Double?) -> Void
    ) {
        stop(persisting: true)

        self.source = source
        mediaItem = item
        self.episode = episode
        progressHandler = onProgress
        playbackError = nil
        isPaused = false
        positionSeconds = 0
        durationSeconds = nil
        lastPersistedPosition = 0
        audioTracks = []
        subtitleTracks = []
        areTracksLoading = false

        #if os(macOS)
        let mpv = OMMpvPlayerController(url: source.url, requestHeaders: source.requestHeaders)
        mpv.stateChangeHandler = { [weak self] snapshot in
            self?.apply(snapshot)
        }
        player = mpv
        areTracksLoading = true
        let mediaPolicy = PlaybackMediaSelectionPolicy.resolve(
            preferences: preferences,
            isAnime: item.hasAnimeIdentity
        )
        mpv.setPreferredAudioLanguages(mediaPolicy.audioLanguages ?? [])
        mpv.setPreferredSubtitleLanguages(mediaPolicy.subtitleLanguages ?? [])
        mpv.setSubtitlesDisabled(mediaPolicy.disablesSubtitles)
        if preferences.subtitleAppearance != .followSystem {
            mpv.setSubtitleStyle(Self.mpvSubtitleStyle(for: preferences))
        }
        mpv.setVolume(volume * 100)
        mpv.setPlaybackRate(playbackRate)
        if let position, position > 0 { mpv.seek(to: position) }
        isPresentingPlayer = true
        refreshState()
        observePlaybackState()
        #else
        let playerItem = AVPlayerItem(url: source.url)
        let player = AVPlayer(playerItem: playerItem)
        applyMediaSelection(
            PlaybackMediaSelectionPolicy.resolve(
                preferences: preferences,
                isAnime: item.hasAnimeIdentity
            ),
            to: player,
            item: playerItem
        )
        player.volume = Float(volume)
        self.player = player
        if let position, position > 0 {
            player.seek(to: CMTime(seconds: position, preferredTimescale: 600))
        }
        player.play()
        isPresentingPlayer = true
        observePlaybackState()
        #endif
    }

    func togglePause() {
        #if os(macOS)
        player?.togglePause()
        #else
        guard let player else { return }
        player.timeControlStatus == .playing ? player.pause() : player.play()
        #endif
        refreshState()
    }

    func seek(by seconds: Double) {
        #if os(macOS)
        player?.seek(by: seconds)
        #else
        guard let player else { return }
        player.seek(to: CMTime(seconds: max(positionSeconds + seconds, 0), preferredTimescale: 600))
        #endif
    }

    func seek(to seconds: Double) {
        #if os(macOS)
        player?.seek(to: seconds)
        #else
        player?.seek(to: CMTime(seconds: max(seconds, 0), preferredTimescale: 600))
        #endif
    }

    func setVolume(_ value: Double) {
        volume = min(max(value, 0), 1)
        #if os(macOS)
        player?.setVolume(volume * 100)
        #else
        player?.volume = Float(volume)
        #endif
    }

    func setPlaybackRate(_ value: Double) {
        playbackRate = min(max(value, 0.25), 4)
        #if os(macOS)
        player?.setPlaybackRate(playbackRate)
        #else
        guard let player else { return }
        player.rate = isPaused ? 0 : Float(playbackRate)
        #endif
    }

    func cycleSubtitles() {
        #if os(macOS)
        player?.cycleSubtitles()
        #endif
    }

    func cycleAudioTrack() {
        #if os(macOS)
        player?.cycleAudioTrack()
        #endif
    }

    func selectAudioTrack(_ id: Int) {
        #if os(macOS)
        player?.selectAudioTrack(id: id)
        refreshState()
        #endif
    }

    func selectSubtitleTrack(_ id: Int?) {
        #if os(macOS)
        player?.selectSubtitleTrack(id: id.map { NSNumber(value: $0) })
        refreshState()
        #endif
    }

    func toggleFullScreen() {
        #if os(macOS)
        NSApplication.shared.keyWindow?.toggleFullScreen(nil)
        #endif
    }

    func stop(persisting: Bool = true) {
        if persisting { persistProgress(force: true) }
        stateTask?.cancel()
        stateTask = nil
        #if !os(macOS)
        mediaSelectionTask?.cancel()
        mediaSelectionTask = nil
        #endif
        #if os(macOS)
        player?.stateChangeHandler = nil
        player?.stop()
        #else
        player?.pause()
        #endif
        player = nil
        source = nil
        mediaItem = nil
        episode = nil
        progressHandler = nil
        positionSeconds = 0
        durationSeconds = nil
        isPaused = false
        audioTracks = []
        subtitleTracks = []
        areTracksLoading = false
        isPresentingPlayer = false
    }

    #if !os(macOS)
    private func applyMediaSelection(
        _ policy: PlaybackMediaSelectionPolicy,
        to player: AVPlayer,
        item: AVPlayerItem
    ) {
        player.appliesMediaSelectionCriteriaAutomatically = true

        if let languages = policy.audioLanguages {
            player.setMediaSelectionCriteria(
                AVPlayerMediaSelectionCriteria(
                    preferredLanguages: languages,
                    preferredMediaCharacteristics: nil
                ),
                forMediaCharacteristic: .audible
            )
        }

        if policy.disablesSubtitles {
            player.setMediaSelectionCriteria(
                AVPlayerMediaSelectionCriteria(
                    preferredLanguages: [],
                    preferredMediaCharacteristics: []
                ),
                forMediaCharacteristic: .legible
            )
            mediaSelectionTask = Task { [weak item] in
                guard let item else { return }
                guard let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) else { return }
                guard !Task.isCancelled else { return }
                item.select(nil, in: group)
            }
        } else if policy.subtitleLanguages != nil || policy.prefersSDH {
            let characteristics: [AVMediaCharacteristic]? = policy.prefersSDH
                ? [.transcribesSpokenDialogForAccessibility, .describesMusicAndSoundForAccessibility]
                : nil
            player.setMediaSelectionCriteria(
                AVPlayerMediaSelectionCriteria(
                    preferredLanguages: policy.subtitleLanguages,
                    preferredMediaCharacteristics: characteristics
                ),
                forMediaCharacteristic: .legible
            )
        }
    }
    #endif

    #if os(macOS)
    private static func mpvSubtitleStyle(for preferences: SettingsPreferences) -> [String: Any] {
        let appearance = preferences.resolvedSubtitleAppearance.normalized
        let outlineSize: Double
        let shadowOffset: Double
        switch appearance.edgeStyle {
        case .none:
            outlineSize = 0
            shadowOffset = 0
        case .outline:
            outlineSize = 1.65
            shadowOffset = 0
        case .shadow:
            outlineSize = 0
            shadowOffset = 2
        case .outlineAndShadow:
            outlineSize = 1.65
            shadowOffset = 2
        }

        return [
            "scale": Double(appearance.textScalePercent) / 100,
            "textColor": appearance.textColor.mpvColor,
            "outlineColor": appearance.outlineColor.mpvColor,
            "backgroundColor": appearance.backgroundColor.mpvColor(
                alphaPercent: appearance.backgroundOpacityPercent
            ),
            "edgeStyle": appearance.usesBackground ? "background-box" : "outline-and-shadow",
            "outlineSize": outlineSize,
            "shadowOffset": shadowOffset,
            "position": appearance.position.mpvPosition,
            "alignment": appearance.alignment.mpvAlignment,
            "margin": appearance.horizontalMarginPercent,
            "bold": appearance.isBold,
            "italic": appearance.isItalic,
        ]
    }
    #endif

    var nextEpisode: MediaEpisode? {
        guard let episode else { return nil }
        let episodes = mediaItem?.details?.seasons.flatMap(\.episodes).sorted {
            ($0.seasonNumber, $0.episodeNumber) < ($1.seasonNumber, $1.episodeNumber)
        } ?? []
        guard let index = episodes.firstIndex(where: {
            $0.id == episode.id
                || ($0.seasonNumber == episode.seasonNumber && $0.episodeNumber == episode.episodeNumber)
        }), episodes.indices.contains(index + 1) else { return nil }
        return episodes[index + 1]
    }

    private func observePlaybackState() {
        stateTask?.cancel()
        stateTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                self?.refreshState()
            }
        }
    }

    private func refreshState() {
        #if os(macOS)
        guard let player else { return }
        playbackError = player.errorMessage
        positionSeconds = max(player.position, 0)
        let duration = player.duration
        durationSeconds = duration.isFinite && duration > 0 ? duration : nil
        isPaused = player.isPaused
        volume = min(max(player.volume / 100, 0), 1)
        playbackRate = player.playbackRate.isFinite && player.playbackRate > 0 ? player.playbackRate : 1
        #else
        guard let player else { return }
        positionSeconds = max(player.currentTime().seconds, 0)
        let duration = player.currentItem?.duration.seconds ?? 0
        durationSeconds = duration.isFinite && duration > 0 ? duration : nil
        isPaused = player.timeControlStatus != .playing
        #endif
        persistProgress(force: false)
    }

    #if os(macOS)
    private func apply(_ snapshot: OMMpvPlaybackSnapshot) {
        playbackError = snapshot.errorMessage
        audioTracks = snapshot.audioTracks.map(PlaybackTrack.init)
        subtitleTracks = snapshot.subtitleTracks.map(PlaybackTrack.init)
        areTracksLoading = snapshot.tracksLoading
    }
    #endif

    private func persistProgress(force: Bool) {
        guard positionSeconds > 0 else { return }
        guard force || positionSeconds - lastPersistedPosition >= 10 else { return }
        lastPersistedPosition = positionSeconds
        progressHandler?(positionSeconds, durationSeconds)
    }
}

#if os(macOS)
private extension SubtitleAppearance.SemanticColor {
    var mpvColor: String { mpvColor(alphaPercent: 100) }

    func mpvColor(alphaPercent: Int) -> String {
        let rgb: String
        switch self {
        case .white: rgb = "FFFFFF"
        case .yellow: rgb = "FFFF00"
        case .black: rgb = "000000"
        }
        let boundedAlpha = min(max(alphaPercent, 0), 100)
        let alpha = Int((Double(boundedAlpha) / 100 * 255).rounded())
        return String(format: "#%02X%@", alpha, rgb)
    }
}

private extension SubtitleAppearance.Position {
    var mpvPosition: Int {
        switch self {
        case .top: 10
        case .middle: 50
        case .bottom: 95
        }
    }
}

private extension SubtitleAppearance.Alignment {
    var mpvAlignment: String {
        switch self {
        case .leading: "left"
        case .center: "center"
        case .trailing: "right"
        }
    }
}
#endif
