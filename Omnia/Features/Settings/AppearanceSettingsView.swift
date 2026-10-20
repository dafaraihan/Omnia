import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(OmniaStore.self) private var store
    @Environment(SettingsPreferencesStore.self) private var settings

    var body: some View {
        OmniaSettingsForm {
            Section {
                Picker(
                    "Appearance",
                    selection: Binding(
                        get: { store.appearance },
                        set: { store.appearance = $0 }
                    )
                ) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.inline)
            } footer: {
                Text("Match System follows the appearance selected for this device.")
            }

            Section {
                AccentSwatchGrid(selection: settings.binding(\.display.accentTheme))
                    .padding(.vertical, 4)
                if settings.preferences.display.accentTheme == .custom {
                    Picker("Style", selection: settings.binding(\.display.customAccentMode)) {
                        ForEach(CustomAccentMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
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
                Toggle(isOn: settings.binding(\.display.amoledBlack)) {
                    Text("AMOLED Black")
                    Text("Use true black behind pages in Dark appearance.")
                }
            } header: {
                Text("Accent Color")
            } footer: {
                Text(accentFooter)
            }

            Section {
                SettingsRouteLink(route: .posterCards, summary: posterCardsSummary)
                Toggle(
                    "Show Details Under Posters",
                    isOn: settings.binding(\.showMediaCardLabels)
                )
            } header: {
                Text("Media Cards")
            } footer: {
                Text("Shows each title, release year, and primary genre below standard posters.")
            }

            #if os(macOS)
            Section {
                Toggle("Hover Preview", isOn: settings.binding(\.display.hoverPreviewEnabled))
                if settings.preferences.display.hoverPreviewEnabled {
                    Picker("Delay", selection: settings.binding(\.display.hoverPreviewDelay)) {
                        ForEach(HoverPreviewDelay.allCases) { delay in
                            Text(delay.title).tag(delay)
                        }
                    }
                }
            } header: {
                Text("Hover Preview")
            } footer: {
                Text("Rest the pointer on a poster to see its backdrop and synopsis.")
            }
            #endif

            #if os(macOS)
            Section {
                Picker(
                    "Navigation Style",
                    selection: settings.binding(\.navigationStyle)
                ) {
                    ForEach(MacNavigationStyle.allCases) { style in
                        Label(style.title, systemImage: style.systemImage)
                            .tag(style)
                    }
                }
                .pickerStyle(.inline)

                if settings.preferences.navigationStyle == .topBar {
                    Picker("Top Bar Style", selection: settings.binding(\.display.topBarStyle)) {
                        ForEach(TopBarStyle.allCases) { style in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.title)
                                Text(style.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(style)
                        }
                    }
                    .pickerStyle(.inline)

                    if settings.preferences.display.topBarStyle.isNuvio {
                        Toggle(isOn: settings.binding(\.display.topBarGlow)) {
                            Text("Glass Glow")
                            Text("Adds soft light around the floating bar while you press or drag it.")
                        }
                    }
                }

                Picker(
                    "Search",
                    selection: settings.binding(\.searchStyle)
                ) {
                    ForEach(MacSearchStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
            } header: {
                Text("Navigation")
            } footer: {
                Text("Choose whether Omnia’s main sections appear in a sidebar or a floating top tab bar, and whether Search opens as its own page or floats over the current one.")
            }
            #endif
        }
        .omniaNavigationTitle("Appearance")
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

/// Nuvio's theme swatches. Each circle shows its colour; the chosen one has
/// a ring.
private struct AccentSwatchGrid: View {
    @Binding var selection: AccentTheme

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 30, maximum: 30), spacing: 12)], alignment: .leading, spacing: 12) {
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

    private func swatch(for theme: AccentTheme) -> some View {
        Circle()
            .fill(fill(for: theme))
            .frame(width: 24, height: 24)
            .overlay {
                Circle().strokeBorder(.primary.opacity(0.15))
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
#endif
