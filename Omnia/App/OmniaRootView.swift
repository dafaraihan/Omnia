//
//  OmniaRootView.swift
//  Omnia
//
//  Created by Dafa Raihan on 28/07/26.
//

import SwiftUI

struct OmniaRootView: View {
    @Environment(OmniaStore.self) private var store
    @Environment(PlaybackSession.self) private var playback
    @State private var selection: AppDestination = .home

    var body: some View {
        @Bindable var playback = playback

        navigationTabs
        .preferredColorScheme(store.appearance.colorScheme)
        #if os(iOS)
        .fullScreenCover(isPresented: $playback.isPresentingPlayer) {
            PlaybackExperienceView()
        }
        #elseif os(macOS)
        // macOS does not provide SwiftUI's fullScreenCover. Rendering the
        // player over the root window gives the same full-window playback
        // transition without nesting a sheet inside the source chooser.
        .overlay {
            if playback.isPresentingPlayer {
                PlaybackExperienceView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        #endif
        #if os(macOS)
        .focusedSceneValue(\.appDestination, $selection)
        // macOS window chrome does not change between Home and a pushed title
        // detail. It supplies the sidebar toggle and native Back command,
        // while each page owns its own content and artwork below it.
        .toolbar(.automatic, for: .windowToolbar)
        // Playback owns the whole window. Hiding the browsing toolbar here
        // prevents the sidebar toggle and navigation Back button from leaking
        // into AVKit's native player presentation.
        .toolbarVisibility(playback.isPresentingPlayer ? .hidden : .automatic, for: .windowToolbar)
        .background(WindowChrome())
        #endif
    }

    private var navigationTabs: some View {
        TabView(selection: $selection) {
            #if os(iOS)
            Tab("Home", systemImage: "house.fill", value: .home) {
                NavigationStack { HomeView() }
            }
            Tab("Anime", systemImage: "sparkles.tv", value: .anime) {
                NavigationStack { AnimeDiscoveryView() }
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
            Tab("Anime", systemImage: "sparkles.tv", value: .anime) {
                NavigationStack { AnimeDiscoveryView() }
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
        .toolbarBackground(OmniaMaterial.tabBar, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .tabBarMinimizeBehavior(.onScrollDown)
        #endif
    }
}

#if os(macOS)
private struct AppDestinationFocusedValueKey: FocusedValueKey {
    typealias Value = Binding<AppDestination>
}

extension FocusedValues {
    var appDestination: Binding<AppDestination>? {
        get { self[AppDestinationFocusedValueKey.self] }
        set { self[AppDestinationFocusedValueKey.self] = newValue }
    }
}
#endif

#Preview {
    OmniaRootView()
        .environment(OmniaStore.preview)
        .environment(LiveMetadataStore.preview)
        .environment(OmniaAccount())
        .environment(PlaybackSession())
        .environment(SettingsPreferencesStore())
}
