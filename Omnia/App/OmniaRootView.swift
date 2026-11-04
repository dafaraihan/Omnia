//
//  OmniaRootView.swift
//  Omnia
//
//  Created by Dafa Raihan on 28/07/26.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct OmniaRootView: View {
    @Environment(OmniaStore.self) private var store
    @Environment(PlaybackSession.self) private var playback
    @Environment(SettingsPreferencesStore.self) private var settings
    @Environment(ProfileStore.self) private var profiles
    @Environment(CredentialVaultSync.self) private var credentialVault
    @Environment(OmniaAccount.self) private var account
    @AppStorage(OnboardingView.completedKey) private var onboardingCompleted = false
    @Environment(\.displayPreferences) private var effectiveDisplay
    @State private var liveTV = LiveTVStore.shared
    @State private var switchCenter = ProfileSwitchCenter.shared
    #if os(macOS)
    @State private var navigation = MacPrimaryNavigationState()
    @State private var hoveredSidebarDestination: AppDestination?
    @State private var windowHeroState = HeroBackdropState()
    /// Each tab's last scroll report for Nuvio's top bar.
    @State private var topBarScroll: [AppDestination: TopBarScrollReport] = [:]
    @State private var windowWidth: CGFloat = 0
    #else
    @State private var selection: AppDestination = .home
    @State private var profileTabImage: UIImage?
    /// Each tab's last scroll report for Nuvio's bar.
    @State private var topBarScroll: [AppDestination: TopBarScrollReport] = [:]
    @State private var windowWidth: CGFloat = 0
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        @Bindable var playback = playback
        #if os(macOS)
        let isFullWindowPlayback = playback.isPresentingPlayer && !playback.isPictureInPictureActive
        #endif

        Group {
            if account.localResetPending { Color.clear }
            else { gatedContent }
        }
        .disabled(credentialVault.isRestoring || credentialVault.identityBlocked || account.localResetPending || account.isSigningOut)
        .overlay {
            if account.localResetPending {
                VStack(spacing: 16) {
                    if account.isResettingLocalData {
                        OmniaLoadingRow("Preparing a fresh start…")
                    } else {
                        Text(account.errorMessage ?? "Local cleanup needs to finish.")
                        Button("Retry Cleanup") { Task { await account.finishLocalSignOut() } }
                    }
                }
                .padding(28)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            } else if account.isSigningOut {
                OmniaLoadingRow("Syncing and signing out…")
                    .padding(28)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            } else if credentialVault.isRestoring || credentialVault.identityBlocked {
                VStack(spacing: 16) {
                    if credentialVault.isRestoring {
                        OmniaLoadingRow("Restoring saved credentials…")
                    } else {
                        Label("Secure storage needs attention", systemImage: "lock.trianglebadge.exclamationmark")
                        Text("Unlock Keychain, then retry. Your saved credentials have been kept.")
                            .font(.callout)
                        Button("Retry Secure Storage") {
                            Task {
                                credentialVault.retrySecureStorage()
                                await account.restoreSession()
                                await credentialVault.identityChanged()
                            }
                        }
                    }
                }
                .padding(28)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .accessibilityElement(children: .contain)
            }
        }
        .preferredColorScheme(onboardingCompleted ? store.appearance.colorScheme : nil)
        #if os(iOS)
        .background {
            IOSSampleBufferLayerHost(controller: playback.pictureInPictureController)
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
        .background {
            PhonePlaybackOrientationHost(isPresented: playback.isPresentingPlayer && !playback.isPictureInPictureActive)
                .frame(width: 0, height: 0)
        }
        // A floating video leaves Omnia usable underneath.
        .fullScreenCover(isPresented: Binding(
            get: { playback.isPresentingPlayer && !playback.isPictureInPictureActive },
            set: { isPresented in
                if !isPresented, !playback.isPictureInPictureActive { playback.isPresentingPlayer = false }
            }
        )) {
            PhonePlaybackPresentation(content: AnyView(PlaybackExperienceView()))
                .ignoresSafeArea()
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
        // Leaves Live TV when it is hidden or its last source is removed.
        .onChange(of: liveTV.showsInNavigation) { _, shows in
            if !shows, navigation.selection == .liveTV { navigation.select(.home) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            playback.handleFullScreenEnter()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            playback.handleFullScreenExit()
        }
        #endif
    }

    /// Onboarding on first launch, then Who's Watching when there's more
    /// than one profile and the last one isn't remembered.
    @ViewBuilder
    private var gatedContent: some View {
        Group {
            if !onboardingCompleted {
                OnboardingView { onboardingCompleted = true }
                    .transition(.opacity)
            } else if profiles.needsSelection {
                ProfilePickerView(onCancel: pickerCancel)
                .transition(.opacity.combined(with: .scale(scale: 1.04)))
            } else {
                rootContent
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.35), value: onboardingCompleted)
        .animation(.smooth(duration: 0.6), value: profiles.needsSelection)
        // Nuvio's startup screen, and its profile switch.
        .overlay {
            if let transition = switchCenter.transition {
                ProfileTransitionOverlay(
                    transition: transition,
                    isExiting: switchCenter.isExiting,
                    anchor: switchCenter.profileAnchor
                ) {
                    switchCenter.finish(transition.id)
                }
                .id(transition.id)
                .zIndex(2)
            }
        }
        .onAppear {
            switchCenter.beginLaunch()
            // Profiles were removed outside the app: start again with one.
            if onboardingCompleted, profiles.profiles.isEmpty {
                profiles.create(name: "Profile 1", avatarID: AvatarCatalog.random().id, colorHex: ViewerProfile.colors[0])
            }
        }
    }

    /// Back from Who's Watching, when Switch Profile opened it.
    private var pickerCancel: (() -> Void)? {
        guard switchCenter.isPickerOpen, profiles.activeProfile != nil else { return nil }
        let center = switchCenter
        let profiles = profiles
        return { center.cancelPicker(using: profiles) }
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
        // Allocate a real layout region outside TabView. UIKit-backed tab
        // content can consume an outer safe-area inset without moving its
        // scroll content, which left bottom rows behind the custom bar.
        VStack(spacing: 0) {
            styledTabs
                .tint(accentColor)
                .overlay(alignment: .top) {
                    if usesNuvioBar && !isCompactWidth {
                        nuvioBar.padding(.top, 2)
                    }
                }
            if usesNuvioBar && isCompactWidth {
                nuvioBar
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity)
                    .background { OmniaPageBackground() }
            }
        }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                windowWidth = width
            }
            .environment(\.reportTopBarScroll) { destination, report in
                if topBarScroll[destination] != report {
                    topBarScroll[destination] = report
                }
            }
            .onChange(of: liveTV.showsInNavigation) { _, shows in
                if !shows, selection == .liveTV { selection = .home }
            }
        #endif
    }

    #if os(iOS)
    /// iPhone, and iPad in a narrow multitasking window.
    private var isCompactWidth: Bool {
        UIDevice.current.userInterfaceIdiom == .phone || horizontalSizeClass == .compact
    }

    /// Settings › Layout. A narrow window always uses a tab bar, so the
    /// Sidebar choice only applies to a regular-width iPad window.
    private var usesSidebar: Bool {
        !isCompactWidth && settings.preferences.navigationStyle == .sidebar
    }

    /// iPhone always uses system tabs, regardless of a saved/shared custom
    /// style. iPad retains its navigation choices, including compact windows.
    /// iOS draws its own tab bar in its own glass, so turning the bar's glass
    /// off on iPhone swaps in Omnia's, which can have a solid fill.
    private var usesNuvioBar: Bool {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return !effectiveDisplay.liquidGlass.applies(to: .navigationBar)
        }
        return !usesSidebar && settings.preferences.display.topBarStyle.isNuvio
    }

    @ViewBuilder
    private var styledTabs: some View {
        if usesSidebar {
            tabs
                .tabViewStyle(.sidebarAdaptable)
                // Upright, the sidebar would open over the hero's buttons, so
                // it starts closed there; its button still opens it.
                .defaultAdaptableTabBarPlacement(opensWithSidebar ? .sidebar : .tabBar)
                .toolbarBackground(OmniaMaterial.tabBar, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .tabBarMinimizeBehavior(.onScrollDown)
        } else {
            tabs
                .tabViewStyle(.tabBarOnly)
                .toolbar(usesNuvioBar ? .hidden : .visible, for: .tabBar)
                .toolbarBackground(OmniaMaterial.tabBar, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .tabBarMinimizeBehavior(usesNuvioBar ? .never : .onScrollDown)
        }
    }

    /// Wide enough for the sidebar to sit beside the page: an iPad on its side.
    private var opensWithSidebar: Bool {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return (scene?.effectiveGeometry.coordinateSpace.bounds.width ?? 0) > 1100
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: AppDestination.home.symbolName, value: .home) {
                tabStack { HomeView() }
            }
            Tab("Library", systemImage: AppDestination.library.symbolName, value: .library) {
                tabStack { LibraryView() }
            }

            Tab("Discover", systemImage: AppDestination.discover.symbolName, value: .discover) {
                tabStack { DiscoverView() }
            }

            if liveTV.showsInNavigation {
                Tab("Live TV", systemImage: AppDestination.liveTV.symbolName, value: .liveTV) {
                    tabStack { LiveTVView() }
                }
            }

            Tab(value: AppDestination.settings) {
                // A regular-width iPad shows the groups beside the open page.
                if isCompactWidth {
                    tabStack { SettingsView() }
                } else {
                    SettingsSplitView()
                        .toolbar(usesNuvioBar ? .hidden : .automatic, for: .tabBar)
                }
            } label: {
                Label {
                    Text(AppDestination.settings.title(for: profiles.activeProfile))
                } icon: {
                    if let profileTabImage {
                        Image(uiImage: profileTabImage).renderingMode(.original)
                    } else {
                        Image(systemName: AppDestination.settings.symbolName)
                    }
                }
            }
        }
        .task(id: ProfileTabImageKey(profile: profiles.activeProfile, isSelected: selection == .settings, accent: accentColor)) {
            await updateProfileTabImage()
        }
    }

    private struct ProfileTabImageKey: Equatable {
        let profile: ViewerProfile?
        let isSelected: Bool
        let accent: Color
    }

    /// Native tabs extract an Image from their label, so rasterize the same
    /// avatar used by the custom bar after its cached artwork is available.
    @MainActor
    private func updateProfileTabImage() async {
        guard let profile = profiles.activeProfile else {
            profileTabImage = nil
            return
        }
        func render() {
            // The same accent glow as the iPad and Mac bar, while its tab is open.
            let isSelected = selection == .settings
            let renderer = ImageRenderer(
                content: ProfileAvatarView(profile: profile, size: 26, isSelected: isSelected)
                    .shadow(color: isSelected ? accentColor.opacity(0.9) : .clear, radius: 4)
                    .padding(5)
            )
            renderer.scale = 3
            // The native tab bar reads UIImage's rendering mode; the SwiftUI
            // Image modifier alone leaves UIKit free to template the avatar.
            profileTabImage = renderer.uiImage?.withRenderingMode(.alwaysOriginal)
        }
        render()
        if let avatar = profile.avatarID.flatMap(AvatarCatalog.avatar(id:)) {
            _ = await RemoteArtworkCache.shared.image(
                for: avatar.url,
                target: RemoteArtworkTarget(width: 96, height: 96, fills: true)
            )
            guard !Task.isCancelled, profiles.activeProfile == profile else { return }
            render()
        }
    }

    /// A tab's stack. With Nuvio's bar the system tab bar is hidden on
    /// every page, as the floating bar stays in place.
    private func tabStack<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        NavigationStack {
            content()
                .omniaPageDestinations()
                .toolbar(usesNuvioBar ? .hidden : .automatic, for: .tabBar)
        }
    }

    private var nuvioBar: some View {
        NuvioTopBar(
            destinations: AppDestination.macTopBarDestinations(showsLiveTV: liveTV.showsInNavigation),
            selection: selection,
            style: settings.preferences.display.topBarStyle,
            showsGlow: settings.preferences.display.topBarGlow,
            scroll: topBarScroll[selection] ?? TopBarScrollReport(),
            // On iPad it shares the navigation bar's row, so it leaves room
            // for the Back button and the page's own buttons.
            maximumWidth: max(windowWidth - (isCompactWidth ? 0 : 280), 0),
            select: { selection = $0 }
        )
    }
    #endif

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

    private var macTopBarNavigation: some View {
        nuvioTopBarNavigation
    }

    /// Nuvio's bar sits where the system tab bar does, in the centre of the
    /// window toolbar, so every page shows it in the same place.
    private var nuvioTopBarNavigation: some View {
        macNavigationStack(for: navigation.selection)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    NuvioTopBar(
                        destinations: AppDestination.macTopBarDestinations(showsLiveTV: liveTV.showsInNavigation),
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

    @ViewBuilder
    private func macNavigationStack(for destination: AppDestination) -> some View {
        if destination == .settings {
            SettingsSplitView()
                .id(destination)
                .environment(\.isActiveDestination, destination == navigation.selection)
                .tint(accentColor)
        } else {
            macPagesStack(for: destination)
        }
    }

    private func macPagesStack(for destination: AppDestination) -> some View {
        NavigationStack(path: macPath(for: destination)) {
            Group {
                switch destination {
                case .home:
                    HomeView()
                case .library:
                    LibraryView()
                case .discover:
                    DiscoverView()
                case .liveTV:
                    LiveTVView()
                case .search:
                    SearchView()
                case .settings:
                    SettingsView()
                }
            }
            .omniaPageDestinations()
        }
        .id(destination)
        .environment(\.isActiveDestination, destination == navigation.selection)
        // Sidebar row colors are local to the leading column. Destination
        // controls and native context-menu selection retain Apple system blue.
        .tint(accentColor)
    }

    private var macSidebarDestinations: [AppDestination] {
        [.settings, .home, .library, .discover] + (liveTV.showsInNavigation ? [.liveTV] : [])
    }

    private func macSidebarLabel(for destination: AppDestination) -> some View {
        Label {
            Text(destination.title(for: profiles.activeProfile))
                .foregroundStyle(.primary)
        } icon: {
            if destination == .settings, let profile = profiles.activeProfile {
                ProfileAvatarView(profile: profile, size: 28, isSelected: navigation.selection == .settings)
                    .modifier(ProfileAnchorReporting())
            } else {
                Image(systemName: destination.symbolName)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(macSidebarSymbolColor(for: destination))
            }
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
