import SwiftUI

struct SubtitleAppearanceSettingsView: View {
    @Environment(SettingsPreferencesStore.self) private var settings
    @State private var showsResetConfirmation = false

    var body: some View {
        subtitleSettings
    }

    private var subtitleSettings: some View {
        OmniaSettingsForm {
            Section("Language") {
                Toggle("Subtitles Enabled", isOn: settings.binding(\.subtitlesEnabled))
                .settingsRow("Subtitles Enabled")
                LanguagePicker(
                    "Preferred subtitles",
                    selection: settings.binding(\.preferredSubtitleLanguage),
                    includesNone: true
                )
                .settingsRow("Preferred subtitles")
                LanguagePicker(
                    "Subtitle fallback",
                    selection: settings.binding(\.subtitleFallbackLanguage),
                    includesNone: true
                )
                .settingsRow("Subtitle fallback")
                Toggle("Prefer SDH Captions", isOn: Binding(
                    get: { settings.preferences.sdhPreference == .prefer },
                    set: { enabled in
                        settings.update { $0.sdhPreference = enabled ? .prefer : .followSystem }
                    }
                ))
                .settingsRow("Prefer SDH Captions")
                Toggle(isOn: settings.binding(\.playbackBehavior.stripSDHSubtitles)) {
                    Text("Strip SDH Text")
                    Text("Removes sound descriptions and speaker names, like [door creaks].")
                }
                .settingsRow("Strip SDH Text")
                Toggle(isOn: settings.binding(\.playbackBehavior.useForcedSubtitles)) {
                    Text("Use Forced Subtitles")
                    Text("When the audio is in your subtitle language, shows only forced subtitles, such as signs and foreign dialogue.")
                }
                .settingsRow("Use Forced Subtitles")
                Toggle(isOn: settings.binding(\.playbackBehavior.showOnlyPreferredSubtitleLanguages)) {
                    Text("Only Preferred Languages")
                    Text("Add-on subtitles in other languages aren't added to the player.")
                }
                .settingsRow("Only Preferred Languages")
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

            Section {
                SettingsDropdown(
                    "Subtitle Background",
                    selection: styleBinding(\.background),
                    options: Array(PlaybackSubtitleBackground.allCases)
                ) { background in background.settingsTitle }
                .settingsRow("Subtitle Background")
                SubtitleDoubleSlider(
                    title: "Size",
                    value: styleBinding(\.fontSize),
                    range: 14 ... 72,
                    valueLabel: { "\(Int($0.rounded())) pt" }
                )
                .settingsRow("Size")
                SubtitleDoubleSlider(
                    title: "Scale",
                    value: styleBinding(\.scale),
                    range: 0.5 ... 2,
                    valueLabel: { "\(Int(($0 * 100).rounded()))%" }
                )
                .settingsRow("Scale")
                SubtitleDoubleSlider(
                    title: "Position",
                    value: styleBinding(\.height),
                    range: 0 ... 100,
                    valueLabel: { "\(Int($0.rounded()))" }
                )
                .settingsRow("Position")
                SubtitleDoubleSlider(
                    title: "Shadow Opacity",
                    value: styleBinding(\.shadowOpacity),
                    range: 0 ... 1,
                    valueLabel: { "\(Int(($0 * 100).rounded()))%" }
                )
                .settingsRow("Shadow Opacity")
                SubtitleDoubleSlider(
                    title: "Shadow Blur",
                    value: styleBinding(\.shadowBlurRadius),
                    range: 0 ... 20,
                    valueLabel: { "\(Int($0.rounded()))" }
                )
                .settingsRow("Shadow Blur")
                if settings.preferences.playbackSubtitleStyle.background != .none {
                    ColorPicker(
                        "Background Color",
                        selection: hexColorBinding(\.backgroundColorHex),
                        supportsOpacity: false
                    )
                    .settingsRow("Background Color")
                }
            } header: {
                SettingsSectionHeader("Style", resetTitle: "Reset to Defaults", canReset: true) {
                    showsResetConfirmation = true
                }
            }

            Section("Text") {
                ColorPicker("Text Color", selection: hexColorBinding(\.textColorHex), supportsOpacity: false)
                .settingsRow("Text Color")
                Toggle("Bold", isOn: styleBinding(\.isBold))
                .settingsRow("Bold")
                Toggle("Italic", isOn: styleBinding(\.isItalic))
                .settingsRow("Italic")
                Toggle("Outline", isOn: styleBinding(\.outlineEnabled))
                .settingsRow("Outline")
                if settings.preferences.playbackSubtitleStyle.outlineEnabled {
Group {
                    ColorPicker("Outline Color", selection: hexColorBinding(\.outlineColorHex), supportsOpacity: false)
                    .settingsRow("Outline Color")
                    SubtitleDoubleSlider(
                        title: "Outline Width",
                        value: styleBinding(\.outlineSize),
                        range: 0.5 ... 5,
                        valueLabel: { String(format: "%.1f", $0) }
                    )
                    .settingsRow("Outline Width")
                }
.settingsDependentRows()
}
            }

            Section {
                #if OMNIA_MPV
                Toggle(isOn: settings.binding(\.playbackBehavior.autoSyncsSubtitles)) {
                    Text("Auto Sync Subtitles")
                    Text("When an add-on subtitle starts, Omnia listens to the speech for up to three minutes and lines the subtitle up with it. Subtitles inside the video are left as they are.")
                }
                .settingsRow("Auto Sync Subtitles")
                SubtitleDoubleSlider(
                    title: "Subtitle Delay",
                    value: Binding(
                        get: { settings.preferences.playbackSubtitleStyle.delaySeconds },
                        // Tenth-of-a-second steps, like the player's own control.
                        set: { value in
                            settings.update { $0.playbackSubtitleStyle.delaySeconds = (value * 10).rounded() / 10 }
                        }
                    ),
                    range: -10 ... 10,
                    valueLabel: { String(format: "%+.1f s", $0) }
                )
                .settingsRow("Subtitle Delay")
                #endif
            } header: {
                SettingsSectionHeader("Sync and Delay", resetTitle: "Reset Delay", canReset: !(settings.preferences.playbackSubtitleStyle.delaySeconds == 0)) {
                    settings.update { $0.playbackSubtitleStyle.delaySeconds = 0 }

                }
            } footer: {
                Text("The delay applies to every video. A delay set in the player is kept for that title.")
            }

        }
        .settingsPinnedPreview {
            MacSubtitlePlaybackPreview(
                style: settings.preferences.playbackSubtitleStyle,
                height: previewHeight
            )
        }
        .omniaNavigationTitle("Subtitles")
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
            LabeledContent(title) {
                SettingsValueChip(
                    text: valueLabel(value),
                    editText: value.formatted(.number.precision(.fractionLength(0 ... 2)).grouping(.never))
                ) { typed in
                    value = min(max(typed, range.lowerBound), range.upperBound)
                }
            }
            Slider(value: $value, in: range)
                .accessibilityValue(valueLabel(value))
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
