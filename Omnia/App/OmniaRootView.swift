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
    /// Each tab's last scroll report for Nuvio's top bar.
    @State private var topBarScroll: [AppDestination: TopBarScrollReport] = [:]
    @State private var windowWidth: CGFloat = 0
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
        .background(
            WindowChrome(
                isPlaybackPresented: isFullWindowPlayback,
                isExclusiveFullScreen: playback.isFullScreenActive
            )
        )
        .onChange(of: usesFloatingSearch) { _, floating in
            navigation.applySearchStyle(floating: floating)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            playback.handleFullScreenEnter()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            playback.handleFullScreenExit()
        }
        #endif
    }

    /// Settings › Appearance › Accent Color.
    private var accentColor: Color {
        settings.preferences.display.accentColor
    }

    @ViewBuilder
    private var rootContent: some View {
        #if os(macOS)
        ZStack {
            // The floating search panel sits over the page, so the page's
            // hero stays behind it.
            if navigation.selection.allowsWindowHeroBackdrop {
                WindowHeroBackdrop(state: windowHeroState)
            } else {
                OmniaPageBackground()
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
        .environment(\.activateWindowHeroBackdrop) { source, owner in
            windowHeroState.activate(source, owner: owner)
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
        .tint(accentColor)
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
                .tint(.gray)
                .accentColor(.gray)
        } detail: {
            macNavigationStack(for: navigation.selection)
                .tint(accentColor)
        }
        // The detail stack is rebuilt per destination, so a destination left
        // behind starts again at its root, as it did before paths were stored.
        .onChange(of: navigation.selection) { previous, _ in
            navigation.resetPath(for: previous)
        }
        // Keep the platform sidebar so macOS owns its Liquid Glass surface,
        // resizing, keyboard behavior, and the single native toolbar toggle.
        .navigationSplitViewStyle(.balanced)
        .modifier(floatingSearchPanel)
    }

    /// Whether Search opens as a floating panel instead of a page.
    private var usesFloatingSearch: Bool {
        settings.preferences.searchStyle.usesFloatingSearch(with: settings.preferences.navigationStyle)
    }

    private var floatingSearchPanel: FloatingSearchPanel {
        FloatingSearchPanel(
            isPresented: macSearchPresentation,
            accentColor: accentColor,
            openDetail: { navigation.openDetailFromSearch($0) }
        )
    }

    /// Settings › Layout › Top Bar Style. Standard is the system
    /// tab bar; the other styles are Nuvio's floating bar.
    @ViewBuilder
    private var macTopBarNavigation: some View {
        if settings.preferences.display.topBarStyle.isNuvio {
            nuvioTopBarNavigation
        } else {
            nativeTopBarNavigation
        }
    }

    /// Nuvio's bar sits where the system tab bar does, in the centre of the
    /// window toolbar, so every page shows it in the same place.
    private var nuvioTopBarNavigation: some View {
        macNavigationStack(for: navigation.selection)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    NuvioTopBar(
                        destinations: AppDestination.macTopBarDestinations,
                        selection: navigation.selection,
                        style: settings.preferences.display.topBarStyle,
                        showsGlow: settings.preferences.display.topBarGlow,
                        scroll: topBarScroll[navigation.selection] ?? TopBarScrollReport(),
                        // Leaves room for the title and the page's own
                        // toolbar buttons on either side.
                        maximumWidth: max(windowWidth - 420, 0),
                        select: { navigation.select($0, floatingSearch: usesFloatingSearch) }
                    )
                }
                .sharedBackgroundVisibility(.hidden)
            }
        // Only the width is tracked, so resizing doesn't rebuild every page.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            windowWidth = width
        }
        .environment(\.reportTopBarScroll) { destination, report in
            if topBarScroll[destination] != report {
                topBarScroll[destination] = report
            }
        }
        // Like the sidebar, each tab starts again at its root when left.
        .onChange(of: navigation.selection) { previous, _ in
            navigation.resetPath(for: previous)
            topBarScroll[previous] = nil
        }
        .tint(accentColor)
        .modifier(floatingSearchPanel)
    }

    private var nativeTopBarNavigation: some View {
        TabView(selection: macTopBarSelection) {
            ForEach(AppDestination.macTopBarDestinations, id: \.self) { destination in
                if destination == .search && usesFloatingSearch {
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
        .tint(accentColor)
        .modifier(floatingSearchPanel)
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
        NavigationStack(path: macPath(for: destination)) {
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
        .environment(\.isActiveDestination, destination == navigation.selection)
        // Sidebar row colors are local to the leading column. Destination
        // controls and native context-menu selection retain Apple system blue.
        .tint(accentColor)
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
            accentColor
        case .secondary:
            .secondary
        }
    }

    private var macSelection: Binding<AppDestination> {
        Binding(
            get: { navigation.selection },
            set: { navigation.select($0, floatingSearch: usesFloatingSearch) }
        )
    }

    private var macTopBarSelection: Binding<AppDestination> {
        Binding(
            get: { navigation.selection },
            set: { navigation.select($0, floatingSearch: usesFloatingSearch) }
        )
    }

    private func macPath(for destination: AppDestination) -> Binding<NavigationPath> {
        Binding(
            get: { navigation.paths[destination] ?? NavigationPath() },
            set: { navigation.paths[destination] = $0 }
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
/// The floating search panel, used from either navigation style.
private struct FloatingSearchPanel: ViewModifier {
    let isPresented: Binding<Bool>
    let accentColor: Color
    let openDetail: (MediaItem) -> Void

    func body(content: Content) -> some View {
        content.popover(
            isPresented: isPresented,
            attachmentAnchor: .point(.top),
            arrowEdge: .top
        ) {
            NavigationStack {
                SearchView(presentation: .popover)
            }
            .environment(\.openMediaDetail, OpenMediaDetailAction { item in
                openDetail(item)
            })
            .tint(accentColor)
        }
    }
}

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
