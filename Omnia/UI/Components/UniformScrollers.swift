//
//  UniformScrollers.swift
//  Omnia
//

#if os(macOS)
import AppKit
import ObjectiveC

/// One scroll bar look on every page. Native Forms, SwiftUI scroll views and
/// pages that run beneath the top bar each got AppKit's scrollers configured
/// a little differently, so their size, knob and length didn't match. Every
/// scroll view now uses the system's scroller style at regular size with the
/// default knob, and a vertical scroll bar always starts below the window's
/// top bar.
///
/// Scroll views that set their own scroll bar margins, like the player's
/// side panels, are left exactly as they are.
@MainActor
enum UniformScrollers {
    private static var isInstalled = false

    static func install() {
        guard !isInstalled else { return }
        isInstalled = true
        guard let original = class_getInstanceMethod(NSScrollView.self, #selector(NSScrollView.tile)),
              let uniform = class_getInstanceMethod(NSScrollView.self, #selector(NSScrollView.omnia_uniformTile))
        else { return }
        method_exchangeImplementations(original, uniform)
    }
}

extension NSScrollView {
    /// Runs in place of `tile()`; after the exchange, calling itself runs
    /// AppKit's original layout.
    @objc fileprivate func omnia_uniformTile() {
        omnia_uniformTile()
        applyUniformScrollers()
    }

    private func applyUniformScrollers() {
        // Custom side or bottom margins mean the view styles its own scroll
        // bar (the player's panels use contentMargins for this).
        guard scrollerInsets.left == 0, scrollerInsets.right == 0, scrollerInsets.bottom == 0 else { return }

        let style = NSScroller.preferredScrollerStyle
        if scrollerStyle != style { scrollerStyle = style }
        if scrollerKnobStyle != .default { scrollerKnobStyle = .default }
        for scroller in [verticalScroller, horizontalScroller].compactMap({ $0 }) where scroller.controlSize != .regular {
            scroller.controlSize = .regular
        }

        guard hasVerticalScroller else { return }
        let top = topBarOverlap
        if abs(scrollerInsets.top - top) > 0.5 {
            var insets = scrollerInsets
            insets.top = top
            scrollerInsets = insets
        }
    }

    /// How far the window's top bar covers this scroll view beyond what its
    /// content insets already account for. Zero for views below the bar.
    private var topBarOverlap: CGFloat {
        guard let window else { return 0 }
        let barBottom = window.contentLayoutRect.maxY
        let viewTop = convert(bounds, to: nil).maxY
        let covered = viewTop - barBottom
        guard covered > 0 else { return 0 }
        return max(0, covered - contentInsets.top)
    }
}
#endif
