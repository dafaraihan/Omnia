import SwiftUI

/// Settings › Appearance › Poster Cards: Nuvio's Poster Card Style and Card
/// Depth Effect. Every poster row, grid and card reads these values.
struct PosterCardSettingsView: View {
    @Environment(SettingsPreferencesStore.self) private var settings

    private var display: DisplayPreferences { settings.preferences.display }

    var body: some View {
        OmniaSettingsForm {
            Section {
                PosterCardPreview(display: display)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }

            Section {
                Picker("Size", selection: settings.binding(\.display.posterWidth)) {
                    ForEach(PosterWidthPreset.allCases) { preset in
                        Text("\(preset.title) (\(Int(preset.width)) pt)").tag(preset)
                    }
                }
                Picker("Corners", selection: settings.binding(\.display.posterCorner)) {
                    ForEach(PosterCornerPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                Toggle(isOn: settings.binding(\.display.landscapePosters)) {
                    Text("Landscape Posters")
                    Text("Show backdrops with the title logo instead of portrait posters.")
                }
            } header: {
                Text("Poster Card Style")
            }

            Section {
                Toggle("Card Depth Effect", isOn: settings.binding(\.display.cardDepth.isEnabled))

                if display.cardDepth.isEnabled {
                    Picker("Edge Glow", selection: settings.binding(\.display.cardDepth.edgeStrength)) {
                        Text("Subtle").tag(28)
                        Text("Medium").tag(42)
                        Text("Strong").tag(56)
                    }
                    Picker("Top Sheen", selection: settings.binding(\.display.cardDepth.sheenStrength)) {
                        Text("Off").tag(0)
                        Text("Soft").tag(10)
                        Text("Bright").tag(16)
                    }
                    Picker("Edge Coverage", selection: settings.binding(\.display.cardDepth.edgeCoverage)) {
                        Text("Top Edge").tag(0)
                        Text("Half").tag(50)
                        Text("Full Border").tag(100)
                    }
                }
            } header: {
                Text("Card Depth")
            } footer: {
                Text("Adds a light edge and a soft sheen so cards look lifted off the page.")
            }

            if display.cardDepth.isEnabled {
                Section {
                    ForEach(CardDepthPreferences.Surface.allCases) { surface in
                        Toggle(surface.title, isOn: surfaceBinding(surface))
                    }
                } header: {
                    Text("Apply Card Depth To")
                }
            }

            Section {
                Toggle(isOn: settings.binding(\.display.cardHover.isEnabled)) {
                    Text("Hover Glow")
                    Text("Lights a card's edge when the pointer rests on it, as on collection cards.")
                }

                if display.cardHover.isEnabled {
                    Picker("Color", selection: settings.binding(\.display.cardHover.colorSource)) {
                        ForEach(CardHoverPreferences.ColorSource.allCases) { source in
                            Text(source.title).tag(source)
                        }
                    }
                    if display.cardHover.colorSource == .custom {
                        ColorPicker("Custom Color", selection: hoverColorBinding, supportsOpacity: false)
                    }
                    Picker("Intensity", selection: settings.binding(\.display.cardHover.intensity)) {
                        ForEach(CardHoverPreferences.Intensity.allCases) { intensity in
                            Text(intensity.title).tag(intensity)
                        }
                    }
                    Toggle(isOn: settings.binding(\.display.cardHover.outerGlow)) {
                        Text("Outer Glow")
                        Text("Adds a soft light around the card in the same color.")
                    }
                    Toggle("Lift on Hover", isOn: settings.binding(\.display.cardHover.lift))
                }
            } header: {
                Text("Hover Glow")
            } footer: {
                if display.cardHover.isEnabled {
                    Text("Hover over the preview above to try it.")
                }
            }

            if display.cardHover.isEnabled {
                Section {
                    ForEach(CardDepthPreferences.Surface.allCases) { surface in
                        Toggle(surface.title, isOn: hoverSurfaceBinding(surface))
                    }
                } header: {
                    Text("Apply Hover Glow To")
                }
            }

            Section {
                Button("Reset Poster Cards") {
                    settings.update {
                        let defaults = DisplayPreferences.default
                        $0.display.posterWidth = defaults.posterWidth
                        $0.display.posterCorner = defaults.posterCorner
                        $0.display.landscapePosters = defaults.landscapePosters
                        $0.display.cardDepth = defaults.cardDepth
                        $0.display.cardHover = defaults.cardHover
                    }
                }
            }
        }
        .omniaNavigationTitle("Poster Cards")
    }

    private var hoverColorBinding: Binding<Color> {
        Binding(
            get: { Color(omniaHex: settings.preferences.display.cardHover.customHex) ?? .white },
            set: { color in
                guard let hex = color.omniaHex else { return }
                settings.update { $0.display.cardHover.customHex = hex }
            }
        )
    }

    private func hoverSurfaceBinding(_ surface: CardDepthPreferences.Surface) -> Binding<Bool> {
        Binding(
            get: { !settings.preferences.display.cardHover.disabledSurfaces.contains(surface) },
            set: { isOn in
                settings.update {
                    if isOn {
                        $0.display.cardHover.disabledSurfaces.remove(surface)
                    } else {
                        $0.display.cardHover.disabledSurfaces.insert(surface)
                    }
                }
            }
        )
    }

    private func surfaceBinding(_ surface: CardDepthPreferences.Surface) -> Binding<Bool> {
        Binding(
            get: { !settings.preferences.display.cardDepth.disabledSurfaces.contains(surface) },
            set: { isOn in
                settings.update {
                    if isOn {
                        $0.display.cardDepth.disabledSurfaces.remove(surface)
                    } else {
                        $0.display.cardDepth.disabledSurfaces.insert(surface)
                    }
                }
            }
        )
    }
}

/// A sample card drawn with the current size, corners and depth, so each
/// change shows before leaving Settings.
private struct PosterCardPreview: View {
    let display: DisplayPreferences

    private var size: CGSize {
        display.landscapePosters
            ? CGSize(width: MediaBrowseMetrics.landscapeCardWidth, height: MediaBrowseMetrics.landscapeCardWidth / 1.72)
            : CGSize(width: display.posterCardWidth, height: display.posterCardHeight)
    }

    private var radius: CGFloat {
        display.landscapePosters ? display.landscapeCornerRadius : display.posterCornerRadius
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [display.accentColor.opacity(0.85), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: display.landscapePosters ? "film" : "film.stack")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("Preview")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(12)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        // The same depth and hover glow as a real poster.
        .cardDepth(.posters, cornerRadius: radius)
        .environment(\.displayPreferences, display)
        .padding(12)
        .animation(.easeInOut(duration: 0.2), value: display)
        .accessibilityHidden(true)
    }
}
