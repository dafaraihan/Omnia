import SwiftUI

/// Whether a page's accumulated scroll direction requests compact navigation.
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

/// Accumulates scroll in one direction; a reversal starts a fresh threshold.
struct TopBarScrollReporting: ViewModifier {
    let destination: AppDestination
    var hasHero = false
    @Environment(\.reportTopBarScroll) private var report
    @State private var isScrolled = false
    @State private var accumulated: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { previous, current in
                let delta = current - previous
                guard delta != 0 else { return }
                if (delta > 0) != (accumulated > 0) { accumulated = 0 }
                accumulated += delta
                if abs(accumulated) > 60 || current == 0 {
                    isScrolled = current > 0 && delta > 0
                    accumulated = 0
                    report(destination, TopBarScrollReport(isScrolled: isScrolled, hasHero: hasHero))
                }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ProfileStore.self) private var profiles
    @State private var isHovered = false
    @State private var isPressing = false
    @State private var dragIndex: Int?
    @State private var pointer: CGPoint?
    @State private var glowOpacity: Double = 0
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    #if os(macOS)
    /// The system tab bar's height and text size in the window toolbar.
    static let height: CGFloat = 36
    private static let iconSize: CGFloat = 15
    /// The profile's avatar, larger than the symbols so the picture reads.
    private static let avatarSize: CGFloat = 26
    private static let compactItemWidth: CGFloat = 44
    #else
    /// Touch sizes: each tab keeps at least a 44 point target.
    static let height: CGFloat = 52
    private static let iconSize: CGFloat = 18
    private static let avatarSize: CGFloat = 30
    private static let compactItemWidth: CGFloat = 56
    #endif
    private static let inset: CGFloat = 4
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
                        .frame(width: tabWidth, height: barHeight - verticalInset * 2)
                }
            }
            .padding(.horizontal, Self.inset)
            .padding(.vertical, verticalInset)
            if showsGlow {
                glow(width: width)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: barHeight)
        .clipShape(Capsule())
        .background { if reduceTransparency { OmniaPageBackground().clipShape(Capsule()) } }
        .glassEffect(.regular, in: Capsule())
        .contentShape(Capsule())
        .scaleEffect(reduceMotion || dragIndex == nil ? 1 : 1.025)
        .simultaneousGesture(pressGesture(tabWidth: tabWidth))
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : Self.chromeAnimation) { isHovered = hovering }
        }
        .animation(reduceMotion ? nil : Self.chromeAnimation, value: showsLabels)
        .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 1), value: highlightedIndex)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: dragIndex == nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tabs")
    }

    private var barHeight: CGFloat {
        #if os(iOS)
        stacksLabels ? (showsLabels ? 64 : 52) : (showsLabels ? 52 : 48)
        #else
        Self.height
        #endif
    }

    private var verticalInset: CGFloat {
        #if os(iOS)
        min(Self.inset, (barHeight - 44) / 2)
        #else
        Self.inset
        #endif
    }

    // MARK: State

    private func itemWidth(showsLabels: Bool) -> CGFloat {
        if stacksLabels {
            let desired = min(maximumWidth - 32, 480)
            let minimum = CGFloat(destinations.count) * 44 + Self.inset * 2
            let width = min(max(desired, minimum), max(maximumWidth - 16, minimum))
            return (width - Self.inset * 2) / CGFloat(max(destinations.count, 1))
        }
        return Self.compactItemWidth + (showsLabels ? Self.labelWidth : 0)
    }

    /// iPhone has no room for labels beside the icons, so they sit under
    /// them, as on Nuvio's phone bar.
    private var stacksLabels: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    private var showsLabels: Bool {
        prefersLabels && labelsFit && !dynamicTypeSize.isAccessibilitySize
    }

    /// Adaptive follows the page's directional scroll report. Hover exposes
    /// labels on pointer platforms; large accessibility text falls back to icons.
    private var prefersLabels: Bool {
        switch style {
        case .native, .expanded: true
        case .compact: false
        case .adaptive:
            if isHovered { true }
            else if scroll.isScrolled { false }
            else { true }
        }
    }

    /// A window too narrow for labelled tabs shows icons only.
    private var labelsFit: Bool {
        stacksLabels || itemWidth(showsLabels: true) * CGFloat(destinations.count) + Self.inset * 2 <= maximumWidth
    }

    /// A smaller avatar leaves room for the label under it.
    private var avatarSize: CGFloat {
        stacksLabels && showsLabels ? 24 : Self.avatarSize
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
            .frame(width: tabWidth, height: barHeight - verticalInset * 2)
            .scaleEffect(x: reduceMotion || dragIndex == nil ? 1 : 1.06, y: reduceMotion || dragIndex == nil ? 1 : 0.94)
            .offset(x: Self.inset + CGFloat(highlightedIndex) * tabWidth)
    }

    private func tab(_ destination: AppDestination, isHighlighted: Bool) -> some View {
        let layout = stacksLabels ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 6))
        return Button { select(destination) } label: {
            layout {
                icon(destination, isHighlighted: isHighlighted)
                    .frame(width: destination == .settings && profiles.activeProfile != nil ? avatarSize : Self.iconSize + 4)
                if showsLabels {
                    Text(destination.title(for: profiles.activeProfile))
                        .font(.system(stacksLabels ? .caption2 : .subheadline, weight: isHighlighted ? .semibold : .regular))
                        .lineLimit(1)
                        .foregroundStyle(isHighlighted ? .primary : .secondary)
                        .minimumScaleFactor(0.8)
                        .transition(.opacity)
                }
            }
            // Inside the button, so the whole tab answers and not only its
            // icon and label.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(!reduceMotion && isHighlighted && isPressing ? 1.06 : 1)
        .help(destination.title(for: profiles.activeProfile))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(destination.title(for: profiles.activeProfile))
        .accessibilityAddTraits(destination == selection ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { select(destination) }
    }

    /// The selected icon takes the accent, or its gradient with a gradient
    /// theme, as on Nuvio's bar.
    @ViewBuilder
    private func icon(_ destination: AppDestination, isHighlighted: Bool) -> some View {
        if destination == .settings, let profile = profiles.activeProfile {
            ProfileAvatarView(profile: profile, size: avatarSize, isSelected: isHighlighted)
                .modifier(ProfileAnchorReporting())
        } else {
            symbol(destination, isHighlighted: isHighlighted)
        }
    }

    @ViewBuilder
    private func symbol(_ destination: AppDestination, isHighlighted: Bool) -> some View {
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
        let point = pointer ?? CGPoint(x: width / 2, y: barHeight / 2)
        return RadialGradient(
            stops: [
                .init(color: display.accentColor.opacity(alpha), location: 0),
                .init(color: display.accentColor.opacity(alpha * 0.43), location: 0.45),
                .init(color: display.accentColor.opacity(0), location: 1),
            ],
            center: UnitPoint(x: point.x / max(width, 1), y: point.y / barHeight),
            startRadius: 0,
            endRadius: 300
        )
    }

    // MARK: Interaction

    private func pressGesture(tabWidth: CGFloat) -> some Gesture {
        // Starts only once the pointer moves, so a tap is left to the tab's button.
        DragGesture(minimumDistance: 6, coordinateSpace: .local)
            .onChanged { value in
                pointer = value.location
                if !isPressing {
                    isPressing = true
                    withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.9)) { glowOpacity = 1 }
                }
                dragIndex = index(at: value.location.x, tabWidth: tabWidth)
            }
            .onEnded { value in
                let target = index(at: value.location.x, tabWidth: tabWidth)
                let isInside = value.location.y >= -12 && value.location.y <= barHeight + 12
                isPressing = false
                dragIndex = nil
                withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.9)) {
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
