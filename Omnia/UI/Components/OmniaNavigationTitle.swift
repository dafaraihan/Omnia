//
//  OmniaNavigationTitle.swift
//  Omnia
//

import SwiftUI

enum MacToolbarScreen {
    case home
    case mediaDetail
    case library
    case discover
    case search
    case settings
}

enum MacToolbarElement: Equatable {
    case title
    case fixedSpacer
    case back
    case primaryAction
}

enum MacToolbarPresentation {
    static let discoverFilterButtonCount = 1
    static let usesVisibleNativeWindowTitle = true
    static let pushedPageOrder: [MacToolbarElement] = [.back, .fixedSpacer, .title]
    static let addonsPageOrder: [MacToolbarElement] = [.back, .fixedSpacer, .title, .primaryAction]

    static func navigationTitle(_ proposedTitle: String, for screen: MacToolbarScreen) -> String {
        switch screen {
        case .home, .mediaDetail:
            ""
        case .library, .discover, .search, .settings:
            proposedTitle
        }
    }
}

extension View {
    @ViewBuilder
    func omniaNavigationTitle(
        _ title: String,
        screen: MacToolbarScreen? = nil
    ) -> some View {
        #if os(macOS)
        if let screen {
            self.navigationTitle(MacToolbarPresentation.navigationTitle(title, for: screen))
                .toolbarTitleDisplayMode(.inline)
        } else {
            self.modifier(MacPushedToolbarTitleModifier(title: title))
        }
        #else
        self.navigationTitle(title)
        #endif
    }
}

#if os(macOS)
private struct MacPushedToolbarTitleModifier: ViewModifier {
    let title: String
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationTitle("")
            .toolbarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .accessibilityLabel("Back")
                    .help("Back")
                }

                ToolbarSpacer(.fixed, placement: .navigation)

                ToolbarItem(placement: .navigation) {
                    Text(title)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                }
                .sharedBackgroundVisibility(.hidden)
            }
    }
}
#endif
