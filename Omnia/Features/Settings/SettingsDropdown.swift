import SwiftUI

/// A settings row that picks one value from a list in a dropdown.
///
/// On macOS the list is drawn by Omnia instead of a system menu, because a
/// system menu always highlights in the Mac's own accent color. Here the
/// current value, the hovered row and the checkmark all follow the accent
/// chosen in Settings › Layout. iOS uses the system menu for the list.
struct SettingsDropdown<Value: Hashable>: View {
    private let title: String
    private let subtitle: String?
    @Binding private var selection: Value
    private let sections: [[Value]]
    private let label: (Value) -> String
    private let systemImage: ((Value) -> String)?

    init(
        _ title: String,
        subtitle: String? = nil,
        selection: Binding<Value>,
        options: [Value],
        systemImage: ((Value) -> String)? = nil,
        label: @escaping (Value) -> String
    ) {
        self.init(title, subtitle: subtitle, selection: selection, sections: [options], systemImage: systemImage, label: label)
    }

    /// Options split into groups, with a divider between each group.
    init(
        _ title: String,
        subtitle: String? = nil,
        selection: Binding<Value>,
        sections: [[Value]],
        systemImage: ((Value) -> String)? = nil,
        label: @escaping (Value) -> String
    ) {
        self.title = title
        self.subtitle = subtitle
        _selection = selection
        self.sections = sections.filter { !$0.isEmpty }
        self.label = label
        self.systemImage = systemImage
    }

    var body: some View { dropdown }

    @ViewBuilder
    private var dropdown: some View {
        // Laid out by hand: a Form's own menu picker drops the value below the
        // title as soon as the subtitle runs long.
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            #if os(macOS)
            // The Mac's own pop-up button: its menu draws every choice in the
            // normal text color, ready to pick.
            Picker(selection: $selection) {
                ForEach(Array(sections.enumerated()), id: \.offset) { index, options in
                    if index > 0 { Divider() }
                    ForEach(options, id: \.self) { option in
                        Text(label(option)).tag(option)
                    }
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(.primary)
            .fixedSize()
            #else
            Menu {
                Picker(selection: $selection) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { index, options in
                        if index > 0 { Divider() }
                        ForEach(options, id: \.self) { option in
                            if let systemImage {
                                Label(label(option), systemImage: systemImage(option)).tag(option)
                            } else {
                                Text(label(option)).tag(option)
                            }
                        }
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 4) {
                    Text(label(selection))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            #endif
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(label(selection))
    }
}
