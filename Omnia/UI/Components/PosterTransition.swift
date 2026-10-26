//
//  PosterTransition.swift
//  Omnia
//

import SwiftUI

/// Nuvio's Poster Transition (Settings › Layout › Detail Page): the poster
/// that was clicked expands from its place in the window and blurs away as
/// the title page appears. Posters record where they are; the title page
/// takes that frame once, when it opens.
@Observable
final class PosterTransitionCenter {
    struct Anchor {
        let item: MediaItem
        let frame: CGRect
        let prefersBackdrop: Bool
        let cornerRadius: CGFloat
        let date: Date
    }

    static let shared = PosterTransitionCenter()

    @ObservationIgnored private var pending: Anchor?

    private init() {}

    func prepare(_ anchor: Anchor) {
        pending = anchor
    }

    func clear(itemID: String) {
        if pending?.item.id == itemID { pending = nil }
    }

    /// The anchor for a title page that just opened, if its poster was
    /// pointed at or tapped in the last few seconds.
    func consume(itemID: String, now: Date = .now) -> Anchor? {
        defer { pending = nil }
        guard let pending, pending.item.id == itemID, now.timeIntervalSince(pending.date) < 4 else { return nil }
        return pending
    }
}

extension View {
    /// Marks a poster as the starting point of the Poster Transition.
    func posterTransitionSource(
        _ item: MediaItem,
        prefersBackdrop: Bool = false,
        cornerRadius: CGFloat
    ) -> some View {
        modifier(PosterTransitionSourceModifier(item: item, prefersBackdrop: prefersBackdrop, cornerRadius: cornerRadius))
    }
}

private struct PosterTransitionSourceModifier: ViewModifier {
    let item: MediaItem
    let prefersBackdrop: Bool
    let cornerRadius: CGFloat
    @Environment(\.displayPreferences) private var display
    /// Not `@State`: the frame changes on every scrolled frame, and storing
    /// it as state redrew every poster on screen each time. It is only read
    /// when a poster is pointed at or tapped.
    @State private var frameBox = FrameBox()

    private final class FrameBox {
        var frame: CGRect = .zero
    }

    private var frame: CGRect { frameBox.frame }

    func body(content: Content) -> some View {
        if display.posterTransition {
            content
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frameBox.frame = $0 }
                #if os(macOS)
                // A click on the Mac always follows the pointer entering the
                // poster, so the hovered poster is the one that opens.
                .onHover { isHovering in
                    if isHovering {
                        prepare()
                    } else {
                        PosterTransitionCenter.shared.clear(itemID: item.id)
                    }
                }
                #else
                .simultaneousGesture(TapGesture().onEnded { prepare() })
                #endif
        } else {
            content
        }
    }

    private func prepare() {
        guard frame.width > 0, frame.height > 0 else { return }
        PosterTransitionCenter.shared.prepare(
            PosterTransitionCenter.Anchor(
                item: item,
                frame: frame,
                prefersBackdrop: prefersBackdrop,
                cornerRadius: cornerRadius,
                date: .now
            )
        )
    }
}

/// Draws the expanding, blurring poster over a title page that just opened.
struct PosterTransitionOverlay: View {
    let anchor: PosterTransitionCenter.Anchor
    let onFinish: () -> Void
    @State private var isExpanded = false

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let start = anchor.frame.offsetBy(dx: -origin.x, dy: -origin.y)
            let end = CGRect(origin: .zero, size: proxy.size)
            let rect = isExpanded ? end : start

            ArtworkView(item: anchor.item, prefersBackdrop: anchor.prefersBackdrop)
                .frame(width: rect.width, height: rect.height)
                .clipShape(.rect(cornerRadius: isExpanded ? 0 : anchor.cornerRadius, style: .continuous))
                .blur(radius: isExpanded ? 36 : 0)
                .opacity(isExpanded ? 0 : 1)
                .position(x: rect.midX, y: rect.midY)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.55)) {
                isExpanded = true
            } completion: {
                onFinish()
            }
        }
    }
}
