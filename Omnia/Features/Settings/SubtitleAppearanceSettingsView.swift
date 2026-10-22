import SwiftUI

struct SubtitleAppearanceSettingsView: View {
    @Environment(SettingsPreferencesStore.self) private var settings
    @State private var showsResetConfirmation = false

    private var resolvedAppearance: SubtitleAppearance {
        SubtitleAppearanceSettingsModel(
            mode: settings.preferences.subtitleAppearance,
            custom: settings.preferences.customSubtitleAppearance
        ).resolvedAppearance
    }

    var body: some View {
        #if os(macOS)
        macSettings
        #else
        OmniaSettingsForm {
            Section("Preview") {
                ZStack {
                    LinearGradient(colors: [.blue.opacity(0.7), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                    SubtitleOverlayView(
                        cues: [SubtitleCue(startSeconds: 0, endSeconds: 10, text: "The quick brown fox jumps over the lazy dog")],
                        appearance: resolvedAppearance
                    )
                }
                .frame(minHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Subtitle appearance preview")
                .accessibilityValue("The quick brown fox jumps over the lazy dog")
            }

            Section {
                SettingsDropdown(
                    "Appearance",
                    selection: settings.binding(\.subtitleAppearance),
                    options: Array(SubtitleAppearanceMode.allCases)
                ) { mode in mode.title }
            } header: {
                Text("Style")
            } footer: {
                Text(settings.preferences.subtitleAppearance == .followSystem
                     ? "Uses the platform caption style when the playback engine supports it."
                     : "Preset and custom styles use semantic colors and scale with the viewing surface.")
            }

            if settings.preferences.subtitleAppearance == .custom {
                customControls
            }

            Section {
                Button("Reset to Defaults", role: .destructive) { showsResetConfirmation = true }
            }
        }
        .omniaNavigationTitle("Subtitle")
        .confirmationDialog("Reset subtitle appearance?", isPresented: $showsResetConfirmation, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                settings.update {
                    $0.subtitleAppearance = .followSystem
                    $0.customSubtitleAppearance = .default
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This restores Follow System and resets all custom values.")
        }
        #endif
    }

    #if os(macOS)
    private var macSettings: some View {
        OmniaSettingsForm {
            Section("Live Preview") {
                MacSubtitlePlaybackPreview(style: settings.preferences.playbackSubtitleStyle)
            }

            Section("Language") {
                Toggle("Subtitles Enabled", isOn: settings.binding(\.subtitlesEnabled))
                SubtitleSettingsLanguagePicker(
                    "Preferred subtitles",
                    selection: settings.binding(\.preferredSubtitleLanguage),
                    includesNone: true
                )
                SubtitleSettingsLanguagePicker(
                    "Subtitle fallback",
                    selection: settings.binding(\.subtitleFallbackLanguage),
                    includesNone: true
                )
                Toggle("Prefer SDH Captions", isOn: Binding(
                    get: { settings.preferences.sdhPreference == .prefer },
                    set: { enabled in
                        settings.update { $0.sdhPreference = enabled ? .prefer : .followSystem }
                    }
                ))
            }

            Section("Font") {
                DisclosureGroup(previewFontTitle) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(MacSubtitleFontCatalog.availableDisplayNames, id: \.self) { displayName in
                                Button {
                                    settings.update {
                                        $0.playbackSubtitleStyle.fontName = displayName == "System"
                                            ? PlaybackSubtitleStyle.default.fontName
                                            : displayName
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "checkmark")
                                            .opacity(displayName == previewFontTitle ? 1 : 0)
                                            .frame(width: 18)
                                        Text(displayName)
                                            .font(displayName == "System" ? .body : .custom(displayName, size: 15))
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .frame(height: 190)
                }
            }

            Section("Style") {
                SettingsDropdown(
                    "Background",
                    selection: styleBinding(\.background),
                    options: Array(PlaybackSubtitleBackground.allCases)
                ) { background in background.settingsTitle }
                SubtitleDoubleSlider(
                    title: "Size",
                    value: styleBinding(\.fontSize),
                    range: 14 ... 72,
                    valueLabel: { "\(Int($0.rounded())) pt" }
                )
                SubtitleDoubleSlider(
                    title: "Scale",
                    value: styleBinding(\.scale),
                    range: 0.5 ... 2,
                    valueLabel: { "\(Int(($0 * 100).rounded()))%" }
                )
                SubtitleDoubleSlider(
                    title: "Position",
                    value: styleBinding(\.height),
                    range: 0 ... 100,
                    valueLabel: { "\(Int($0.rounded()))" }
                )
                SubtitleDoubleSlider(
                    title: "Shadow Opacity",
                    value: styleBinding(\.shadowOpacity),
                    range: 0 ... 1,
                    valueLabel: { "\(Int(($0 * 100).rounded()))%" }
                )
                SubtitleDoubleSlider(
                    title: "Shadow Blur",
                    value: styleBinding(\.shadowBlurRadius),
                    range: 0 ... 20,
                    valueLabel: { "\(Int($0.rounded()))" }
                )
                if settings.preferences.playbackSubtitleStyle.background != .none {
                    ColorPicker(
                        "Background Color",
                        selection: hexColorBinding(\.backgroundColorHex),
                        supportsOpacity: false
                    )
                }
            }

            Section("Text") {
                ColorPicker("Text Color", selection: hexColorBinding(\.textColorHex), supportsOpacity: false)
                Toggle("Bold", isOn: styleBinding(\.isBold))
                Toggle("Italic", isOn: styleBinding(\.isItalic))
                Toggle("Outline", isOn: styleBinding(\.outlineEnabled))
                if settings.preferences.playbackSubtitleStyle.outlineEnabled {
                    ColorPicker("Outline Color", selection: hexColorBinding(\.outlineColorHex), supportsOpacity: false)
                    SubtitleDoubleSlider(
                        title: "Outline Width",
                        value: styleBinding(\.outlineSize),
                        range: 0.5 ... 5,
                        valueLabel: { String(format: "%.1f", $0) }
                    )
                }
            }

            Section {
                Button("Reset to Defaults", role: .destructive) { showsResetConfirmation = true }
            }
        }
        .omniaNavigationTitle("Subtitle")
        .confirmationDialog("Reset subtitle preferences?", isPresented: $showsResetConfirmation, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                settings.update {
                    $0.subtitlesEnabled = true
                    $0.preferredSubtitleLanguage = .followSystem
                    $0.subtitleFallbackLanguage = .none
                    $0.sdhPreference = .followSystem
                    $0.playbackSubtitleStyle = .default
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var previewFontTitle: String {
        let name = settings.preferences.playbackSubtitleStyle.fontName
        return name == PlaybackSubtitleStyle.default.fontName ? "System" : name
    }

    private func hexColorBinding(_ keyPath: WritableKeyPath<PlaybackSubtitleStyle, String>) -> Binding<Color> {
        Binding(
            get: { Color(omniaHex: settings.preferences.playbackSubtitleStyle[keyPath: keyPath]) ?? .white },
            set: { color in
                guard let hex = color.omniaHex else { return }
                settings.update { $0.playbackSubtitleStyle[keyPath: keyPath] = hex }
            }
        )
    }

    private func styleBinding<Value>(
        _ keyPath: WritableKeyPath<PlaybackSubtitleStyle, Value>
    ) -> Binding<Value> {
        Binding(
            get: { settings.preferences.playbackSubtitleStyle[keyPath: keyPath] },
            set: { value in
                settings.update { $0.playbackSubtitleStyle[keyPath: keyPath] = value }
            }
        )
    }
    #endif

    @ViewBuilder
    private var customControls: some View {
        Section("Text") {
            SettingsIntSlider(
                title: "Text scale",
                value: customBinding(\.textScalePercent),
                range: 75 ... 200,
                step: 5,
                valueLabel: { "\($0)%" }
            )
            Toggle("Bold", isOn: customBinding(\.isBold))
            Toggle("Italic", isOn: customBinding(\.isItalic))
            SettingsDropdown(
                "Text color",
                selection: customBinding(\.textColor),
                options: Array(SubtitleAppearance.SemanticColor.allCases)
            ) { color in color.title }
        }

        Section("Background & Edge") {
            SettingsIntSlider(
                title: "Background opacity",
                value: customBinding(\.backgroundOpacityPercent),
                range: 0 ... 100,
                step: 5,
                valueLabel: { "\($0)%" }
            )
            SettingsDropdown(
                "Edge style",
                selection: customBinding(\.edgeStyle),
                options: Array(SubtitleAppearance.EdgeStyle.allCases)
            ) { style in style.title }
        }

        Section("Position") {
            SettingsDropdown(
                "Vertical position",
                selection: customBinding(\.position),
                options: Array(SubtitleAppearance.Position.allCases)
            ) { position in position.title }
            SettingsDropdown(
                "Alignment",
                selection: customBinding(\.alignment),
                options: Array(SubtitleAppearance.Alignment.allCases)
            ) { alignment in alignment.title }
            SettingsIntSlider(
                title: "Horizontal margin",
                value: customBinding(\.horizontalMarginPercent),
                range: 0 ... 15,
                step: 1,
                valueLabel: { "\($0)%" }
            )
        }
    }

    private func customBinding<Value>(_ keyPath: WritableKeyPath<SubtitleAppearance, Value>) -> Binding<Value> {
        Binding(
            get: { settings.preferences.customSubtitleAppearance[keyPath: keyPath] },
            set: { value in
                settings.update {
                    $0.subtitleAppearance = .custom
                    $0.customSubtitleAppearance[keyPath: keyPath] = value
                }
            }
        )
    }
}

private struct SettingsIntSlider: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let valueLabel: (Int) -> String

    var body: some View {
        VStack(alignment: .leading) {
            LabeledContent(title, value: valueLabel(value))
            Slider(
                value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                in: Double(range.lowerBound) ... Double(range.upperBound),
                step: Double(step)
            )
            .accessibilityValue(valueLabel(value))
        }
    }
}

#if os(macOS)
struct SubtitleDoubleSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let valueLabel: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(title, value: valueLabel(value))
            Slider(value: $value, in: range)
                .accessibilityValue(valueLabel(value))
        }
    }
}

private struct SubtitleSettingsLanguagePicker: View {
    let title: String
    @Binding var selection: PreferredLanguage
    let includesNone: Bool

    init(_ title: String, selection: Binding<PreferredLanguage>, includesNone: Bool) {
        self.title = title
        _selection = selection
        self.includesNone = includesNone
    }

    var body: some View {
        SettingsDropdown(
            title,
            selection: $selection,
            sections: [
                includesNone ? [.followSystem, PreferredLanguage.none] : [.followSystem],
                PlaybackLanguageCatalog.codes.map { PreferredLanguage.language($0) }
            ]
        ) { language in
            switch language {
            case .followSystem: "Follow System"
            case .none: "Off / No preference"
            case let .language(code): PlaybackLanguageCatalog.name(for: code)
            }
        }
    }
}

private extension PlaybackSubtitleBackground {
    var settingsTitle: String {
        switch self {
        case .none: "None"
        case .translucent: "Translucent"
        case .solid: "Solid"
        }
    }
}
#endif

private extension SubtitleAppearanceMode {
    var title: String {
        switch self {
        case .followSystem: "Follow System"
        case .standard: "Standard"
        case .boxed: "Boxed"
        case .classic: "Classic"
        case .minimal: "Minimal"
        case .bold: "Bold"
        case .custom: "Custom"
        }
    }
}

private extension SubtitleAppearance.SemanticColor {
    var title: String { rawValue.capitalized }
}

private extension SubtitleAppearance.EdgeStyle {
    var title: String {
        switch self {
        case .none: "None"
        case .outline: "Outline"
        case .shadow: "Shadow"
        case .outlineAndShadow: "Outline & Shadow"
        }
    }
}

private extension SubtitleAppearance.Position {
    var title: String { rawValue.capitalized }
}

private extension SubtitleAppearance.Alignment {
    var title: String { rawValue.capitalized }
}
