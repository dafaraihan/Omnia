import SwiftUI

/// Settings › Layout › Liquid Glass.
struct LiquidGlassSettingsView: View {
    @Environment(SettingsPreferencesStore.self) private var settings

    @State private var draftIntensity: Double?

    private var glass: LiquidGlassPreferences { settings.preferences.display.liquidGlass }

    /// The preview follows the slider while the drag is still going.
    private var previewDisplay: DisplayPreferences {
        var display = settings.preferences.display
        if let draftIntensity { display.liquidGlass.intensity = draftIntensity }
        return display
    }

    var body: some View {
        OmniaSettingsForm {
            Section {
                LiquidGlassPreview()
                    .environment(\.displayPreferences, previewDisplay)
                    .listRowInsets(EdgeInsets())
            } header: {
                Text("Preview")
            }

            Section {
                Toggle("Liquid Glass", isOn: settings.binding(\.display.liquidGlass.isEnabled))
                .settingsRow("Liquid Glass")
                if glass.isEnabled {
                    SettingsDropdown(
                        "Style",
                        subtitle: styleDetail,
                        selection: settings.binding(\.display.liquidGlass.style),
                        options: LiquidGlassStyle.allCases
                    ) { $0.title }
                    .settingsRow("Style")
                    SettingsDeferredSlider(
                        title: "Intensity",
                        minimumLabel: "Clear",
                        maximumLabel: "Frosted",
                        value: settings.binding(\.display.liquidGlass.intensity),
                        range: 0 ... 1,
                        onDraft: { draftIntensity = $0 }
                    )
                    .settingsRow("Intensity")
                }
            } header: {
                Text("Glass")
            } footer: {
                Text(glass.isEnabled
                    ? "The middle of the slider is the designed look."
                    : "Buttons and panels use solid fills instead of glass.")
            }

            if glass.isEnabled {
                Section {
                    Toggle(isOn: settings.binding(\.display.liquidGlass.actionButtons)) {
                        Text("Action Buttons")
                        Text("Play, View Details, watched and My List on heroes.")
                    }
                    .settingsRow("Action Buttons")
                    Toggle(isOn: settings.binding(\.display.liquidGlass.playerControls)) {
                        Text("Player Controls")
                        Text("Buttons, timeline and menus in the player.")
                    }
                    .settingsRow("Player Controls")
                    Toggle(isOn: settings.binding(\.display.liquidGlass.panels)) {
                        Text("Menus and Panels")
                        Text("Stream picker, sheets, shelf arrows, and account and profile buttons.")
                    }
                    .settingsRow("Menus and Panels")
                    Toggle(isOn: settings.binding(\.display.liquidGlass.navigationBar)) {
                        Text("Floating Navigation Bar")
                        Text(OmniaDevice.isPhone
                            ? "The bar at the bottom of the screen. Off, Omnia draws it with a solid fill."
                            : "The bar at the top of the window.")
                    }
                    .settingsRow("Floating Navigation Bar")
                } header: {
                    Text("Use Glass On")
                } footer: {
                    Text(systemBarsFooter)
                }
            }
        }
        .omniaNavigationTitle("Liquid Glass")
    }

    private var styleDetail: String {
        switch glass.style {
        case .standard: "Each part keeps the glass designed for it."
        case .clear: "See-through glass everywhere."
        case .frosted: "Heavier, more readable glass everywhere."
        }
    }

    private var systemBarsFooter: String {
        OmniaDevice.isPhone
            ? "With its glass on, iOS draws the bar, so the slider doesn't reach it. System menus always use iOS's glass."
            : "The sidebar, toolbars and system menus are drawn by the system and always use its glass."
    }
}

/// Live: built from the same glass as the real controls, over moving colour
/// so the glass has something to bend.
private struct LiquidGlassPreview: View {
    private static let colors: [Color] = [.indigo, .pink, .orange, .teal]

    var body: some View {
        ZStack {
            LinearGradient(colors: Self.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { index in
                    Rectangle()
                        .fill(.white.opacity(index.isMultiple(of: 2) ? 0.28 : 0))
                }
            }
            .rotationEffect(.degrees(18))
            .scaleEffect(1.6)

            VStack(spacing: 14) {
                Text("Home    Library    Discover")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 18)
                    .frame(height: 38)
                    .omniaGlass(.navigationBar, base: .clear, in: Capsule())

                HStack(spacing: 8) {
                    Button {} label: {
                        HeroPrimaryActionLabel(title: "Play")
                    }
                    .omniaCapsuleGlassButton()
                    Button {} label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .frame(width: 46, height: 46)
                    }
                    .omniaCircularGlassButton()
                }

                HStack(spacing: 10) {
                    Button {} label: {
                        Image(systemName: "pause.fill")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
                    .omniaCircularGlassButton(element: .playerControls)

                    Text("Menu")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 22)
                        .frame(height: 44)
                        .omniaGlass(.panels, base: .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .frame(height: OmniaDevice.isPhone ? 200 : 240)
        .clipped()
        .labelStyle(.titleAndIcon)
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the current Liquid Glass settings")
    }
}
