import SwiftUI

/// Every labelled loading state: the spinner and its text on one line, centred
/// as a group. A bare `ProgressView("…")` stacks them on iOS and sits at the
/// leading edge of a card or form row, which looked off-centre.
struct OmniaLoadingRow: View {
    private let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
    }
}
