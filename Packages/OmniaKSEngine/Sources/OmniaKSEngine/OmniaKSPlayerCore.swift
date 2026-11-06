//
//  OmniaKSPlayerCore.swift
//  OmniaKSEngine
//
//  KSPlayer's FFmpeg player behind a small API that Omnia's player drives
//  the same way it drives mpv. KSPlayer is imported implementation-only, so
//  neither its types nor its FFmpeg reach the app.
//

import AVFoundation
import AVKit
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers
@_implementationOnly import KSPlayer
#if canImport(UIKit)
import UIKit
public typealias OmniaKSView = UIView
#else
import AppKit
public typealias OmniaKSView = NSView
#endif

/// One audio or subtitle track, as Omnia's track panels list it.
public struct OmniaKSTrack: Equatable, Sendable {
    public let id: Int
    public let title: String?
    public let language: String?
    public let codec: String?
    public let isSelected: Bool
    /// The add-on file an added subtitle came from; nil inside the video.
    public let externalFilename: String?
}

public enum OmniaKSAspectMode: Sendable {
    case fit
    case fill
    case stretch
}

@MainActor
public final class OmniaKSPlayerCore {
    private let engine: KSEngine

    /// Holds the video and the subtitles drawn over it.
    public var videoView: OmniaKSView { engine.containerView }
    public var errorMessage: String? { engine.errorMessage }
    public var isPaused: Bool { engine.isPaused }
    public var position: Double { engine.position }
    public var duration: Double { engine.duration }
    /// 0 to 100.
    public var volume: Double { engine.volume }
    public var playbackRate: Double { engine.playbackRate }
    public var hasRenderedVideoFrame: Bool { engine.hasRenderedVideoFrame }
    public var audioTracks: [OmniaKSTrack] { engine.audioTracks }
    public var subtitleTracks: [OmniaKSTrack] { engine.subtitleTracks }
    public var tracksLoading: Bool { engine.tracksLoading }
    /// KSPlayer's own floating window, fed straight from the decoder. It can
    /// be replaced when the video's format changes; `onStateChange` fires then.
    public var pictureInPictureController: AVPictureInPictureController? { engine.pictureInPictureController }
    /// Tracks, loading, the error or the floating window changed.
    public var onStateChange: (() -> Void)? {
        get { engine.onStateChange }
        set { engine.onStateChange = newValue }
    }

    public init(url: URL, requestHeaders: [String: String]) {
        engine = KSEngine(url: url, requestHeaders: requestHeaders)
    }

    public func startIfNeeded() { engine.startIfNeeded() }
    public func play() { engine.play() }
    public func pause() { engine.pause() }
    public func togglePause() { engine.isPaused ? engine.play() : engine.pause() }
    public func seek(to seconds: Double, exact: Bool = true) { engine.seek(to: seconds, exact: exact) }
    public func seek(by seconds: Double) { engine.seek(to: engine.position + seconds, exact: true) }
    public func setVolume(_ percent: Double) { engine.setVolume(percent) }
    public func setPlaybackRate(_ rate: Double) { engine.setPlaybackRate(rate) }
    public func setAspectMode(_ mode: OmniaKSAspectMode) { engine.setAspectMode(mode) }
    public func setPreferredAudioLanguages(_ languages: [String]) { engine.preferredAudioLanguages = languages }
    public func setPreferredSubtitleLanguages(_ languages: [String]) { engine.preferredSubtitleLanguages = languages }
    public func setSubtitlesDisabled(_ disabled: Bool) { engine.subtitlesDisabled = disabled }
    /// The same keys Omnia gives mpv: font, fontSize, scale, position,
    /// textColor, outlineColor, outlineSize, shadowOpacity, shadowBlur,
    /// background, backgroundRGB, bold, italic, delay.
    public func setSubtitleStyle(_ style: [String: Any]) { engine.mergeSubtitleStyle(style) }
    /// Settings: hardware decoding off, SDH stripping, forced subtitles only.
    public func configure(hardwareDecoding: Bool, stripsSDH: Bool, forcedSubtitlesOnly: Bool) {
        engine.configure(hardwareDecoding: hardwareDecoding, stripsSDH: stripsSDH, forcedSubtitlesOnly: forcedSubtitlesOnly)
    }
    public func addSubtitle(url: URL, title: String?, language: String?, select: Bool) {
        engine.addSubtitle(url: url, title: title, language: language, select: select)
    }
    @discardableResult
    public func selectAudioTrack(id: Int) -> Bool { engine.selectAudioTrack(id: id) }
    @discardableResult
    public func selectSubtitleTrack(id: Int?) -> Bool { engine.selectSubtitleTrack(id: id) }
    public func cycleAudioTrack() { engine.cycleAudioTrack() }
    public func cycleSubtitles() { engine.cycleSubtitles() }
    public func setSpeechActivityProbeEnabled(_ enabled: Bool) { engine.setSpeechActivityProbeEnabled(enabled) }
    /// Loudness of the latest audio in dBFS, or nil while the probe is off.
    public func speechActivityLevel() -> Double? { engine.speechActivityLevel }
    public func togglePictureInPicture() { engine.togglePictureInPicture() }
    /// Saves the frame on screen, without subtitles; the extension picks the format.
    public func writeCurrentFrame(to url: URL) -> Bool { engine.writeCurrentFrame(to: url) }
    public func stop() { engine.stop() }
}

// MARK: - Engine

@MainActor
final class KSEngine {
    let containerView: OmniaKSView
    private(set) var errorMessage: String?
    private(set) var tracksLoading = true
    var onStateChange: (() -> Void)?
    var preferredAudioLanguages: [String] = []
    var preferredSubtitleLanguages: [String] = []
    var subtitlesDisabled = false

    private let options: KSOptions
    private let player: KSMEPlayer
    private let delegateBox = DelegateBox()
    private let subtitleView = SubtitleOverlayView()
    private var started = false
    private var stopped = false
    private var userPaused = false
    private var pendingStart: Double = 0
    private var tick: Timer?
    private var forcedSubtitlesOnly = false
    private var appliedDefaults = false
    private var external: [ExternalSubtitle] = []
    private var nextExternalID = 10_000
    private var selectedSubtitleID: Int?
    private var subtitleDelay: Double = 0
    private var lastPictureInPictureController: AVPictureInPictureController?
    private var probe: SpeechProbe?

    private struct ExternalSubtitle {
        let id: Int
        let title: String?
        let language: String?
        let url: URL
        let info: URLSubtitleInfo
    }

    init(url: URL, requestHeaders: [String: String]) {
        let options = KSOptions()
        options.registerRemoteControll = false
        options.isAccurateSeek = true
        options.autoSelectEmbedSubtitle = false
        options.canStartPictureInPictureAutomaticallyFromInline = true
        // FFmpeg's own user agent unless the add-on asked for one.
        options.userAgent = requestHeaders.first { $0.key.caseInsensitiveCompare("User-Agent") == .orderedSame }?.value
        let headers = requestHeaders.filter { $0.key.caseInsensitiveCompare("User-Agent") != .orderedSame }
        if !headers.isEmpty { options.appendHeader(headers) }
        self.options = options
        player = KSMEPlayer(url: url, options: options)
        containerView = OmniaKSView()
        #if canImport(UIKit)
        containerView.backgroundColor = .black
        containerView.isUserInteractionEnabled = false
        #else
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.black.cgColor
        #endif
        if let video = player.view {
            video.frame = containerView.bounds
            #if canImport(UIKit)
            video.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            #else
            video.autoresizingMask = [.width, .height]
            #endif
            containerView.addSubview(video)
        }
        subtitleView.frame = containerView.bounds
        #if canImport(UIKit)
        subtitleView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        #else
        subtitleView.autoresizingMask = [.width, .height]
        #endif
        containerView.addSubview(subtitleView)
        player.contentMode = .scaleAspectFit
        delegateBox.engine = self
        player.delegate = delegateBox
    }

    // MARK: State

    var isPaused: Bool {
        if userPaused { return true }
        switch player.playbackState {
        case .paused, .finished, .stopped: return true
        default: return false
        }
    }

    var position: Double {
        guard player.isReadyToPlay else { return pendingStart }
        let time = player.currentPlaybackTime
        return time.isFinite ? max(time, 0) : 0
    }

    var duration: Double {
        let value = player.duration
        return value.isFinite ? value : 0
    }

    var volume: Double { Double(player.playbackVolume) * 100 }
    var playbackRate: Double { Double(player.playbackRate) }
    var hasRenderedVideoFrame: Bool { player.isReadyToPlay && player.videoOutput?.pixelBuffer != nil }

    var pictureInPictureController: AVPictureInPictureController? {
        guard player.isReadyToPlay else { return nil }
        return player.pipController
    }

    var audioTracks: [OmniaKSTrack] {
        player.tracks(mediaType: .audio).map { track in
            OmniaKSTrack(
                id: Int(track.trackID),
                title: track.name.isEmpty ? nil : track.name,
                language: track.languageCode,
                codec: (track as? FFmpegAssetTrack)?.codecName,
                isSelected: track.isEnabled,
                externalFilename: nil
            )
        }
    }

    var subtitleTracks: [OmniaKSTrack] {
        let embedded = player.tracks(mediaType: .subtitle).map { track in
            OmniaKSTrack(
                id: Int(track.trackID),
                title: track.name.isEmpty ? nil : track.name,
                language: track.languageCode,
                codec: (track as? FFmpegAssetTrack)?.codecName,
                isSelected: selectedSubtitleID == Int(track.trackID),
                externalFilename: nil
            )
        }
        return embedded + external.map { subtitle in
            OmniaKSTrack(
                id: subtitle.id,
                title: subtitle.title,
                language: subtitle.language,
                codec: subtitle.url.pathExtension.lowercased(),
                isSelected: selectedSubtitleID == subtitle.id,
                externalFilename: subtitle.url.absoluteString
            )
        }
    }

    // MARK: Lifecycle

    func startIfNeeded() {
        guard !started, !stopped, containerView.window != nil else { return }
        started = true
        options.startPlayTime = pendingStart
        player.prepareToPlay()
        tick = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        tick?.invalidate()
        tick = nil
        probe?.stop()
        probe = nil
        player.pipController?.stopPictureInPicture()
        player.delegate = nil
        player.shutdown()
        containerView.removeFromSuperview()
        onStateChange = nil
    }

    fileprivate func readyToPlay() {
        tracksLoading = false
        applyDefaultTracks()
        if !userPaused { player.play() }
        notify()
    }

    fileprivate func finished(error: Error?) {
        guard let error else { return }
        let message = (error as NSError).localizedDescription
        errorMessage = message.isEmpty ? "The video could not be played." : message
        tracksLoading = false
        notify()
    }

    private func notify() {
        onStateChange?()
    }

    private func update() {
        guard !stopped else { return }
        if player.isReadyToPlay, player.pipController !== lastPictureInPictureController {
            lastPictureInPictureController = player.pipController
            notify()
        }
        renderSubtitle()
    }

    // MARK: Transport

    func play() {
        userPaused = false
        guard player.isReadyToPlay else { return }
        player.play()
    }

    func pause() {
        userPaused = true
        guard player.isReadyToPlay else { return }
        player.pause()
    }

    func seek(to seconds: Double, exact: Bool) {
        let target = max(seconds.isFinite ? seconds : 0, 0)
        guard player.isReadyToPlay else {
            pendingStart = target
            return
        }
        options.isAccurateSeek = exact
        player.seek(time: target) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.stopped, !self.userPaused else { return }
                self.player.play()
            }
        }
    }

    func setVolume(_ percent: Double) {
        player.playbackVolume = Float(min(max(percent, 0), 100) / 100)
    }

    func setPlaybackRate(_ rate: Double) {
        guard rate.isFinite, rate > 0 else { return }
        player.playbackRate = Float(rate)
    }

    func setAspectMode(_ mode: OmniaKSAspectMode) {
        switch mode {
        case .fit: player.contentMode = .scaleAspectFit
        case .fill: player.contentMode = .scaleAspectFill
        case .stretch: player.contentMode = .scaleToFill
        }
    }

    func configure(hardwareDecoding: Bool, stripsSDH: Bool, forcedSubtitlesOnly: Bool) {
        options.hardwareDecode = hardwareDecoding
        self.forcedSubtitlesOnly = forcedSubtitlesOnly
        subtitleView.stripsSDH = stripsSDH
    }

    // MARK: Tracks

    private func applyDefaultTracks() {
        guard !appliedDefaults else { return }
        appliedDefaults = true
        let audio = player.tracks(mediaType: .audio)
        if let match = Self.firstMatch(audio, languages: preferredAudioLanguages), !match.isEnabled {
            player.select(track: match)
        }
        guard !subtitlesDisabled else { return }
        let subtitles = player.tracks(mediaType: .subtitle)
        let audioLanguage = player.tracks(mediaType: .audio).first(where: \.isEnabled)?.languageCode
        let languages = preferredSubtitleLanguages
        let candidates: [MediaPlayerTrack]
        if forcedSubtitlesOnly, let audioLanguage,
           languages.contains(where: { Self.sameLanguage($0, audioLanguage) }) {
            // The audio is already in the subtitle language: only a forced track.
            candidates = subtitles.filter { $0.name.lowercased().contains("forced") }
        } else {
            candidates = subtitles
        }
        if let match = Self.firstMatch(candidates, languages: languages) {
            _ = selectSubtitleTrack(id: Int(match.trackID))
        }
    }

    private static func firstMatch(_ tracks: [MediaPlayerTrack], languages: [String]) -> MediaPlayerTrack? {
        for language in languages {
            if let track = tracks.first(where: { sameLanguage(language, $0.languageCode) }) { return track }
        }
        return nil
    }

    static func sameLanguage(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = normalizedLanguage(lhs), let rhs = normalizedLanguage(rhs) else { return false }
        return lhs == rhs
    }

    private static func normalizedLanguage(_ code: String?) -> String? {
        guard let code = code?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !code.isEmpty else { return nil }
        let base = String(code.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? Substring(code))
        if base.count == 3, let two = Locale.LanguageCode(base).identifier(.alpha2) { return two }
        return base
    }

    func selectAudioTrack(id: Int) -> Bool {
        guard let track = player.tracks(mediaType: .audio).first(where: { Int($0.trackID) == id }) else { return false }
        if !track.isEnabled { player.select(track: track) }
        notify()
        return true
    }

    func selectSubtitleTrack(id: Int?) -> Bool {
        // The current one goes off first.
        if let current = selectedSubtitleID {
            if let track = player.tracks(mediaType: .subtitle).first(where: { Int($0.trackID) == current }) {
                track.isEnabled = false
            } else if let subtitle = external.first(where: { $0.id == current }) {
                subtitle.info.isEnabled = false
            }
        }
        selectedSubtitleID = nil
        subtitleView.show([])
        guard let id else {
            notify()
            return true
        }
        if let track = player.tracks(mediaType: .subtitle).first(where: { Int($0.trackID) == id }) {
            player.select(track: track)
            track.isEnabled = true
        } else if let subtitle = external.first(where: { $0.id == id }) {
            subtitle.info.isEnabled = true
        } else {
            notify()
            return false
        }
        selectedSubtitleID = id
        notify()
        return true
    }

    func addSubtitle(url: URL, title: String?, language: String?, select: Bool) {
        guard let scheme = url.scheme?.lowercased(), ["http", "https", "file"].contains(scheme) else { return }
        let id = nextExternalID
        nextExternalID += 1
        let name = (title?.isEmpty == false ? title : nil) ?? url.lastPathComponent
        let info = URLSubtitleInfo(subtitleID: "omnia-\(id)", name: name, url: url, userAgent: options.userAgent)
        external.append(ExternalSubtitle(id: id, title: title, language: language, url: url, info: info))
        if select { _ = selectSubtitleTrack(id: id) } else { notify() }
    }

    func cycleAudioTrack() {
        let tracks = player.tracks(mediaType: .audio)
        guard !tracks.isEmpty else { return }
        let index = tracks.firstIndex(where: \.isEnabled) ?? -1
        _ = selectAudioTrack(id: Int(tracks[(index + 1) % tracks.count].trackID))
    }

    func cycleSubtitles() {
        let ids: [Int?] = [nil] + subtitleTracks.map(\.id)
        let index = ids.firstIndex(of: selectedSubtitleID) ?? 0
        _ = selectSubtitleTrack(id: ids[(index + 1) % ids.count])
    }

    // MARK: Subtitles

    func mergeSubtitleStyle(_ style: [String: Any]) {
        if let delay = style["delay"] as? Double, delay.isFinite { subtitleDelay = delay }
        subtitleView.style.merge(style)
        subtitleView.restyle()
    }

    private func renderSubtitle() {
        guard let id = selectedSubtitleID, player.isReadyToPlay else { return }
        let time = player.currentPlaybackTime - subtitleDelay
        let parts: [SubtitlePart]
        if let track = player.tracks(mediaType: .subtitle).first(where: { Int($0.trackID) == id }) as? FFmpegAssetTrack {
            parts = track.search(for: time)
        } else if let subtitle = external.first(where: { $0.id == id }) {
            parts = subtitle.info.search(for: time)
        } else {
            parts = []
        }
        subtitleView.show(parts.map { SubtitleOverlayView.Cue(text: $0.text?.string, image: $0.image) })
    }

    // MARK: Picture in Picture

    func togglePictureInPicture() {
        guard let controller = pictureInPictureController else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else if controller.isPictureInPicturePossible {
            controller.startPictureInPicture()
        }
    }

    // MARK: Auto Sync

    var speechActivityLevel: Double? { probe?.level }

    func setSpeechActivityProbeEnabled(_ enabled: Bool) {
        if enabled {
            guard probe == nil, let output = player.audioOutput as? AudioEnginePlayer else { return }
            probe = SpeechProbe(engine: output.engine)
        } else {
            probe?.stop()
            probe = nil
        }
    }

    // MARK: Frames

    func writeCurrentFrame(to url: URL) -> Bool {
        guard let image = player.videoOutput?.pixelBuffer?.cgImage() else { return false }
        let type: UTType = switch url.pathExtension.lowercased() {
        case "png": .png
        case "heic": .heic
        default: .jpeg
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }
}

// MARK: - Delegate

/// KSPlayer's delegate protocol stays inside this module.
@MainActor
private final class DelegateBox: MediaPlayerDelegate {
    weak var engine: KSEngine?

    func readyToPlay(player _: some MediaPlayerProtocol) { engine?.readyToPlay() }
    func changeLoadState(player _: some MediaPlayerProtocol) {}
    func changeBuffering(player _: some MediaPlayerProtocol, progress _: Int) {}
    func playBack(player _: some MediaPlayerProtocol, loopCount _: Int) {}
    func finish(player _: some MediaPlayerProtocol, error: Error?) { engine?.finished(error: error) }
}

// MARK: - Speech probe

/// Measures how loud the audio is, without changing it, for Auto Sync.
private final class SpeechProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: Double?
    private weak var mixer: AVAudioMixerNode?

    init(engine: AVAudioEngine) {
        let mixer = engine.mainMixerNode
        self.mixer = mixer
        let format = mixer.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        mixer.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.measure(buffer)
        }
    }

    var level: Double? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    func stop() {
        mixer?.removeTap(onBus: 0)
    }

    private func measure(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        let frames = Int(buffer.frameLength)
        let count = Int(buffer.format.channelCount)
        var sum: Double = 0
        for channel in 0 ..< count {
            let samples = channels[channel]
            for index in 0 ..< frames {
                let value = Double(samples[index])
                sum += value * value
            }
        }
        let rms = sqrt(sum / Double(frames * max(count, 1)))
        let decibels = rms > 0 ? 20 * log10(rms) : -120
        lock.lock()
        latest = max(decibels, -120)
        lock.unlock()
    }
}
