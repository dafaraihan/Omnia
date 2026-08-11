//
//  OmniaMaterial.swift
//  Omnia
//

import SwiftUI

/// Semantic material recipes shared across Omnia's native controls.
///
/// Materials intentionally live in code instead of `Assets.xcassets`: the
/// system resolves their vibrancy, blur, and contrast for the current Apple
/// platform and appearance. Fixed resources such as provider marks remain in
/// the asset catalog.
enum OmniaMaterial {
    /// A quiet material for floating carousel and shelf controls.
    static let floatingControl: Material = .thinMaterial

    /// The system-adaptive tab bar material used on iOS and iPadOS.
    static let tabBar: Material = .ultraThinMaterial

    /// A low-emphasis surface for grouped settings content on iOS and iPadOS.
    static let settingsSurface: Material = .thinMaterial
}
