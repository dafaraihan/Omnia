import SwiftUI

/// A settings row that picks one value from a list in a dropdown.
///
/// On macOS the list is drawn by Omnia instead of a system menu, because a
/// system menu always highlights in the Mac's own accent color. Here the
/// current value, the hovered row and the checkmark all follow the accent
/// chosen in Settings › Layout. iOS keeps the native menu picker.
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

    var body: some View {
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
            Text(title)
            if let subtitle { Text(subtitle) }
        }
        .pickerStyle(.menu)
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
            .foregroundStyle(isEnabled ? accent : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(accent.opacity(isHovered || isPresented ? 0.18 : 0.1))
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
                    .fill(isHovered ? accent : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var foreground: Color {
        if isHovered { return accent.prefersDarkForeground ? .black : .white }
        return isSelected ? accent : .primary
    }
}
#endif

extension Color {
    /// True for light colors (white, gold), where white text would be hard
    /// to read.
    var prefersDarkForeground: Bool {
        let resolved = resolve(in: EnvironmentValues())
        let luminance = 0.2126 * Double(resolved.linearRed)
            + 0.7152 * Double(resolved.linearGreen)
            + 0.0722 * Double(resolved.linearBlue)
        return luminance > 0.5
    }
}
