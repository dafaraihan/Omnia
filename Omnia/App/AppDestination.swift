//
//  AppDestination.swift
//  Omnia
//

import Foundation
#if os(macOS)
import Observation
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
    case search
    case settings

    static func visibleDestinations(for platform: AppPlatform) -> [AppDestination] {
        let browsing: [AppDestination] = [.home, .library, .discover, .search]
        return browsing + [.settings]
    }

    static let macTopBarDestinations: [AppDestination] = [
        .home,
        .library,
        .discover,
        .settings,
        .search
    ]

    var symbolName: String {
        switch self {
        case .home: "house"
        case .library: "rectangle.stack"
        case .discover: "bag"
        case .search: "magnifyingglass"
        case .settings: "gearshape"
        }
    }

    var title: String {
        switch self {
        case .home: "Home"
        case .library: "Library"
        case .discover: "Discover"
        case .search: "Search"
        case .settings: "Settings"
        }
    }

    var allowsWindowHeroBackdrop: Bool {
        switch self {
        case .home, .library, .discover:
            true
        case .search, .settings:
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

    func selectFromTopBar(_ destination: AppDestination) {
        if destination == .search {
            isSearchPresented = true
        } else {
            select(destination)
        }
    }

    func activateTopBar() {
        guard selection == .search else { return }
        selection = previousContentSelection
        isSearchPresented = true
    }

    func setSearchPresented(_ isPresented: Bool) {
        isSearchPresented = isPresented
    }
}
#endif
