//
//  RowNavigationButton.swift
//  Omnia
//

import SwiftUI

/// The disclosure that sits beside a section title. It intentionally stays a
/// bare chevron: it opens the full catalog and is not a scroll control.
struct RowNavigationButton: View {
    let label: String
    var symbol = "chevron.right"

    var body: some View {
        Image(systemName: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary.opacity(0.78))
            .frame(width: 18, height: 24)
            .contentShape(.rect)
            .accessibilityLabel(label)
    }
}

/// A temporary, edge-mounted control for a horizontally scrolling shelf.
/// Unlike `RowNavigationButton`, this is deliberately a vertical capsule and
/// belongs over the shelf content, never beside its title.
struct ShelfNavigationButton: View {
    let label: String
    var symbol = "chevron.right"

    var body: some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary.opacity(0.78))
            .frame(width: 40, height: 62)
            .glassEffect(.regular.interactive(), in: Capsule())
            .contentShape(Capsule())
            .accessibilityLabel(label)
    }
}
