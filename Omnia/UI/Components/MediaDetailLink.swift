//
//  MediaDetailLink.swift
//  Omnia
//

import SwiftUI

/// Lets a container decide where a title's detail page opens. The macOS
/// search popover sets this so a title opens as a real page in the main
/// window instead of being pushed inside the popover's own stack.
struct OpenMediaDetailAction {
    let handler: (MediaItem) -> Void

    func callAsFunction(_ item: MediaItem) {
        handler(item)
    }
}

private struct OpenMediaDetailKey: EnvironmentKey {
    static let defaultValue: OpenMediaDetailAction? = nil
}

extension EnvironmentValues {
    var openMediaDetail: OpenMediaDetailAction? {
        get { self[OpenMediaDetailKey.self] }
        set { self[OpenMediaDetailKey.self] = newValue }
    }
}

/// A `NavigationLink(value:)` for a title that defers to `openMediaDetail`
/// when one is set.
struct MediaDetailLink<Label: View>: View {
    let item: MediaItem
    @ViewBuilder let label: () -> Label
    @Environment(\.openMediaDetail) private var openMediaDetail

    var body: some View {
        if let openMediaDetail {
            Button {
                openMediaDetail(item)
            } label: {
                label()
            }
        } else {
            NavigationLink(value: item) {
                label()
            }
        }
    }
}
