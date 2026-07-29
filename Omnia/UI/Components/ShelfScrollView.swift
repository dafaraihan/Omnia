//
//  ShelfScrollView.swift
//  Omnia
//

import SwiftUI

/// A gesture-first horizontal shelf. The edge controls are an affordance for
/// the row, not a replacement for native trackpad or touch scrolling.
struct ShelfScrollView<Item: Identifiable, Content: View>: View {
    let items: [Item]
    var spacing: CGFloat = 16
    let itemSpan: CGFloat
    let accessibilityLabel: String
    @ViewBuilder let content: (Item) -> Content

    @State private var leadingItemID: Item.ID?
    @State private var controlsVisible = false
    @State private var concealTask: Task<Void, Never>?

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .leading) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: spacing) {
                        ForEach(items) { item in
                            content(item)
                                .id(item.id)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.vertical, 2)
                }
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

                if controlsVisible, items.count > 1 {
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
                if controlsVisible, currentIndex < items.count - 1 {
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
                    withAnimation(.easeOut(duration: 0.12)) {
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
        withAnimation(.easeInOut(duration: 0.28)) {
            proxy.scrollTo(items[index].id, anchor: .leading)
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
            withAnimation(.easeInOut(duration: 0.16)) { controlsVisible = true }
        }
    }

    private func concealControlsAfterPause() {
        concealTask?.cancel()
        concealTask = Task {
            try? await Task.sleep(for: .seconds(1.35))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = false }
            }
        }
    }
}
