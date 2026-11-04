import SwiftUI

extension View {
    /// Nuvio's Card Depth Effect on a rounded card, when Settings turns it on
    /// for `surface`. Otherwise the card keeps `fallbackBorderOpacity`, its
    /// own hairline border, if it had one.
    func cardDepth(
        _ surface: CardDepthPreferences.Surface,
        cornerRadius: CGFloat,
        fallbackBorderOpacity: Double = 0
    ) -> some View {
        modifier(CardDepthModifier(
            surface: surface,
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            fallbackBorderOpacity: fallbackBorderOpacity
        ))
    }

    func cardDepth<S: InsettableShape>(_ surface: CardDepthPreferences.Surface, shape: S) -> some View {
        modifier(CardDepthModifier(surface: surface, shape: shape, fallbackBorderOpacity: 0))
    }
}

private struct CardDepthModifier<S: InsettableShape>: ViewModifier {
    let surface: CardDepthPreferences.Surface
    let shape: S
    let fallbackBorderOpacity: Double
    @Environment(\.displayPreferences) private var display
    @Environment(\.settingsForcesCardHover) private var forcesHover
    @State private var isHovered = false

    func body(content: Content) -> some View {
        let depth = display.cardDepth
        let hover = display.cardHover
        let hovers = hover.isEnabled(for: surface)
        let isLit = hovers && (isHovered || forcesHover)
        let color = hover.color(accent: display.accentColor)
        content
            .overlay {
                if depth.isEnabled(for: surface) {
                    CardDepthOverlay(
                        shape: shape,
                        edge: Double(depth.edgeStrength) / 100,
                        sheen: Double(depth.sheenStrength) / 100,
                        coverage: Double(depth.edgeCoverage) / 100
                    )
                } else if fallbackBorderOpacity > 0 {
                    shape.strokeBorder(.white.opacity(fallbackBorderOpacity))
                }
            }
            // Resting cards get no hover layer at all, except the collection
            // card's faint hairline.
            .overlay {
                if hovers && (isLit || surface == .collections) {
                    CardHoverOverlay(
                        shape: shape,
                        color: color,
                        intensity: hover.intensity,
                        // Collection cards keep their resting hairline.
                        restOpacity: surface == .collections ? 0.08 : 0,
                        isLit: isLit
                    )
                }
            }
            // The halo is a blurred copy of the card's shape behind it, drawn
            // only while lit, so resting cards render no shadow pass at all.
            .background {
                if hover.outerGlow && isLit {
                    shape
                        .fill(color.opacity(hover.intensity.edgeOpacity * 0.7))
                        .blur(radius: hover.intensity.glowRadius)
                }
            }
            .scaleEffect(hover.lift && isLit ? 1.03 : 1)
            // Animated here rather than with .animation on the whole card, so
            // only the hover change animates, never the artwork loading in.
            .onHover { hovering in
                guard hovers || isHovered else { return }
                withAnimation(.snappy(duration: 0.18)) { isHovered = hovering }
            }
    }
}

/// The collection card's hover edge: an optional 1 point hairline at rest
/// that turns into a 2 point edge in the chosen colour while the pointer is on the card.
struct CardHoverOverlay<S: InsettableShape>: View {
    let shape: S
    let color: Color
    let intensity: CardHoverPreferences.Intensity
    var restOpacity: Double = 0
    let isLit: Bool

    var body: some View {
        shape
            .strokeBorder(
                isLit ? color.opacity(intensity.edgeOpacity) : .white.opacity(restOpacity),
                lineWidth: isLit ? 2 : 1
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The same drawing as Nuvio's cardDepthVisual: a 1 pt border whose white
/// fades from `edge` at the top to `edge × coverage` at the bottom, and a
/// sheen over the top 22% of the card.
struct CardDepthOverlay<S: InsettableShape>: View {
    let shape: S
    let edge: Double
    let sheen: Double
    let coverage: Double

    var body: some View {
        ZStack {
            if sheen > 0 {
                shape.fill(LinearGradient(
                    stops: [
                        .init(color: .white.opacity(sheen), location: 0),
                        .init(color: .white.opacity(0), location: 0.22)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            }
            if edge > 0 {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(edge),
                            .white.opacity(edge * (0.33 + 0.67 * coverage)),
                            .white.opacity(edge * coverage)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
