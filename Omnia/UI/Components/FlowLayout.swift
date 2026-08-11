import SwiftUI

/// A compact wrapping layout for immutable metadata labels. It keeps each
/// label intact while avoiding a horizontal scroller on narrow layouts.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? .greatestFiniteMagnitude
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let proposedX = x == 0 ? size.width : x + spacing + size.width
            if x > 0, proposedX > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            if x > 0 { x += spacing }
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }

        return .init(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let proposedX = x == bounds.minX ? x + size.width : x + spacing + size.width
            if x > bounds.minX, proposedX > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            if x > bounds.minX { x += spacing }
            subview.place(at: .init(x: x, y: y), proposal: .unspecified)
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }
    }
}
