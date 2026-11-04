import SwiftUI

/// What the preview column shows. Set by the page on screen in the middle.
enum SettingsPreviewKind: Equatable {
    case home, cards, player, glass
}

extension SettingsRoute {
    var previewKind: SettingsPreviewKind? {
        switch self {
        case .appearance: .home
        case .posterCards: .cards
        case .subtitle: .player
        case .liquidGlass: .glass
        default: nil
        }
    }
}

/// Shared between the page in the middle and the preview on the right.
@MainActor
@Observable
final class SettingsPreviewModel {
    var kind: SettingsPreviewKind?
    var showsPlayerMenu = true
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

/// Settings on iPad and Mac: categories, the page, and a live preview. Narrow
/// windows lose the preview first, then go back to the plain drill-down.
struct SettingsThreeColumnView: View {
    private static let categoriesWidth: CGFloat = 220
    private static let previewWidth: CGFloat = 340
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
                SettingsColumns(
                    categoriesWidth: Self.categoriesWidth,
                    previewWidth: width >= Self.categoriesWidth + Self.middleMinimum + Self.previewWidth
                        ? Self.previewWidth : nil
                )
            }
        }
    }
}

private struct SettingsColumns: View {
    let categoriesWidth: CGFloat
    let previewWidth: CGFloat?

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
                .environment(\.settingsPreviewInColumn, previewWidth != nil)
                if let previewWidth, let kind = model.kind {
                    Divider().ignoresSafeArea()
                    SettingsPreviewColumn(kind: kind, model: model)
                        .frame(width: previewWidth)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.25), value: model.kind)
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

private struct SettingsPreviewColumn: View {
    let kind: SettingsPreviewKind
    @Bindable var model: SettingsPreviewModel
    @Environment(SettingsPreferencesStore.self) private var settings

    var body: some View {
        let display = model.applyingDrafts(to: settings.preferences.display)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Live Preview")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                preview(display: display)
                    .environment(\.displayPreferences, display)
                    .tint(display.accentColor)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Preview of these settings")
                if kind == .player {
                    Toggle("Show a Menu", isOn: $model.showsPlayerMenu)
                        .tint(display.accentColor)
                }
            }
            .padding(16)
        }
        .settingsClearsTopBar()
    }

    @ViewBuilder
    private func preview(display: DisplayPreferences) -> some View {
        switch kind {
        case .home:
            SettingsScaledPreview(size: CGSize(width: 620, height: 600)) {
                SettingsMiniHome(display: display)
            }
        case .cards:
            LegacyPosterCardPreview(display: display)
                .frame(maxWidth: .infinity)
        case .player:
            SettingsScaledPreview(size: CGSize(width: 900, height: 520)) {
                MacSubtitlePlaybackPreview(
                    style: settings.preferences.playbackSubtitleStyle,
                    height: 520,
                    showsMenu: model.showsPlayerMenu
                )
            }
        case .glass:
            LegacyLiquidGlassPreview()
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
        }
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
