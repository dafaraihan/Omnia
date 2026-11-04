// Settings on iPad and Mac, as they were before the iPhone redesign.
import SwiftUI

struct LegacySubtitleAppearanceSettingsView: View {
    @Environment(SettingsPreferencesStore.self) private var settings
    @State private var showsResetConfirmation = false
    @State private var showsMenuInPreview = true
    @State private var draftSize: PlayerSizePreferences?

    /// The preview follows a size slider while the drag is still going.
    private var previewDisplay: DisplayPreferences {
        var display = settings.preferences.display
        if let draftSize { display.playerSize = draftSize }
        return display
    }

    private func sizeSlider(
        _ title: String,
        _ keyPath: WritableKeyPath<PlayerSizePreferences, Double>,
        range: ClosedRange<Double> = PlayerSizePreferences.range
    ) -> some View {
        SettingsDeferredSlider(
            title: title,
            value: Binding(
                get: { settings.preferences.display.playerSize[keyPath: keyPath] },
                set: { value in settings.update { $0.display.playerSize[keyPath: keyPath] = value } }
            ),
            range: range,
            onDraft: { value in
                guard let value else { draftSize = nil; return }
                var size = settings.preferences.display.playerSize
                size[keyPath: keyPath] = value
                draftSize = size
            }
        )
    }

    var body: some View {
        subtitleSettings
    }

    private var subtitleSettings: some View {
        OmniaSettingsForm {
            Section("Live Preview") {
                MacSubtitlePlaybackPreview(
                    style: settings.preferences.playbackSubtitleStyle,
                    height: previewHeight,
                    showsMenu: showsMenuInPreview
                )
                .environment(\.displayPreferences, previewDisplay)
                Toggle("Show a Menu in the Preview", isOn: $showsMenuInPreview)
            }

            Section {
                sizeSlider("Controls Size", \.controls)
                sizeSlider("Timeline Length", \.timelineLength, range: 0.5 ... 1)
                sizeSlider("Menu Size", \.menuSize)
                sizeSlider("Menu Width", \.menuWidth)
                sizeSlider("Menu Height", \.menuHeight)
                Button("Reset Player Size") {
                    settings.update { $0.display.playerSize = PlayerSizePreferences() }
                }
                .disabled(settings.preferences.display.playerSize == PlayerSizePreferences())
            } header: {
                Text("Controls and Menus")
            }

            Section("Language") {
                Toggle("Subtitles Enabled", isOn: settings.binding(\.subtitlesEnabled))
                LanguagePicker(
                    "Preferred subtitles",
                    selection: settings.binding(\.preferredSubtitleLanguage),
                    includesNone: true
                )
                LanguagePicker(
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
                Toggle(isOn: settings.binding(\.playbackBehavior.stripSDHSubtitles)) {
                    Text("Strip SDH Text")
                    Text("Removes sound descriptions and speaker names, like [door creaks].")
                }
                Toggle(isOn: settings.binding(\.playbackBehavior.useForcedSubtitles)) {
                    Text("Use Forced Subtitles")
                    Text("When the audio is in your subtitle language, shows only forced subtitles, such as signs and foreign dialogue.")
                }
                Toggle(isOn: settings.binding(\.playbackBehavior.showOnlyPreferredSubtitleLanguages)) {
                    Text("Only Preferred Languages")
                    Text("Add-on subtitles in other languages aren't added to the player.")
                }
                #if OMNIA_MPV
                Toggle(isOn: settings.binding(\.playbackBehavior.autoSyncsSubtitles)) {
                    Text("Auto Sync Subtitles")
                    Text("When an add-on subtitle starts, Omnia listens to the speech for up to three minutes and lines the subtitle up with it. Subtitles inside the video are left as they are.")
                }
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
                Button("Reset Delay") {
                    settings.update { $0.playbackSubtitleStyle.delaySeconds = 0 }
                }
                .disabled(settings.preferences.playbackSubtitleStyle.delaySeconds == 0)
                #endif
            } header: {
                Text("Subtitles")
            } footer: {
                Text("Subtitles from add-ons such as OpenSubtitles are added to the player's list as they arrive. The delay applies to every video; a delay set in the player's Sync panel is kept for that title only, and a positive delay shows subtitles later.")
            }

            Section {
                Button("Reset to Defaults", role: .destructive) { showsResetConfirmation = true }
            }
        }
        .omniaNavigationTitle("Player Appearance")
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

private extension PlaybackSubtitleBackground {
    var settingsTitle: String {
        switch self {
        case .none: "None"
        case .translucent: "Translucent"
        case .solid: "Solid"
        }
    }
}
