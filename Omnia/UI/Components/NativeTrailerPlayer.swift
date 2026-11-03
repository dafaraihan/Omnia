import SwiftUI
import AVFoundation

/// A decorative, cropped preview with no web content or playback controls.
/// Each instance owns its player; it never changes the main playback session.
struct NativeTrailerPlayer {
    enum Event { case playing, paused, ended, failed }

    let source: HeroTrailerSource
    var isMuted: Bool
    var isPlaying: Bool
    var registerPause: ((@escaping () -> Double) -> Void)? = nil
    let onEvent: (Event) -> Void
    @Environment(\.scenePhase) private var scenePhase

    func makeCoordinator() -> Coordinator { Coordinator() }

    fileprivate func configure(_ view: TrailerVideoView, coordinator: Coordinator) {
        coordinator.onEvent = onEvent
        coordinator.start(source: source, layer: view.videoLayer, muted: isMuted)
        // Pauses the preview and says where it stopped, for the full player.
        registerPause? { [weak coordinator] in
            coordinator?.update(muted: true, playing: false)
            let position = coordinator?.position ?? 0
            return position.isFinite ? position : 0
        }
        coordinator.update(muted: isMuted, playing: isPlaying && scenePhase == .active)
    }

    fileprivate func update(_ coordinator: Coordinator) {
        coordinator.onEvent = onEvent
        coordinator.update(muted: isMuted, playing: isPlaying && scenePhase == .active)
    }

    @MainActor
    final class Coordinator {
        var onEvent: ((Event) -> Void)?
        private var player: AVPlayer?
        private weak var videoLayer: AVPlayerLayer?
        private var observations: [NSKeyValueObservation] = []
        private var notifications: [NSObjectProtocol] = []
        private var watchdog: Task<Void, Never>?
        private var wantsPlayback = false
        private var finished = false
        private var playlistLoader: TrailerPlaylistLoader?

        func start(source: HeroTrailerSource, layer: AVPlayerLayer, muted: Bool) {
            let asset: AVURLAsset
            if let playlist = source.playlist {
                let loader = TrailerPlaylistLoader(playlist: playlist)
                playlistLoader = loader
                asset = AVURLAsset(url: loader.url)
                asset.resourceLoader.setDelegate(loader, queue: loader.queue)
            } else {
                asset = AVURLAsset(url: source.url)
            }
            let item = AVPlayerItem(asset: asset)
            item.preferredMaximumResolution = CGSize(width: 1_920, height: 1_080)
            let player = AVPlayer(playerItem: item)
            player.isMuted = muted
            player.preventsDisplaySleepDuringVideoPlayback = false
            player.allowsExternalPlayback = false
            self.player = player
            videoLayer = layer
            layer.videoGravity = .resizeAspectFill
            layer.player = player

            observations = [
                item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                    let failed = item.status == .failed
                    Task { @MainActor [weak self] in
                        if failed { self?.finish(.failed) }
                    }
                },
                layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.reportPlayback() }
                },
                player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.reportPlayback() }
                },
                item.observe(\.presentationSize, options: [.new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.reportPlayback() }
                }
            ]
            for (name, event) in [
                (AVPlayerItem.didPlayToEndTimeNotification, Event.ended),
                (AVPlayerItem.failedToPlayToEndTimeNotification, Event.failed)
            ] {
                notifications.append(NotificationCenter.default.addObserver(
                    forName: name, object: item, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.finish(event) }
                })
            }
        }

        var position: Double { player?.currentTime().seconds ?? 0 }

        func update(muted: Bool, playing: Bool) {
            guard !finished else { return }
            player?.isMuted = muted
            let wasPlaying = wantsPlayback
            wantsPlayback = playing
            if playing {
                player?.play()
                reportPlayback()
            } else {
                player?.pause()
                if wasPlaying { onEvent?(.paused) }
                watchdog?.cancel()
                watchdog = nil
            }
        }

        private func reportPlayback() {
            guard !finished, wantsPlayback else { return }
            let size = player?.currentItem?.presentationSize ?? .zero
            if videoLayer?.isReadyForDisplay == true, player?.timeControlStatus == .playing, size != .zero {
                // The manifest/format says Full HD; also verify the rendered
                // track before exposing it, including later size changes.
                guard size == CGSize(width: 1_920, height: 1_080) else {
                    finish(.failed)
                    return
                }
                watchdog?.cancel()
                watchdog = nil
                onEvent?(.playing)
            } else if watchdog == nil {
                watchdog = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(15)) } catch { return }
                    self?.finish(.failed)
                }
            }
        }

        private func finish(_ event: Event) {
            guard !finished else { return }
            finished = true
            player?.pause()
            watchdog?.cancel()
            watchdog = nil
            onEvent?(event)
        }

        func stop() {
            finished = true
            watchdog?.cancel()
            watchdog = nil
            observations.removeAll()
            notifications.forEach { NotificationCenter.default.removeObserver($0) }
            notifications.removeAll()
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            videoLayer?.player = nil
            player = nil
            playlistLoader = nil
            onEvent = nil
        }
    }
}

/// Serves only the generated master. Its child playlists remain validated
/// absolute HTTPS URLs, loaded directly by AVFoundation as before.
nonisolated final class TrailerPlaylistLoader: NSObject, AVAssetResourceLoaderDelegate, Sendable {
    let url = URL(string: "omnia-trailer://preview/\(UUID().uuidString)/master.m3u8")!
    let queue = DispatchQueue(label: "app.omnia.trailer-playlist")
    private let playlist: Data

    init(playlist: Data) { self.playlist = playlist }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        guard request.request.url == url else { return false }
        request.contentInformationRequest?.contentType = "public.m3u-playlist"
        request.contentInformationRequest?.contentLength = Int64(playlist.count)
        request.contentInformationRequest?.isByteRangeAccessSupported = true
        if let dataRequest = request.dataRequest {
            let offset = dataRequest.currentOffset
            guard offset >= 0, offset <= Int64(playlist.count) else {
                request.finishLoading(with: URLError(.badServerResponse))
                return true
            }
            let start = Int(offset)
            let count = dataRequest.requestsAllDataToEndOfResource
                ? playlist.count - start : min(dataRequest.requestedLength, playlist.count - start)
            dataRequest.respond(with: playlist.subdata(in: start..<(start + count)))
        }
        request.finishLoading()
        return true
    }
}

#if os(macOS)
import AppKit

final class TrailerVideoView: NSView {
    let videoLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(videoLayer)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        CATransaction.commit()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

extension NativeTrailerPlayer: NSViewRepresentable {
    func makeNSView(context: Context) -> TrailerVideoView {
        let view = TrailerVideoView()
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: TrailerVideoView, context: Context) { update(context.coordinator) }

    static func dismantleNSView(_ view: TrailerVideoView, coordinator: Coordinator) { coordinator.stop() }
}
#else
import UIKit

final class TrailerVideoView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var videoLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

extension NativeTrailerPlayer: UIViewRepresentable {
    func makeUIView(context: Context) -> TrailerVideoView {
        let view = TrailerVideoView()
        view.isUserInteractionEnabled = false
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ view: TrailerVideoView, context: Context) { update(context.coordinator) }

    static func dismantleUIView(_ view: TrailerVideoView, coordinator: Coordinator) { coordinator.stop() }
}
#endif
