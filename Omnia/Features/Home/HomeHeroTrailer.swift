import SwiftUI
import Observation

/// Nuvio Enhanced's hero trailer: after the chosen delay, the featured
/// title's trailer fades in over its artwork. While a trailer is waiting or
/// playing, the carousel doesn't advance on its own; it moves on again
/// once the trailer ends or a title has none.
@Observable
@MainActor
final class HomeHeroTrailerModel {
    private(set) var streamURL: URL?
    /// True once the player reports playback, so the trailer never covers
    /// the artwork with a black or loading frame.
    private(set) var isVisible = false
    private(set) var isPending = false
    /// Shared across titles, like Nuvio's speaker button.
    var isMuted = true
    @ObservationIgnored private var appliedStartsWithSound: Bool?
    @ObservationIgnored private var generation = UUID()

    var holdsCarousel: Bool { isPending || streamURL != nil }

    func load(
        _ item: MediaItem?,
        preferences: HeroTrailerPreferences,
        metadata: LiveMetadataStore,
        autoplayAllowed: Bool = true
    ) async {
        reset()
        let requestGeneration = generation
        guard preferences.autoplay, autoplayAllowed, let item else { return }
        if appliedStartsWithSound != preferences.startsWithSound {
            appliedStartsWithSound = preferences.startsWithSound
            isMuted = !preferences.startsWithSound
        }
        isPending = true

        var trailer = item.details?.heroTrailer
        if trailer == nil {
            let detailed = await metadata.details(for: item)
            guard !Task.isCancelled, generation == requestGeneration else { return }
            trailer = detailed.details?.heroTrailer
        }
        guard let id = trailer?.youtubeVideoID else {
            isPending = false
            return
        }
        // Resolve during the chosen delay instead of delaying network work.
        async let resolvedURL = YouTubeTrailerExtractor().resolve(videoID: id)
        do {
            try await Task.sleep(for: .seconds(preferences.startDelaySeconds))
        } catch { return }
        let url = await resolvedURL
        guard !Task.isCancelled, generation == requestGeneration else { return }
        streamURL = url
        isPending = false
    }

    func handle(_ event: NativeTrailerPlayer.Event, for url: URL) {
        guard streamURL == url else { return }
        switch event {
        case .playing:
            isVisible = true
        case .ended, .failed:
            reset()
        }
    }

    private func reset() {
        generation = UUID()
        streamURL = nil
        isVisible = false
        isPending = false
    }
}

/// Which hero trailer may play. Title pages play the same trailer as the
/// Home hero; only the page on top plays, and Home pauses while any title
/// page is open, so two trailers never play at once.
@Observable
@MainActor
final class HeroTrailerFocus {
    static let shared = HeroTrailerFocus()

    private(set) var titlePages: [UUID] = []

    private init() {}

    var homeMayPlay: Bool { titlePages.isEmpty }

    func titlePageMayPlay(_ token: UUID) -> Bool { titlePages.last == token }

    func appear(_ token: UUID) {
        titlePages.removeAll { $0 == token }
        titlePages.append(token)
    }

    func disappear(_ token: UUID) {
        titlePages.removeAll { $0 == token }
    }
}

/// The trailer drawn over the hero artwork, with the scrim the artwork uses
/// so the logo and synopsis stay readable.
struct HomeHeroTrailerLayer: View {
    let model: HomeHeroTrailerModel
    let isPlaying: Bool

    var body: some View {
        ZStack {
            if let url = model.streamURL {
                NativeTrailerPlayer(
                    url: url,
                    isMuted: model.isMuted,
                    isPlaying: isPlaying
                ) { event in
                    model.handle(event, for: url)
                }
                .id(url)

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

    /// Distance from the top of a hero that runs beneath the window's top
    /// bar, so the button sits just below the bar.
    static var fullBleedTopInset: CGFloat {
        #if os(macOS)
        88
        #else
        64
        #endif
    }

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
