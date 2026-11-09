#if os(iOS)
import AVKit
import MediaPlayer
import SwiftUI

/// Keeps app controls on the same scale as the hardware buttons and output route.
@MainActor
final class IOSOutputVolumeController {
    let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 160, height: 44))
    private var observation: NSKeyValueObservation?
    var changed: ((Double) -> Void)?

    init() {
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.initial, .new]) { [weak self] session, _ in
            let value = Double(session.outputVolume)
            Task { @MainActor [weak self] in self?.changed?(value) }
        }
    }

    /// False when the output route doesn't let the app change its volume.
    @discardableResult
    func setVolume(_ value: Double) -> Bool {
        guard let slider = view.subviews.compactMap({ $0 as? UISlider }).first, slider.isEnabled else { return false }
        slider.value = Float(min(max(value, 0), 1))
        slider.sendActions(for: .valueChanged)
        return true
    }
}

struct IOSSystemVolumeHost: UIViewRepresentable {
    let controller: IOSOutputVolumeController

    func makeUIView(context: Context) -> MPVolumeView { controller.view }
    func updateUIView(_ view: MPVolumeView, context: Context) {}
}

final class IOSPlayerScreenView: UIView {
    var changed: ((UIScreen?) -> Void)?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        let screen = window?.windowScene?.screen
        DispatchQueue.main.async { [weak self] in self?.changed?(screen) }
    }
}

struct IOSPlayerScreenReader: UIViewRepresentable {
    let changed: (UIScreen?) -> Void
    func makeUIView(context: Context) -> IOSPlayerScreenView {
        let view = IOSPlayerScreenView()
        view.changed = changed
        return view
    }
    func updateUIView(_ view: IOSPlayerScreenView, context: Context) { view.changed = changed }
}

/// A muted hero trailer leaves other apps' audio alone. With sound it plays
/// like any other video, through the silent switch.
enum OmniaPreviewAudio {
    /// A preview behind the open player mustn't change the player's audio.
    @MainActor static var playerOwnsSession = false

    @MainActor
    static func update(muted: Bool) {
        guard !playerOwnsSession else { return }
        let session = AVAudioSession.sharedInstance()
        if muted {
            try? session.setCategory(.ambient, mode: .default)
        } else {
            try? session.setCategory(.playback, mode: .moviePlayback)
            try? session.setActive(true)
        }
    }
}

/// AVKit owns the floating window and its system controls. A native mpv
/// source may hand off to an AVPlayer only when AVFoundation can open it.
@MainActor
final class IOSPictureInPictureController: NSObject, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
    let layer = AVPlayerLayer()
    /// Holds mpv's frames while a video floats. iOS needs it on screen, and
    /// showing a frame, before it will offer Picture in Picture.
    let sampleLayer = AVSampleBufferDisplayLayer()
    private var usesSampleBuffers = false
    private var sampleTimebase: CMTimebase?
    private var sampleClock: Task<Void, Never>?
    private(set) var player: AVPlayer?
    private(set) var isHandoff = false
    private var controller: AVPictureInPictureController?
    /// An engine's own floating window (KSPlayer), fed by its decoder.
    private var usesEngineController = false
    private weak var engineVideoView: UIView?
    /// The view behind the whole app that keeps a floating video's layer in
    /// the window while the player is closed.
    weak var backgroundHost: UIView?
    private var possibility: NSKeyValueObservation?
    private var readiness: NSKeyValueObservation?
    private var preparation: Task<Void, Never>?
    private var backgroundObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?
    private var startedInBackground = false
    private var isRestoring = false
    private var startTask: Task<Void, Never>?
    private var handingOff = false
    private var handoffWasPlaying = false
    private var handoffPosition = 0.0
    private var startDeadline: Task<Void, Never>?
    private var preparationDeadline: Task<Void, Never>?
    private var preparingAsset: AVURLAsset?
    private var generation = UUID()
    private var ownsAudioSession = false
    var stateChanged: ((Bool, Bool) -> Void)?
    var position: (() -> Double)?
    var isPlaying: (() -> Bool)?
    var rate: (() -> Double)?
    var audioTrack: (() -> PlaybackTrack?)?
    var subtitleTrack: (() -> PlaybackTrack?)?
    var handoffFailed: (() -> Void)?
    var beginHandoff: (() -> Void)?
    var endHandoff: ((Double, Bool) -> Void)?
    var unavailable: ((String?) -> Void)?
    var duration: (() -> Double)?
    var setPlaying: ((Bool) -> Void)?
    var seekBy: ((Double) -> Void)?
    /// Starts and stops mpv drawing for the floating window.
    var beginFrames: ((@escaping (CVPixelBuffer) -> Void) -> Bool)?
    var endFrames: (() -> Void)?
    /// Copies the frame on screen, for the floating window to open with.
    var captureFrame: ((@escaping (CVPixelBuffer) -> Void) -> Void)?
    private var resignObserver: NSObjectProtocol?
    /// The floating window's Back to app button, before it closes.
    var willRestore: (() -> Void)?
    /// The floating window's close button.
    var closedFromWindow: (() -> Void)?

    override init() {
        super.init()
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.controller?.isPictureInPictureActive == true { self.startedInBackground = true }
                guard self.isHandoff, self.isPlaying?() == true else { return }
                self.start()
            }
        }
        // Swiping home starts here, while the GPU can still copy the frame.
        resignObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.usesSampleBuffers, self.controller?.isPictureInPictureActive != true else { return }
                self.refreshSampleFrame()
            }
        }
        // Coming back to Omnia returns a video that floated when the user
        // left, as other video apps do.
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.startedInBackground else { return }
                self.startedInBackground = false
                self.controller?.stopPictureInPicture()
            }
        }
    }

    deinit {
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    func activateAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
            ownsAudioSession = true
            OmniaPreviewAudio.playerOwnsSession = true
        } catch {
            stateChanged?(false, false)
        }
    }

    func deactivateAudioSession() {
        OmniaPreviewAudio.playerOwnsSession = false
        guard ownsAudioSession else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            ownsAudioSession = false
        } catch {
            // Keep ownership so a later stop can retry releasing the session.
        }
    }

    func configure(player: AVPlayer) {
        reset()
        attach(player, handoff: false)
    }

    /// An engine that floats its own video (KSPlayer). Swiping home floats
    /// it too; its view moves behind the app while the player is closed.
    func attachEngineController(_ engineController: AVPictureInPictureController, videoView: UIView) {
        engineVideoView = videoView
        guard controller !== engineController else { return }
        guard controller?.isPictureInPictureActive != true else { return }
        reset()
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        usesEngineController = true
        controller = engineController
        engineController.delegate = self
        engineController.canStartPictureInPictureAutomaticallyFromInline = true
        possibility = engineController.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.publish() }
        }
    }

    /// mpv's sources: iOS floats the frames mpv hands over.
    func attachSampleBuffers() {
        guard !usesSampleBuffers else { return }
        reset()
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        usesSampleBuffers = true
        sampleLayer.videoGravity = .resizeAspect
        var timebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &timebase)
        sampleTimebase = timebase
        sampleLayer.controlTimebase = timebase
        syncSampleClock()
        Self.enqueueBlackFrame(to: SampleTarget(sampleLayer))
        controller = AVPictureInPictureController(
            contentSource: .init(sampleBufferDisplayLayer: sampleLayer, playbackDelegate: self)
        )
        controller?.delegate = self
        controller?.canStartPictureInPictureAutomaticallyFromInline = true
        possibility = controller?.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.publish() }
        }
    }

    /// The player closes behind the floating window, taking its views with
    /// it; the engine's video moves behind the app, at the size it had, so
    /// its layer stays in the window. The player takes it back when it opens
    /// again.
    private func parkEngineVideo() {
        guard let view = engineVideoView, let backgroundHost, view.superview !== backgroundHost else { return }
        view.frame = view.superview.map { backgroundHost.convert(view.frame, from: $0) } ?? backgroundHost.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backgroundHost.addSubview(view)
    }

    /// Keeps the layer on the real picture and its shape, ready to float.
    private func refreshSampleFrame() {
        let layer = sampleLayer
        let target = SampleTarget(layer)
        captureFrame? { frame in Self.enqueue(frame, to: target) }
    }

    private func syncSampleClock() {
        guard let sampleTimebase else { return }
        let seconds = position?() ?? 0
        CMTimebaseSetTime(sampleTimebase, time: CMTime(seconds: seconds.isFinite ? seconds : 0, preferredTimescale: 600))
        CMTimebaseSetRate(sampleTimebase, rate: isPlaying?() == true ? 1 : 0)
    }

    /// Tells the buttons in the floating window where playback is.
    func samplePlaybackChanged() {
        guard usesSampleBuffers else { return }
        syncSampleClock()
        controller?.invalidatePlaybackState()
    }

    /// The layer's renderer and clock, read on the main thread for frames
    /// that arrive on mpv's queue. Both are safe to use from any thread.
    private nonisolated struct SampleTarget: @unchecked Sendable {
        let renderer: AVSampleBufferVideoRenderer
        let timebase: CMTimebase?

        @MainActor init(_ layer: AVSampleBufferDisplayLayer) {
            renderer = layer.sampleBufferRenderer
            timebase = layer.controlTimebase
        }
    }

    private nonisolated static func enqueue(_ frame: CVPixelBuffer, to target: SampleTarget) {
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: frame, formatDescriptionOut: &format)
        guard let format else { return }
        // Stamped with the layer's own clock, so it never counts as late or early.
        let now = target.timebase.map { CMTimebaseGetTime($0) } ?? CMClockGetTime(CMClockGetHostTimeClock())
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: now, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: frame, formatDescription: format,
            sampleTiming: &timing, sampleBufferOut: &sample
        )
        guard let sample else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dictionary,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }
        let renderer = target.renderer
        if renderer.status == .failed { renderer.flush() }
        renderer.enqueue(sample)
    }

    private static func enqueueBlackFrame(to target: SampleTarget) {
        var frame: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, 16, 9, kCVPixelFormatType_32BGRA, attributes, &frame)
        guard let frame else { return }
        CVPixelBufferLockBaseAddress(frame, [])
        if let base = CVPixelBufferGetBaseAddress(frame) {
            memset(base, 0, CVPixelBufferGetDataSize(frame))
        }
        CVPixelBufferUnlockBaseAddress(frame, [])
        enqueue(frame, to: target)
    }

    // MARK: AVPictureInPictureSampleBufferPlaybackDelegate

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        // The system can ask for this while Omnia is only inactive, under
        // Control Center or Notification Center; only the floating window's own
        // button should pause or play.
        guard pictureInPictureController.isPictureInPictureActive else { return }
        setPlaying?(playing)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            self?.samplePlaybackChanged()
        }
    }

    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        let seconds = duration?() ?? 0
        guard seconds.isFinite, seconds > 0 else {
            // A live stream: no end, so the window shows no timeline.
            return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
        }
        return CMTimeRange(start: .zero, duration: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        isPlaying?() != true
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        seekBy?(skipInterval.seconds)
        syncSampleClock()
        completionHandler()
    }

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        // KSPlayer's layer stays where it is while the window opens; moving
        // it now blanked the start of the animation.
        if usesEngineController { return }
        guard usesSampleBuffers else { return }
        let layer = sampleLayer
        let target = SampleTarget(layer)
        let started = beginFrames? { frame in Self.enqueue(frame, to: target) } ?? false
        if !started { unavailable?(nil) }
        sampleClock?.cancel()
        sampleClock = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.samplePlaybackChanged()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private static let unplayableExtensions: Set<String> = ["mkv", "avi", "webm", "flv", "wmv", "vob", "iso", "m2ts"]

    func prepare(source: PlaybackSource) {
        reset()
        // Header-bearing sources stay with the authorized native player:
        // AVURLAsset has no public arbitrary HTTP-header API.
        guard source.requestHeaders.isEmpty else { return }
        // AVFoundation can't open these, so there's no point connecting to ask.
        guard !Self.unplayableExtensions.contains(source.url.pathExtension.lowercased()) else { return }
        let token = generation
        preparation = Task { [weak self] in
            let asset = AVURLAsset(url: source.url)
            self?.preparingAsset = asset
            let deadline = Task {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                asset.cancelLoading()
            }
            self?.preparationDeadline = deadline
            defer { deadline.cancel() }
            do {
                guard try await asset.load(.isPlayable), !Task.isCancelled,
                      let self, self.generation == token else { return }
                self.attach(AVPlayer(playerItem: AVPlayerItem(asset: asset)), handoff: true)
            } catch {
                // Native playback continues; PiP remains unavailable.
            }
        }
    }

    private func attach(_ player: AVPlayer, handoff: Bool) {
        self.player = player
        isHandoff = handoff
        layer.player = player
        layer.videoGravity = .resizeAspect
        // Inline video must render even when this device cannot offer PiP.
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        controller = AVPictureInPictureController(playerLayer: layer)
        controller?.delegate = self
        controller?.canStartPictureInPictureAutomaticallyFromInline = !handoff
        possibility = controller?.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.publish() }
        }
        readiness = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.publish() }
        }
    }

    private func publish() {
        stateChanged?(controller?.isPictureInPictureActive == true,
                      controller?.isPictureInPicturePossible == true
                        && (usesSampleBuffers || usesEngineController || player?.currentItem?.status == .readyToPlay))
    }

    func toggle() {
        if controller?.isPictureInPictureActive == true {
            controller?.stopPictureInPicture()
        } else {
            start()
        }
    }

    private func start() {
        if usesEngineController {
            guard let controller, controller.isPictureInPicturePossible else { unavailable?(nil); return }
            controller.startPictureInPicture()
            return
        }
        if usesSampleBuffers {
            guard let controller, controller.isPictureInPicturePossible else { unavailable?(nil); return }
            refreshSampleFrame()
            controller.startPictureInPicture()
            return
        }
        guard let controller, controller.isPictureInPicturePossible,
              !controller.isPictureInPictureActive, startTask == nil,
              let player, player.currentItem?.status == .readyToPlay else {
            if controller?.isPictureInPictureActive != true, startTask == nil { unavailable?(nil) }
            return
        }
        if !isHandoff { controller.startPictureInPicture(); return }
        let target = position?() ?? 0
        let token = generation
        let shouldPlay = isPlaying?() == true
        handingOff = true
        handoffWasPlaying = shouldPlay
        handoffPosition = target
        beginHandoff?()
        startDeadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self, self.generation == token,
                  self.controller?.isPictureInPictureActive != true else { return }
            self.startTask?.cancel()
            self.startTask = nil
            self.restore()
            self.handoffFailed?()
        }
        startTask = Task { [weak self] in
            guard let self else { return }
            let selectedAudio = self.audioTrack?()
            let selectedSubtitle = self.subtitleTrack?()
            let selectionMatches = await self.selectTracks(audio: selectedAudio, subtitle: selectedSubtitle, player: player)
            guard !Task.isCancelled, self.generation == token else { return }
            guard selectionMatches else {
                self.startTask = nil
                self.restore()
                self.handoffFailed?()
                return
            }
            let finished = await player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            guard !Task.isCancelled, self.generation == token else { return }
            self.startTask = nil
            guard finished else { self.restore(); self.handoffFailed?(); return }
            if shouldPlay { player.playImmediately(atRate: Float(self.rate?() ?? 1)) }
            controller.startPictureInPicture()
        }
    }

    private func selectTracks(audio: PlaybackTrack?, subtitle: PlaybackTrack?, player: AVPlayer) async -> Bool {
        guard let item = player.currentItem, subtitle?.externalURL == nil else { return false }
        do {
            for (characteristic, track) in [(AVMediaCharacteristic.audible, audio), (.legible, subtitle)] {
                guard let group = try await item.asset.loadMediaSelectionGroup(for: characteristic) else {
                    if track != nil { return false }
                    continue
                }
                guard !Task.isCancelled else { return false }
                guard let track else {
                    if characteristic == .legible { item.select(nil, in: group) }
                    continue
                }
                let byTitle = group.options.filter { option in
                    guard let title = track.title, !title.isEmpty else { return false }
                    return option.displayName.caseInsensitiveCompare(title) == .orderedSame
                }
                let matches = byTitle.isEmpty ? group.options.filter { option in
                    guard let language = PlaybackLanguageMatching.normalized(track.language) else { return false }
                    return PlaybackLanguageMatching.normalized(option.extendedLanguageTag ?? option.locale?.identifier) == language
                } : byTitle
                guard matches.count == 1, let option = matches.first else {
                    // A sole audio stream is unambiguous even without language tags.
                    if characteristic == .audible, group.options.count == 1 {
                        item.select(group.options[0], in: group)
                        continue
                    }
                    return false
                }
                item.select(option, in: group)
            }
            return true
        } catch { return false }
    }

    private func restore(completed: Bool = false) {
        guard handingOff, let player else { return }
        player.currentItem?.cancelPendingSeeks()
        let time = completed ? player.currentTime().seconds : handoffPosition
        let playing = completed ? player.rate != 0 : handoffWasPlaying
        player.pause()
        handingOff = false
        startDeadline?.cancel()
        startDeadline = nil
        endHandoff?(time.isFinite ? time : (position?() ?? 0), playing)
    }

    func reset() {
        generation = UUID()
        preparingAsset?.cancelLoading()
        preparingAsset = nil
        preparationDeadline?.cancel()
        preparationDeadline = nil
        startDeadline?.cancel()
        startDeadline = nil
        preparation?.cancel()
        preparation = nil
        startTask?.cancel()
        startTask = nil
        possibility = nil
        readiness = nil
        sampleClock?.cancel()
        sampleClock = nil
        if usesSampleBuffers {
            endFrames?()
            sampleLayer.sampleBufferRenderer.flush()
            sampleLayer.controlTimebase = nil
            sampleTimebase = nil
            usesSampleBuffers = false
        }
        controller?.delegate = nil
        controller?.stopPictureInPicture()
        controller = nil
        usesEngineController = false
        if isHandoff { player?.pause(); player?.replaceCurrentItem(with: nil) }
        layer.player = nil
        player = nil
        isHandoff = false
        handingOff = false
        stateChanged?(false, false)
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard !isHandoff || handingOff else {
            pictureInPictureController.stopPictureInPicture()
            return
        }
        startDeadline?.cancel()
        startDeadline = nil
        // The window is up; the video's layer moves behind the app before
        // the player closes over it.
        if usesEngineController, pictureInPictureController === controller {
            parkEngineVideo()
        }
        publish()
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        let wasClosed = !isRestoring
        isRestoring = false
        startedInBackground = false
        sampleClock?.cancel()
        sampleClock = nil
        if usesSampleBuffers {
            endFrames?()
            // Keeps the layer showing something, so it can float again.
            Self.enqueueBlackFrame(to: SampleTarget(sampleLayer))
        }
        restore(completed: true)
        publish()
        if wasClosed { closedFromWindow?() }
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        sampleClock?.cancel()
        if usesSampleBuffers { endFrames?() }
        restore()
        handoffFailed?()
        unavailable?(error.localizedDescription)
        publish()
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        isRestoring = true
        willRestore?()
        // Back on Metal now, so the player has its picture when the window lands.
        if usesSampleBuffers { endFrames?() }
        // Lets the player come back on screen for the window to land on.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            completionHandler(true)
        }
    }
}

final class IOSPictureInPictureHostView: UIView {
    var videoLayer: AVPlayerLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let videoLayer { layer.addSublayer(videoLayer) }
            setNeedsLayout()
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        videoLayer?.frame = bounds
    }
}

/// Keeps mpv's frame layer in the window behind the app. It has to stay there
/// while a video floats, and the player closes behind the floating window.
struct IOSSampleBufferLayerHost: UIViewRepresentable {
    let controller: IOSPictureInPictureController

    final class HostView: UIView {
        var sampleLayer: AVSampleBufferDisplayLayer? {
            didSet { if let sampleLayer { layer.addSublayer(sampleLayer) } }
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            sampleLayer?.frame = bounds
        }
    }

    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        view.isUserInteractionEnabled = false
        view.sampleLayer = controller.sampleLayer
        controller.backgroundHost = view
        return view
    }

    func updateUIView(_ view: HostView, context: Context) {}
}

struct IOSPictureInPictureHost: UIViewRepresentable {
    let controller: IOSPictureInPictureController
    let fillsFrame: Bool

    func makeUIView(context: Context) -> IOSPictureInPictureHostView {
        let view = IOSPictureInPictureHostView()
        view.videoLayer = controller.layer
        controller.layer.videoGravity = fillsFrame ? .resizeAspectFill : .resizeAspect
        return view
    }
    func updateUIView(_ view: IOSPictureInPictureHostView, context: Context) {
        controller.layer.videoGravity = fillsFrame ? .resizeAspectFill : .resizeAspect
    }
}
#endif
