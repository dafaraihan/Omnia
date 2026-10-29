import SwiftUI

struct SubtitleAppearanceSettingsView: View {
    @Environment(SettingsPreferencesStore.self) private var settings
    @State private var showsResetConfirmation = false

    var body: some View {
        subtitleSettings
    }

    private var subtitleSettings: some View {
        OmniaSettingsForm {
            Section("Live Preview") {
                MacSubtitlePlaybackPreview(
                    style: settings.preferences.playbackSubtitleStyle,
                    height: previewHeight
                )
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
    private var previewHeight: CGFloat {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone ? 220 : 380
        #else
        380
        #endif
    }
}

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
