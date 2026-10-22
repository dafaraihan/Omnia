//
//  AppDestination.swift
//  Omnia
//

import Foundation
#if os(macOS)
import Observation
import SwiftUI
#endif

enum AppPlatform: Equatable, Sendable {
    case mobile
    case mac
}

enum MacSidebarSelectionTint: Equatable, Sendable {
    case neutralGray
}

enum MacSidebarRowTreatment: Equatable, Sendable {
    case clear
    case neutralGray
}

enum MacSidebarSymbolTreatment: Equatable, Sendable {
    case appleBlue
    case secondary
}

enum MacSidebarPresentation {
    static let selectionTint: MacSidebarSelectionTint = .neutralGray

    static func backgroundOutset(
        for destination: AppDestination,
        selection: AppDestination,
        isHovered: Bool
    ) -> CGSize {
        rowTreatment(for: destination, selection: selection, isHovered: isHovered) == .neutralGray
            ? CGSize(width: 7, height: 4)
            : .zero
    }

    static func rowTreatment(
        for destination: AppDestination,
        selection: AppDestination,
        isHovered: Bool
    ) -> MacSidebarRowTreatment {
        destination == selection || isHovered ? .neutralGray : .clear
    }

    static func symbolTreatment(
        for destination: AppDestination,
        selection: AppDestination
    ) -> MacSidebarSymbolTreatment {
        destination == selection ? .appleBlue : .secondary
    }
}

enum AppDestination: Hashable {
    case home
    case library
    case discover
    case liveTV
    case search
    case settings

    static func visibleDestinations(for platform: AppPlatform, showsLiveTV: Bool = false) -> [AppDestination] {
        let browsing: [AppDestination] = [.home, .library, .discover] + (showsLiveTV ? [.liveTV] : []) + [.search]
        return browsing + [.settings]
    }

    /// Live TV sits between Discover and Settings once a source is set up.
    static func macTopBarDestinations(showsLiveTV: Bool) -> [AppDestination] {
        [.home, .library, .discover] + (showsLiveTV ? [.liveTV] : []) + [.search, .settings]
    }

    /// Settings is the watching profile's page, named after it.
    @MainActor
    func title(for profile: ViewerProfile?) -> String {
        self == .settings ? (profile?.name ?? "Profile") : title
    }

    var symbolName: String {
        switch self {
        case .home: "house"
        case .library: "rectangle.stack"
        case .discover: "bag"
        case .liveTV: "play.tv"
        case .search: "magnifyingglass"
        case .settings: "gearshape"
        }
    }

    var title: String {
        switch self {
        case .home: "Home"
        case .library: "Library"
        case .discover: "Discover"
        case .liveTV: "Live TV"
        case .search: "Search"
        case .settings: "Settings"
        }
    }

    var allowsWindowHeroBackdrop: Bool {
        switch self {
        case .home, .library, .discover:
            true
        case .liveTV, .search, .settings:
            false
        }
    }

    /// Whether this destination's stack declares a `MediaItem` destination.
    var hostsMediaDetail: Bool {
        switch self {
        case .home, .library, .discover, .search:
            true
        case .liveTV, .settings:
            false
        }
    }
}

#if os(macOS)
@MainActor
@Observable
final class MacPrimaryNavigationState {
    private(set) var selection: AppDestination
    private(set) var isSearchPresented = false
    /// Each destination's navigation stack, so titles opened from the search
    /// popover can be pushed onto the main window's current page.
    var paths: [AppDestination: NavigationPath] = [:]
    var stackIdentity: AppDestination { selection }
    private var previousContentSelection: AppDestination

    init(selection: AppDestination = .home) {
        self.selection = selection
        previousContentSelection = selection == .search ? .home : selection
    }

    func select(_ destination: AppDestination) {
        isSearchPresented = false
        guard destination != selection else { return }
        selection = destination
        if destination != .search {
            previousContentSelection = destination
        }
    }

    /// Selecting Search either opens the floating search panel over the
    /// current page or goes to the Search page, depending on the setting.
    func select(_ destination: AppDestination, floatingSearch: Bool) {
        if destination == .search, floatingSearch {
            isSearchPresented = true
        } else {
            select(destination)
        }
    }

    /// Applies a change of search style: leaving the Search page for the
    /// floating panel, or closing the panel when Search becomes a page.
    func applySearchStyle(floating: Bool) {
        if floating {
            guard selection == .search else { return }
            selection = previousContentSelection
            isSearchPresented = true
        } else {
            isSearchPresented = false
        }
    }

    func setSearchPresented(_ isPresented: Bool) {
        isSearchPresented = isPresented
    }

    func resetPath(for destination: AppDestination) {
        paths[destination] = nil
    }

    /// Closes the search popover and opens the title as a normal detail page
    /// on the current browsing destination. Settings has no title pages, so
    /// it falls back to Home.
    func openDetailFromSearch(_ item: MediaItem) {
        isSearchPresented = false
        if selection == .search {
            selection = previousContentSelection
        }
        if !selection.hostsMediaDetail {
            select(.home)
        }
        paths[selection, default: NavigationPath()].append(item)
    }
}
#endif
