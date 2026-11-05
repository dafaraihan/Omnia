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
            OmniaPageLink {
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

/// A pushed page that isn't a title (a shelf's page, a studio, a person, a
/// genre). The macOS stacks are bound to a path, and a destination-closure
/// link sits above that path, so a title opened from such a page was pushed
/// underneath it. Pushing these pages by value keeps everything in order.
/// Only ever built and read on the main actor; it is Sendable so the
/// stack's path can hold it, like `CollectionFolderRoute`.
nonisolated struct OmniaPageRoute: Hashable, @unchecked Sendable {
    private let id = UUID()
    let makePage: @MainActor () -> AnyView

    init(makePage: @escaping @MainActor () -> AnyView) {
        self.makePage = makePage
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// `NavigationLink { destination } label: { label }`, pushed by value.
struct OmniaPageLink<Destination: View, Label: View>: View {
    private let destination: () -> Destination
    private let label: Label

    init(@ViewBuilder destination: @escaping () -> Destination, @ViewBuilder label: () -> Label) {
        self.destination = destination
        self.label = label()
    }

    var body: some View {
        NavigationLink(value: OmniaPageRoute(makePage: { AnyView(destination()) })) {
            label
        }
    }
}

extension View {
    /// Registers `OmniaPageRoute` on a navigation stack's root. Each page
    /// draws the plain page background so a hero behind it in the window
    /// (Home's rotating hero, or the title page it was opened from) never
    /// shows through.
    func omniaPageDestinations() -> some View {
        navigationDestination(for: OmniaPageRoute.self) { route in
            route.makePage()
                .background(OmniaPageBackground().ignoresSafeArea())
                .omniaMediaDetailMenuDestination()
        }
        .omniaMediaDetailMenuDestination()
    }

    /// Each page has its own, so opening from a card there pushes on top of
    /// that page rather than going back to the stack's root first.
    @ViewBuilder
    func omniaMediaDetailMenuDestination() -> some View {
        modifier(MediaDetailMenuDestination())
    }
}
