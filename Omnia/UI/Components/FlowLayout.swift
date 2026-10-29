import SwiftUI

/// A compact wrapping layout for immutable metadata labels. It keeps each
/// label intact while avoiding a horizontal scroller on narrow layouts.
struct FlowLayout: Layout {
    var spacing: CGFloat
    var alignment: HorizontalAlignment = .leading

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
        var row: [(LayoutSubview, CGSize)] = []
        var rowWidth: CGFloat = 0
        var y = bounds.minY

        func placeRow() {
            let offset = alignment == .center ? max(0, (bounds.width - rowWidth) / 2) : 0
            var x = bounds.minX + offset
            for (subview, size) in row {
                subview.place(at: .init(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
        }

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let nextWidth = row.isEmpty ? size.width : rowWidth + spacing + size.width
            if !row.isEmpty, nextWidth > bounds.width {
                placeRow()
                y += (row.map { $0.1.height }.max() ?? 0) + spacing
                row.removeAll(keepingCapacity: true)
                rowWidth = 0
            }
            rowWidth += (row.isEmpty ? 0 : spacing) + size.width
            row.append((subview, size))
        }
        placeRow()
    }
}
