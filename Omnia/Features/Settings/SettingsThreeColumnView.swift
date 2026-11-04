import SwiftUI

/// What the preview column shows. The page on screen sets the default, and
/// the section being edited replaces it.
enum SettingsPreviewKind: Equatable {
    case home, cards, player, glass
    case topBar, heroGradient, collections, continueWatching, theme, playerControls, subtitles

    var title: String {
        switch self {
        case .home: "Home"
        case .cards: "Poster Cards"
        case .player: "Player"
        case .glass: "Liquid Glass"
        case .topBar: "Top Bar"
        case .heroGradient: "Hero Gradient"
        case .collections: "Collections"
        case .continueWatching: "Continue Watching"
        case .theme: "Theme & Accent"
        case .playerControls: "Controls and Menus"
        case .subtitles: "Subtitles"
        }
    }
}

extension SettingsRoute {
    var previewKind: SettingsPreviewKind? {
        switch self {
        case .appearance: .home
        case .posterCards: .cards
        case .subtitle: .player
        case .liquidGlass: .glass
        case .collections: .collections
        case .continueWatching: .continueWatching
        default: nil
        }
    }
}

extension ContainerValues {
    @Entry var settingsPreviewSection: SettingsPreviewKind? = nil
}

extension View {
    /// Which preview this Settings section drives, beside its page.
    func settingsPreviewSection(_ kind: SettingsPreviewKind) -> some View {
        containerValue(\.settingsPreviewSection, kind)
    }
}

/// Shared between the page in the middle and the preview on the right.
@MainActor
@Observable
final class SettingsPreviewModel {
    /// The page's own preview. Nil hides the column.
    private(set) var kind: SettingsPreviewKind?
    /// The section being edited, which the others dim around.
    private(set) var activeSection: SettingsPreviewKind?
    /// What's shown: a section with nothing visual keeps the last preview.
    private(set) var shown: SettingsPreviewKind?
    var showsPlayerMenu = true

    func openPage(_ kind: SettingsPreviewKind?) {
        self.kind = kind
        shown = kind
        activeSection = nil
    }

    func activate(_ section: SettingsPreviewKind?) {
        guard kind != nil else { return }
        activeSection = section
        if let section { shown = section }
    }

    /// A slider's value while it's being dragged, before it's saved.
    private var drafts: [WritableKeyPath<DisplayPreferences, Double>: Double] = [:]

    func setDraft(_ keyPath: WritableKeyPath<DisplayPreferences, Double>, _ value: Double?) {
        drafts[keyPath] = value
    }

    func applyingDrafts(to display: DisplayPreferences) -> DisplayPreferences {
        var display = display
        for (keyPath, value) in drafts { display[keyPath: keyPath] = value }
        return display
    }
}

private struct SettingsPreviewModelKey: EnvironmentKey {
    static let defaultValue: SettingsPreviewModel? = nil
}

private struct SettingsPreviewInColumnKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var settingsPreviewModel: SettingsPreviewModel? {
        get { self[SettingsPreviewModelKey.self] }
        set { self[SettingsPreviewModelKey.self] = newValue }
    }

    /// True when the preview column shows this page's preview, so the page
    /// doesn't draw its own as well.
    var settingsPreviewInColumn: Bool {
        get { self[SettingsPreviewInColumnKey.self] }
        set { self[SettingsPreviewInColumnKey.self] = newValue }
    }
}

/// Home's featured title, for the Layout preview to show something real.
@MainActor
enum HomeFeaturedMemory {
    static var item: MediaItem?
}

/// Settings on iPad and Mac: categories beside the page. Narrow windows go
/// back to the plain drill-down.
struct SettingsThreeColumnView: View {
    private static let categoriesWidth: CGFloat = 220
    private static let middleMinimum: CGFloat = 460

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            if width < Self.categoriesWidth + Self.middleMinimum {
                NavigationStack {
                    SettingsView()
                        .omniaPageDestinations()
                }
            } else {
                SettingsColumns(categoriesWidth: Self.categoriesWidth)
            }
        }
    }
}

private struct SettingsColumns: View {
    let categoriesWidth: CGFloat

    @State private var selection: SettingsRoute = .appearance
    @State private var searchText = ""
    @State private var model = SettingsPreviewModel()

    var body: some View {
        SettingsLockGate {
            HStack(spacing: 0) {
                categories
                    .frame(width: categoriesWidth)
                Divider().ignoresSafeArea()
                NavigationStack {
                    SettingsColumnRoot(route: selection)
                        .omniaPageDestinations()
                }
                .id(selection)
                .frame(maxWidth: .infinity)
                .environment(\.settingsPreviewModel, model)
                .environment(\.settingsPreviewInColumn, true)
            }
            .animation(.smooth(duration: 0.25), value: model.kind)
            .animation(.smooth(duration: 0.2), value: model.activeSection)
        }
    }

    private var categories: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Button { selection = .account } label: {
                    SettingsProfileCard(avatarSize: 36)
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                TextField("Search Settings", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.vertical, 8)

                ForEach(SettingsRoute.filteredRootGroups(query: searchText)) { group in
                    ForEach(group.routes, id: \.self) { route in
                        Button { selection = route } label: {
                            Label(route.title, systemImage: route.systemImage)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(rowBackground(route), in: .rect(cornerRadius: 9, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection == route ? .isSelected : [])
                    }
                }
            }
            .padding(12)
        }
        .settingsClearsTopBar()
    }

    private func rowBackground(_ route: SettingsRoute) -> Color {
        selection == route ? display.accentColor.opacity(0.22) : .clear
    }

    @Environment(\.displayPreferences) private var display
}

/// The first page in the middle: its big title, then the page.
private struct SettingsColumnRoot: View {
    let route: SettingsRoute

    var body: some View {
        SettingsDestinationView(route: route)
            .safeAreaInset(edge: .top, spacing: 0) {
                Text(route.title)
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background {
                        #if os(iOS)
                        Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                        #else
                        OmniaPageBackground().ignoresSafeArea()
                        #endif
                    }
            }
    }
}

/// Stays at the top of a page while its options scroll underneath.
struct SettingsPinnedPreviewPanel: View {
    let kind: SettingsPreviewKind
    @Bindable var model: SettingsPreviewModel
    @Environment(SettingsPreferencesStore.self) private var settings

    var body: some View {
        let display = model.applyingDrafts(to: settings.preferences.display)
        VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Live Preview")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    if let section = model.activeSection {
                        Text(section.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(display.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(display.accentColor.opacity(0.2), in: Capsule())
                            .transition(.opacity)
                    }
                    Spacer(minLength: 8)
                    if let caption = caption(display: display) {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if kind == .player || kind == .playerControls {
                        Toggle("Show a Menu", isOn: $model.showsPlayerMenu)
                            .font(.caption)
                            .fixedSize()
                            .tint(display.accentColor)
                    }
                }
                preview(display: display)
                    .environment(\.displayPreferences, display)
                    .tint(display.accentColor)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Preview of \(kind.title)")
                    .frame(height: 230)
                    .frame(maxWidth: .infinity)
                    .id(kind)
                    .transition(.opacity)
        }
        .animation(.smooth(duration: 0.2), value: kind)
        .frame(maxWidth: 560)
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background {
            #if os(iOS)
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            #else
            OmniaPageBackground().ignoresSafeArea()
            #endif
        }
    }

    private func caption(display: DisplayPreferences) -> String? {
        func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
        switch kind {
        case .topBar:
            return "\(percent(display.topBarSize.size)) · \(display.topBarStyle.title) · Glow \(display.topBarGlow ? "on" : "off")"
        case .heroGradient:
            return display.heroBlend.isEnabled
                ? "Strength \(percent(display.heroBlend.strength)) · Height \(percent(display.heroBlend.height))"
                : "Gradient Overlay is off"
        case .cards: return "One card at rest and one hovered."
        case .theme: return display.amoledBlack ? "AMOLED black background" : "Your page background"
        case .glass: return "Parts turned off draw with a solid fill."
        default: return nil
        }
    }

    @ViewBuilder
    private func preview(display: DisplayPreferences) -> some View {
        switch kind {
        case .home:
            SettingsScaledPreview(size: CGSize(width: 620, height: 600)) {
                SettingsMiniHome(display: display)
            }
        case .heroGradient:
            SettingsScaledPreview(size: CGSize(width: 620, height: 400)) {
                SettingsMiniHome(display: display, showsTopBar: false)
                    .offset(y: -110)
            }
        case .topBar:
            SettingsScaledPreview(size: CGSize(width: 620, height: 300)) {
                SettingsTopBarPreview(display: display)
            }
        case .cards:
            SettingsCardsPreview(display: display)
        case .collections:
            CollectionCardPreview(folders: Array(collections.collections.flatMap(\.folders).prefix(4)))
                .defaultScrollAnchor(.center, for: .alignment)
        case .continueWatching:
            ContinueWatchingLivePreview(style: display.continueWatchingStyle)
        case .theme:
            SettingsThemePreview(display: display)
        case .player, .playerControls, .subtitles:
            SettingsScaledPreview(size: CGSize(width: 900, height: 520)) {
                MacSubtitlePlaybackPreview(
                    style: settings.preferences.playbackSubtitleStyle,
                    height: 520,
                    showsMenu: model.showsPlayerMenu && kind != .subtitles,
                    controlsOpacity: kind == .subtitles ? 0.2 : 1,
                    subtitleOpacity: kind == .playerControls ? 0.25 : 1
                )
            }
        case .glass:
            LegacyLiquidGlassPreview()
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
        }
    }

    @Environment(CollectionsStore.self) private var collections
}

/// The real top bar at its current settings, and as it looks after scrolling.
private struct SettingsTopBarPreview: View {
    let display: DisplayPreferences

    var body: some View {
        ZStack {
            LinearGradient(colors: [.indigo, .teal, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 34) {
                bar(style: display.topBarStyle == .compact ? .expanded : display.topBarStyle)
                    .shadow(color: display.topBarGlow ? display.accentColor.opacity(0.6) : .clear, radius: 18)
                VStack(spacing: 8) {
                    bar(style: .compact)
                    Text("Compact, after scrolling down")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private func bar(style: TopBarStyle) -> some View {
        NuvioTopBar(
            destinations: [.home, .library, .discover, .settings],
            selection: .home,
            style: style,
            showsGlow: false,
            scroll: TopBarScrollReport(),
            maximumWidth: 600,
            select: { _ in }
        )
    }
}

/// One card at rest and one hovered, at the current size, corners and depth.
private struct SettingsCardsPreview: View {
    let display: DisplayPreferences

    private var size: CGSize {
        display.landscapePosters
            ? CGSize(width: display.landscapePosterCardWidth, height: display.landscapePosterCardWidth)
            : CGSize(width: display.posterCardWidth, height: display.posterCardHeight)
    }

    var body: some View {
        // Two cards and their captions, whichever size they are.
        SettingsScaledPreview(size: CGSize(
            width: max(size.width * 2 + 72, 300),
            height: max(size.height + 72, 200)
        )) {
            HStack(spacing: 8) {
                card("At rest", hovered: false)
                card("Hovered", hovered: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.primary.opacity(0.06))
        }
    }

    private func card(_ title: String, hovered: Bool) -> some View {
        VStack(spacing: 2) {
            LegacyPosterCardPreview(display: display)
                .environment(\.settingsForcesCardHover, hovered)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// A tab, a switch and a button in the accent, on the chosen background.
private struct SettingsThemePreview: View {
    let display: DisplayPreferences

    var body: some View {
        ZStack {
            OmniaPageBackground()
            VStack(spacing: 16) {
                Text("Home")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 7)
                    .background(display.accentColor.opacity(0.25), in: Capsule())
                HStack {
                    Text("A switch")
                    Spacer()
                    Toggle("A switch", isOn: .constant(true))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .padding(12)
                .background(.primary.opacity(0.08), in: .rect(cornerRadius: 10, style: .continuous))
                Button("Play") {}
                    .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .aspectRatio(1.1, contentMode: .fit)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.primary.opacity(0.15))
        }
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
    }
}

/// Draws a real view at a window's size, shrunk to fit the column.
private struct SettingsScaledPreview<Content: View>: View {
    let size: CGSize
    @ViewBuilder let content: () -> Content

    var body: some View {
        Color.clear
            .aspectRatio(size.width / size.height, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    content()
                        .frame(width: size.width, height: size.height)
                        .scaleEffect(proxy.size.width / size.width, anchor: .topLeading)
                }
            }
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
    }
}

/// Home in miniature, from the same pieces Home uses, so it answers to the
/// same settings: background, gradient, AMOLED, accent, glass and top bar.
private struct SettingsMiniHome: View {
    let display: DisplayPreferences
    var showsTopBar = true
    @Environment(HomeLayoutStore.self) private var homeLayout
    @Environment(OmniaStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme

    private var dynamic: Bool { homeLayout.preferences.dynamicBackground }

    private var cards: [MediaItem] {
        Array(store.localMediaSnapshots.map(\.item).filter { $0.backdropURL != nil }.prefix(3))
    }

    private var item: MediaItem? {
        HomeFeaturedMemory.item ?? cards.first
    }

    var body: some View {
        ZStack(alignment: .top) {
            HomeArtworkBackground(item: item, isEnabled: dynamic)
            VStack(alignment: .leading, spacing: 18) {
                hero
                Text("Continue Watching")
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 24)
                HStack(spacing: 12) {
                    ForEach(0 ..< 3, id: \.self) { index in
                        Group {
                            if cards.indices.contains(index) {
                                ArtworkView(item: cards[index], prefersBackdrop: true)
                            } else {
                                MediaItem.placeholderArtworkColor
                            }
                        }
                        .frame(width: 180, height: 102)
                        .clipShape(.rect(cornerRadius: display.posterCornerRadius, style: .continuous))
                    }
                }
                .padding(.horizontal, 24)
                Spacer(minLength: 0)
            }
            if showsTopBar {
            NuvioTopBar(
                destinations: [.home, .library, .discover, .settings],
                selection: .home,
                style: display.topBarStyle,
                showsGlow: false,
                scroll: TopBarScrollReport(),
                maximumWidth: 580,
                select: { _ in }
            )
            .padding(.top, 14)
            }
        }
        .environment(\.colorScheme, dynamic ? .dark : colorScheme)
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            if let item {
                FeaturedBackdrop(item: item, artworkAlignment: .topTrailing)
                if display.heroBlend.isEnabled, dynamic {
                    HeroBottomBlend(item: item)
                }
            } else {
                MediaItem.placeholderArtworkColor
            }
            VStack(alignment: .leading, spacing: 14) {
                if let logo = item?.logoURL {
                    TitleLogoView(url: logo, title: item?.title ?? "", maximumWidth: 260, maximumHeight: 80)
                } else {
                    Text(item?.title ?? "Omnia")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                }
                Button {} label: {
                    HeroPrimaryActionLabel(title: "View Details")
                }
                .omniaCapsuleGlassButton()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(height: 370)
        .clipped()
    }
}

private struct SettingsClearsTopBar: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        // On iPad the floating bar sits over the top of the window.
        content.safeAreaPadding(.top, 44)
        #else
        content
        #endif
    }
}

extension View {
    fileprivate func settingsClearsTopBar() -> some View {
        modifier(SettingsClearsTopBar())
    }
}


/// How a Settings section behaves beside the preview: hovering or tapping it
/// makes it the one being edited, and the others dim around it.
struct SettingsSectionFocus: ViewModifier {
    let kind: SettingsPreviewKind?
    @Environment(\.settingsPreviewModel) private var model
    @Environment(\.settingsPreviewInColumn) private var inColumn

    private var isDimmed: Bool {
        guard inColumn, let active = model?.activeSection else { return false }
        return active != kind
    }

    func body(content: Content) -> some View {
        if inColumn {
            content
                .opacity(isDimmed ? 0.45 : 1)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering { model?.activate(kind) }
                }
                .simultaneousGesture(TapGesture().onEnded { model?.activate(kind) })
                .environment(\.settingsSectionKind, kind)
        } else {
            content
        }
    }
}

private struct SettingsSectionKindKey: EnvironmentKey {
    static let defaultValue: SettingsPreviewKind? = nil
}

private struct SettingsForcesCardHoverKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var settingsSectionKind: SettingsPreviewKind? {
        get { self[SettingsSectionKindKey.self] }
        set { self[SettingsSectionKindKey.self] = newValue }
    }

    /// Draws a card as if the pointer were on it, for a preview.
    var settingsForcesCardHover: Bool {
        get { self[SettingsForcesCardHoverKey.self] }
        set { self[SettingsForcesCardHoverKey.self] = newValue }
    }
}
