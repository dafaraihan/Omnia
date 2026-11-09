import SwiftUI

/// A settings row that picks one value from a list in a dropdown.
///
/// On macOS the list is drawn by Omnia instead of a system menu, because a
/// system menu always highlights in the Mac's own accent color. Text stays in
/// the label colors; only the checkmark on the chosen value takes the accent
/// chosen in Settings › Appearance. iOS uses the system menu for the list.
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
        #if os(macOS)
        MacSettingsDropdown(
            title: title,
            subtitle: subtitle,
            selection: $selection,
            sections: sections,
            label: label,
            systemImage: systemImage
        )
        #else
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
            .fixedSize()
            #endif
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(label(selection))
        #endif
    }
}

#if os(macOS)
private struct MacSettingsDropdown<Value: Hashable>: View {
    @Environment(SettingsPreferencesStore.self) private var settings
    @Environment(\.isEnabled) private var isEnabled

    let title: String
    let subtitle: String?
    @Binding var selection: Value
    let sections: [[Value]]
    let label: (Value) -> String
    let systemImage: ((Value) -> String)?

    @State private var isPresented = false
    @State private var isHovered = false

    private static var rowHeight: CGFloat { 24 }
    private static var maximumListHeight: CGFloat { 360 }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            button
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(label(selection))
    }

    private var accent: Color { settings.preferences.display.accentColor }

    private var button: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage(selection))
                }
                Text(label(selection))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(isEnabled ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isPresented ? 0.16 : isHovered ? 0.11 : 0.06))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            list
        }
    }

    private var list: some View {
        let rows = sections.reduce(0) { $0 + $1.count }
        let dividers = max(sections.count - 1, 0)
        let height = CGFloat(rows) * (Self.rowHeight + 2) + CGFloat(dividers) * 9 + 10

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { index, options in
                        if index > 0 {
                            Divider().padding(.vertical, 4).padding(.horizontal, 6)
                        }
                        ForEach(options, id: \.self) { option in
                            DropdownRow(
                                title: label(option),
                                systemImage: systemImage?(option),
                                isSelected: option == selection,
                                accent: accent,
                                height: Self.rowHeight
                            ) {
                                selection = option
                                isPresented = false
                            }
                            .id(option)
                        }
                    }
                }
                .padding(5)
            }
            .scrollIndicators(height > Self.maximumListHeight ? .automatic : .never)
            .frame(width: listWidth, height: min(height, Self.maximumListHeight))
            .onAppear {
                if height > Self.maximumListHeight {
                    proxy.scrollTo(selection, anchor: .center)
                }
            }
        }
    }

    /// Wide enough for the longest option, within reason.
    private var listWidth: CGFloat {
        let longest = sections.joined().map { label($0).count }.max() ?? 0
        let iconSpace: CGFloat = systemImage == nil ? 0 : 22
        return min(max(CGFloat(longest) * 7.5 + 50 + iconSpace, 160), 340)
    }
}

private struct DropdownRow: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool
    let accent: Color
    let height: CGFloat
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
                    .frame(width: 14)
                    .opacity(isSelected ? 1 : 0)
                if let systemImage {
                    Image(systemName: systemImage)
                        .frame(width: 16)
                }
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.1) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var foreground: Color { .primary }
}
#endif
