//
//  ShelfScrollView.swift
//  Omnia
//

import SwiftUI

/// A gesture-first horizontal shelf. The edge controls are an affordance for
/// the row, not a replacement for native trackpad or touch scrolling.
struct ShelfScrollView<Item: Identifiable, Content: View>: View {
    let items: [Item]
    var spacing: CGFloat = MediaBrowseMetrics.shelfSpacing
    let itemSpan: CGFloat
    let accessibilityLabel: String
    @ViewBuilder let content: (Item) -> Content

    /// Enough for a 1.03 hover scale on a wide card plus its 2 pt stroke.
    private static var hoverRoom: CGFloat { 12 }

    @State private var leadingItemID: Item.ID?
    @State private var controlsVisible = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var concealTask: Task<Void, Never>?

    /// On an iPhone the arrows would cover the cards a swipe already
    /// scrolls.
    private var showsArrows: Bool {
        #if os(iOS)
        horizontalSizeClass != .compact
        #else
        true
        #endif
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .leading) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: spacing) {
                        ForEach(items) { item in
                            content(item)
                                .modifier(OmniaScrollEdgeEffect(axis: .horizontal))
                                .id(item.id)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.vertical, Self.hoverRoom)
                }
                // Room around the cards for their hover scale and glow,
                // taken back outside so the first card still lines up with
                // the row title. Without it the scroll view clipped the
                // first card's left edge and the top and bottom of every card.
                .contentMargins(.horizontal, Self.hoverRoom, for: .scrollContent)
                #if os(iOS)
                // Rows run on past the page margin, and behind the iPad sidebar.
                .scrollClipDisabled()
                #endif
                .padding(.horizontal, -Self.hoverRoom)
                .padding(.vertical, 2 - Self.hoverRoom)
                .scrollPosition(id: $leadingItemID, anchor: .leading)
                .onScrollPhaseChange { _, newPhase in
                    handleScrollPhase(newPhase)
                }
                // Scroll phases describe the active/inertial state, while the
                // geometry callback catches trackpad, mouse-wheel, keyboard,
                // and programmatic offset changes. Using both makes this an
                // affordance for every *real* horizontal movement without
                // installing a gesture that can compete with ScrollView.
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.x
                } action: { oldOffset, newOffset in
                    guard oldOffset != newOffset else { return }
                    showControls()
                }

                if controlsVisible, showsArrows, items.count > 1 {
                    // This button is its intrinsic 40 × 62 pt hit target. It
                    // is aligned to the edge rather than wrapped in a
                    // full-width overlay, so all remaining shelf content
                    // keeps the native scroll gesture.
                    if currentIndex > 0 {
                        Button {
                            move(by: -1, proxy: proxy)
                        } label: {
                            ShelfNavigationButton(label: "Previous \(accessibilityLabel)", symbol: "chevron.left")
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 8)
                        .transition(.opacity)
                    }
                }
            }
            .overlay(alignment: .trailing) {
                if controlsVisible, showsArrows, currentIndex < items.count - 1 {
                    Button {
                        move(by: 1, proxy: proxy)
                    } label: {
                        ShelfNavigationButton(label: "Next \(accessibilityLabel)")
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                    .transition(.opacity)
                }
            }
            #if os(macOS)
            // Match the desktop media-browser convention: a shelf's controls
            // become available as soon as the pointer enters the row. The
            // scroll-phase/geometry handlers above still cover trackpad and
            // mouse-wheel movement, and iOS/iPadOS remain gesture-first.
            .onHover { isHovering in
                if isHovering {
                    showControls()
                } else {
                    concealTask?.cancel()
                    // Pointer exit is intentional, unlike the end of a
                    // trackpad scroll. Hide immediately to keep the shelf
                    // visually quiet once it is no longer being inspected.
                    withAnimation(.smooth(duration: 0.12)) {
                        controlsVisible = false
                    }
                }
            }
            #endif
            .onDisappear { concealTask?.cancel() }
        }
    }

    private var currentIndex: Int {
        guard let leadingItemID,
              let index = items.firstIndex(where: { $0.id == leadingItemID })
        else { return 0 }
        return index
    }

    private func move(by delta: Int, proxy: ScrollViewProxy) {
        let index = min(max(currentIndex + delta, 0), items.count - 1)
        // Scroll through the position binding, not the proxy: a proxy
        // scroll never updated `leadingItemID`, so every later press
        // computed the same target from index 0 and the row moved once.
        withAnimation(.easeInOut(duration: 0.28)) {
            leadingItemID = items[index].id
        }
        showControls()
    }

    private func handleScrollPhase(_ phase: ScrollPhase) {
        if phase.isScrolling {
            showControls()
        } else {
            concealControlsAfterPause()
        }
    }

    private func showControls() {
        concealTask?.cancel()
        if !controlsVisible {
            withAnimation(.smooth(duration: 0.16)) { controlsVisible = true }
        }
    }

    private func concealControlsAfterPause() {
        concealTask?.cancel()
        concealTask = Task {
            try? await Task.sleep(for: .seconds(1.35))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.smooth(duration: 0.2)) { controlsVisible = false }
            }
        }
    }
}

/// A slight fade and scale as a card reaches the edge of its scroll view. Off
/// with Reduce Motion and Low Power Mode. It only moves when a card crosses
/// the edge, not on every scrolled frame.
struct OmniaScrollEdgeEffect: ViewModifier {
    let axis: Axis
    @Environment(\.displayPreferences) private var display
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion || LowPowerMonitor.shared.isActive(display.lowPowerMode) {
            content
        } else {
            content.scrollTransition(.animated(.smooth(duration: 0.2)), axis: axis) { view, phase in
                view
                    .opacity(phase.isIdentity ? 1 : 0.88)
                    .scaleEffect(phase.isIdentity ? 1 : 0.98)
            }
        }
    }
}
