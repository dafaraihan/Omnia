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
    @MainActor
    static func update(muted: Bool) {
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
final class IOSPictureInPictureController: NSObject, AVPictureInPictureControllerDelegate {
    let layer = AVPlayerLayer()
    private(set) var player: AVPlayer?
    private(set) var isHandoff = false
    private var controller: AVPictureInPictureController?
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
    }

    func activateAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
            ownsAudioSession = true
        } catch {
            stateChanged?(false, false)
        }
    }

    func deactivateAudioSession() {
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
                      controller?.isPictureInPicturePossible == true && player?.currentItem?.status == .readyToPlay)
    }

    func toggle() {
        if controller?.isPictureInPictureActive == true {
            controller?.stopPictureInPicture()
        } else {
            start()
        }
    }

    private func start() {
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
        controller?.delegate = nil
        controller?.stopPictureInPicture()
        controller = nil
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
        publish()
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        let wasClosed = !isRestoring
        isRestoring = false
        startedInBackground = false
        restore(completed: true)
        publish()
        if wasClosed { closedFromWindow?() }
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        restore()
        handoffFailed?()
        unavailable?(error.localizedDescription)
        publish()
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        isRestoring = true
        willRestore?()
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
