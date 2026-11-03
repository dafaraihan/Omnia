import SwiftUI
import Observation

/// Nuvio Enhanced's hero trailer: after the chosen delay, the featured
/// title's trailer fades in over its artwork. While a trailer is waiting or
/// playing, the carousel doesn't advance on its own; once it ends, Settings ›
/// Home Layout › Hero › After Trailer decides what happens next.
@Observable
@MainActor
final class HomeHeroTrailerModel {
    private(set) var stream: HeroTrailerSource?
    /// True once the player reports playback, so the trailer never covers
    /// the artwork with a black or loading frame.
    private(set) var isVisible = false
    private(set) var isPending = false
    /// Shared across titles, like Nuvio's speaker button.
    var isMuted = true
    /// Counts trailers that played to the end, so the hero can move on.
    private(set) var endCount = 0
    /// The title whose trailer last played to the end. It isn't played again
    /// while that title stays in the hero, unless Replay Trailer is chosen.
    @ObservationIgnored private var endedItemID: String?
    @ObservationIgnored private var currentItemID: String?
    @ObservationIgnored private var appliedStartsWithSound: Bool?
    private(set) var generation = UUID()

    @ObservationIgnored private var pausePreview: (() -> Double)?

    /// Pauses audio synchronously before handing the complete playlist, and the
    /// place it had reached, to the player.
    func consumeForPlayback() -> (source: HeroTrailerSource, position: Double)? {
        guard isVisible, let stream else { return nil }
        let position = pausePreview?() ?? 0
        pausePreview = nil
        endedItemID = currentItemID
        reset()
        return (stream, position)
    }

    func registerPause(_ pause: @escaping () -> Double, for source: HeroTrailerSource) {
        guard stream == source else { return }
        pausePreview = pause
    }

    var holdsCarousel: Bool { isPending || stream != nil }

    func load(
        _ item: MediaItem?,
        preferences: HeroTrailerPreferences,
        metadata: LiveMetadataStore,
        autoplayAllowed: Bool = true
    ) async {
        reset()
        let requestGeneration = generation
        currentItemID = item?.id
        if item?.id != endedItemID { endedItemID = nil }
        guard preferences.autoplay, autoplayAllowed, let item else { return }
        guard preferences.afterTrailer == .replay || endedItemID != item.id else { return }
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
        stream = url
        isPending = false
    }

    func handle(_ event: NativeTrailerPlayer.Event, for source: HeroTrailerSource, generation: UUID) {
        guard self.generation == generation, stream == source else { return }
        switch event {
        case .playing:
            isVisible = true
        case .paused:
            isVisible = false
        case .ended:
            reset()
            endedItemID = currentItemID
            endCount += 1
        case .failed:
            reset()
        }
    }

    private func reset() {
        _ = pausePreview?()
        pausePreview = nil
        generation = UUID()
        stream = nil
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
            if let source = model.stream {
                let generation = model.generation
                NativeTrailerPlayer(
                    source: source,
                    isMuted: model.isMuted,
                    isPlaying: isPlaying,
                    registerPause: { model.registerPause($0, for: source) }
                ) { event in
                    model.handle(event, for: source, generation: generation)
                }
                .id(generation)

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
    /// In the window's top bar, where the toolbar draws the glass.
    var isInToolbar = false

    var body: some View {
        if model.isVisible {
            if isInToolbar {
                Button {
                    model.isMuted.toggle()
                } label: {
                    Label(
                        model.isMuted ? "Unmute Trailer" : "Mute Trailer",
                        systemImage: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
                    )
                    .contentTransition(.symbolEffect(.replace))
                }
                .help(model.isMuted ? "Unmute Trailer" : "Mute Trailer")
            } else {
                overlayButton
            }
        }
    }

    private var overlayButton: some View {
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
