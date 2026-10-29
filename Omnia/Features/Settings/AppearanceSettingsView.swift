import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(OmniaStore.self) private var store
    @Environment(SettingsPreferencesStore.self) private var settings
    @Environment(CollectionsStore.self) private var collections
    @AppStorage(HomeView.continueWatchingVisibilityKey) private var showsContinueWatching = true
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// Settings › Layout, laid out like Nuvio's: Theme, Display, Home and
    /// Detail Page.
    var body: some View {
        OmniaSettingsForm {
            Section {
                SettingsDropdown(
                    "Appearance",
                    selection: Binding(
                        get: { store.appearance },
                        set: { store.appearance = $0 }
                    ),
                    options: AppAppearance.allCases
                ) { $0.title }
            } header: {
                Text("Theme")
            } footer: {
                Text("Match System follows the appearance selected for this device.")
            }

            Section {
                AccentSwatchGrid(selection: settings.binding(\.display.accentTheme))
                    .padding(.vertical, 4)
                if settings.preferences.display.accentTheme == .custom {
                    SettingsDropdown(
                        "Style",
                        selection: settings.binding(\.display.customAccentMode),
                        options: CustomAccentMode.allCases
                    ) { $0.title }
                    switch settings.preferences.display.customAccentMode {
                    case .single:
                        ColorPicker(
                            "Custom Color",
                            selection: customAccentBinding,
                            supportsOpacity: false
                        )
                    case .gradient:
                        ForEach(0..<3, id: \.self) { index in
                            ColorPicker(
                                Self.gradientStopTitles[index],
                                selection: customGradientBinding(index),
                                supportsOpacity: false
                            )
                        }
                        LinearGradient(
                            colors: settings.preferences.display.accentGradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(height: 28)
                        .clipShape(Capsule())
                        .accessibilityHidden(true)
                    }
                }
            } header: {
                Text("Accent Color")
            } footer: {
                Text(accentFooter)
            }

            Section {
                Toggle(isOn: settings.binding(\.display.amoledBlack)) {
                    Text("AMOLED Black")
                    Text("Use true black behind pages in Dark appearance.")
                }
                if showsNavigationStyle {
                    SettingsDropdown(
                        "Navigation Style",
                        selection: settings.binding(\.navigationStyle),
                        options: MacNavigationStyle.allCases,
                        systemImage: \.systemImage
                    ) { $0.title }
                }

                if showsBarStyle {
                    SettingsDropdown(
                        barStyleTitle,
                        subtitle: settings.preferences.display.topBarStyle.detail,
                        selection: settings.binding(\.display.topBarStyle),
                        options: TopBarStyle.allCases
                    ) { $0.title }

                    if settings.preferences.display.topBarStyle.isNuvio {
                        Toggle(isOn: settings.binding(\.display.topBarGlow)) {
                            Text("Glass Glow")
                            Text("Adds soft light around the floating bar while you press or drag it.")
                        }
                    }
                }

                #if os(macOS)
                Toggle("Hover Preview", isOn: settings.binding(\.display.hoverPreviewEnabled))
                if settings.preferences.display.hoverPreviewEnabled {
                    SettingsDropdown(
                        "Hover Preview Delay",
                        selection: settings.binding(\.display.hoverPreviewDelay),
                        options: HoverPreviewDelay.allCases
                    ) { $0.title }
                }
                #endif
            } header: {
                Text("Display")
            } footer: {
                #if os(macOS)
                Text("Choose a sidebar or a top tab bar, whether Search opens as a page or floats over the current one, and whether resting the pointer on a poster previews it.")
                #else
                Text(horizontalSizeClass == .compact
                    ? "Choose the system tab bar or Nuvio's floating bar."
                    : "Choose a sidebar or a top tab bar, and the system tab bar or Nuvio's floating bar.")
                #endif
            }

            Section {
                SettingsRouteLink(route: .home, summary: homeLayoutSummary)
                SettingsRouteLink(route: .collections, summary: collectionsSummary)
                SettingsRouteLink(route: .continueWatching, summary: continueWatchingSummary)
                SettingsRouteLink(route: .upcoming, summary: upcomingSummary)
                SettingsRouteLink(route: .posterCards, summary: posterCardsSummary)
            } header: {
                Text("Home")
            }

            Section {
                SettingsRouteLink(route: .detailPage, summary: detailPageSummary)
            } header: {
                Text("Detail Page")
            }

            Section {
                SettingsRouteLink(route: .streams, summary: streamsSummary)
            } header: {
                Text("Streams")
            }
        }
        .omniaNavigationTitle("Layout")
    }

    private var homeLayoutSummary: String {
        let catalogs = AddonCatalogStore.catalogs(in: store)
        guard !catalogs.isEmpty else { return "Built-in rows" }
        let visible = catalogs.filter { store.isCatalogEnabled(for: $0.addon, catalog: $0.catalog) }.count
        return "\(visible) of \(catalogs.count) catalogs visible"
    }

    private var collectionsSummary: String {
        let all = collections.collections
        guard !all.isEmpty else { return "None" }
        let visible = all.filter { collections.isVisible($0) }.count
        return visible == all.count ? "\(all.count) on Home" : "\(visible) of \(all.count) on Home"
    }

    private var continueWatchingSummary: String {
        guard showsContinueWatching else { return "Hidden from Home" }
        return "\(settings.preferences.display.continueWatchingStyle.title) cards"
    }

    private var upcomingSummary: String {
        settings.preferences.showUpcoming ? "Shown on Home" : "Hidden from Home"
    }

    private var detailPageSummary: String {
        let hidden = settings.preferences.display.hiddenDetailSections.count
        return hidden == 0 ? "All sections shown" : "\(hidden) hidden"
    }

    private var streamsSummary: String {
        let streams = settings.preferences.streams
        var parts = [streams.background.title]
        if let active = StreamBadgeStore.shared.activeImport {
            parts.append("Badges from \(active.displayHost)")
        }
        if streams.showsSearchBar { parts.append("Search") }
        return parts.joined(separator: " · ")
    }

    private var posterCardsSummary: String {
        let display = settings.preferences.display
        var parts = [display.posterWidth.title]
        if display.landscapePosters { parts.append("Landscape") }
        if display.cardDepth.isEnabled { parts.append("Depth") }
        if display.cardHover.isEnabled { parts.append("Hover") }
        return parts.joined(separator: " · ")
    }

    private static let gradientStopTitles = ["Start Color", "Middle Color", "End Color"]

    // MARK: Navigation

    /// A narrow iOS window always uses a tab bar, so only a regular-width
    /// window offers Sidebar or Top Bar.
    private var showsNavigationStyle: Bool {
        #if os(macOS)
        true
        #else
        horizontalSizeClass != .compact
        #endif
    }

    private var showsBarStyle: Bool {
        !showsNavigationStyle || settings.preferences.navigationStyle == .topBar
    }

    /// iPhone's bar sits at the bottom, so it is a tab bar there.
    private var barStyleTitle: String {
        showsNavigationStyle ? "Top Bar Style" : "Tab Bar Style"
    }

    private var accentFooter: String {
        let display = settings.preferences.display
        var text = "\(display.accentTheme.title) tints buttons, switches, selection and the active tab."
        if display.usesAccentGradient {
            text += " Its gradient colors the theme swatch and the selected tab icon in Nuvio's top bar."
        }
        if display.accentTheme == .custom && display.customAccentMode == .gradient {
            text += " The middle color is used where one color is needed."
        }
        return text
    }

    private func customGradientBinding(_ index: Int) -> Binding<Color> {
        Binding(
            get: {
                let hexes = settings.preferences.display.customGradientHexes
                let fallback = DisplayPreferences.defaultCustomGradient[index]
                return Color(omniaHex: hexes.indices.contains(index) ? hexes[index] : fallback)
                    ?? Color(omniaHex: fallback) ?? .purple
            },
            set: { color in
                guard let hex = color.omniaHex else { return }
                settings.update { preferences in
                    var hexes = preferences.display.customGradientHexes
                    if hexes.count != 3 { hexes = DisplayPreferences.defaultCustomGradient }
                    hexes[index] = hex
                    preferences.display.customGradientHexes = hexes
                }
            }
        )
    }

    private var customAccentBinding: Binding<Color> {
        Binding(
            get: { Color(omniaHex: settings.preferences.display.customAccentHex) ?? .blue },
            set: { color in
                guard let hex = color.omniaHex else { return }
                settings.update { $0.display.customAccentHex = hex }
            }
        )
    }
}

/// Nuvio's theme swatches, centred. Each circle shows its colour; the
/// chosen one has a ring and a checkmark.
private struct AccentSwatchGrid: View {
    @Binding var selection: AccentTheme

    var body: some View {
        // One centred row when it fits, otherwise centred wrapping rows.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { swatches }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 30, maximum: 30), spacing: 12)], alignment: .center, spacing: 12) {
                swatches
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var swatches: some View {
        ForEach(AccentTheme.allCases) { theme in
            Button {
                selection = theme
            } label: {
                swatch(for: theme)
            }
            .buttonStyle(.plain)
            .help(theme.title)
            .accessibilityLabel(theme.title)
            .accessibilityAddTraits(selection == theme ? .isSelected : [])
        }
    }

    private func fill(for theme: AccentTheme) -> AnyShapeStyle {
        switch theme {
        case .blue:
            AnyShapeStyle(Color.blue)
        case .custom:
            AnyShapeStyle(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
        default:
            if let colors = theme.gradientHexes?.compactMap(Color.init(omniaHex:)), colors.count > 1 {
                // Nuvio draws gradient themes corner to corner.
                AnyShapeStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            } else {
                AnyShapeStyle(theme.hex.flatMap(Color.init(omniaHex:)) ?? .blue)
            }
        }
    }

    /// Dark on light swatches (White, Gold), white on the rest.
    private func checkmarkColor(for theme: AccentTheme) -> Color {
        guard theme != .custom else { return .white }
        let color = theme.gradientHexes?.first.flatMap(Color.init(omniaHex:))
            ?? theme.hex.flatMap(Color.init(omniaHex:))
            ?? .blue
        return color.prefersDarkForeground ? .black : .white
    }

    private func swatch(for theme: AccentTheme) -> some View {
        Circle()
            .fill(fill(for: theme))
            .frame(width: 24, height: 24)
            .overlay {
                Circle().strokeBorder(.primary.opacity(0.15))
            }
            .overlay {
                if selection == theme {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(checkmarkColor(for: theme))
                        .shadow(color: .black.opacity(0.25), radius: 1)
                }
            }
            .padding(3)
            .overlay {
                if selection == theme {
                    Circle().strokeBorder(.primary.opacity(0.85), lineWidth: 2)
                }
            }
            .contentShape(Circle())
    }
}


#if os(macOS)
private extension MacSearchStyle {
    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .page: "Page"
        case .floating: "Floating"
        }
    }
}
#endif

private extension MacNavigationStyle {
    var title: String {
        switch self {
        case .sidebar: "Sidebar"
        case .topBar: "Top Bar"
        }
    }

    var systemImage: String {
        switch self {
        case .sidebar: "sidebar.left"
        case .topBar: "rectangle.topthird.inset.filled"
        }
    }
}

