//
//  KSPlayerEngine.swift
//  Omnia
//

import AVKit
import Foundation
import OmniaKSEngine
#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if OMNIA_MPV
/// Settings › Player › Engine › KSPlayer: KSPlayer's FFmpeg
/// player behind the same PlaybackEngine as mpv, so the player's controls,
/// panels and gestures don't change.
@MainActor
final class KSPlayerEngine: PlaybackEngine {
    private let core: OmniaKSPlayerCore
    private var nextRequestID: UInt64 = 0
    var stateChangeHandler: ((OMMpvPlaybackSnapshot) -> Void)?
    /// KSPlayer always draws with Metal and AVSampleBufferDisplayLayer.
    var prefersMetalRendering = true
    var renderingFallbackReason: String? { nil }

    init(url: URL, requestHeaders: [String: String]) {
        core = OmniaKSPlayerCore(url: url, requestHeaders: requestHeaders)
        core.onStateChange = { [weak self] in self?.publish() }
    }

    /// KSPlayer's audio check for Diagnostics.
    var onAudioReport: ((String) -> Void)? {
        get { core.onAudioReport }
        set { core.onAudioReport = newValue }
    }

    var videoView: PlaybackEngineView { core.videoView }
    var errorMessage: String? { core.errorMessage }
    var isPaused: Bool { core.isPaused }
    var position: Double { core.position }
    var duration: Double { core.duration }
    var volume: Double { core.volume }
    var playbackRate: Double { core.playbackRate }
    var hasRenderedVideoFrame: Bool { core.hasRenderedVideoFrame }
    var pictureInPictureActive: Bool { core.pictureInPictureController?.isPictureInPictureActive == true }
    var pictureInPicturePossible: Bool { core.pictureInPictureController?.isPictureInPicturePossible == true }
    #if os(iOS)
    var systemPictureInPictureController: AVPictureInPictureController? { core.pictureInPictureController }
    #endif

    func startIfNeeded() { core.startIfNeeded() }
    func togglePause() { core.togglePause() }
    func play() { core.play() }
    func pause() { core.pause() }
    func seek(by seconds: Double) { core.seek(by: seconds) }
    func seek(to seconds: Double) { core.seek(to: seconds) }
    func previewSeek(to seconds: Double) { core.seek(to: seconds, exact: false) }
    func setVolume(_ volume: Double) { core.setVolume(volume) }
    func setPlaybackRate(_ playbackRate: Double) { core.setPlaybackRate(playbackRate) }

    func setVideoAspectMode(_ mode: OMMpvVideoAspectMode) {
        switch mode {
        case .fill: core.setAspectMode(.fill)
        case .stretch: core.setAspectMode(.stretch)
        default: core.setAspectMode(.fit)
        }
    }

    func setPreferredAudioLanguages(_ languages: [String]) { core.setPreferredAudioLanguages(languages) }
    func setPreferredSubtitleLanguages(_ languages: [String]) { core.setPreferredSubtitleLanguages(languages) }
    func setSubtitlesDisabled(_ disabled: Bool) { core.setSubtitlesDisabled(disabled) }
    func setSubtitleStyle(_ style: [String: Any]) { core.setSubtitleStyle(style) }

    /// The same options Omnia gives mpv, read for what KSPlayer can do.
    func setPlayerOptions(_ options: [String: String]) {
        core.configure(
            hardwareDecoding: options["hwdec"] != "no",
            stripsSDH: options["sub-filter-sdh"] == "yes",
            forcedSubtitlesOnly: options["subs-with-matching-audio"] == "forced"
        )
    }

    func addSubtitleURL(_ url: URL, title: String?, language: String?, select: Bool) {
        core.addSubtitle(url: url, title: title, language: language, select: select)
    }

    func selectAudioTrack(id trackID: Int, completion: OMMpvTrackSelectionCompletion?) -> UInt64 {
        let requestID = nextID()
        let succeeded = core.selectAudioTrack(id: trackID)
        DispatchQueue.main.async {
            completion?(requestID, succeeded, succeeded ? nil : "That audio track isn't available.")
        }
        return requestID
    }

    func selectSubtitleTrack(id trackID: NSNumber?, completion: OMMpvTrackSelectionCompletion?) -> UInt64 {
        let requestID = nextID()
        let succeeded = core.selectSubtitleTrack(id: trackID?.intValue)
        DispatchQueue.main.async {
            completion?(requestID, succeeded, succeeded ? nil : "That subtitle isn't available.")
        }
        return requestID
    }

    func setSpeechActivityProbeEnabled(_ enabled: Bool) { core.setSpeechActivityProbeEnabled(enabled) }
    func speechActivityLevel() -> NSNumber? { core.speechActivityLevel().map { NSNumber(value: $0) } }
    func cycleSubtitles() { core.cycleSubtitles() }
    func cycleAudioTrack() { core.cycleAudioTrack() }

    func attachVideoView(toHost hostView: PlaybackEngineView) {
        let view = core.videoView
        view.frame = hostView.bounds
        #if os(macOS)
        view.autoresizingMask = [.width, .height]
        view.alphaValue = 1
        #else
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        #endif
        hostView.addSubview(view)
    }

    func detachVideoView(fromHost hostView: PlaybackEngineView) {
        if core.videoView.superview === hostView { core.videoView.removeFromSuperview() }
    }

    func togglePictureInPicture() { core.togglePictureInPicture() }

    #if os(iOS)
    // KSPlayer floats its own decoded frames; mpv's copy path isn't needed.
    func beginSampleBufferOutput(_ frameHandler: @escaping (CVPixelBuffer) -> Void) -> Bool { false }
    func endSampleBufferOutput() {}
    func captureCurrentFrame(_ frameHandler: @escaping (CVPixelBuffer) -> Void) {}
    #endif

    func writeCurrentScene(to url: URL) -> Bool { core.writeCurrentFrame(to: url) }
    func stop() { core.stop() }

    private func nextID() -> UInt64 {
        nextRequestID += 1
        return nextRequestID
    }

    private func publish() {
        let snapshot = OMMpvPlaybackSnapshot(
            audioTracks: core.audioTracks.map(Self.track),
            subtitleTracks: core.subtitleTracks.map(Self.track),
            tracksLoading: core.tracksLoading,
            errorMessage: core.errorMessage
        )
        stateChangeHandler?(snapshot)
    }

    private static func track(_ track: OmniaKSTrack) -> OMMpvTrack {
        OMMpvTrack(
            trackID: track.id,
            title: track.title,
            language: track.language,
            codec: track.codec,
            selected: track.isSelected,
            externalFilename: track.externalFilename
        )
    }
}
#endif
