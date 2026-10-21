import SwiftUI
import Observation

/// Nuvio Enhanced's hero trailer: after the chosen delay, the featured
/// title's trailer fades in over its artwork. While a trailer is waiting or
/// playing, the carousel doesn't advance on its own; it moves on again
/// once the trailer ends or a title has none.
@Observable
@MainActor
final class HomeHeroTrailerModel {
    private(set) var videoID: String?
    /// True once the player reports playback, so the trailer never covers
    /// the artwork with a black or loading frame.
    private(set) var isVisible = false
    private(set) var isPending = false
    /// Shared across titles, like Nuvio's speaker button.
    var isMuted = true
    @ObservationIgnored private var appliedStartsWithSound: Bool?
    @ObservationIgnored private var revealTask: Task<Void, Never>?

    var holdsCarousel: Bool { isPending || videoID != nil }

    func load(
        _ item: MediaItem?,
        preferences: HeroTrailerPreferences,
        metadata: LiveMetadataStore
    ) async {
        reset()
        guard preferences.autoplay, let item else { return }
        if appliedStartsWithSound != preferences.startsWithSound {
            appliedStartsWithSound = preferences.startsWithSound
            isMuted = !preferences.startsWithSound
        }
        isPending = true

        var trailer = item.details?.heroTrailer
        if trailer == nil {
            let detailed = await metadata.details(for: item)
            guard !Task.isCancelled else { return }
            trailer = detailed.details?.heroTrailer
        }
        guard let id = trailer?.youtubeVideoID else {
            isPending = false
            return
        }
        if preferences.startDelaySeconds > 0 {
            try? await Task.sleep(for: .seconds(preferences.startDelaySeconds))
            guard !Task.isCancelled else { return }
        }
        videoID = id
        isPending = false
    }

    func handle(_ event: YouTubeTrailerPlayer.Event) {
        switch event {
        case .playing:
            guard !isVisible, revealTask == nil else { return }
            // YouTube shows the title over the first moments; wait for it to
            // clear before fading in.
            revealTask = Task {
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled, videoID != nil else { return }
                isVisible = true
            }
        case .ended, .failed:
            reset()
        }
    }

    private func reset() {
        revealTask?.cancel()
        revealTask = nil
        videoID = nil
        isVisible = false
        isPending = false
    }
}

/// The trailer drawn over the hero artwork, with the scrim the artwork uses
/// so the logo and synopsis stay readable.
struct HomeHeroTrailerLayer: View {
    let model: HomeHeroTrailerModel
    let isPlaying: Bool

    var body: some View {
        ZStack {
            if let videoID = model.videoID {
                YouTubeTrailerPlayer(
                    videoID: videoID,
                    isMuted: model.isMuted,
                    isPlaying: isPlaying
                ) { event in
                    model.handle(event)
                }
                .id(videoID)

                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.62), location: 0),
                        .init(color: .black.opacity(0.18), location: 0.45),
                        .init(color: .clear, location: 0.7)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                LinearGradient(
                    colors: [.clear, .clear, .black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .opacity(model.isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.8), value: model.isVisible)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Nuvio's speaker button for the hero trailer.
struct HomeHeroTrailerMuteButton: View {
    @Bindable var model: HomeHeroTrailerModel

    var body: some View {
        if model.isVisible {
            Button {
                model.isMuted.toggle()
            } label: {
                Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 38, height: 38)
            }
            #if os(macOS)
            .omniaCircularGlassButton()
            #else
            .buttonStyle(.plain)
            .background(.ultraThinMaterial, in: .circle)
            #endif
            .help(model.isMuted ? "Unmute Trailer" : "Mute Trailer")
            .accessibilityLabel(model.isMuted ? "Unmute trailer" : "Mute trailer")
            .transition(.opacity.combined(with: .scale(scale: 0.85)))
        }
    }
}
