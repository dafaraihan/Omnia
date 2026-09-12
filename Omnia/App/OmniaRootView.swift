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
    @Environment(SettingsPreferencesStore.self) private var settings
    #if os(macOS)
    @State private var navigation = MacPrimaryNavigationState()
    @State private var hoveredSidebarDestination: AppDestination?
    @State private var windowHeroState = HeroBackdropState()
    #else
    @State private var selection: AppDestination = .home
    #endif

    var body: some View {
        @Bindable var playback = playback
        #if os(macOS)
        let isFullWindowPlayback = playback.isPresentingPlayer && !playback.isPictureInPictureActive
        #endif

        rootContent
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
            if playback.isPresentingPlayer && !playback.isPictureInPictureActive {
                PlaybackExperienceView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        #endif
        #if os(macOS)
        .focusedSceneValue(\.appDestination, macSelection)
        // macOS window chrome supplies the native sidebar toggle and Back
        // command. The window backdrop tracks each hero's scrolling frame so
        // one artwork layer can extend beneath the translucent sidebar.
        .toolbar(.automatic, for: .windowToolbar)
        // Playback owns the whole window. Hiding the browsing toolbar here
        // prevents the sidebar toggle and navigation Back button from leaking
        // into AVKit's native player presentation.
        .toolbarVisibility(
            WindowChromePresentation.hidesToolbarDuringPlayback && isFullWindowPlayback
                ? .hidden
                : .automatic,
            for: .windowToolbar
        )
        .toolbarBackground(
            WindowChromePresentation.hidesToolbarBackgroundDuringBrowsing ? .hidden : .automatic,
            for: .windowToolbar
        )
        .background(WindowChrome(isPlaybackPresented: isFullWindowPlayback))
        .onChange(of: settings.preferences.navigationStyle) { _, navigationStyle in
            switch navigationStyle {
            case .sidebar:
                navigation.setSearchPresented(false)
            case .topBar:
                navigation.activateTopBar()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            playback.handleFullScreenEnter()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            playback.handleFullScreenExit()
        }
        #endif
    }

    @ViewBuilder
    private var rootContent: some View {
        #if os(macOS)
        ZStack {
            if navigation.selection.allowsWindowHeroBackdrop && !navigation.isSearchPresented {
                WindowHeroBackdrop(state: windowHeroState)
            } else {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
            }
            navigationTabs
        }
        .environment(\.reportWindowHeroBackdrop) { source, owner, item, frame in
            if let item {
                windowHeroState.report(item, frame: frame, from: source, owner: owner)
            } else {
                windowHeroState.clear(source, owner: owner)
            }
        }
        .onChange(of: navigation.selection) { _, _ in
            windowHeroState = HeroBackdropState()
        }
        #else
        navigationTabs
        #endif
    }

    @ViewBuilder
    private var navigationTabs: some View {
        #if os(macOS)
        switch settings.preferences.navigationStyle {
        case .sidebar:
            macSidebarNavigation
        case .topBar:
            macTopBarNavigation
        }
        #else
        TabView(selection: $selection) {
            Tab("Home", systemImage: AppDestination.home.symbolName, value: .home) {
                NavigationStack { HomeView() }
            }
            Tab("Search", systemImage: AppDestination.search.symbolName, value: .search) {
                NavigationStack { SearchView() }
            }
            Tab("Library", systemImage: AppDestination.library.symbolName, value: .library) {
                NavigationStack { LibraryView() }
            }

            Tab("Discover", systemImage: AppDestination.discover.symbolName, value: .discover) {
                NavigationStack { DiscoverView() }
            }

            Tab("Settings", systemImage: AppDestination.settings.symbolName, value: .settings) {
                NavigationStack { SettingsView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(store.accentColor)
        .toolbarBackground(OmniaMaterial.tabBar, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .tabBarMinimizeBehavior(.onScrollDown)
        #endif
    }

    #if os(macOS)
    private var macSidebarNavigation: some View {
        NavigationSplitView {
            macSidebar
                .navigationSplitViewColumnWidth(min: 170, ideal: 220, max: 300)
        } detail: {
            macNavigationStack(for: navigation.selection)
        }
        // Keep the platform sidebar so macOS owns its Liquid Glass surface,
        // resizing, keyboard behavior, and the single native toolbar toggle.
        .navigationSplitViewStyle(.balanced)
        .tint(.gray)
        .accentColor(.gray)
    }

    private var macTopBarNavigation: some View {
        TabView(selection: macTopBarSelection) {
            ForEach(AppDestination.macTopBarDestinations, id: \.self) { destination in
                if destination == .search {
                    Tab(
                        destination.title,
                        systemImage: destination.symbolName,
                        value: destination
                    ) {
                        Color.clear
                    }
                } else {
                    Tab(
                        destination.title,
                        systemImage: destination.symbolName,
                        value: destination
                    ) {
                        macNavigationStack(for: destination)
                    }
                }
            }
        }
        .tabViewStyle(.tabBarOnly)
        .tint(store.accentColor)
        .popover(
            isPresented: macSearchPresentation,
            attachmentAnchor: .point(.top),
            arrowEdge: .top
        ) {
            NavigationStack {
                SearchView(presentation: .popover)
            }
            .tint(store.accentColor)
        }
    }

    private var macSidebar: some View {
        List(selection: macSelection) {
            ForEach(macSidebarDestinations, id: \.self) { destination in
                let backgroundOutset = MacSidebarPresentation.backgroundOutset(
                    for: destination,
                    selection: navigation.selection,
                    isHovered: hoveredSidebarDestination == destination
                )
                macSidebarLabel(for: destination)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(
                                    navigation.selection == destination
                                        ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
                                        : hoveredSidebarDestination == destination
                                            ? Color.gray.opacity(0.20)
                                            : Color.clear
                                )
                                .padding(.horizontal, -backgroundOutset.width)
                                .padding(.vertical, -backgroundOutset.height)
                            MacSidebarSelectionConfigurator()
                                .allowsHitTesting(false)
                        }
                    }
                    .contentShape(Rectangle())
                    .tag(destination)
                    .onHover { isHovered in
                        if isHovered {
                            hoveredSidebarDestination = destination
                        } else if hoveredSidebarDestination == destination {
                            hoveredSidebarDestination = nil
                        }
                    }
                    .accessibilityAddTraits(destination == navigation.selection ? .isSelected : [])
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private func macNavigationStack(for destination: AppDestination) -> some View {
        NavigationStack {
            switch destination {
            case .home:
                HomeView()
            case .library:
                LibraryView()
            case .discover:
                DiscoverView()
            case .search:
                SearchView()
            case .settings:
                SettingsView()
            }
        }
        .id(destination)
        // Sidebar row colors are local to the leading column. Destination
        // controls and native context-menu selection retain Apple system blue.
        .tint(store.accentColor)
    }

    private var macSidebarDestinations: [AppDestination] {
        [.search, .home, .library, .discover, .settings]
    }

    private func macSidebarLabel(for destination: AppDestination) -> some View {
        Label {
            Text(destination.title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: destination.symbolName)
                .symbolRenderingMode(.palette)
                .foregroundStyle(macSidebarSymbolColor(for: destination))
        }
    }

    private func macSidebarSymbolColor(for destination: AppDestination) -> Color {
        switch MacSidebarPresentation.symbolTreatment(for: destination, selection: navigation.selection) {
        case .appleBlue:
            .blue
        case .secondary:
            .secondary
        }
    }

    private var macSelection: Binding<AppDestination> {
        Binding(
            get: { navigation.selection },
            set: { navigation.select($0) }
        )
    }

    private var macTopBarSelection: Binding<AppDestination> {
        Binding(
            get: { navigation.selection },
            set: { navigation.selectFromTopBar($0) }
        )
    }

    private var macSearchPresentation: Binding<Bool> {
        Binding(
            get: { navigation.isSearchPresented },
            set: { navigation.setSearchPresented($0) }
        )
    }

    #endif
}

#if os(macOS)
private struct MacSidebarSelectionConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> MacSidebarSelectionConfigurationView {
        MacSidebarSelectionConfigurationView()
    }

    func updateNSView(_ view: MacSidebarSelectionConfigurationView, context: Context) {
        view.configureEnclosingList()
    }
}

private final class MacSidebarSelectionConfigurationView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureEnclosingList()
    }

    func configureEnclosingList() {
        DispatchQueue.main.async { [weak self] in
            var ancestor = self?.superview
            while let view = ancestor {
                if let tableView = view as? NSTableView {
                    tableView.selectionHighlightStyle = .none
                    tableView.focusRingType = .none
                    return
                }
                ancestor = view.superview
            }
        }
    }
}

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
