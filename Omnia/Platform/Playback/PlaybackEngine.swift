//
//  PlaybackEngine.swift
//  Omnia
//

import Foundation
#if os(macOS)
import AppKit
typealias PlaybackEngineView = NSView
#else
import AVKit
import CoreVideo
import UIKit
typealias PlaybackEngineView = UIView
#endif

#if OMNIA_MPV
/// What Omnia's player asks of the engine that decodes and draws a title.
/// mpv is the default; Settings › Player › Engine can pick
/// KSPlayer. The player's controls, timeline, panels and gestures talk only
/// to this, so they're the same whichever engine plays.
///
/// The names follow mpv's controller, which conforms as it is.
@MainActor
protocol PlaybackEngine: AnyObject {
    /// The view the engine draws into, attached to the player's host view.
    var videoView: PlaybackEngineView { get }
    var errorMessage: String? { get }
    var isPaused: Bool { get }
    var position: Double { get }
    var duration: Double { get }
    /// 0 to 100.
    var volume: Double { get }
    var playbackRate: Double { get }
    var hasRenderedVideoFrame: Bool { get }
    var pictureInPictureActive: Bool { get }
    var pictureInPicturePossible: Bool { get }
    /// Called on the main thread when tracks, loading or the error change.
    var stateChangeHandler: ((OMMpvPlaybackSnapshot) -> Void)? { get set }
    var prefersMetalRendering: Bool { get set }
    var renderingFallbackReason: String? { get }

    func startIfNeeded()
    func togglePause()
    func play()
    func pause()
    func seek(by seconds: Double)
    func seek(to seconds: Double)
    func previewSeek(to seconds: Double)
    func setVolume(_ volume: Double)
    func setPlaybackRate(_ playbackRate: Double)
    func setVideoAspectMode(_ mode: OMMpvVideoAspectMode)
    func setPreferredAudioLanguages(_ languages: [String])
    func setPreferredSubtitleLanguages(_ languages: [String])
    func setSubtitlesDisabled(_ disabled: Bool)
    func setSubtitleStyle(_ style: [String: Any])
    func setPlayerOptions(_ options: [String: String])
    func addSubtitleURL(_ url: URL, title: String?, language: String?, select: Bool)
    func selectAudioTrack(id trackID: Int, completion: OMMpvTrackSelectionCompletion?) -> UInt64
    func selectSubtitleTrack(id trackID: NSNumber?, completion: OMMpvTrackSelectionCompletion?) -> UInt64
    func setSpeechActivityProbeEnabled(_ enabled: Bool)
    func speechActivityLevel() -> NSNumber?
    func cycleSubtitles()
    func cycleAudioTrack()
    func attachVideoView(toHost hostView: PlaybackEngineView)
    func detachVideoView(fromHost hostView: PlaybackEngineView)
    func togglePictureInPicture()
    #if os(iOS)
    /// An engine that floats its own video gives its controller here; nil
    /// has Omnia copy frames into its own floating window, as for mpv.
    var systemPictureInPictureController: AVPictureInPictureController? { get }
    func beginSampleBufferOutput(_ frameHandler: @escaping (CVPixelBuffer) -> Void) -> Bool
    func endSampleBufferOutput()
    func captureCurrentFrame(_ frameHandler: @escaping (CVPixelBuffer) -> Void)
    #endif
    func writeCurrentScene(to url: URL) -> Bool
    func stop()
}

extension OMMpvPlayerController: PlaybackEngine {
    #if os(iOS)
    var systemPictureInPictureController: AVPictureInPictureController? { nil }
    #endif
}
#endif
