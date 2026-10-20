#if os(macOS)
import SwiftUI

/// What a page tells Nuvio's top bar: whether it has scrolled past
/// Nuvio's threshold, and whether a hero sits at its top.
struct TopBarScrollReport: Equatable {
    var isScrolled = false
    var hasHero = false
}

private struct TopBarScrollReporterKey: EnvironmentKey {
    static let defaultValue: (AppDestination, TopBarScrollReport) -> Void = { _, _ in }
}

extension EnvironmentValues {
    var reportTopBarScroll: (AppDestination, TopBarScrollReport) -> Void {
        get { self[TopBarScrollReporterKey.self] }
        set { self[TopBarScrollReporterKey.self] = newValue }
    }
}

/// Reports a page's scroll position to the top bar. Only Home and Settings
/// do this, as in Nuvio, and only when the position crosses the threshold.
struct TopBarScrollReporting: ViewModifier {
    let destination: AppDestination
    var hasHero = false
    @Environment(\.reportTopBarScroll) private var report
    @State private var isScrolled = false

    /// Nuvio's thresholds: 35 points on Home and 70 on Settings.
    private var threshold: CGFloat { destination == .settings ? 70 : 35 }

    func body(content: Content) -> some View {
        // A local, so the scroll closure doesn't reach into the main actor.
        let threshold = threshold
        return content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > threshold
            } action: { _, scrolled in
                isScrolled = scrolled
                report(destination, TopBarScrollReport(isScrolled: scrolled, hasHero: hasHero))
            }
            .onChange(of: hasHero, initial: true) { _, hero in
                report(destination, TopBarScrollReport(isScrolled: isScrolled, hasHero: hero))
            }
    }
}

/// Nuvio's floating tab bar, sized and placed like the iPadOS-style system
/// tab bar: it sits in the centre of the window toolbar on the same Liquid
/// Glass, at the same height and text size. Nuvio's parts are the icons, the
/// accent pill that slides to the selected tab, the label rules of each
/// style, dragging across tabs, and Glass Glow.
struct NuvioTopBar: View {
    let destinations: [AppDestination]
    let selection: AppDestination
    let style: TopBarStyle
    let showsGlow: Bool
    let scroll: TopBarScrollReport
    let maximumWidth: CGFloat
    let select: (AppDestination) -> Void

    @Environment(\.displayPreferences) private var display
    @State private var isHovered = false
    @State private var isPressing = false
    @State private var dragIndex: Int?
    @State private var pointer: CGPoint?
    @State private var glowOpacity: Double = 0

    /// The system tab bar's height and text size in the window toolbar.
    static let height: CGFloat = 36
    private static let inset: CGFloat = 4
    private static let iconSize: CGFloat = 15
    private static let compactItemWidth: CGFloat = 44
    private static let labelWidth: CGFloat = 52

    /// Nuvio animates the bar with a 320 ms FastOutSlowIn curve.
    private static let chromeAnimation = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.32)

    var body: some View {
        let tabWidth = itemWidth(showsLabels: showsLabels)
        let width = tabWidth * CGFloat(destinations.count) + Self.inset * 2

        ZStack(alignment: .leading) {
            pill(tabWidth: tabWidth)
            HStack(spacing: 0) {
                ForEach(Array(destinations.enumerated()), id: \.element) { index, destination in
                    tab(destination, isHighlighted: index == highlightedIndex)
                        .frame(width: tabWidth, height: Self.height - Self.inset * 2)
                }
            }
            .padding(Self.inset)
            if showsGlow {
                glow(width: width)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: Self.height)
        .clipShape(Capsule())
        .glassEffect(.regular, in: Capsule())
        .contentShape(Capsule())
        .scaleEffect(dragIndex == nil ? 1 : 1.025)
        .gesture(pressGesture(tabWidth: tabWidth))
        .onHover { hovering in
            withAnimation(Self.chromeAnimation) { isHovered = hovering }
        }
        .animation(Self.chromeAnimation, value: showsLabels)
        .animation(.spring(response: 0.22, dampingFraction: 1), value: highlightedIndex)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dragIndex == nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tabs")
    }

    // MARK: State

    private func itemWidth(showsLabels: Bool) -> CGFloat {
        Self.compactItemWidth + (showsLabels ? Self.labelWidth : 0)
    }

    private var showsLabels: Bool {
        prefersLabels && labelsFit
    }

    /// Nuvio's label rules: Expanded always shows labels, Compact never does,
    /// and Adaptive hides them over the Home hero or once Home has scrolled,
    /// unless the pointer is over the bar.
    private var prefersLabels: Bool {
        switch style {
        case .native, .expanded: true
        case .compact: false
        case .adaptive:
            if isHovered { true }
            else if selection == .home && (scroll.hasHero || scroll.isScrolled) { false }
            else { true }
        }
    }

    /// A window too narrow for labelled tabs shows icons only.
    private var labelsFit: Bool {
        itemWidth(showsLabels: true) * CGFloat(destinations.count) + Self.inset * 2 <= maximumWidth
    }

    private var selectedIndex: Int {
        destinations.firstIndex(of: selection) ?? 0
    }

    private var highlightedIndex: Int {
        dragIndex ?? selectedIndex
    }

    // MARK: Drawing

    /// The selected pill: the accent at 15%, as Nuvio's `Opacity.selected`.
    private func pill(tabWidth: CGFloat) -> some View {
        Capsule()
            .fill(display.accentColor.opacity(0.15))
            .frame(width: tabWidth, height: Self.height - Self.inset * 2)
            .scaleEffect(x: dragIndex == nil ? 1 : 1.06, y: dragIndex == nil ? 1 : 0.94)
            .offset(x: Self.inset + CGFloat(highlightedIndex) * tabWidth)
    }

    private func tab(_ destination: AppDestination, isHighlighted: Bool) -> some View {
        HStack(spacing: 6) {
            icon(destination, isHighlighted: isHighlighted)
                .frame(width: Self.iconSize + 4)
            if showsLabels {
                Text(destination.title)
                    .font(.system(size: 13, weight: isHighlighted ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(isHighlighted ? .primary : .secondary)
                    .fixedSize()
                    .transition(.opacity)
            }
        }
        .scaleEffect(isHighlighted && isPressing ? 1.06 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .help(destination.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(destination.title)
        .accessibilityAddTraits(destination == selection ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { select(destination) }
    }

    /// The selected icon takes the accent, or its gradient with a gradient
    /// theme, as on Nuvio's bar.
    @ViewBuilder
    private func icon(_ destination: AppDestination, isHighlighted: Bool) -> some View {
        let image = Image(systemName: destination.symbolName)
            .font(.system(size: Self.iconSize, weight: .medium))
        if isHighlighted {
            image.foregroundStyle(display.accentStyle)
        } else {
            image.foregroundStyle(.secondary)
        }
    }

    /// Nuvio's drawJellyGlow: a 300 point radial light at the pointer, 15%
    /// of the accent at its centre, 43% of that at the 45% stop, then clear.
    private func glow(width: CGFloat) -> some View {
        let alpha = 0.15 * glowOpacity
        let point = pointer ?? CGPoint(x: width / 2, y: Self.height / 2)
        return RadialGradient(
            stops: [
                .init(color: display.accentColor.opacity(alpha), location: 0),
                .init(color: display.accentColor.opacity(alpha * 0.43), location: 0.45),
                .init(color: display.accentColor.opacity(0), location: 1),
            ],
            center: UnitPoint(x: point.x / max(width, 1), y: point.y / Self.height),
            startRadius: 0,
            endRadius: 300
        )
    }

    // MARK: Interaction

    private func pressGesture(tabWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                pointer = value.location
                if !isPressing {
                    isPressing = true
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) { glowOpacity = 1 }
                }
                // A press stays on its tab until the pointer actually moves.
                let moved = hypot(value.translation.width, value.translation.height) > 4
                if moved || dragIndex != nil {
                    dragIndex = index(at: value.location.x, tabWidth: tabWidth)
                }
            }
            .onEnded { value in
                let target = index(at: value.location.x, tabWidth: tabWidth)
                let isInside = value.location.y >= -12 && value.location.y <= Self.height + 12
                isPressing = false
                dragIndex = nil
                withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
                    glowOpacity = 0
                    pointer = nil
                }
                if isInside, destinations.indices.contains(target) {
                    select(destinations[target])
                }
            }
    }

    private func index(at x: CGFloat, tabWidth: CGFloat) -> Int {
        guard tabWidth > 0 else { return selectedIndex }
        let raw = Int(((x - Self.inset) / tabWidth).rounded(.down))
        return min(max(raw, 0), destinations.count - 1)
    }
}
#endif
