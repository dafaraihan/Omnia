import Observation
import SwiftUI

/// Nuvio's launch and profile-switch overlay: the wordmark (at launch) or
/// the chosen profile's avatar drops in with a bounce, a glow and a ring
/// that pulses out, holds briefly, then clears. A profile's avatar glides
/// up into its place in the top bar or sidebar as it goes.
@Observable
@MainActor
final class ProfileSwitchCenter {
    static let shared = ProfileSwitchCenter()

    enum Emblem: Equatable {
        case wordmark
        case profile(ViewerProfile)
    }

    struct Transition: Identifiable, Equatable {
        let id = UUID()
        let emblem: Emblem
        /// Where the tapped avatar was, in window coordinates.
        let origin: CGPoint?
    }

    private(set) var transition: Transition?
    private(set) var isExiting = false
    /// Who's Watching was opened by Switch Profile rather than at launch.
    private(set) var isPickerOpen = false
    /// The profile's avatar in the top bar or sidebar, in window
    /// coordinates; the switch ends there.
    @ObservationIgnored var profileAnchor: CGRect?
    @ObservationIgnored private var hasLaunched = false
    @ObservationIgnored private var exitTask: Task<Void, Never>?

    private init() {}

    /// Once per launch, however many windows open.
    func beginLaunch() {
        guard !hasLaunched else { return }
        hasLaunched = true
        // Nuvio holds its intro for 1.3 s; Omnia lingers a little longer.
        begin(Transition(emblem: .wordmark, origin: nil), minimum: .milliseconds(2400))
    }

    func beginSwitch(to profile: ViewerProfile, from origin: CGPoint?) {
        isPickerOpen = false
        // Nuvio's pacing (650 ms after a glide, 1 s for a bounce), slowed
        // down so each step can be seen.
        begin(Transition(emblem: .profile(profile), origin: origin), minimum: .milliseconds(origin == nil ? 1700 : 1500))
    }

    /// Account › Switch Profile: Who's Watching, with Back to stay.
    func openPicker(using profiles: ProfileStore) {
        isPickerOpen = true
        profiles.needsSelection = true
    }

    func cancelPicker(using profiles: ProfileStore) {
        isPickerOpen = false
        profiles.needsSelection = false
    }

    func finish(_ id: Transition.ID) {
        guard transition?.id == id else { return }
        transition = nil
        isExiting = false
    }

    private func begin(_ next: Transition, minimum: Duration) {
        exitTask?.cancel()
        isExiting = false
        transition = next
        exitTask = Task { [weak self] in
            try? await Task.sleep(for: minimum)
            guard !Task.isCancelled, let self, self.transition?.id == next.id else { return }
            self.isExiting = true
        }
    }
}

struct ProfileTransitionOverlay: View {
    let transition: ProfileSwitchCenter.Transition
    let isExiting: Bool
    let anchor: CGRect?
    let onFinished: () -> Void
    @Environment(\.displayPreferences) private var display

    @State private var emblemScale: CGFloat = 1.7
    @State private var emblemOpacity: Double = 0
    @State private var emblemOffset = CGSize(width: 0, height: -36)
    @State private var haloOpacity: Double = 0
    @State private var ringScale: CGFloat = 0.7
    @State private var ringOpacity: Double = 0
    @State private var backdropOpacity: Double = 1

    private static let avatarSize: CGFloat = 112

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            ZStack {
                backdrop
                    .opacity(backdropOpacity)
                Circle()
                    .fill(RadialGradient(
                        colors: [glowColor.opacity(0.32), glowColor.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 180
                    ))
                    .frame(width: 360, height: 360)
                    .opacity(haloOpacity)
                Circle()
                    .strokeBorder(glowColor, lineWidth: 1.5)
                    .frame(width: Self.avatarSize + 16, height: Self.avatarSize + 16)
                    .scaleEffect(ringScale)
                    .opacity(ringOpacity)
                emblem
                    .scaleEffect(emblemScale)
                    .opacity(emblemOpacity)
                    .offset(emblemOffset)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .task { await enter(in: frame) }
            .onChange(of: isExiting) { _, exiting in
                if exiting { exit(in: frame) }
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
    }

    @ViewBuilder
    private var emblem: some View {
        switch transition.emblem {
        case .wordmark:
            OmniaWordmark(height: 54)
        case let .profile(profile):
            ProfileAvatarView(profile: profile, size: Self.avatarSize)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        }
    }

    private var backdrop: some View {
        ZStack {
            Color.black
            RadialGradient(
                colors: [glowColor.opacity(0.22), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 520
            )
        }
    }

    /// The theme's accent, for the wordmark and every profile alike.
    private var glowColor: Color { display.accentColor }

    private var accessibilityTitle: String {
        switch transition.emblem {
        case .wordmark: "Omnia"
        case let .profile(profile): "Switching to \(profile.name)"
        }
    }

    // MARK: Timeline

    private func enter(in frame: CGRect) async {
        if let origin = transition.origin {
            // The tapped avatar glides from its tile to the centre.
            emblemScale = 120 / Self.avatarSize
            emblemOpacity = 1
            emblemOffset = CGSize(width: origin.x - frame.midX, height: origin.y - frame.midY)
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.85)) {
                emblemOffset = .zero
                emblemScale = 1
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.55)) { haloOpacity = 1 }
            try? await Task.sleep(for: .milliseconds(850))
        } else {
            withAnimation(.easeOut(duration: 0.5)) { emblemOpacity = 1 }
            withAnimation(.easeOut(duration: 0.9)) { haloOpacity = 1 }
            withAnimation(.spring(response: 0.9, dampingFraction: 0.6)) {
                emblemOffset = .zero
                emblemScale = 1
            }
        }
        guard !Task.isCancelled else { return }
        pulseRing()
    }

    private func pulseRing() {
        ringScale = 0.7
        ringOpacity = 0.45
        withAnimation(.easeOut(duration: 1.4)) {
            ringScale = 1.9
            ringOpacity = 0
        }
    }

    private func exit(in frame: CGRect) {
        withAnimation(.easeOut(duration: 0.4)) {
            haloOpacity = 0
            ringOpacity = 0
        }
        switch transition.emblem {
        case .wordmark:
            withAnimation(.easeInOut(duration: 0.8)) {
                emblemOpacity = 0
                emblemScale = 0.92
                backdropOpacity = 0
            } completion: {
                onFinished()
            }
        case .profile:
            // Up into the profile's place in the top bar or sidebar, staying
            // solid until the very end, as on Nuvio.
            let target = anchor.map { CGPoint(x: $0.midX, y: $0.midY) }
                ?? CGPoint(x: frame.minX + frame.width * 0.64, y: frame.minY + 30)
            let end = CGSize(width: target.x - frame.midX, height: target.y - frame.midY)
            let endScale = max(0.12, (anchor?.width ?? 26) / Self.avatarSize)
            withAnimation(.easeInOut(duration: 0.7)) { backdropOpacity = 0 }
            withAnimation(.easeOut(duration: 0.25).delay(0.55)) { emblemOpacity = 0 }
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.8)) {
                emblemOffset = end
                emblemScale = endScale
            } completion: {
                onFinished()
            }
        }
    }
}

/// Tells the switch animation where the profile's avatar sits in the top
/// bar or sidebar. Only layout changes report, never scrolling content.
struct ProfileAnchorReporting: ViewModifier {
    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            if frame.width > 0 { ProfileSwitchCenter.shared.profileAnchor = frame }
        }
    }
}
