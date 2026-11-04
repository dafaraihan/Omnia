import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(OmniaStore.self) private var store
    @Environment(SettingsPreferencesStore.self) private var settings

    /// Settings › Appearance: how Omnia looks everywhere.
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
                .settingsRow("Appearance")
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
                    .settingsRow("Style")
                    switch settings.preferences.display.customAccentMode {
                    case .single:
                        ColorPicker(
                            "Custom Color",
                            selection: customAccentBinding,
                            supportsOpacity: false
                        )
                        .settingsRow("Custom Color")
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
                    Text("True black behind pages in Dark appearance.")
                }
                .settingsRow("AMOLED Black")
                SettingsRouteLink(route: .liquidGlass, summary: liquidGlassSummary)
            } header: {
                Text("Display")
            }
        }
        .omniaNavigationTitle("Appearance")
    }

    private var liquidGlassSummary: String {
        let glass = settings.preferences.display.liquidGlass
        return glass.isEnabled ? glass.style.title : "Off"
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
