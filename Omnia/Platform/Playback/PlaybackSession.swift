//
//  PlaybackSession.swift
//  Omnia
//

import Foundation
import Observation

#if os(macOS)
import AppKit
import AudioToolbox
import CoreAudio
#else
import AVFoundation
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

    var preservesAspectRatio: Bool { true }
    var panScan: Double { self == .fill ? 1 : 0 }

    var title: String {
        switch self {
        case .original: "Original"
        case .fill: "Fill"
        }
    }
}

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
    private(set) var aspectRatioMode: PlaybackAspectRatioMode = .original
    private(set) var playbackError: String?
    private(set) var audioTracks: [PlaybackTrack] = []
    private(set) var subtitleTracks: [PlaybackTrack] = []
    private(set) var areTracksLoading = false
    private(set) var subtitleStyle = PlaybackSubtitleStyle()
    private(set) var isFullScreenActive = false
    private(set) var isPictureInPictureActive = false
    private(set) var isPictureInPictureAvailable = false
    var isPresentingPlayer = false

    @ObservationIgnored private var progressHandler: (@MainActor (Double, Double?) -> Void)?
    @ObservationIgnored private var subtitlePreferencesHandler: (@MainActor (PlaybackSubtitlePreferenceUpdate) -> Void)?
    @ObservationIgnored private var stateTask: Task<Void, Never>?
    #if !os(macOS)
    @ObservationIgnored private var mediaSelectionTask: Task<Void, Never>?
    #else
    @ObservationIgnored private var cacheProtection: LocalPlaybackJobCoordinator.PlaybackProtection?
    @ObservationIgnored private let outputVolumeController: MacOutputVolumeControlling
    #endif
    @ObservationIgnored private var lastPersistedPosition: Double = 0

    #if os(macOS)
    init(outputVolumeController: MacOutputVolumeControlling? = nil) {
        let outputVolumeController = outputVolumeController ?? CoreAudioOutputVolumeController()
        self.outputVolumeController = outputVolumeController
        if let currentVolume = outputVolumeController.currentVolume {
            volume = min(max(currentVolume, 0), 1)
        }
    }
    #else
    init() {}
    #endif

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

        let source = input.source
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
        isFullScreenActive = false
        isPictureInPictureActive = false
        isPictureInPictureAvailable = false
        aspectRatioMode = .original

        #if os(macOS)
        cacheProtection = input.cacheProtection
        let mpv: OMMpvPlayerController
        switch input {
        case .stream, .cachedStream:
            mpv = OMMpvPlayerController(
                url: source.url,
                requestHeaders: source.requestHeaders
            )
        case let .disc(_, request, _):
            mpv = OMMpvPlayerController(
                url: request.playbackURL,
                requestHeaders: request.requestHeaders,
                blurayDeviceURL: request.deviceURL
            )
        }
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
        subtitleStyle = preferences.playbackSubtitleStyle.normalized
        var mpvStyle = preferences.subtitleAppearance == .followSystem
            ? [String: Any]()
            : Self.mpvSubtitleStyle(for: preferences)
        mpvStyle.merge(Self.mpvSubtitleOverrides(for: subtitleStyle)) { _, latest in latest }
        mpv.setSubtitleStyle(mpvStyle)
        let usesSystemVolume = synchronizeOutputVolume()
        mpv.setVolume(
            MacPlaybackVolumeRouting.playerVolumePercent(
                requestedVolume: volume,
                systemVolumeAvailable: usesSystemVolume
            )
        )
        mpv.setPlaybackRate(playbackRate)
        mpv.setVideoAspectMode(.original)
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
        let usesSystemVolume = outputVolumeController.setVolume(volume)
        player?.setVolume(
            MacPlaybackVolumeRouting.playerVolumePercent(
                requestedVolume: volume,
                systemVolumeAvailable: usesSystemVolume
            )
        )
        #else
        player?.volume = Float(volume)
        #endif
    }

    #if os(macOS)
    @discardableResult
    func synchronizeOutputVolume() -> Bool {
        guard let currentVolume = outputVolumeController.currentVolume else { return false }
        volume = min(max(currentVolume, 0), 1)
        return true
    }
    #endif

    func setPlaybackRate(_ value: Double) {
        playbackRate = min(max(value, 0.25), 4)
        #if os(macOS)
        player?.setPlaybackRate(playbackRate)
        #else
        guard let player else { return }
        player.rate = isPaused ? 0 : Float(playbackRate)
        #endif
    }

    func cycleAspectRatio() {
        aspectRatioMode = aspectRatioMode.next
        #if os(macOS)
        switch aspectRatioMode {
        case .original:
            player?.setVideoAspectMode(.original)
        case .fill:
            player?.setVideoAspectMode(.fill)
        }
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
        subtitlePreferencesHandler?(.selecting(id: id, from: subtitleTracks, style: subtitleStyle))
        refreshState()
        #endif
    }

    func setSubtitlePreferencesHandler(
        _ handler: (@MainActor (PlaybackSubtitlePreferenceUpdate) -> Void)?
    ) {
        subtitlePreferencesHandler = handler
    }

    func setSubtitleFont(_ fontName: String) {
        subtitleStyle.fontName = fontName
        #if os(macOS)
        applySubtitleStyle()
        #endif
    }

    func setSubtitleFontSize(_ size: Double) {
        subtitleStyle.fontSize = size
        #if os(macOS)
        applySubtitleStyle()
        #endif
    }

    func setSubtitleScale(_ scale: Double) {
        subtitleStyle.scale = scale
        #if os(macOS)
        applySubtitleStyle()
        #endif
    }

    func setSubtitlePosition(_ position: Double) {
        subtitleStyle.position = position
        #if os(macOS)
        applySubtitleStyle()
        #endif
    }

    func setSubtitleShadowOpacity(_ opacity: Double) {
        subtitleStyle.shadowOpacity = opacity
        #if os(macOS)
        applySubtitleStyle()
        #endif
    }

    func setSubtitleShadowBlurRadius(_ radius: Double) {
        subtitleStyle.shadowBlurRadius = radius
        #if os(macOS)
        applySubtitleStyle()
        #endif
    }

    func setSubtitleBackground(_ background: PlaybackSubtitleBackground) {
        subtitleStyle.background = background
        #if os(macOS)
        applySubtitleStyle()
        #endif
    }

    func toggleFullScreen() {
        #if os(macOS)
        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow else { return }
        setFullScreen(!window.styleMask.contains(.fullScreen), in: window)
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
    }

    func togglePictureInPicture() {
        player?.togglePictureInPicture()
        refreshState()
    }
    #endif

    func stop(persisting: Bool = true) {
        if persisting { flushProgress() }
        #if os(macOS)
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
        #if os(macOS)
        let cacheProtection = cacheProtection
        self.cacheProtection = nil
        if let cacheProtection {
            Task {
                await LocalPlaybackJobCoordinator.shared.unprotect(cacheProtection)
            }
        }
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
        isFullScreenActive = false
        isPictureInPictureActive = false
        isPictureInPictureAvailable = false
        aspectRatioMode = .original
        isPresentingPlayer = false
    }

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
        let isCurrentlyFullScreen = window.styleMask.contains(.fullScreen)
        guard active != isCurrentlyFullScreen else {
            isFullScreenActive = active
            return
        }
        window.toggleFullScreen(nil)
    }

    private func applySubtitleStyle() {
        subtitleStyle = subtitleStyle.normalized
        player?.setSubtitleStyle(Self.mpvSubtitleOverrides(for: subtitleStyle))
        subtitlePreferencesHandler?(
            PlaybackSubtitlePreferenceUpdate(
                style: subtitleStyle,
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
        if !synchronizeOutputVolume() {
            volume = min(max(player.volume / 100, 0), 1)
        }
        playbackRate = player.playbackRate.isFinite && player.playbackRate > 0 ? player.playbackRate : 1
        isPictureInPictureActive = player.pictureInPictureActive
        isPictureInPictureAvailable = player.pictureInPicturePossible
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
