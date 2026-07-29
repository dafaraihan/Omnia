//
//  SectionHeader.swift
//  Omnia
//

import SwiftUI

struct SectionHeader: View {
    let title: String
    private let trailing: AnyView?

    init(title: String) {
        self.title = title
        trailing = nil
    }

    init<Trailing: View>(title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
            if let trailing {
                trailing
            }
            Spacer(minLength: 0)
        }
    }
}

/// The interactive version of a section heading. Apple TV treats a shelf's
/// title and its trailing disclosure as one catalog-navigation affordance, so
/// Omnia does the same instead of making the tiny chevron the only target.
struct SectionHeaderLink<Destination: View>: View {
    let title: String
    private let destination: () -> Destination

    init(
        title: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.title = title
        self.destination = destination
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            NavigationLink {
                destination()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    RowNavigationButton(label: "Open \(title)")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(title)")

            Spacer(minLength: 0)
        }
    }
}
