import SwiftUI

#if os(macOS)
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

private struct OmniaLiquidGlassButtonBody<Label: View, S: Shape>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    let label: Label
    let shape: S
    let role: OmniaLiquidGlassSurfaceRole
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
            .glassEffect(.clear.interactive(), in: shape)
            .scaleEffect(transform.scale)
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

    func makeBody(configuration: Configuration) -> some View {
        OmniaLiquidGlassButtonBody(
            label: configuration.label,
            shape: shape,
            role: role,
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
            .glassEffect(.clear.interactive(), in: shape)
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
        glassEffect(.clear, in: shape)
    }

    func omniaCircularGlassButton(
        role: OmniaLiquidGlassSurfaceRole = .control
    ) -> some View {
        buttonStyle(OmniaLiquidGlassButtonStyle(shape: Circle(), role: role))
            .contentShape(Circle())
    }

    func omniaCapsuleGlassButton(
        role: OmniaLiquidGlassSurfaceRole = .control
    ) -> some View {
        buttonStyle(OmniaLiquidGlassButtonStyle(shape: Capsule(), role: role))
            .contentShape(Capsule())
    }

    func omniaRoundedGlassButton(
        cornerRadius: CGFloat = 14,
        role: OmniaLiquidGlassSurfaceRole = .control
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return buttonStyle(OmniaLiquidGlassButtonStyle(shape: shape, role: role))
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
            .glassEffect(.clear, in: shape)
            .clipShape(shape)
    }
}
#endif

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
        sheet(isPresented: isPresented, content: content)
        #endif
    }
}
