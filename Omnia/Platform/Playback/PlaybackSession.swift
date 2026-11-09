//
//  PlaybackSession.swift
//  Omnia
//

import Foundation
import SwiftUI
import Observation
import AVFoundation

#if os(macOS)
import AppKit
import AudioToolbox
import CoreAudio
#else
import AVFoundation
import AVKit
#endif

#if os(macOS)
protocol MacOutputVolumeControlling: AnyObject {
    var currentVolume: Double? { get }
    @discardableResult func setVolume(_ value: Double) -> Bool
}

struct MacPlaybackVolumeRouting {
    static func playerVolumePercent(
        requestedVolume: Double,
        systemVolumeAvailable: Bool
    ) -> Double {
        systemVolumeAvailable ? 100 : min(max(requestedVolume, 0), 1) * 100
    }
}

final class CoreAudioOutputVolumeController: MacOutputVolumeControlling {
    var currentVolume: Double? {
        guard let device = defaultOutputDevice else { return nil }

        var volume = Float32.zero
        var volumeSize = UInt32(MemoryLayout<Float32>.size)
        var volumeAddress = Self.volumeAddress
        guard AudioObjectHasProperty(device, &volumeAddress),
              AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &volumeSize, &volume) == noErr
        else { return nil }

        var mute = UInt32.zero
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        var muteAddress = Self.muteAddress
        if AudioObjectHasProperty(device, &muteAddress),
           AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &muteSize, &mute) == noErr,
           mute != 0 {
            return 0
        }
        return min(max(Double(volume), 0), 1)
    }

    @discardableResult
    func setVolume(_ value: Double) -> Bool {
        guard let device = defaultOutputDevice else { return false }
        var address = Self.volumeAddress
        var isSettable = DarwinBoolean(false)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &isSettable) == noErr,
              isSettable.boolValue
        else { return false }

        let clampedValue = min(max(value, 0), 1)
        if clampedValue > 0 {
            unmute(device)
        }
        var scalar = Float32(clampedValue)
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(device, &address, 0, nil, size, &scalar) == noErr
    }

    private var defaultOutputDevice: AudioDeviceID? {
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        ) == noErr,
        device != kAudioObjectUnknown else { return nil }
        return device
    }

    private func unmute(_ device: AudioDeviceID) {
        var address = Self.muteAddress
        var isSettable = DarwinBoolean(false)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &isSettable) == noErr,
              isSettable.boolValue
        else { return }
        var mute = UInt32.zero
        let size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectSetPropertyData(device, &address, 0, nil, size, &mute)
    }

    private static let volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    private static let muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
}
#endif

nonisolated struct PlaybackTrackSelectionGate: Equatable {
    private(set) var audioRequestID: UInt64?
    private(set) var subtitleRequestID: UInt64?

    mutating func beginAudio(_ id: UInt64) {
        audioRequestID = id == 0 ? nil : id
    }

    mutating func beginSubtitle(_ id: UInt64) {
        subtitleRequestID = id == 0 ? nil : id
    }

    mutating func finishAudio(_ id: UInt64) -> Bool {
        guard audioRequestID == id else { return false }
        audioRequestID = nil
        return true
    }

    mutating func finishSubtitle(_ id: UInt64) -> Bool {
        guard subtitleRequestID == id else { return false }
        subtitleRequestID = nil
        return true
    }

    mutating func reset() {
        audioRequestID = nil
        subtitleRequestID = nil
    }
}

#if os(macOS)

@MainActor
final class PlaybackTimelinePreviewRequestScheduler {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private let sleep: Sleep
    private var task: Task<Void, Never>?

    init(sleep: @escaping Sleep = { try await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    func schedule(
        after delay: Duration,
        operation: @escaping @MainActor () async -> Void
    ) {
        task?.cancel()
        task = Task {
            do {
                try await sleep(delay)
                try Task.checkCancellation()
                await operation()
            } catch {
                return
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
#endif

nonisolated enum PlaybackInput: Sendable {
    case stream(PlaybackSource)
    #if os(macOS)
    case cachedStream(
        source: PlaybackSource,
        protection: LocalPlaybackJobCoordinator.PlaybackProtection
    )
    case disc(
        source: PlaybackSource,
        request: DiscPlaybackRequest,
        protection: LocalPlaybackJobCoordinator.PlaybackProtection
    )
    #endif

    var source: PlaybackSource {
        switch self {
        case let .stream(source):
            source
        #if os(macOS)
        case let .cachedStream(source, _), let .disc(source, _, _):
            source
        #endif
        }
    }

    #if os(macOS)
    var cacheProtection: LocalPlaybackJobCoordinator.PlaybackProtection? {
        switch self {
        case .stream:
            nil
        case let .cachedStream(_, protection), let .disc(_, _, protection):
            protection
        }
    }
    #endif
}

/// One shared player session keeps playback independent from the transient
/// source picker. macOS is backed by libmpv; iOS retains an AVFoundation
/// fallback because libmpv is not bundled for Apple's mobile platforms.
enum PlaybackAspectRatioMode: String, CaseIterable, Sendable {
    case original
    case fill

    var next: Self {
        switch self {
        case .original: .fill
        case .fill: .original
        }
    }

    var title: String {
        switch self {
        case .original: "Original"
        case .fill: "Fill"
        }
    }
}

nonisolated struct PlaybackPeriodicState: Equatable, Sendable {
    let errorMessage: String?
    let positionSeconds: Double
    let durationSeconds: Double?
    let isPaused: Bool
    let playbackRate: Double
    let isPictureInPictureActive: Bool
    let isPictureInPictureAvailable: Bool
}

/// Where automatic subtitle sync stands for what is playing.
enum SubtitleSyncStatus: Equatable, Sendable {
    case idle
    /// Listening to the audio; `progress` runs from 0 to 1.
    case listening(progress: Double)
    case synced(delay: Double)
    case failed(String)
}

@Observable
@MainActor
final class PlaybackSession {
    enum Purpose: Equatable { case title, trailer }
    private(set) var purpose: Purpose = .title
    private(set) var trailerPlayer: AVPlayer?
    @ObservationIgnored private var trailerPlaylistLoader: TrailerPlaylistLoader?

    #if OMNIA_MPV
    private(set) var player: (any PlaybackEngine)?
    #else
    private(set) var player: AVPlayer?
    #endif
    #if OMNIA_MPV && !os(macOS)
    /// AVPlayer plays a source mpv couldn't draw (no Metal output).
    private(set) var fallbackPlayer: AVPlayer?
    /// What started the source, for starting it again with AVPlayer.
    @ObservationIgnored private var fallbackContext: (preferences: SettingsPreferences, position: Double?)?
    #endif
    #if !os(macOS)
    let outputVolumeController = IOSOutputVolumeController()
    let pictureInPictureController = IOSPictureInPictureController()

    private var avPlayer: AVPlayer? {
        if isPictureInPictureActive, pictureInPictureController.isHandoff {
            return pictureInPictureController.player
        }
        if let trailerPlayer { return trailerPlayer }
        #if OMNIA_MPV
        return fallbackPlayer
        #else
        return player
        #endif
    }
    #endif

    /// Whether a player is open, whichever engine plays it.
    var hasPlayer: Bool {
        if trailerPlayer != nil { return true }
        #if OMNIA_MPV && !os(macOS)
        return player != nil || fallbackPlayer != nil
        #else
        return player != nil
        #endif
    }

    private(set) var source: PlaybackSource?
    private(set) var mediaItem: MediaItem?
    private(set) var episode: MediaEpisode?
    private(set) var positionSeconds: Double = 0
    private(set) var durationSeconds: Double?
    private(set) var isPaused = false
    /// False until the first video frame is on screen, for the loading overlay.
    private(set) var hasRenderedVideoFrame = false
    private(set) var volume: Double = 1
    private(set) var playbackRate: Double = 1
    private(set) var aspectRatioMode: PlaybackAspectRatioMode = .original
    private(set) var playbackError: String?
    private(set) var audioTracks: [PlaybackTrack] = []
    private(set) var subtitleTracks: [PlaybackTrack] = []
    private(set) var areTracksLoading = false
    private(set) var subtitleStyle = PlaybackSubtitleStyle()
    private(set) var isFullScreenActive = false
    private(set) var isPictureInPictureActive = false
    private(set) var isPictureInPictureAvailable = false
    #if OMNIA_MPV
    private(set) var subtitleSyncStatus: SubtitleSyncStatus = .idle
    #endif
    #if os(macOS)
    private(set) var timelinePreviewTimestamp: Double?
    private(set) var timelinePreviewImage: NSImage?
    #endif
    var isPresentingPlayer = false
    /// The add-on stream now playing, for binge groups and Reuse Last Link.
    private(set) var currentCandidate: AddonStreamCandidate?
    /// The Reuse Last Link entry for what is playing, dropped if it fails.
    private(set) var currentLinkKey: MediaPlaybackKey?
    /// True while a failed source is being fetched again or replaced, so
    /// the player shows that instead of the error.
    var isRecoveringSource = false
    /// "Switched to another source", shown briefly over the video.
    var recoveryNotice: String?
    /// What a failed source can be recovered from: the title and the
    /// source list it was picked from (Dafa, 2026-10-26).
    @ObservationIgnored var recoveryContext: PlaybackRecoveryContext?

    @ObservationIgnored private var progressHandler: (@MainActor (Double, Double?) -> Void)?
    /// Trakt, Simkl and PublicMetaDB scrobbling.
    @ObservationIgnored private let trackers = TrackerAccountStore.shared
    @ObservationIgnored private var trackerMedia: TrackerMedia?
    private var trackerProgress: Double {
        guard let durationSeconds, durationSeconds > 0 else { return 0 }
        return positionSeconds / durationSeconds * 100
    }
    @ObservationIgnored private var subtitlePreferencesHandler: (@MainActor (PlaybackSubtitlePreferenceUpdate) -> Void)?
    @ObservationIgnored private var stateTask: Task<Void, Never>?
    #if !os(macOS)
    @ObservationIgnored private var mediaSelectionTask: Task<Void, Never>?
    #endif
    #if OMNIA_MPV
    @ObservationIgnored private var trackSelectionGate = PlaybackTrackSelectionGate()
    @ObservationIgnored private var pendingSubtitlePreference: (id: Int?, tracks: [PlaybackTrack])?
    @ObservationIgnored private var addonSubtitleTask: Task<Void, Never>?
    /// Metal fell back to OpenGL for this player and Diagnostics has it.
    @ObservationIgnored private var didLogRenderingFallback = false
    /// Settings' subtitle delay; delays set in the player are kept per title
    /// instead of replacing it.
    @ObservationIgnored private var defaultSubtitleDelay: Double = 0
    #endif
    #if os(macOS)
    @ObservationIgnored private var cacheProtection: LocalPlaybackJobCoordinator.PlaybackProtection?
    @ObservationIgnored private let outputVolumeController: MacOutputVolumeControlling
    @ObservationIgnored private var timelinePreviewService: PlaybackTimelinePreviewService?
    @ObservationIgnored private var pictureInPictureAfterFullScreen = false
    /// Settings › Video Player › Use Whole Screen, read when playback starts.
    @ObservationIgnored private var usesWholeScreen = false
    @ObservationIgnored private let wholeScreen = WholeScreenPresentation()
    @ObservationIgnored private let displaySleep = DisplaySleepAssertion()
    @ObservationIgnored private let timelinePreviewScheduler = PlaybackTimelinePreviewRequestScheduler()
    #endif
    #if OMNIA_MPV
    @ObservationIgnored private var autoSyncsSubtitles = false
    @ObservationIgnored private var didAutoSyncAtStart = false
    @ObservationIgnored private var subtitleSyncTask: Task<Void, Never>?
    @ObservationIgnored private var subtitleCueCache: (url: URL, cues: [SubtitleCue])?
    #endif
    @ObservationIgnored private var lastPersistedPosition: Double = 0
    @ObservationIgnored private var preloadedSources: (key: MediaPlaybackKey, resolution: PlaybackSourceResolution, loadedAt: Date)?
    @ObservationIgnored private var sourceSelectionID: UUID?

    /// A new episode choice supersedes pending work from every older picker,
    /// including an Up Next picker that is still fading out.
    func beginSourceSelection() -> UUID {
        let id = UUID()
        sourceSelectionID = id
        return id
    }

    func isCurrentSourceSelection(_ id: UUID) -> Bool {
        sourceSelectionID == id
    }

    func cancelSourceSelection(_ id: UUID) {
        if sourceSelectionID == id { sourceSelectionID = nil }
    }

    func claimSourceSelection(_ id: UUID) -> Bool {
        guard sourceSelectionID == id else { return false }
        sourceSelectionID = nil
        return true
    }

    /// Records which add-on stream `start` is playing. Call after `start`,
    /// which clears it.
    func setCurrentSource(_ candidate: AddonStreamCandidate?, linkKey: MediaPlaybackKey?) {
        currentCandidate = candidate
        currentLinkKey = linkKey
    }

    /// Nuvio's Preload Next Episode Sources: one lookup kept for the next
    /// episode so its source list opens without waiting.
    func storePreloadedSources(_ resolution: PlaybackSourceResolution, for key: MediaPlaybackKey) {
        guard !resolution.candidates.isEmpty else { return }
        preloadedSources = (key, resolution, Date())
    }

    /// The preloaded lookup for `key`, used once, while under 15 minutes old.
    func takePreloadedSources(for key: MediaPlaybackKey) -> PlaybackSourceResolution? {
        guard let preloadedSources, preloadedSources.key == key else { return nil }
        self.preloadedSources = nil
        guard Date().timeIntervalSince(preloadedSources.loadedAt) < 15 * 60 else { return nil }
        return preloadedSources.resolution
    }

    #if os(macOS)
    init(outputVolumeController: MacOutputVolumeControlling? = nil) {
        let outputVolumeController = outputVolumeController ?? CoreAudioOutputVolumeController()
        self.outputVolumeController = outputVolumeController
        if let currentVolume = outputVolumeController.currentVolume {
            volume = min(max(currentVolume, 0), 1)
        }
    }
    #else
    init() {
        volume = Double(AVAudioSession.sharedInstance().outputVolume)
        outputVolumeController.changed = { [weak self] value in self?.volume = value }
        pictureInPictureController.stateChanged = { [weak self] active, available in
            self?.isPictureInPictureActive = active
            self?.isPictureInPictureAvailable = available
            if active { self?.recoveryNotice = nil }
        }
        pictureInPictureController.position = { [weak self] in self?.positionSeconds ?? 0 }
        pictureInPictureController.isPlaying = { [weak self] in self?.isPaused == false }
        pictureInPictureController.rate = { [weak self] in self?.playbackRate ?? 1 }
        pictureInPictureController.audioTrack = { [weak self] in self?.audioTracks.first(where: \.isSelected) }
        pictureInPictureController.subtitleTrack = { [weak self] in self?.subtitleTracks.first(where: \.isSelected) }
        pictureInPictureController.unavailable = { [weak self] reason in
            self?.recoveryNotice = reason.map { "Picture in Picture couldn't start: \($0)" }
                ?? "Picture in Picture isn't available for this video right now."
        }
        pictureInPictureController.willRestore = { [weak self] in
            self?.isPictureInPictureActive = false
        }
        pictureInPictureController.closedFromWindow = { [weak self] in
            self?.stop()
        }
        pictureInPictureController.handoffFailed = { [weak self] in
            self?.recoveryNotice = "Picture in Picture is unavailable for this source or track selection. Playback continues in Omnia."
        }
        #if OMNIA_MPV
        pictureInPictureController.duration = { [weak self] in self?.player?.duration ?? 0 }
        pictureInPictureController.setPlaying = { [weak self] playing in
            if playing { self?.player?.play() } else { self?.player?.pause() }
        }
        pictureInPictureController.seekBy = { [weak self] seconds in self?.player?.seek(by: seconds) }
        pictureInPictureController.beginFrames = { [weak self] handler in
            self?.player?.beginSampleBufferOutput { frame in handler(frame) } ?? false
        }
        pictureInPictureController.endFrames = { [weak self] in self?.player?.endSampleBufferOutput() }
        pictureInPictureController.captureFrame = { [weak self] handler in
            self?.player?.captureCurrentFrame { frame in handler(frame) }
        }
        pictureInPictureController.beginHandoff = { [weak self] in self?.player?.pause() }
        pictureInPictureController.endHandoff = { [weak self] position, playing in
            guard let self else { return }
            self.player?.seek(to: position)
            self.player?.setPlaybackRate(self.playbackRate)
            if playing { self.player?.play() } else { self.player?.pause() }
        }
        #endif
    }
    #endif

    /// Uses AVFoundation on every platform so the generated master retains its audio renditions.
    func startTrailer(item: MediaItem, source: HeroTrailerSource, adopting handoff: TrailerHandoff?, preferences: SettingsPreferences) {
        stop(persisting: true)
        purpose = .trailer
        recoveryContext = nil
        isRecoveringSource = false
        recoveryNotice = nil
        mediaItem = item
        playbackError = nil
        let player: AVPlayer
        if let handoff {
            player = handoff.player
            player.isMuted = false
            player.preventsDisplaySleepDuringVideoPlayback = true
            trailerPlaylistLoader = handoff.playlistLoader
        } else {
            let asset: AVURLAsset
            if let playlist = source.playlist {
                let loader = TrailerPlaylistLoader(playlist: playlist)
                trailerPlaylistLoader = loader
                asset = AVURLAsset(url: loader.url)
                asset.resourceLoader.setDelegate(loader, queue: loader.queue)
            } else {
                asset = AVURLAsset(url: source.url)
            }
            player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            player.allowsExternalPlayback = false
        }
        trailerPlayer = player
        #if os(macOS)
        usesWholeScreen = preferences.playbackBehavior.usesWholeScreen
        let usesSystemVolume = synchronizeOutputVolume()
        player.volume = usesSystemVolume ? 1 : Float(volume)
        #endif
        #if os(iOS)
        pictureInPictureController.activateAudioSession()
        pictureInPictureController.configure(player: player)
        #endif
        // Already playing, so no loading overlay; and the same picture carries
        // on, so the player appears without sliding in.
        if handoff != nil {
            hasRenderedVideoFrame = true
            positionSeconds = player.currentTime().seconds
            if let duration = player.currentItem?.duration.seconds, duration.isFinite {
                durationSeconds = duration
            }
        }
        var transaction = Transaction()
        transaction.disablesAnimations = handoff != nil
        withTransaction(transaction) { isPresentingPlayer = true }
        player.playImmediately(atRate: Float(playbackRate))
        observePlaybackState()
    }

    func start(
        item: MediaItem,
        episode: MediaEpisode? = nil,
        source: PlaybackSource,
        resumeAt position: Double?,
        preferences: SettingsPreferences,
        onProgress: @escaping @MainActor (Double, Double?) -> Void
    ) {
        start(
            item: item,
            episode: episode,
            input: .stream(source),
            resumeAt: position,
            preferences: preferences,
            onProgress: onProgress
        )
    }

    func start(
        item: MediaItem,
        episode: MediaEpisode? = nil,
        input: PlaybackInput,
        resumeAt position: Double?,
        preferences: SettingsPreferences,
        onProgress: @escaping @MainActor (Double, Double?) -> Void
    ) {
        stop(persisting: true)

        purpose = .title
        let source = input.source
        self.source = source
        #if os(iOS)
        pictureInPictureController.activateAudioSession()
        #endif
        // A title switched without closing the player still stops the last
        // one on the trackers.
        trackers.playbackStopped(trackerMedia, progress: trackerProgress, runtimeSeconds: durationSeconds)
        mediaItem = item
        self.episode = episode
        trackerMedia = TrackerMedia(item: item, episode: episode)
        // Live TV has nothing to resume.
        if !item.id.hasPrefix(PlaybackSource.liveTVIDPrefix) {
            ResumePromptMarker.mark(item.id)
        }
        progressHandler = onProgress
        playbackError = nil
        isPaused = false
        hasRenderedVideoFrame = false
        positionSeconds = 0
        durationSeconds = nil
        lastPersistedPosition = 0
        audioTracks = []
        subtitleTracks = []
        areTracksLoading = false
        isFullScreenActive = false
        isPictureInPictureActive = false
        isPictureInPictureAvailable = false
        aspectRatioMode = .original

        #if OMNIA_MPV
        trackSelectionGate.reset()
        pendingSubtitlePreference = nil
        let mpv: any PlaybackEngine
        let usesKSPlayer = preferences.playbackBehavior.engine == .ksPlayer
        #if os(macOS)
        cacheProtection = input.cacheProtection
        switch input {
        case .stream, .cachedStream:
            mpv = usesKSPlayer
                ? KSPlayerEngine(url: source.url, requestHeaders: source.requestHeaders)
                : OMMpvPlayerController(url: source.url, requestHeaders: source.requestHeaders)
        case let .disc(_, request, _):
            // Discs stay with mpv, which reads Blu-ray menus and playlists.
            mpv = OMMpvPlayerController(
                url: request.playbackURL,
                requestHeaders: request.requestHeaders,
                blurayDeviceURL: request.deviceURL
            )
        }
        #else
        mpv = usesKSPlayer
            ? KSPlayerEngine(url: source.url, requestHeaders: source.requestHeaders)
            : OMMpvPlayerController(url: source.url, requestHeaders: source.requestHeaders)
        fallbackContext = (preferences, position)
        #endif
        mpv.stateChangeHandler = { [weak self] snapshot in
            self?.apply(snapshot)
        }
        // KSPlayer notes what its audio is doing in Diagnostics, with the
        // stream it played, until its sound is confirmed on every build.
        (mpv as? KSPlayerEngine)?.onAudioReport = { [weak self] report in
            guard let self, let mediaItem = self.mediaItem else { return }
            let stream = [self.currentCandidate?.displayName, self.currentCandidate?.filename]
                .compactMap { $0 }
                .joined(separator: " / ")
            _ = PlaybackFailureLog.shared.record(
                item: mediaItem,
                episode: self.episode,
                candidate: self.currentCandidate,
                streamURL: self.source?.url,
                message: "KSPlayer audio check · \(report) · stream \(stream.isEmpty ? "unknown" : String(stream.prefix(160)))"
            )
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
        mpv.setPlayerOptions(Self.mpvPlayerOptions(for: preferences))
        mpv.prefersMetalRendering = preferences.playbackBehavior.metalRendering
        didLogRenderingFallback = false
        subtitleStyle = preferences.playbackSubtitleStyle.normalized
        defaultSubtitleDelay = subtitleStyle.delaySeconds
        #if os(macOS)
        usesWholeScreen = preferences.playbackBehavior.usesWholeScreen
        #endif
        if let key = subtitleDelayKey, let remembered = SubtitleDelayMemory.delay(for: key) {
            subtitleStyle.delaySeconds = remembered
        }
        autoSyncsSubtitles = preferences.playbackBehavior.autoSyncsSubtitles
        didAutoSyncAtStart = false
        subtitleSyncStatus = .idle
        subtitleCueCache = nil
        var mpvStyle = preferences.subtitleAppearance == .followSystem
            ? [String: Any]()
            : Self.mpvSubtitleStyle(for: preferences)
        mpvStyle.merge(Self.mpvSubtitleOverrides(for: subtitleStyle)) { _, latest in latest }
        mpv.setSubtitleStyle(mpvStyle)
        #if os(macOS)
        let usesSystemVolume = synchronizeOutputVolume()
        mpv.setVolume(
            MacPlaybackVolumeRouting.playerVolumePercent(
                requestedVolume: volume,
                systemVolumeAvailable: usesSystemVolume
            )
        )
        #else
        mpv.setVolume(100)
        #endif
        mpv.setPlaybackRate(playbackRate)
        mpv.setVideoAspectMode(.original)
        if let position, position > 0 { mpv.seek(to: position) }
        isPresentingPlayer = true
        refreshState()
        observePlaybackState()
        #else
        startAVPlayer(source: source, item: item, preferences: preferences, resumeAt: position)
        isPresentingPlayer = true
        observePlaybackState()
        #endif
    }

    #if !os(macOS)
    private func startAVPlayer(
        source: PlaybackSource,
        item: MediaItem,
        preferences: SettingsPreferences,
        resumeAt position: Double?
    ) {
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
        player.volume = 1
        pictureInPictureController.configure(player: player)
        #if OMNIA_MPV
        fallbackPlayer = player
        #else
        self.player = player
        #endif
        if let position, position > 0 {
            player.seek(to: CMTime(seconds: position, preferredTimescale: 600))
        }
        player.play()
    }
    #endif

    #if OMNIA_MPV && !os(macOS)
    /// mpv couldn't draw this source (no Metal output on this device), so
    /// AVPlayer plays it from where it was. Network and format errors stay
    /// mpv's, since AVPlayer would fail the same way and say less.
    private func fallBackToAVPlayer(from mpv: any PlaybackEngine) {
        guard let source, let mediaItem, let fallbackContext,
              mpv.renderingFallbackReason != nil || mpv.errorMessage?.hasPrefix("libmpv could not create") == true
        else { return }
        let resumeAt = max(positionSeconds, fallbackContext.position ?? 0)
        self.fallbackContext = nil
        mpv.stateChangeHandler = nil
        mpv.stop()
        player = nil
        playbackError = nil
        audioTracks = []
        subtitleTracks = []
        areTracksLoading = false
        startAVPlayer(source: source, item: mediaItem, preferences: fallbackContext.preferences, resumeAt: resumeAt)
    }
    #endif

    func togglePause() {
        if let trailerPlayer {
            trailerPlayer.rate == 0 ? trailerPlayer.playImmediately(atRate: Float(playbackRate)) : trailerPlayer.pause()
            refreshState()
            return
        }
        #if os(iOS)
        if isPictureInPictureActive, pictureInPictureController.isHandoff,
           let player = pictureInPictureController.player {
            player.rate == 0 ? player.playImmediately(atRate: Float(playbackRate)) : player.pause()
            return
        }
        #endif
        #if OMNIA_MPV
        player?.togglePause()
        #endif
        #if !os(macOS)
        if let avPlayer {
            avPlayer.timeControlStatus == .playing ? avPlayer.pause() : avPlayer.play()
        }
        #endif
        refreshState()
    }

    func seek(by seconds: Double) {
        if trailerPlayer != nil { seek(to: positionSeconds + seconds); return }
        #if os(iOS)
        if isPictureInPictureActive, pictureInPictureController.isHandoff {
            pictureInPictureController.player?.seek(to: CMTime(seconds: max(positionSeconds + seconds, 0), preferredTimescale: 600))
            return
        }
        #endif
        #if OMNIA_MPV
        player?.seek(by: seconds)
        #endif
        #if !os(macOS)
        avPlayer?.seek(to: CMTime(seconds: max(positionSeconds + seconds, 0), preferredTimescale: 600))
        #endif
    }

    func seek(to seconds: Double) {
        if let trailerPlayer { trailerPlayer.seek(to: CMTime(seconds: max(seconds, 0), preferredTimescale: 600)); return }
        #if os(iOS)
        if isPictureInPictureActive, pictureInPictureController.isHandoff {
            pictureInPictureController.player?.seek(to: CMTime(seconds: max(seconds, 0), preferredTimescale: 600))
            return
        }
        #endif
        #if OMNIA_MPV
        player?.seek(to: seconds)
        #endif
        #if !os(macOS)
        avPlayer?.seek(to: CMTime(seconds: max(seconds, 0), preferredTimescale: 600))
        #endif
    }

    /// Follows a timeline drag with quick keyframe seeks; the exact seek
    /// comes when the drag ends.
    func previewSeek(to seconds: Double) {
        if trailerPlayer != nil { seek(to: seconds); return }
        #if OMNIA_MPV
        player?.previewSeek(to: seconds)
        #endif
        #if !os(macOS)
        avPlayer?.seek(to: CMTime(seconds: max(seconds, 0), preferredTimescale: 600))
        #endif
    }

    func endTimelinePreview() {
        #if os(macOS)
        timelinePreviewScheduler.cancel()
        timelinePreviewTimestamp = nil
        timelinePreviewImage = nil
        let service = timelinePreviewService
        timelinePreviewService = nil
        Task {
            await service?.stop()
        }
        #endif
    }

    func setVolume(_ value: Double) {
        #if os(macOS)
        volume = min(max(value, 0), 1)
        let usesSystemVolume = outputVolumeController.setVolume(volume)
        trailerPlayer?.volume = usesSystemVolume ? 1 : Float(volume)
        player?.setVolume(
            MacPlaybackVolumeRouting.playerVolumePercent(
                requestedVolume: volume,
                systemVolumeAvailable: usesSystemVolume
            )
        )
        #else
        #if OMNIA_MPV
        player?.setVolume(100)
        #endif
        avPlayer?.volume = 1
        // outputVolume updates a moment later, and its observer confirms then;
        // reading it here would show the previous level during a drag.
        let requested = min(max(value, 0), 1)
        volume = outputVolumeController.setVolume(requested)
            ? requested
            : Double(AVAudioSession.sharedInstance().outputVolume)
        #endif
    }

    #if os(macOS)
    @discardableResult
    func synchronizeOutputVolume() -> Bool {
        guard let currentVolume = outputVolumeController.currentVolume else { return false }
        let nextVolume = min(max(currentVolume, 0), 1)
        if volume != nextVolume {
            volume = nextVolume
        }
        return true
    }
    #endif

    func setPlaybackRate(_ value: Double) {
        if let trailerPlayer {
            playbackRate = min(max(value, 0.25), 3)
            trailerPlayer.rate = isPaused ? 0 : Float(playbackRate)
            return
        }
        playbackRate = min(max(value, 0.25), 4)
        #if os(iOS)
        if isPictureInPictureActive, pictureInPictureController.isHandoff {
            pictureInPictureController.player?.rate = isPaused ? 0 : Float(playbackRate)
            return
        }
        #endif
        #if OMNIA_MPV
        player?.setPlaybackRate(playbackRate)
        #endif
        #if !os(macOS)
        if let avPlayer {
            avPlayer.rate = isPaused ? 0 : Float(playbackRate)
        }
        #endif
    }

    func cycleAspectRatio() {
        aspectRatioMode = aspectRatioMode.next
        #if OMNIA_MPV
        switch aspectRatioMode {
        case .original:
            player?.setVideoAspectMode(.original)
        case .fill:
            player?.setVideoAspectMode(.fill)
        }
        #endif
    }

    func cycleSubtitles() {
        #if OMNIA_MPV
        player?.cycleSubtitles()
        #endif
    }

    func cycleAudioTrack() {
        #if OMNIA_MPV
        player?.cycleAudioTrack()
        #endif
    }

    func selectAudioTrack(_ id: Int) {
        #if OMNIA_MPV
        guard let player else { return }
        let requestID = player.selectAudioTrack(id: id) { [weak self] completedID, succeeded, message in
            guard let self, self.trackSelectionGate.finishAudio(completedID) else { return }
            if !succeeded, let message {
                self.playbackError = message
            }
            self.refreshState()
        }
        trackSelectionGate.beginAudio(requestID)
        if requestID == 0 {
            playbackError = "Audio track selection is unavailable."
        }
        #endif
    }

    func selectSubtitleTrack(_ id: Int?) {
        #if OMNIA_MPV
        guard let player else { return }
        let requestedTracks = subtitleTracks
        let requestID = player.selectSubtitleTrack(id: id.map { NSNumber(value: $0) }) {
            [weak self] completedID,
            succeeded,
            message in
            guard let self, self.trackSelectionGate.finishSubtitle(completedID) else { return }
            if succeeded {
                self.pendingSubtitlePreference = (id, requestedTracks)
                self.confirmPendingSubtitlePreference()
            } else if let message {
                self.pendingSubtitlePreference = nil
                self.playbackError = message
            }
            self.refreshState()
        }
        trackSelectionGate.beginSubtitle(requestID)
        if requestID == 0 {
            playbackError = "Subtitle track selection is unavailable."
        }
        #endif
    }

    func setSubtitlePreferencesHandler(
        _ handler: (@MainActor (PlaybackSubtitlePreferenceUpdate) -> Void)?
    ) {
        subtitlePreferencesHandler = handler
    }

    func setSubtitleFont(_ fontName: String) {
        subtitleStyle.fontName = fontName
        #if OMNIA_MPV
        applySubtitleStyle()
        #endif
    }

    func setSubtitleFontSize(_ size: Double) {
        subtitleStyle.fontSize = size
        #if OMNIA_MPV
        applySubtitleStyle()
        #endif
    }

    func setSubtitleScale(_ scale: Double) {
        subtitleStyle.scale = scale
        #if OMNIA_MPV
        applySubtitleStyle()
        #endif
    }

    func setSubtitlePosition(_ position: Double) {
        subtitleStyle.position = position
        #if OMNIA_MPV
        applySubtitleStyle()
        #endif
    }

    func setSubtitleShadowOpacity(_ opacity: Double) {
        subtitleStyle.shadowOpacity = opacity
        #if OMNIA_MPV
        applySubtitleStyle()
        #endif
    }

    func setSubtitleShadowBlurRadius(_ radius: Double) {
        subtitleStyle.shadowBlurRadius = radius
        #if OMNIA_MPV
        applySubtitleStyle()
        #endif
    }

    func setSubtitleBackground(_ background: PlaybackSubtitleBackground) {
        subtitleStyle.background = background
        #if OMNIA_MPV
        applySubtitleStyle()
        #endif
    }

    #if OMNIA_MPV
    /// mpv's sub-delay in tenths of a second; positive shows subtitles later.
    /// Kept for this title only.
    func setSubtitleDelay(_ seconds: Double) {
        guard seconds.isFinite else { return }
        let delay = (min(max(seconds, -30), 30) * 10).rounded() / 10
        subtitleStyle.delaySeconds = delay
        if let key = subtitleDelayKey {
            SubtitleDelayMemory.remember(delay == defaultSubtitleDelay ? nil : delay, for: key)
        }
        applySubtitleStyle()
    }

    private var subtitleDelayKey: String? {
        guard let mediaItem, !mediaItem.id.hasPrefix(PlaybackSource.liveTVIDPrefix) else { return nil }
        return [mediaItem.id, episode?.id].compactMap { $0 }.joined(separator: "#")
    }

    enum SubtitleSyncProblem: LocalizedError {
        case noSubtitle
        case embedded
        case unreadable
        case unavailable

        var errorDescription: String? {
            switch self {
            case .noSubtitle:
                "Turn on a subtitle first."
            case .embedded:
                "This subtitle is part of the video, so it is usually already in sync. Use the delay slider or Sync by Ear if it isn't."
            case .unreadable:
                "This subtitle file's timing couldn't be read."
            case .unavailable:
                "The subtitle file couldn't be downloaded."
            }
        }
    }

    /// The timing of every line in the selected add-on subtitle.
    func selectedSubtitleCues() async throws -> [SubtitleCue] {
        guard let track = subtitleTracks.first(where: \.isSelected) else { throw SubtitleSyncProblem.noSubtitle }
        guard let url = track.externalURL else { throw SubtitleSyncProblem.embedded }
        if let subtitleCueCache, subtitleCueCache.url == url { return subtitleCueCache.cues }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let data: Data
        do {
            let (body, response) = try await OmniaNetwork.noStore.data(for: request)
            guard (response as? HTTPURLResponse).map({ (200 ..< 300).contains($0.statusCode) }) ?? true else {
                throw SubtitleSyncProblem.unavailable
            }
            data = body
        } catch {
            throw SubtitleSyncProblem.unavailable
        }
        let cues = await Task.detached(priority: .userInitiated) {
            SubtitleAutoSync.cues(fromSubtitleData: data)
        }.value
        guard cues.count >= 8 else { throw SubtitleSyncProblem.unreadable }
        subtitleCueCache = (url, cues)
        return cues
    }

    /// Nuvio Enhanced's AutoSync, done Omnia's way: listen to how loud the
    /// audio is while the video plays, then pick the delay at which the
    /// subtitle's lines show while people speak. Tries after 45 seconds of
    /// listening and keeps listening, up to three minutes, until it is sure.
    func startAutomaticSubtitleSync() {
        guard let player else { return }
        subtitleSyncTask?.cancel()
        subtitleSyncStatus = .listening(progress: 0)
        subtitleSyncTask = Task { [weak self] in
            guard let self else { return }
            let cues: [SubtitleCue]
            do {
                cues = try await self.selectedSubtitleCues()
            } catch {
                guard !Task.isCancelled else { return }
                self.subtitleSyncStatus = .failed(error.localizedDescription)
                return
            }
            player.setSpeechActivityProbeEnabled(true)
            defer { player.setSpeechActivityProbeEnabled(false) }
            var samples: [SubtitleSyncSample] = []
            var lastTime = -1.0
            let attempts = [450, 750, 1_050, 1_400, 1_800]
            let target = attempts.last ?? 1_800
            var waited = 0
            var lastAttempt = 0
            while !Task.isCancelled, self.player === player {
                try? await Task.sleep(for: .milliseconds(100))
                waited += 1
                let time = player.position
                // Only fresh audio counts: skip pauses, seeks backwards and
                // the moments before the probe reports anything.
                if !player.isPaused, time > lastTime, time - lastTime < 2,
                   let level = player.speechActivityLevel()?.doubleValue {
                    samples.append(SubtitleSyncSample(time: time, decibels: level))
                }
                lastTime = time
                let progress = (min(Double(samples.count) / Double(target), 0.99) * 100).rounded() / 100
                if self.subtitleSyncStatus != .listening(progress: progress) {
                    self.subtitleSyncStatus = .listening(progress: progress)
                }
                guard attempts.contains(samples.count), samples.count != lastAttempt else {
                    // Ten minutes without enough fresh audio, e.g. paused.
                    if waited > 6_000 { break }
                    continue
                }
                lastAttempt = samples.count
                let snapshot = samples
                let match = await Task.detached(priority: .utility) {
                    SubtitleAutoSync.bestDelay(cues: cues, samples: snapshot)
                }.value
                guard !Task.isCancelled, self.player === player else { return }
                if let match, match.confidence >= 0.03 || samples.count >= target {
                    self.setSubtitleDelay(match.delay)
                    self.subtitleSyncStatus = .synced(delay: match.delay)
                    return
                }
                if samples.count >= target { break }
            }
            guard !Task.isCancelled, self.player === player else { return }
            self.subtitleSyncStatus = .failed(
                "Couldn't match this subtitle to the speech. Try Sync by Ear, or pick a different subtitle."
            )
        }
    }

    func cancelAutomaticSubtitleSync() {
        subtitleSyncTask?.cancel()
        subtitleSyncTask = nil
        player?.setSpeechActivityProbeEnabled(false)
        subtitleSyncStatus = .idle
    }

    /// Settings › Playback › Subtitles › Auto Sync: once per video, as soon
    /// as an add-on subtitle is showing and the video is playing.
    private func autoSyncSubtitlesIfNeeded() {
        guard autoSyncsSubtitles, !didAutoSyncAtStart, hasRenderedVideoFrame,
              subtitleTracks.first(where: \.isSelected)?.externalURL != nil,
              subtitleStyle.delaySeconds == defaultSubtitleDelay
        else { return }
        didAutoSyncAtStart = true
        startAutomaticSubtitleSync()
    }
    #endif

    func toggleFullScreen() {
        #if os(macOS)
        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow else { return }
        setFullScreen(!(window.styleMask.contains(.fullScreen) || wholeScreen.isActive), in: window)
        #endif
    }

    #if os(macOS)
    func setFullScreen(_ active: Bool) {
        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow else { return }
        setFullScreen(active, in: window)
    }

    func handleFullScreenEnter() {
        isFullScreenActive = true
    }

    func handleFullScreenExit() {
        isFullScreenActive = false
        // Picture in Picture asked for from full screen starts once the
        // window is back on the desktop.
        if pictureInPictureAfterFullScreen {
            pictureInPictureAfterFullScreen = false
            if !isPictureInPictureActive {
                player?.togglePictureInPicture()
                refreshState()
            }
        }
    }

    /// Picture in Picture leaves exclusive full screen first; otherwise the
    /// window stayed full screen, empty, behind the floating player.
    func togglePictureInPicture() {
        if !isPictureInPictureActive, isFullScreenActive {
            pictureInPictureAfterFullScreen = true
            setFullScreen(false)
            return
        }
        player?.togglePictureInPicture()
        refreshState()
    }
    #endif

    #if os(iOS)
    func togglePictureInPicture() {
        pictureInPictureController.toggle()
    }
    #endif

    func stop(persisting: Bool = true) {
        trailerPlayer?.pause()
        trailerPlayer?.replaceCurrentItem(with: nil)
        trailerPlayer = nil
        trailerPlaylistLoader = nil
        trackers.playbackStopped(trackerMedia, progress: trackerProgress, runtimeSeconds: durationSeconds)
        trackerMedia = nil
        sourceSelectionID = nil
        ResumePromptMarker.clear()
        shuffledNextEpisode = nil
        endTimelinePreview()
        // Opening streams have no new progress to save. Refreshing native
        // properties here can wait behind the demuxer while the user closes.
        #if os(iOS)
        if persisting && hasRenderedVideoFrame { flushProgress() }
        #else
        if persisting { flushProgress() }
        #endif
        #if os(macOS)
        pictureInPictureAfterFullScreen = false
        if isFullScreenActive {
            setFullScreen(false)
        }
        #endif
        stateTask?.cancel()
        stateTask = nil
        #if !os(macOS)
        mediaSelectionTask?.cancel()
        mediaSelectionTask = nil
        #endif
        #if OMNIA_MPV
        addonSubtitleTask?.cancel()
        addonSubtitleTask = nil
        trackSelectionGate.reset()
        pendingSubtitlePreference = nil
        subtitleSyncTask?.cancel()
        subtitleSyncTask = nil
        subtitleSyncStatus = .idle
        subtitleCueCache = nil
        #endif
        #if os(macOS)
        let cacheProtection = cacheProtection
        self.cacheProtection = nil
        if let cacheProtection {
            Task {
                await LocalPlaybackJobCoordinator.shared.unprotect(cacheProtection)
            }
        }
        #endif
        #if OMNIA_MPV
        player?.stateChangeHandler = nil
        #if os(macOS)
        if persisting { captureContinueWatchingScene() }
        #endif
        player?.stop()
        #endif
        #if os(macOS)
        displaySleep.release()
        #else
        avPlayer?.pause()
        pictureInPictureController.reset()
        pictureInPictureController.deactivateAudioSession()
        #endif
        #if OMNIA_MPV && !os(macOS)
        fallbackPlayer = nil
        fallbackContext = nil
        #endif
        player = nil
        source = nil
        mediaItem = nil
        episode = nil
        currentCandidate = nil
        currentLinkKey = nil
        progressHandler = nil
        positionSeconds = 0
        durationSeconds = nil
        isPaused = false
        hasRenderedVideoFrame = false
        audioTracks = []
        subtitleTracks = []
        areTracksLoading = false
        isFullScreenActive = false
        isPictureInPictureActive = false
        isPictureInPictureAvailable = false
        aspectRatioMode = .original
        isPresentingPlayer = false
    }

    /// Nuvio's Decoder Priority, Strip SDH and Use Forced Subtitles, as mpv
    /// options.
    static func mpvPlayerOptions(for preferences: SettingsPreferences) -> [String: String] {
        let behavior = preferences.playbackBehavior
        var options: [String: String] = [:]
        switch behavior.decoderPriority {
        case .deviceOnly:
            options["hwdec"] = "auto-safe"
            options["vd-lavc-software-fallback"] = "no"
        case .preferDevice:
            options["hwdec"] = "auto-safe"
        case .preferApp:
            options["hwdec"] = "no"
        }
        if behavior.stripSDHSubtitles {
            options["sub-filter-sdh"] = "yes"
            options["sub-filter-sdh-harder"] = "yes"
        }
        if behavior.useForcedSubtitles {
            // When the audio is already in the subtitle language, only a
            // forced track is picked, and otherwise none.
            options["subs-with-matching-audio"] = "forced"
        }
        return options
    }

    /// Asks every subtitle add-on for this title and adds what they return
    /// as tracks, as Nuvio does. Embedded tracks load first, so one in the
    /// preferred language stays selected; otherwise the first add-on track in
    /// the preferred language is selected, then one in the fallback language.
    func loadAddonSubtitles(
        addons: [InstalledAddon],
        item: MediaItem,
        episode: MediaEpisode?,
        videoSize: Int64?,
        preferences: SettingsPreferences
    ) {
        #if OMNIA_MPV
        addonSubtitleTask?.cancel()
        let subtitleAddons = addons.filter { $0.isEnabled && $0.manifest.supportsSubtitles }
        let identifiers = item.streamIdentifierCandidates(for: episode)
        guard !subtitleAddons.isEmpty,
              let player,
              let videoID = identifiers.first(where: { $0.hasPrefix("tt") }) ?? identifiers.first
        else { return }
        let mediaType = item.kind == .series ? "series" : "movie"
        let policy = PlaybackMediaSelectionPolicy.resolve(
            preferences: preferences,
            isAnime: item.hasAnimeIdentity
        )
        let behavior = preferences.playbackBehavior
        let targets = policy.disablesSubtitles ? [] : (policy.subtitleLanguages ?? Locale.preferredLanguages)
        addonSubtitleTask = Task { [weak self] in
            // Let embedded tracks load so an embedded match wins.
            for _ in 0 ..< 60 {
                guard let self, !Task.isCancelled else { return }
                if !self.areTracksLoading { break }
                try? await Task.sleep(for: .milliseconds(250))
            }
            var didSelect = false
            var fallbacks: [(subtitle: AddonSubtitle, addonName: String)] = []
            await withTaskGroup(of: (String, [AddonSubtitle]).self) { group in
                for addon in subtitleAddons {
                    group.addTask {
                        let subtitles = (try? await StremioAddonClient.fetchSubtitles(
                            from: addon,
                            mediaType: mediaType,
                            videoID: videoID,
                            videoSize: videoSize
                        )) ?? []
                        return (addon.displayName, subtitles)
                    }
                }
                for await (addonName, subtitles) in group {
                    guard let self, !Task.isCancelled, self.player === player else { return }
                    for subtitle in subtitles.prefix(80) {
                        guard let url = subtitle.url else { continue }
                        let match = targets.firstIndex { PlaybackLanguageMatching.matches(subtitle.lang, $0) }
                        if behavior.showOnlyPreferredSubtitleLanguages, !targets.isEmpty, match == nil { continue }
                        let isForced = "\(subtitle.id) \(url.absoluteString)".lowercased().contains("forced")
                        let canSelect = !didSelect
                            && isForced == behavior.useForcedSubtitles
                            && !self.subtitleTracks.contains(where: \.isSelected)
                        if match == 0, canSelect {
                            didSelect = true
                            self.addSubtitle(subtitle, url: url, addonName: addonName, select: true, to: player)
                        } else if let match, match > 0, canSelect {
                            fallbacks.append((subtitle, addonName))
                        } else {
                            self.addSubtitle(subtitle, url: url, addonName: addonName, select: false, to: player)
                        }
                    }
                }
            }
            guard let self, !Task.isCancelled, self.player === player else { return }
            let selectsFallback = !didSelect && !self.subtitleTracks.contains(where: \.isSelected)
            for (index, fallback) in fallbacks.enumerated() {
                guard let url = fallback.subtitle.url else { continue }
                self.addSubtitle(
                    fallback.subtitle,
                    url: url,
                    addonName: fallback.addonName,
                    select: selectsFallback && index == 0,
                    to: player
                )
            }
        }
        #endif
    }

    #if OMNIA_MPV
    private func addSubtitle(
        _ subtitle: AddonSubtitle,
        url: URL,
        addonName: String,
        select: Bool,
        to player: any PlaybackEngine
    ) {
        let language = PlaybackLanguageMatching.normalized(subtitle.lang)
        let languageName = language.flatMap { Locale.current.localizedString(forLanguageCode: $0) }
            ?? subtitle.lang
            ?? "Unknown"
        player.addSubtitleURL(url, title: "\(languageName) · \(addonName)", language: language, select: select)
    }
    #endif

    func flushProgress() {
        refreshState()
        persistProgress(force: true)
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
    private func setFullScreen(_ active: Bool, in window: NSWindow) {
        // Omnia's whole-screen mode has no system notifications, so it
        // reports entering and leaving itself.
        if wholeScreen.isActive || (active && usesWholeScreen && !window.styleMask.contains(.fullScreen)) {
            if active {
                wholeScreen.enter(window)
                handleFullScreenEnter()
            } else {
                wholeScreen.leave()
                handleFullScreenExit()
            }
            return
        }
        let isCurrentlyFullScreen = window.styleMask.contains(.fullScreen)
        guard active != isCurrentlyFullScreen else {
            isFullScreenActive = active
            return
        }
        window.toggleFullScreen(nil)
    }
    #endif

    #if OMNIA_MPV
    /// The style Settings keeps: everything chosen in the player except
    /// the delay, which belongs to this title.
    private var persistedSubtitleStyle: PlaybackSubtitleStyle {
        var style = subtitleStyle
        style.delaySeconds = defaultSubtitleDelay
        return style
    }

    private func applySubtitleStyle() {
        subtitleStyle = subtitleStyle.normalized
        player?.setSubtitleStyle(Self.mpvSubtitleOverrides(for: subtitleStyle))
        subtitlePreferencesHandler?(
            PlaybackSubtitlePreferenceUpdate(
                style: persistedSubtitleStyle,
                isEnabled: nil,
                preferredLanguage: nil
            )
        )
    }

    static func mpvSubtitleOverrides(for style: PlaybackSubtitleStyle) -> [String: Any] {
        let style = style.normalized
        return [
            "font": style.fontName,
            "fontSize": style.fontSize,
            "scale": style.scale,
            "position": style.position,
            "shadowOpacity": style.shadowOpacity,
            "shadowBlur": style.shadowBlurRadius,
            "background": style.background.rawValue,
            "backgroundRGB": style.backgroundColorHex,
            "textColor": "#" + style.textColorHex,
            "outlineColor": "#" + style.outlineColorHex,
            "outlineSize": style.outlineEnabled ? style.outlineSize : 0,
            "bold": style.isBold,
            "italic": style.isItalic,
            "delay": style.delaySeconds,
        ]
    }

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

    /// Set by Shuffle (Settings › Layout › Detail Page) for this episode.
    var shuffledNextEpisode: MediaEpisode?

    #if os(macOS)
    /// The frame playback stopped on, for Continue Watching's Paused Scene
    /// artwork. Skipped near the start and once the title counts as finished.
    private func captureContinueWatchingScene() {
        guard purpose == .title, let mediaItem, positionSeconds > 10,
              !mediaItem.id.hasPrefix(PlaybackSource.liveTVIDPrefix) else { return }
        if let durationSeconds, durationSeconds > 0, positionSeconds / durationSeconds >= 0.9 { return }
        let store = ContinueWatchingSceneStore.shared
        if let player, hasRenderedVideoFrame,
           store.capture(for: mediaItem.id, write: { player.writeCurrentScene(to: $0) }) {
            return
        }
        // mpv couldn't save the frame on screen (it can't with some decoders):
        // decode the frame at the same moment from the stream instead.
        guard let source else { return }
        let mediaID = mediaItem.id
        let position = positionSeconds
        Task { await store.generate(for: mediaID, source: source, at: position) }
    }
    #endif

    /// A show opened from Continue Watching is stored without its seasons,
    /// which left the player without Episodes, Next Episode and Up Next.
    /// The player fills them in once the title's details load.
    func fillMissingEpisodes(from resolved: MediaItem) {
        guard let current = mediaItem,
              current.id == resolved.id || current.isSameTitle(as: resolved),
              current.details == nil,
              resolved.details?.seasons.contains(where: { !$0.episodes.isEmpty }) == true
        else { return }
        mediaItem = current.mergingSourceIdentifiers(from: resolved)
    }

    var nextEpisode: MediaEpisode? {
        guard let episode else { return nil }
        if let shuffledNextEpisode { return shuffledNextEpisode }
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
                // A paused player has little to report; property changes still
                // arrive through the player's own callback.
                let interval = self?.isPaused == true ? 750 : 250
                try? await Task.sleep(for: .milliseconds(interval))
                guard !Task.isCancelled else { return }
                self?.refreshState()
            }
        }
    }

    private func refreshState() {
        if let trailerPlayer {
            let position = trailerPlayer.currentTime().seconds
            positionSeconds = position.isFinite ? max(position, 0) : 0
            let duration = trailerPlayer.currentItem?.duration.seconds ?? 0
            durationSeconds = duration.isFinite && duration > 0 ? duration : nil
            // Buffering isn't paused: the pause overlay is for a chosen pause.
            isPaused = trailerPlayer.timeControlStatus == .paused
            if positionSeconds > 0 { hasRenderedVideoFrame = true }
            // A trailer has nothing after it, so reaching its end closes the player.
            if isPaused, let durationSeconds, positionSeconds >= durationSeconds - 0.25 {
                stop(persisting: false)
                return
            }
            if trailerPlayer.currentItem?.status == .failed {
                playbackError = "The trailer could not be played. Close the player and try again."
            }
            #if os(macOS)
            displaySleep.update(isPlaying: !isPaused)
            #endif
            return
        }
        #if OMNIA_MPV
        if let player {
            #if os(iOS)
            if isPictureInPictureActive, pictureInPictureController.isHandoff,
               let pipPlayer = pictureInPictureController.player {
                let position = pipPlayer.currentTime().seconds
                if position.isFinite { positionSeconds = max(position, 0) }
                isPaused = pipPlayer.rate == 0
                trackers.playbackChanged(trackerMedia, progress: trackerProgress, runtimeSeconds: durationSeconds, isPlaying: !isPaused && hasRenderedVideoFrame)
                persistProgress(force: false)
                return
            }
            #endif
            refreshState(from: player)
            persistProgress(force: false)
            return
        }
        #endif
        #if !os(macOS)
        guard let player = avPlayer else { return }
        positionSeconds = max(player.currentTime().seconds, 0)
        let duration = player.currentItem?.duration.seconds ?? 0
        durationSeconds = duration.isFinite && duration > 0 ? duration : nil
        isPaused = player.timeControlStatus != .playing
        if !hasRenderedVideoFrame, positionSeconds > 0 { hasRenderedVideoFrame = true }
        trackers.playbackChanged(trackerMedia, progress: trackerProgress, runtimeSeconds: durationSeconds, isPlaying: !isPaused && hasRenderedVideoFrame)
        persistProgress(force: false)
        #endif
    }

    #if OMNIA_MPV
    private func refreshState(from player: any PlaybackEngine) {
        #if os(iOS)
        // FILE_LOADED arrives through the native snapshot callback. Until
        // then, keep opening-stream queries off the main-thread poller.
        if areTracksLoading && !hasRenderedVideoFrame { return }
        #endif
        let duration = player.duration
        if player.hasRenderedVideoFrame != hasRenderedVideoFrame {
            hasRenderedVideoFrame = player.hasRenderedVideoFrame
            autoSyncSubtitlesIfNeeded()
            #if os(iOS)
            // iOS needs a frame on screen before it will float a video.
            if hasRenderedVideoFrame {
                if let engineController = player.systemPictureInPictureController {
                    // KSPlayer keeps the session it set up for its audio
                    // engine; changing it while the engine runs stops it.
                    pictureInPictureController.attachEngineController(engineController, videoView: player.videoView)
                } else {
                    // mpv's audio output sets up the session as it opens, so
                    // Omnia's playback settings go back on once it has.
                    pictureInPictureController.activateAudioSession()
                    pictureInPictureController.attachSampleBuffers()
                }
            }
            #endif
        }
        #if os(macOS)
        let usesSystemVolume = synchronizeOutputVolume()
        #else
        let usesSystemVolume = true
        #endif
        if !usesSystemVolume {
            let nextVolume = min(max(player.volume / 100, 0), 1)
            if volume != nextVolume {
                volume = nextVolume
            }
        }
        #if os(macOS)
        let pipActive = player.pictureInPictureActive
        let pipAvailable = player.pictureInPicturePossible
        #else
        let pipActive = isPictureInPictureActive
        let pipAvailable = isPictureInPictureAvailable
        #endif
        applyPeriodicState(
            PlaybackPeriodicState(
                errorMessage: player.errorMessage,
                positionSeconds: max(player.position, 0),
                durationSeconds: duration.isFinite && duration > 0 ? duration : nil,
                isPaused: player.isPaused,
                playbackRate: player.playbackRate.isFinite && player.playbackRate > 0
                    ? player.playbackRate
                    : 1,
                isPictureInPictureActive: pipActive,
                isPictureInPictureAvailable: pipAvailable
            )
        )
    }
    #endif

    func applyPeriodicState(_ state: PlaybackPeriodicState) {
        if playbackError != state.errorMessage {
            playbackError = state.errorMessage
        }
        if positionSeconds != state.positionSeconds {
            positionSeconds = state.positionSeconds
        }
        if durationSeconds != state.durationSeconds {
            durationSeconds = state.durationSeconds
        }
        if isPaused != state.isPaused {
            isPaused = state.isPaused
        }
        let isPlaying = hasPlayer && !state.isPaused && state.errorMessage == nil
        #if os(macOS)
        displaySleep.update(isPlaying: isPlaying)
        #endif
        trackers.playbackChanged(trackerMedia, progress: trackerProgress, runtimeSeconds: durationSeconds, isPlaying: isPlaying && hasRenderedVideoFrame)
        if playbackRate != state.playbackRate {
            playbackRate = state.playbackRate
        }
        if isPictureInPictureActive != state.isPictureInPictureActive {
            isPictureInPictureActive = state.isPictureInPictureActive
        }
        if isPictureInPictureAvailable != state.isPictureInPictureAvailable {
            isPictureInPictureAvailable = state.isPictureInPictureAvailable
        }
    }

    #if OMNIA_MPV
    private func apply(_ snapshot: OMMpvPlaybackSnapshot) {
        #if !os(macOS)
        if snapshot.errorMessage != nil, !hasRenderedVideoFrame, let player {
            fallBackToAVPlayer(from: player)
            if self.player == nil { return }
        }
        #endif
        playbackError = snapshot.errorMessage
        #if os(macOS)
        if !didLogRenderingFallback, let reason = player?.renderingFallbackReason, let mediaItem {
            didLogRenderingFallback = true
            let date = PlaybackFailureLog.shared.record(
                item: mediaItem,
                episode: episode,
                candidate: currentCandidate,
                streamURL: source?.url,
                message: "Metal rendering unavailable: \(reason)"
            )
            PlaybackFailureLog.shared.setOutcome("Played with OpenGL", for: date)
        }
        #endif
        #if os(iOS)
        // KSPlayer makes a new floating window when the video's format changes.
        if hasRenderedVideoFrame, let player, let engineController = player.systemPictureInPictureController {
            pictureInPictureController.attachEngineController(engineController, videoView: player.videoView)
        }
        #endif
        audioTracks = snapshot.audioTracks.map(PlaybackTrack.init)
        let previousSubtitle = subtitleTracks.first(where: \.isSelected)?.id
        subtitleTracks = snapshot.subtitleTracks.map(PlaybackTrack.init)
        confirmPendingSubtitlePreference()
        areTracksLoading = snapshot.tracksLoading
        // A sync measured against one subtitle file says nothing about
        // another.
        if subtitleTracks.first(where: \.isSelected)?.id != previousSubtitle,
           case .listening = subtitleSyncStatus {
            cancelAutomaticSubtitleSync()
        }
        autoSyncSubtitlesIfNeeded()
    }

    private func confirmPendingSubtitlePreference() {
        guard let pendingSubtitlePreference else { return }
        let isConfirmed: Bool
        if let id = pendingSubtitlePreference.id {
            isConfirmed = subtitleTracks.contains { $0.id == id && $0.isSelected }
        } else {
            isConfirmed = !subtitleTracks.contains(where: \.isSelected)
        }
        guard isConfirmed else { return }
        subtitlePreferencesHandler?(
            .selecting(
                id: pendingSubtitlePreference.id,
                from: pendingSubtitlePreference.tracks,
                style: persistedSubtitleStyle
            )
        )
        self.pendingSubtitlePreference = nil
    }
    #endif

    private func persistProgress(force: Bool) {
        guard purpose == .title, positionSeconds > 0 else { return }
        guard force || positionSeconds - lastPersistedPosition >= 10 else { return }
        lastPersistedPosition = positionSeconds
        progressHandler?(positionSeconds, durationSeconds)
    }
}

#if OMNIA_MPV
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

/// Nuvio's resume prompt: the title being played is remembered until the
/// player closes, so a launch after Omnia quit during playback can offer
/// to continue it.
nonisolated enum ResumePromptMarker {
    private static let key = "resume-prompt-media-id"

    static func mark(_ mediaID: String) {
        UserDefaults.standard.set(mediaID, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// The title left in the player, read once.
    static func consume() -> String? {
        defer { clear() }
        return UserDefaults.standard.string(forKey: key)
    }
}
