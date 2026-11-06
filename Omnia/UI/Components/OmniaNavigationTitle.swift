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
    case liveTV
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
        // Top-level pages name themselves in the window's toolbar on Mac.
        case .home, .mediaDetail:
            ""
        case .library, .discover, .liveTV, .search, .settings:
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
        if screen == .mediaDetail {
            // Title pages always draw their own Back button. The system one
            // goes missing when the page before hid it, such as a collection
            // folder.
            self.modifier(MacPushedToolbarTitleModifier(title: nil))
        } else if let screen {
            self.navigationTitle(MacToolbarPresentation.navigationTitle(title, for: screen))
                .toolbarTitleDisplayMode(.inline)
        } else {
            self.modifier(MacPushedToolbarTitleModifier(title: title))
        }
        #else
        if screen == .home {
            // Home's hero runs under the tab bar, as on the Mac; the title
            // stays for VoiceOver and Back menus.
            self.navigationTitle(title)
                .toolbarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
        } else if screen == .mediaDetail {
            // The artwork runs under a clear bar that keeps only the
            // system Back button, so Back and the edge swipe both work. A
            // hidden bar dropped both, and its area still took the taps
            // meant for a Back button drawn there.
            self.navigationTitle(title)
                .toolbarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                // Light status bar and Back over the dark artwork.
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
                }
        } else {
            self.navigationTitle(title)
        }
        #endif
    }
}

#if os(macOS)
private struct MacPushedToolbarTitleModifier: ViewModifier {
    /// Nil shows the Back button alone.
    let title: String?
    @Environment(\.dismiss) private var dismiss
    /// False for a stack's first page, such as a Settings page beside its
    /// categories, which has nowhere to go back to and draws its own title.
    @Environment(\.isPresented) private var isPresented

    func body(content: Content) -> some View {
        content
            .navigationTitle("")
            .toolbarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden()
            .toolbar {
                if isPresented {
                ToolbarItem(placement: .navigation) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .accessibilityLabel("Back")
                    .help("Back")
                }

                if let title {
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
    }
}
#endif

/// A toolbar's symbols in the label color, not the accent.
struct OmniaToolbarSymbol<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .tint(.primary)
    }
}
