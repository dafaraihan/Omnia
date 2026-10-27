//
//  PlatformStyles.swift
//  Omnia
//

import SwiftUI

/// Styles whose macOS form has no iOS counterpart, so shared views can use
/// one name on both.
extension View {
    /// macOS's link-styled button; a plain borderless button on iOS.
    @ViewBuilder
    func omniaLinkButtonStyle() -> some View {
        #if os(macOS)
        buttonStyle(.link)
        #else
        buttonStyle(.borderless)
        #endif
    }
}

extension Color {
    /// The window's background: macOS's window colour, iOS's system
    /// background.
    static var omniaWindowBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
}

/// The device's name in copy, as in "stays on this Mac".
enum OmniaDevice {
    @MainActor
    static var name: String {
        #if os(macOS)
        "Mac"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }
}
