import SwiftUI

/// Settings › Layout › Poster Card Style: Nuvio's Poster Card Style and Card
/// Depth Effect. Every poster row, grid and card reads these values.
struct PosterCardSettingsView: View {
    @Environment(SettingsPreferencesStore.self) private var settings
    @State private var posterPatternDraft = ""

    private var display: DisplayPreferences { settings.preferences.display }

    private var trimmedPosterPattern: String {
        posterPatternDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let showsAdvanced: Bool

    init(showsAdvanced: Bool = false) {
        self.showsAdvanced = showsAdvanced
    }

    var body: some View {
        Group {
            if showsAdvanced {
                OmniaSettingsForm {
            Section {
                Toggle(isOn: settings.binding(\.display.sharesCardStyles)) {
                    Text("Same Style on All Devices")
                    Text("Off, this \(OmniaDevice.name) keeps its own card styles, since a size that suits a Mac can be too big for an iPhone.")
                }
                .settingsRow("Same Style on All Devices")
            } header: {
                SettingsSectionHeader("Style", resetTitle: "Reset Poster Cards", canReset: true) {
                    settings.update {
                        let defaults = DisplayPreferences.default
                        $0.display.posterWidth = defaults.posterWidth
                        $0.display.posterCorner = defaults.posterCorner
                        $0.display.landscapePosters = defaults.landscapePosters
                        $0.display.cardDepth = defaults.cardDepth
                        $0.display.cardHover = defaults.cardHover
                    }

                }
            } footer: {
                Text("Every card shown in portrait uses this page. Landscape cards take their size and corners from Landscape Card Style.")
            }

            customPosterSourceSection

            Section {
                Toggle("Card Depth Effect", isOn: settings.binding(\.display.cardDepth.isEnabled))
                .settingsRow("Card Depth Effect")

                if display.cardDepth.isEnabled {
                    SettingsDropdown(
                        "Edge Glow",
                        selection: settings.binding(\.display.cardDepth.edgeStrength),
                        options: [28, 42, 56]
                    ) { value in
                        switch value {
                        case 28: "Subtle"
                        case 42: "Medium"
                        case 56: "Strong"
                        default: "\(value)"
                        }
                    }
                    .settingsRow("Edge Glow")
                    SettingsDropdown(
                        "Top Sheen",
                        selection: settings.binding(\.display.cardDepth.sheenStrength),
                        options: [0, 10, 16]
                    ) { value in
                        switch value {
                        case 0: "Off"
                        case 10: "Soft"
                        case 16: "Bright"
                        default: "\(value)"
                        }
                    }
                    .settingsRow("Top Sheen")
                    SettingsDropdown(
                        "Edge Coverage",
                        selection: settings.binding(\.display.cardDepth.edgeCoverage),
                        options: [0, 50, 100]
                    ) { value in
                        switch value {
                        case 0: "Top Edge"
                        case 50: "Half"
                        case 100: "Full Border"
                        default: "\(value)"
                        }
                    }
                    .settingsRow("Edge Coverage")
                }
            } header: {
                Text("Card Depth")
            } footer: {
                Text("Adds a light edge and a soft sheen so cards look lifted off the page.")
            }

            if display.cardDepth.isEnabled {
                Section {
                    ForEach(CardDepthPreferences.Surface.allCases.filter { $0 != .continueWatching && $0 != .collections }) { surface in
                        Toggle(surface.title, isOn: surfaceBinding(surface))
                    }
                } header: {
                    Text("Apply Card Depth To")
                }
            }

            // iPhone has no pointer to hover with; iPad can have one.
            if !OmniaDevice.isPhone {
            Section {
                Toggle(isOn: settings.binding(\.display.cardHover.isEnabled)) {
                    Text("Hover Glow")
                    Text("Lights a card's edge when the pointer rests on it, as on collection cards.")
                }
                .settingsRow("Hover Glow")

                if display.cardHover.isEnabled {
                    SettingsDropdown(
                        "Color",
                        selection: settings.binding(\.display.cardHover.colorSource),
                        options: Array(CardHoverPreferences.ColorSource.allCases)
                    ) { source in source.title }
                    .settingsRow("Color")
                    if display.cardHover.colorSource == .custom {
                        ColorPicker("Custom Color", selection: hoverColorBinding, supportsOpacity: false)
                        .settingsRow("Custom Color")
                    }
                    SettingsDropdown(
                        "Intensity",
                        selection: settings.binding(\.display.cardHover.intensity),
                        options: Array(CardHoverPreferences.Intensity.allCases)
                    ) { intensity in intensity.title }
                    .settingsRow("Intensity")
                    Toggle(isOn: settings.binding(\.display.cardHover.outerGlow)) {
                        Text("Outer Glow")
                        Text("Adds a soft light around the card in the same color.")
                    }
                    .settingsRow("Outer Glow")
                    Toggle("Lift on Hover", isOn: settings.binding(\.display.cardHover.lift))
                    .settingsRow("Lift on Hover")
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
                    ForEach(CardDepthPreferences.Surface.allCases.filter { $0 != .continueWatching && $0 != .collections }) { surface in
                        Toggle(surface.title, isOn: hoverSurfaceBinding(surface))
                    }
                } header: {
                    Text("Apply Hover Glow To")
                }
            }
            }


                }
            } else {
                OmniaSettingsForm {
            Section {
                SettingsDropdown(
                    "Size",
                    selection: settings.binding(\.display.posterWidth),
                    options: Array(PosterWidthPreset.allCases)
                ) { preset in "\(preset.title) (\(Int(preset.width)) pt)" }
                .settingsRow("Size")
                SettingsDropdown(
                    "Corners",
                    selection: settings.binding(\.display.posterCorner),
                    options: Array(PosterCornerPreset.allCases)
                ) { preset in preset.title }
                .settingsRow("Corners")
                Toggle(isOn: settings.binding(\.display.landscapePosters)) {
                    Text("Landscape Posters")
                    Text("Show backdrops with the title logo instead of portrait posters.")
                }
                .settingsRow("Landscape Posters")
                Toggle(isOn: settings.binding(\.showMediaCardLabels)) {
                    Text("Show Details Under Posters")
                    Text("Shows each title, release year, and primary genre below standard posters.")
                }
                .settingsRow("Show Details Under Posters")
            }

            Section {
                SettingsRouteLink(route: .advanced(.posterCards), summary: nil)
            }
                }
        .settingsPinnedPreview {
            PosterCardPreview(display: display)
                .frame(maxWidth: .infinity)
        }
            }
        }
        .omniaNavigationTitle(showsAdvanced ? "Advanced" : "Poster Card Style")
        .onAppear { posterPatternDraft = display.customPosterURLPattern }
    }

    /// Nuvio's Custom Poster Source: a URL pattern from a poster service.
    private var customPosterSourceSection: some View {
        Section {
            TextField(
                "Poster URL Pattern",
                text: $posterPatternDraft,
                prompt: Text("https://example.com/poster?id={id}&id_type={id_type}&type={type}")
            )
            .font(.body.monospaced())
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            #endif
            .onSubmit(savePosterPattern)
            if !trimmedPosterPattern.isEmpty, !CustomPosterURLResolver.isValidPattern(trimmedPosterPattern) {
                Label("Enter an http or https address.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            HStack {
                Button("Save", action: savePosterPattern)
                    .disabled(trimmedPosterPattern == display.customPosterURLPattern
                              || (!trimmedPosterPattern.isEmpty && !CustomPosterURLResolver.isValidPattern(trimmedPosterPattern)))
                Button("Clear", role: .destructive) {
                    posterPatternDraft = ""
                    settings.update { $0.display.customPosterURLPattern = "" }
                }
                .disabled(display.customPosterURLPattern.isEmpty && posterPatternDraft.isEmpty)
            }
            #if os(iOS)
            // In an iOS Form a tap on the row fires every button in it.
            .buttonStyle(.borderless)
            #endif
            Label(
                display.customPosterURLPattern.isEmpty ? "No pattern configured" : "Custom poster source active",
                systemImage: display.customPosterURLPattern.isEmpty ? "circle.dashed" : "checkmark.circle.fill"
            )
            .foregroundStyle(.secondary)
        } header: {
            Text("Custom Poster Source")
        } footer: {
            Text("Provide a poster URL pattern from an external service, such as RPDB. Placeholders: {id}, {id_type}, {typed_id}, {type}, {shape}, {imdb_id}, {tmdb_id}, {tvdb_id}, {kitsu_id}, {anilist_id}, {mal_id}, {anidb_id}. Add ? for an optional one ({imdb_id?}) or | for the first available ({imdb_id|tmdb_id}). If a placeholder has no value for a title, or the image fails to load, its original poster is used. Landscape cards use the pattern only when it includes {shape}.")
        }
    }

    private func savePosterPattern() {
        let pattern = trimmedPosterPattern
        guard pattern.isEmpty || CustomPosterURLResolver.isValidPattern(pattern) else { return }
        settings.update { $0.display.customPosterURLPattern = pattern }
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
            ? CGSize(width: display.landscapePosterCardWidth, height: display.landscapeCardHeight)
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
