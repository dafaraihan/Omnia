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
        Form {
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
                Picker("Appearance", selection: settings.binding(\.subtitleAppearance)) {
                    ForEach(SubtitleAppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
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
        .navigationTitle("Subtitle")
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
    }

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
            Picker("Text color", selection: customBinding(\.textColor)) {
                ForEach(SubtitleAppearance.SemanticColor.allCases, id: \.self) { color in
                    Text(color.title).tag(color)
                }
            }
        }

        Section("Background & Edge") {
            SettingsIntSlider(
                title: "Background opacity",
                value: customBinding(\.backgroundOpacityPercent),
                range: 0 ... 100,
                step: 5,
                valueLabel: { "\($0)%" }
            )
            Picker("Edge style", selection: customBinding(\.edgeStyle)) {
                ForEach(SubtitleAppearance.EdgeStyle.allCases, id: \.self) { style in
                    Text(style.title).tag(style)
                }
            }
        }

        Section("Position") {
            Picker("Vertical position", selection: customBinding(\.position)) {
                ForEach(SubtitleAppearance.Position.allCases, id: \.self) { position in
                    Text(position.title).tag(position)
                }
            }
            Picker("Alignment", selection: customBinding(\.alignment)) {
                ForEach(SubtitleAppearance.Alignment.allCases, id: \.self) { alignment in
                    Text(alignment.title).tag(alignment)
                }
            }
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
