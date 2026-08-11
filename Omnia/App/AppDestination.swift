//
//  AppDestination.swift
//  Omnia
//

import Foundation

enum AppPlatform: Equatable, Sendable {
    case mobile
    case mac
}

enum AppDestination: Hashable {
    case home
    case anime
    case library
    case discover
    case search
    case settings

    static func visibleDestinations(for platform: AppPlatform) -> [AppDestination] {
        let browsing: [AppDestination] = [.home, .anime, .library, .discover, .search]
        return browsing + [.settings]
    }
}
