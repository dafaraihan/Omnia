//
//  PlaybackSession.swift
//  Omnia
//

import AVFoundation
import Observation

/// Shared AVFoundation engine. Platform-specific AVKit views present this
/// player with Apple’s native controls while this type owns resume timing.
@Observable
@MainActor
final class PlaybackSession {
    private(set) var player: AVPlayer?
    private(set) var source: PlaybackSource?
    private(set) var mediaItem: MediaItem?
    private(set) var positionSeconds: Double = 0
    private(set) var durationSeconds: Double?
    private(set) var hasFinished = false

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var completionObserver: NSObjectProtocol?
    @ObservationIgnored private var lastPersistedPosition: Double = 0
    @ObservationIgnored private var progressHandler: (@MainActor (Double, Double?) -> Void)?

    func start(
        item: MediaItem,
        source: PlaybackSource,
        resumeAt position: Double?,
        onProgress: @escaping @MainActor (Double, Double?) -> Void
    ) {
        stop(persisting: true)

        let playerItem = AVPlayerItem(url: source.url)
        let player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = true

        self.player = player
        self.source = source
        self.mediaItem = item
        self.progressHandler = onProgress
        hasFinished = false
        durationSeconds = nil
        positionSeconds = 0
        lastPersistedPosition = 0

        installObservers(for: player, item: playerItem)
        if let position, position > 0 {
            player.seek(to: CMTime(seconds: position, preferredTimescale: 600))
            positionSeconds = position
        }
        player.play()
    }

    func pause() {
        player?.pause()
        persistProgress(force: true)
    }

    func stop(persisting: Bool = true) {
        if persisting { persistProgress(force: true) }
        player?.pause()
        removeObservers()
        player = nil
        source = nil
        mediaItem = nil
        progressHandler = nil
        positionSeconds = 0
        durationSeconds = nil
    }

    private func installObservers(for player: AVPlayer, item: AVPlayerItem) {
        let interval = CMTime(seconds: 1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.observe(time: time)
            }
        }
        completionObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.hasFinished = true
                self.positionSeconds = self.durationSeconds ?? self.positionSeconds
                self.progressHandler?(self.positionSeconds, self.durationSeconds)
            }
        }
    }

    private func observe(time: CMTime) {
        guard time.isNumeric else { return }
        positionSeconds = max(time.seconds, 0)
        if let duration = player?.currentItem?.duration, duration.isNumeric, duration.seconds > 0 {
            durationSeconds = duration.seconds
        }
        persistProgress(force: false)
    }

    private func persistProgress(force: Bool) {
        guard positionSeconds > 0 else { return }
        guard force || positionSeconds - lastPersistedPosition >= 10 else { return }
        lastPersistedPosition = positionSeconds
        progressHandler?(positionSeconds, durationSeconds)
    }

    private func removeObservers() {
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let completionObserver { NotificationCenter.default.removeObserver(completionObserver) }
        completionObserver = nil
    }
}
