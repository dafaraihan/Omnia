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
        // The Settings root is the profile's own tab, already named in the
        // tab bar, so the window shows no title there (Dafa, 2026-10-27).
        // Settings' sub-pages keep their titles.
        case .home, .mediaDetail, .settings:
            ""
        case .library, .discover, .liveTV, .search:
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
#endif
