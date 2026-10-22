import SwiftUI

/// Omnia's wordmark. The asset has a light and a dark version, so it
/// follows the system appearance on its own; both are transparent.
struct OmniaWordmark: View {
    var height: CGFloat = 44

    var body: some View {
        Image("OmniaWordmark")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(height: height)
            .accessibilityLabel("Omnia")
    }
}

/// The wordmark's violet-to-teal, for accents on the brand screens.
enum OmniaBrandColors {
    static let violet = Color(profileHex: "705CFF")
    static let teal = Color(profileHex: "33C9CF")
    static let gradient = LinearGradient(colors: [violet, teal], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// The backdrop behind onboarding, sign in and Who's Watching: the window
/// background with two soft glows in the wordmark's colours, lighter in
/// light mode.
struct OmniaBrandBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            OmniaPageBackground()
            GeometryReader { proxy in
                let size = max(proxy.size.width, proxy.size.height)
                Circle()
                    .fill(OmniaBrandColors.violet.opacity(colorScheme == .dark ? 0.32 : 0.18))
                    .frame(width: size * 0.7)
                    .blur(radius: size * 0.16)
                    .offset(x: -size * 0.22, y: -size * 0.28)
                Circle()
                    .fill(OmniaBrandColors.teal.opacity(colorScheme == .dark ? 0.24 : 0.16))
                    .frame(width: size * 0.6)
                    .blur(radius: size * 0.16)
                    .offset(x: proxy.size.width - size * 0.3, y: proxy.size.height - size * 0.32)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Who's Watching's backdrop: a glow in the accent colour that drifts
/// toward the pointer, with a softer one opposite. Gradients only, no blur,
/// and it redraws only when the pointer moves.
struct AccentSpotlightBackground: View {
    var pointer: UnitPoint
    @Environment(\.displayPreferences) private var display
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let size = max(proxy.size.width, proxy.size.height)
            let accent = display.accentColor
            let strength = colorScheme == .dark ? 1.0 : 0.6
            ZStack {
                OmniaPageBackground()
                RadialGradient(
                    colors: [accent.opacity(0.34 * strength), accent.opacity(0.10 * strength), accent.opacity(0)],
                    center: pointer,
                    startRadius: 0,
                    endRadius: size * 0.6
                )
                RadialGradient(
                    colors: [accent.opacity(0.16 * strength), accent.opacity(0)],
                    center: UnitPoint(x: 1 - pointer.x, y: 1 - pointer.y),
                    startRadius: 0,
                    endRadius: size * 0.45
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// A profile's picture: its avatar, or its first letter on its colour.
struct ProfileAvatarView: View {
    let name: String
    let avatarID: String?
    let colorHex: String
    var size: CGFloat = 96
    var isSelected = false

    init(profile: ViewerProfile, size: CGFloat = 96, isSelected: Bool = false) {
        self.init(name: profile.name, avatarID: profile.avatarID, colorHex: profile.colorHex, size: size, isSelected: isSelected)
    }

    init(name: String, avatarID: String?, colorHex: String, size: CGFloat = 96, isSelected: Bool = false) {
        self.name = name
        self.avatarID = avatarID
        self.colorHex = colorHex
        self.size = size
        self.isSelected = isSelected
    }

    /// Round, like Nuvio's avatars everywhere.
    private var shape: Circle { Circle() }

    var body: some View {
        ZStack {
            shape.fill(Color(profileHex: colorHex).gradient)
            if let avatar = avatarID.flatMap(AvatarCatalog.avatar(id:)) {
                CachedArtworkImage(url: avatar.url, size: CGSize(width: size, height: size)) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        initial
                    }
                }
            } else {
                initial
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                isSelected ? AnyShapeStyle(OmniaBrandColors.gradient) : AnyShapeStyle(.white.opacity(0.12)),
                lineWidth: isSelected ? (size < 40 ? 1.5 : max(3, size * 0.035)) : (size < 40 ? 0.5 : 1)
            )
        }
        .accessibilityHidden(true)
    }

    private var initial: some View {
        Text(name.first.map { String($0).uppercased() } ?? "?")
            .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
    }
}
