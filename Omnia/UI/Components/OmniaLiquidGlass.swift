import SwiftUI

struct OmniaLiquidGlassHoverTransform: Equatable {
    let scale: CGFloat
    let verticalOffset: CGFloat
}

enum OmniaLiquidGlassSurfaceRole {
    case control
    case menuRow
    case sidebar
    case playbackTimeline
    case modal

    var liftsOnHover: Bool {
        self == .control
    }

    var darkensWhenActive: Bool {
        self == .control || self == .menuRow
    }

    var isContinuousSurface: Bool {
        self == .modal
    }

    var baseDarkeningOpacity: Double {
        self == .modal ? 0.34 : 0
    }
}

enum OmniaLiquidGlassPresentation {
    static func transform(isHovering: Bool) -> OmniaLiquidGlassHoverTransform {
        OmniaLiquidGlassHoverTransform(
            scale: isHovering ? 1.04 : 1,
            verticalOffset: isHovering ? -2 : 0
        )
    }

    static func darkeningOpacity(isHovering: Bool, isPressed: Bool) -> Double {
        if isPressed { return 0.22 }
        return isHovering ? 0.14 : 0
    }
}

enum OmniaGlassBase {
    case clear, regular
}

/// Every glass surface goes through here, so Settings › Layout › Liquid Glass
/// reaches all of them.
private struct OmniaGlassSurface<S: Shape>: ViewModifier {
    @Environment(\.displayPreferences) private var display

    let element: OmniaGlassElement
    let base: OmniaGlassBase
    let interactive: Bool
    let shape: S

    private var preferences: LiquidGlassPreferences { display.liquidGlass }

    /// Below the middle of the slider the glass thins to clear. Above it, a
    /// frost layer builds up under the glass.
    private var frost: Double {
        let intensity = preferences.intensity
        return intensity < 0.5 ? intensity * 0.6 : (intensity - 0.5) * 1.6
    }

    private var usesClearBelowMiddle: Bool { preferences.intensity < 0.5 }

    private var glass: Glass {
        let resolved: OmniaGlassBase = switch preferences.style {
        case .standard: usesClearBelowMiddle ? .clear : base
        case .clear: .clear
        case .frosted: .regular
        }
        let glass: Glass = resolved == .clear ? .clear : .regular
        return interactive ? glass.interactive() : glass
    }

    func body(content: Content) -> some View {
        if preferences.applies(to: element) {
            content
                .background {
                    shape.fill(.ultraThinMaterial)
                        .opacity(frost)
                        .allowsHitTesting(false)
                }
                .glassEffect(glass, in: shape)
        } else {
            content.background {
                switch element {
                case .actionButtons:
                    shape.fill(.white)
                case .playerControls:
                    shape.fill(.black.opacity(0.55))
                case .navigationBar, .panels:
                    shape.fill(.regularMaterial)
                }
            }
        }
    }
}

extension View {
    func omniaGlass<S: Shape>(
        _ element: OmniaGlassElement,
        base: OmniaGlassBase = .regular,
        interactive: Bool = false,
        in shape: S
    ) -> some View {
        modifier(OmniaGlassSurface(element: element, base: base, interactive: interactive, shape: shape))
    }

    /// The system's glass button, or its plain counterpart with glass off.
    func omniaSystemGlassButton(
        _ element: OmniaGlassElement = .panels,
        prominent: Bool = false
    ) -> some View {
        modifier(OmniaSystemGlassButton(element: element, prominent: prominent))
    }
}

/// iOS gives sheets its own glass; with Menus and Panels off they get a solid
/// page behind them instead.
struct OmniaPanelSheetBackground: ViewModifier {
    @Environment(\.displayPreferences) private var display

    func body(content: Content) -> some View {
        if display.liquidGlass.applies(to: .panels) {
            content
        } else {
            content.presentationBackground { OmniaPageBackground() }
        }
    }
}

private struct OmniaSystemGlassButton: ViewModifier {
    @Environment(\.displayPreferences) private var display

    let element: OmniaGlassElement
    let prominent: Bool

    func body(content: Content) -> some View {
        switch (display.liquidGlass.applies(to: element), prominent) {
        case (true, true): content.buttonStyle(.glassProminent)
        case (true, false): content.buttonStyle(.glass)
        case (false, true): content.buttonStyle(.borderedProminent)
        case (false, false): content.buttonStyle(.bordered)
        }
    }
}

private struct OmniaLiquidGlassButtonBody<Label: View, S: Shape>: View {
    @Environment(\.displayPreferences) private var display
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    let label: Label
    let shape: S
    let role: OmniaLiquidGlassSurfaceRole
    let element: OmniaGlassElement
    let isPressed: Bool

    var body: some View {
        let transform = OmniaLiquidGlassPresentation.transform(
            isHovering: role.liftsOnHover && isEnabled && isHovering
        )
        let darkening = role.darkensWhenActive
            ? OmniaLiquidGlassPresentation.darkeningOpacity(
                isHovering: isEnabled && isHovering,
                isPressed: isEnabled && isPressed
            )
            : 0

        label
            .contentShape(shape)
            .background {
                shape
                    .fill(.black.opacity(darkening))
                    .allowsHitTesting(false)
            }
            .omniaGlass(element, base: .clear, interactive: true, in: shape)
            // White on glass; black on the solid white fill it falls back to.
            .foregroundStyle(element == .actionButtons && !display.liquidGlass.applies(to: .actionButtons) ? .black : .white)
            .scaleEffect(isPressed ? 0.97 : transform.scale)
            .offset(y: transform.verticalOffset)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(reduceMotion ? nil : .smooth(duration: 0.16), value: isHovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: isPressed)
            .onHover { isHovering = $0 }
    }
}

struct OmniaLiquidGlassButtonStyle<S: Shape>: ButtonStyle {
    let shape: S
    var role: OmniaLiquidGlassSurfaceRole = .control
    var element: OmniaGlassElement = .actionButtons

    func makeBody(configuration: Configuration) -> some View {
        OmniaLiquidGlassButtonBody(
            label: configuration.label,
            shape: shape,
            role: role,
            element: element,
            isPressed: configuration.isPressed
        )
    }
}

private struct OmniaMenuRowButtonBody<Label: View, S: Shape>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    let label: Label
    let shape: S
    let isPressed: Bool

    var body: some View {
        let opacity = OmniaLiquidGlassPresentation.darkeningOpacity(
            isHovering: isEnabled && isHovering,
            isPressed: isEnabled && isPressed
        )
        label
            .contentShape(shape)
            .background(shape.fill(.black.opacity(opacity)))
            .opacity(isEnabled ? 1 : 0.45)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: opacity)
            .onHover { isHovering = $0 }
    }
}

struct OmniaMenuRowButtonStyle<S: Shape>: ButtonStyle {
    let shape: S

    func makeBody(configuration: Configuration) -> some View {
        OmniaMenuRowButtonBody(
            label: configuration.label,
            shape: shape,
            isPressed: configuration.isPressed
        )
    }
}

private struct OmniaInteractiveLiquidGlass<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    let shape: S

    func body(content: Content) -> some View {
        let transform = OmniaLiquidGlassPresentation.transform(
            isHovering: isEnabled && isHovering
        )
        let opacity = OmniaLiquidGlassPresentation.darkeningOpacity(
            isHovering: isEnabled && isHovering,
            isPressed: false
        )
        content
            .contentShape(shape)
            .background(shape.fill(.black.opacity(opacity)))
            .omniaGlass(.playerControls, base: .clear, interactive: true, in: shape)
            .scaleEffect(transform.scale)
            .offset(y: transform.verticalOffset)
            .animation(reduceMotion ? nil : .smooth(duration: 0.16), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

extension View {
    /// Static clear Liquid Glass for non-button surfaces such as the timeline.
    func omniaLiquidGlass<S: Shape>(
        in shape: S,
        role: OmniaLiquidGlassSurfaceRole = .sidebar
    ) -> some View {
        omniaGlass(.playerControls, base: .clear, in: shape)
    }

    func omniaCircularGlassButton(
        role: OmniaLiquidGlassSurfaceRole = .control,
        element: OmniaGlassElement = .actionButtons
    ) -> some View {
        buttonStyle(OmniaLiquidGlassButtonStyle(shape: Circle(), role: role, element: element))
            .contentShape(Circle())
    }

    func omniaCapsuleGlassButton(
        role: OmniaLiquidGlassSurfaceRole = .control,
        element: OmniaGlassElement = .actionButtons
    ) -> some View {
        buttonStyle(OmniaLiquidGlassButtonStyle(shape: Capsule(), role: role, element: element))
            .contentShape(Capsule())
    }

    func omniaRoundedGlassButton(
        cornerRadius: CGFloat = 14,
        role: OmniaLiquidGlassSurfaceRole = .control,
        element: OmniaGlassElement = .panels
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return buttonStyle(OmniaLiquidGlassButtonStyle(shape: shape, role: role, element: element))
            .contentShape(shape)
    }

    func omniaMenuRowButton(cornerRadius: CGFloat = 12) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return buttonStyle(OmniaMenuRowButtonStyle(shape: shape))
            .contentShape(shape)
    }

    func omniaCircularMenuRowButton() -> some View {
        buttonStyle(OmniaMenuRowButtonStyle(shape: Circle()))
            .contentShape(Circle())
    }

    func omniaInteractiveLiquidGlass<S: Shape>(in shape: S) -> some View {
        modifier(OmniaInteractiveLiquidGlass(shape: shape))
    }

    func omniaModalGlass<S: Shape>(in shape: S) -> some View {
        background(shape.fill(.black.opacity(OmniaLiquidGlassSurfaceRole.modal.baseDarkeningOpacity)))
            .omniaGlass(.panels, base: .clear, in: shape)
            .clipShape(shape)
    }
}

extension View {
    /// macOS sheets always contribute an opaque presentation surface. Keep
    /// glass modals in the same window so Liquid Glass can refract the actual
    /// artwork underneath; other platforms retain their native sheet.
    @ViewBuilder
    func omniaGlassModal<ModalContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> ModalContent
    ) -> some View {
        #if os(macOS)
        overlay {
            if isPresented.wrappedValue {
                ZStack {
                    Color.black.opacity(0.42)
                        .ignoresSafeArea()
                        .accessibilityHidden(true)
                        // Clicking outside the panel dismisses it, like a
                        // native popover.
                        .contentShape(Rectangle())
                        .onTapGesture { isPresented.wrappedValue = false }

                    content()
                        .padding(40)
                        .onExitCommand { isPresented.wrappedValue = false }
                }
                .transition(.opacity)
                .zIndex(100)
                .accessibilityAddTraits(.isModal)
            }
        }
        .animation(.easeOut(duration: 0.16), value: isPresented.wrappedValue)
        #else
        sheet(isPresented: isPresented) {
            content().modifier(OmniaPanelSheetBackground())
        }
        #endif
    }
    /// The streams page covers the whole window on macOS, like Nuvio's,
    /// instead of floating as a panel. Other platforms keep the sheet.
    @ViewBuilder
    func omniaStreamsPage<PageContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> PageContent
    ) -> some View {
        #if os(macOS)
        overlay {
            if isPresented.wrappedValue {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .onExitCommand { isPresented.wrappedValue = false }
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                    .zIndex(100)
                    .accessibilityAddTraits(.isModal)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isPresented.wrappedValue)
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            // iPadOS centres every sheet as a floating card, so this one is
            // drawn by hand to stay docked to the bottom edge, as on iPhone.
            fullScreenCover(isPresented: isPresented) {
                DockedStreamsSheet(onClose: { isPresented.wrappedValue = false }, content: content)
                    .presentationBackground(.clear)
            }
        } else {
            sheet(isPresented: isPresented) {
                content().modifier(OmniaPanelSheetBackground())
            }
        }
        #endif
    }
}

#if os(iOS)
/// The stream picker on iPad: an iPhone-style sheet with room for an iPad.
/// Drag it down or tap beside it to close.
private struct DockedStreamsSheet<Content: View>: View {
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var dragOffset: CGFloat = 0

    private static var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 34, topTrailingRadius: 34, style: .continuous)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.28)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    Capsule()
                        .fill(.secondary)
                        .frame(width: 44, height: 5)
                        .frame(maxWidth: .infinity, minHeight: 22)
                        .contentShape(Rectangle())
                        .gesture(dismissDrag)
                        .accessibilityHidden(true)
                    content()
                }
                .frame(
                    width: min(proxy.size.width - 48, 900),
                    height: proxy.size.height * 0.88 + proxy.safeAreaInsets.bottom
                )
                .omniaGlass(.panels, in: Self.shape)
                .clipShape(Self.shape)
                .offset(y: dragOffset)
                .accessibilityAddTraits(.isModal)
                .accessibilityAction(.escape, onClose)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var dismissDrag: some Gesture {
        DragGesture()
            .onChanged { dragOffset = max($0.translation.height, 0) }
            .onEnded { value in
                if value.predictedEndTranslation.height > 200 {
                    onClose()
                } else {
                    withAnimation(.snappy) { dragOffset = 0 }
                }
            }
    }
}
#endif
