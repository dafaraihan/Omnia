//
//  OmniaRootView.swift
//  Omnia
//
//  Created by Dafa Raihan on 28/07/26.
//

import SwiftUI

struct OmniaRootView: View {
    @Environment(OmniaStore.self) private var store
    @State private var selection: AppDestination = .home

    var body: some View {
        navigationTabs
        .preferredColorScheme(store.appearance.colorScheme)
        #if os(macOS)
        // macOS window chrome does not change between Home and a pushed title
        // detail. It supplies the sidebar toggle and native Back command,
        // while each page owns its own content and artwork below it.
        .toolbar(.automatic, for: .windowToolbar)
        .background(WindowChrome())
        #endif
    }

    private var navigationTabs: some View {
        TabView(selection: $selection) {
            #if os(iOS)
            Tab("Home", systemImage: "house.fill", value: .home) {
                NavigationStack { HomeView() }
            }
            Tab("Search", systemImage: "magnifyingglass", value: .search) {
                NavigationStack { SearchView() }
            }
            #else
            Tab("Search", systemImage: "magnifyingglass", value: .search) {
                NavigationStack { SearchView() }
            }
            Tab("Home", systemImage: "house.fill", value: .home) {
                NavigationStack { HomeView() }
            }
            #endif

            Tab("Library", systemImage: "rectangle.stack.fill", value: .library) {
                NavigationStack { LibraryView() }
            }

            Tab("Discover", systemImage: "bag", value: .discover) {
                NavigationStack { DiscoverView() }
            }

            Tab("Settings", systemImage: "gearshape", value: .settings) {
                NavigationStack { SettingsView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(store.accentColor)
        #if os(iOS)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .tabBarMinimizeBehavior(.onScrollDown)
        #endif
    }
}

#Preview {
    OmniaRootView()
        .environment(OmniaStore.preview)
        .environment(LiveMetadataStore.preview)
}
