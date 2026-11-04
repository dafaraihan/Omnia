import Foundation
import SwiftUI

struct SettingsConfirmation<Action> {
    private(set) var pending: Action?

    mutating func request(_ action: Action) {
        pending = action
    }

    mutating func cancel() {
        pending = nil
    }

    mutating func confirm() -> Action? {
        defer { pending = nil }
        return pending
    }
}

struct VideoPlayerSettingsModel: Equatable, Sendable {
    let preferences: SettingsPreferences

    var isAutoSkipEnabled: Bool { preferences.showSkipIntro }
    var autoSkipDisabledExplanation: String? {
        isAutoSkipEnabled ? nil : "Turn on Skip Intro, Recap and Credits to skip segments automatically."
    }
}

struct SubtitleAppearanceSettingsModel: Equatable, Sendable {
    var mode: SubtitleAppearanceMode
    var custom: SubtitleAppearance
    private var resetConfirmation: UUID?

    init(mode: SubtitleAppearanceMode, custom: SubtitleAppearance) {
        self.mode = mode
        self.custom = custom.normalized
    }

    var usesCustomControls: Bool { mode == .custom }

    var resolvedAppearance: SubtitleAppearance {
        var preferences = SettingsPreferences.default
        preferences.subtitleAppearance = mode
        preferences.customSubtitleAppearance = custom
        return preferences.resolvedSubtitleAppearance
    }

    mutating func updateCustom(_ update: (inout SubtitleAppearance) -> Void) {
        update(&custom)
        custom = custom.normalized
        mode = .custom
    }

    mutating func makeResetConfirmation() -> UUID {
        let confirmation = UUID()
        resetConfirmation = confirmation
        return confirmation
    }

    mutating func reset(confirmation: UUID) -> Bool {
        guard confirmation == resetConfirmation else { return false }
        mode = .followSystem
        custom = .default
        resetConfirmation = nil
        return true
    }
}

extension Binding where Value == SettingsPreferences {
    func member<T>(_ keyPath: WritableKeyPath<SettingsPreferences, T>) -> Binding<T> {
        Binding<T>(
            get: { wrappedValue[keyPath: keyPath] },
            set: { newValue in
                var preferences = wrappedValue
                preferences[keyPath: keyPath] = newValue
                wrappedValue = preferences
            }
        )
    }
}

extension SettingsPreferencesStore {
    func binding<T>(_ keyPath: WritableKeyPath<SettingsPreferences, T>) -> Binding<T> {
        Binding(
            get: { self.preferences[keyPath: keyPath] },
            set: { value in self.update { $0[keyPath: keyPath] = value } }
        )
    }
}

/// On macOS every Settings page, the root and its sub-pages, draws Omnia's
/// own grouped cards across the full width of the window, because a grouped
/// `Form` keeps a narrow centered column. Rows keep the Form layout: label
/// leading, control trailing, details under the label. Mobile platforms use
/// Form throughout.
struct OmniaSettingsForm<Content: View>: View {
    private let content: Content
    private let tint: Color?
    private let isRoot: Bool
    @Environment(SettingsPreferencesStore.self) private var settings: SettingsPreferencesStore?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.settingsPreviewModel) private var previewModel
    @Environment(\.settingsPreviewInColumn) private var previewInColumn
    @Environment(\.displayPreferences) private var display
    @Environment(\.colorScheme) private var colorScheme

    /// Forms follow the accent chosen in Settings › Appearance unless a
    /// page passes its own tint.
    init(tint: Color? = nil, isRoot: Bool = false, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.isRoot = isRoot
        self.content = content()
    }

    var body: some View {
        form
            // Rows that depend on a switch slide in with it.
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: OmniaDevice.isPhone ? settings?.preferences : nil)
    }

    @ViewBuilder
    private var form: some View {
        #if os(macOS)
        if isRoot {
            rootCards
        } else {
            pageCards
        }
        #else
        ScrollViewReader { proxy in
            Form {
                if previewInColumn {
                    // Reads each section's preview, and dims or marks its rows.
                    Group(sections: content) { sections in
                        ForEach(sections) { section in
                            Section {
                                section.content
                                    .modifier(SettingsSectionFocus(kind: section.containerValues.settingsPreviewSection))
                                    .listRowBackground(rowBackground(for: section.containerValues.settingsPreviewSection))
                            } header: {
                                section.header
                            } footer: {
                                section.footer
                            }
                        }
                    }
                } else {
                    content
                }
            }
            .modifier(SettingsFocusScroller(proxy: proxy))
        }
        .modifier(AmoledFormBackground(isActive: usesAmoledBackground))
        .tint(resolvedTint)
        #endif
    }

    private var resolvedTint: Color { tint ?? display.accentColor }

    private func isActive(_ kind: SettingsPreviewKind?) -> Bool {
        previewInColumn && kind != nil && previewModel?.activeSection == kind
    }

    #if os(iOS)
    /// A grouped Form can't outline a section, so its rows take the accent.
    private func rowBackground(for kind: SettingsPreviewKind?) -> Color? {
        isActive(kind) ? resolvedTint.opacity(0.18) : nil
    }
    #endif

    private var usesAmoledBackground: Bool {
        display.amoledBlack && colorScheme == .dark
    }

    #if os(macOS)
    private var rootCards: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Group(sections: content) { sections in
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            section.header
                                .font(.caption.weight(.semibold))
                                .textCase(.uppercase)
                                .foregroundStyle(.secondary)

                            Group(subviews: section.content) { rows in
                                VStack(spacing: 0) {
                                    ForEach(rows) { row in
                                        MacSettingsInteractiveRow {
                                            row
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 9)
                                                .focusEffectDisabled()
                                        }

                                        if row.id != rows.last?.id {
                                            Divider()
                                                .padding(.leading, 12)
                                        }
                                    }
                                }
                                .background {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.primary.opacity(0.065))
                                }
                                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                            }

                            section.footer
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, MacSettingsLayout.minimumOuterMargin)
        }
        .scrollIndicators(.automatic)
        .modifier(TopBarScrollReporting(destination: .settings))
        .tint(resolvedTint)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Sub-pages: the root's cards, with Form-style rows for switches,
    /// values and pickers, at the root's width and margins.
    private var pageCards: some View {
        ScrollViewReader { proxy in
        ScrollView {
            // Not lazy, so search can scroll to a row that's still off screen.
            VStack(alignment: .leading, spacing: 20) {
                Group(sections: content) { sections in
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            section.header
                                .font(.caption.weight(.semibold))
                                .textCase(.uppercase)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)

                            Group(subviews: section.content) { rows in
                                if !rows.isEmpty {
                                    VStack(spacing: 0) {
                                        ForEach(rows) { row in
                                            MacSettingsInteractiveRow {
                                                row
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 9)
                                                    .focusEffectDisabled()
                                            }

                                            if row.id != rows.last?.id {
                                                Divider()
                                                    .padding(.leading, 12)
                                            }
                                        }
                                    }
                                    .background {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.primary.opacity(0.065))
                                    }
                                    .clipShape(.rect(cornerRadius: 12, style: .continuous))
                                    .overlay {
                                        if isActive(section.containerValues.settingsPreviewSection) {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .strokeBorder(resolvedTint, lineWidth: 2)
                                        }
                                    }
                                }
                            }

                            section.footer
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                        }
                        .modifier(SettingsSectionFocus(kind: section.containerValues.settingsPreviewSection))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MacSettingsLayout.minimumOuterMargin)
        }
        .modifier(SettingsFocusScroller(proxy: proxy))
        }
        .scrollIndicators(.automatic)
        .toggleStyle(MacSettingsRowToggleStyle())
        .labeledContentStyle(MacSettingsRowLabeledContentStyle())
        .background(usesAmoledBackground ? Color.black : Color.clear)
        .tint(resolvedTint)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    #endif
}

/// AMOLED Black draws Settings pages on true black in Dark appearance.
private struct AmoledFormBackground: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content
                .scrollContentBackground(.hidden)
                .background(Color.black)
        } else {
            content
        }
    }
}

/// A Form row whose switch shares the row with other controls, such as a
/// drag handle and a menu: the label fills the row and the switch sits at its
/// trailing edge, as a plain Toggle in a grouped Form does.
struct TrailingSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(isOn: configuration.$isOn) {
                configuration.label
            }
            .toggleStyle(.switch)
            .labelsHidden()
        }
    }
}

private struct SettingsUsesNativeFormKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True inside a settings sub-page's native Form, where links and rows
    /// take the system's own styling.
    var settingsUsesNativeForm: Bool {
        get { self[SettingsUsesNativeFormKey.self] }
        set { self[SettingsUsesNativeFormKey.self] = newValue }
    }
}

extension View {
    /// A NavigationLink drawn as a full Settings row with a trailing
    /// chevron, as Form draws it. Only macOS needs it; elsewhere the Form
    /// draws the row.
    func settingsLinkRow() -> some View {
        #if os(macOS)
        buttonStyle(MacSettingsLinkRowStyle())
        #else
        self
        #endif
    }
}

#if os(macOS)
enum MacSettingsContainerStyle: Equatable {
    case groupedCards
}

enum MacSettingsSymbolTreatment: Equatable {
    case whiteMonochrome

    var color: Color {
        .white
    }
}

enum MacSettingsInteractionTreatment: Equatable {
    case neutralGray
}

enum MacSettingsPresentation {
    static let containerStyle: MacSettingsContainerStyle = .groupedCards
    static let hoverTreatment: MacSettingsInteractionTreatment = .neutralGray
    static let pressedTreatment: MacSettingsInteractionTreatment = .neutralGray
    static let searchWidth: CGFloat = 320

    static func symbolTreatment(isHovered: Bool, isPressed: Bool) -> MacSettingsSymbolTreatment {
        .whiteMonochrome
    }
}

private struct MacSettingsSymbolTreatmentKey: EnvironmentKey {
    static let defaultValue: MacSettingsSymbolTreatment = .whiteMonochrome
}

extension EnvironmentValues {
    var macSettingsSymbolTreatment: MacSettingsSymbolTreatment {
        get { self[MacSettingsSymbolTreatmentKey.self] }
        set { self[MacSettingsSymbolTreatmentKey.self] = newValue }
    }
}

struct MacSettingsSymbolImage: View {
    let systemName: String
    @Environment(\.macSettingsSymbolTreatment) private var treatment

    var body: some View {
        Image(systemName: systemName)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(treatment.color)
    }
}

private struct MacSettingsLinkRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
/// A Form-style switch row outside a Form: the first line of the label as
/// the title, any further lines as caption details, the switch trailing.
struct MacSettingsRowToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Group(subviews: configuration.label) { lines in
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        if index == 0 {
                            line
                        } else {
                            line
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(isOn: configuration.$isOn) {
                configuration.label
            }
            .toggleStyle(.switch)
            .labelsHidden()
        }
    }
}

/// Label leading and value trailing, as a grouped Form draws it.
struct MacSettingsRowLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 12)
            configuration.content
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct MacSettingsInteractiveRow<Content: View>: View {
    private let content: Content
    @State private var isHovered = false

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let treatment = MacSettingsPresentation.symbolTreatment(
            isHovered: isHovered,
            isPressed: false
        )
        content
            .environment(\.macSettingsSymbolTreatment, treatment)
            .labelStyle(MacSettingsLabelStyle(treatment: treatment))
            .onHover { isHovered = $0 }
    }
}

private struct MacSettingsLabelStyle: LabelStyle {
    let treatment: MacSettingsSymbolTreatment

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 7) {
            configuration.icon
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(treatment.color)
            configuration.title
        }
    }
}

enum MacSettingsLayout {
    struct Presentation: Equatable {
        let leadingOffset: CGFloat
        let contentWidth: CGFloat
        let rowWidth: CGFloat
    }

    static let minimumOuterMargin: CGFloat = 24
    static let leadingOffset: CGFloat = minimumOuterMargin

    static func presentation(for availableWidth: CGFloat) -> Presentation {
        let width = max(0, availableWidth - (minimumOuterMargin * 2))
        return Presentation(
            leadingOffset: leadingOffset,
            contentWidth: width,
            rowWidth: width
        )
    }
}

struct MacSettingsContentContainer<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            let presentation = MacSettingsLayout.presentation(for: geometry.size.width)
            content
                .frame(width: presentation.contentWidth)
                .padding(.horizontal, MacSettingsLayout.minimumOuterMargin)
                .padding(.top, MacSettingsLayout.minimumOuterMargin)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
#endif

/// Writes to Settings when the drag ends: saving on every step redraws the
/// whole app and made sliders lag. `onDraft` carries the value for a preview.
struct SettingsDeferredSlider: View {
    let title: String
    var minimumLabel: String?
    var maximumLabel: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    var onDraft: (Double?) -> Void = { _ in }
    /// Shows the drag in the preview column.
    var previewKeyPath: WritableKeyPath<DisplayPreferences, Double>?

    @Environment(\.settingsPreviewModel) private var previewModel
    @Environment(\.settingsPreviewInColumn) private var inColumn
    @Environment(\.settingsSectionKind) private var sectionKind

    @State private var draft: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                SettingsValueChip(
                    text: valueText,
                    editText: "\(Int(((draft ?? value) * 100).rounded()))"
                ) { typed in
                    value = min(max(typed / 100, range.lowerBound), range.upperBound)
                }
            }
            HStack(spacing: 10) {
                if let minimumLabel { Text(minimumLabel).font(.caption) }
                Slider(
                    value: Binding(
                        get: { draft ?? value },
                        set: { newValue in
                            draft = newValue
                            onDraft(newValue)
                            if let previewKeyPath { previewModel?.setDraft(previewKeyPath, newValue) }
                            if inColumn { previewModel?.activate(sectionKind) }
                        }
                    ),
                    in: range
                ) {
                    Text(title)
                } onEditingChanged: { isEditing in
                    guard !isEditing, let draft else { return }
                    value = draft
                    self.draft = nil
                    onDraft(nil)
                    if let previewKeyPath { previewModel?.setDraft(previewKeyPath, nil) }
                }
                // The title and value are above; macOS would repeat the title here.
                .labelsHidden()
                .accessibilityValue(valueText)
                if let maximumLabel { Text(maximumLabel).font(.caption) }
            }
        }
    }

    private var valueText: String {
        "\(Int(((draft ?? value) * 100).rounded()))%"
    }
}

private struct SettingsFocusRowKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// The row a search result is opening its page to.
    var settingsFocusRow: String? {
        get { self[SettingsFocusRowKey.self] }
        set { self[SettingsFocusRowKey.self] = newValue }
    }
}

/// Lets search scroll to this row, and marks it for a moment when it does.
private struct SettingsRowAnchor: ViewModifier {
    let title: String
    @Environment(\.settingsFocusRow) private var focus
    @Environment(\.displayPreferences) private var display
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHighlighted = false

    func body(content: Content) -> some View {
        content
            .id(title)
            .background {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(display.accentColor.opacity(0.28))
                        .padding(-6)
                        .transition(.opacity)
                }
            }
            .task(id: focus == title) {
                guard focus == title else { return }
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { isHighlighted = true }
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) { isHighlighted = false }
            }
    }
}

extension View {
    func settingsRow(_ title: String) -> some View {
        modifier(SettingsRowAnchor(title: title))
    }
}

/// Takes a page to the row search asked for.
private struct SettingsFocusScroller: ViewModifier {
    let proxy: ScrollViewProxy
    @Environment(\.settingsFocusRow) private var focus

    func body(content: Content) -> some View {
        content.task(id: focus) {
            guard let focus else { return }
            // The page is still being pushed, and may open a hidden section.
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation { proxy.scrollTo(focus, anchor: .center) }
        }
    }
}

/// A slider's value. Tap it to type a number.
struct SettingsValueChip: View {
    let text: String
    let editText: String
    let onCommit: (Double) -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        if OmniaDevice.isPhone {
            chip
        } else {
            Text(text)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var chip: some View {
        Group {
            if isEditing {
                TextField("Value", text: $draft)
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .focused($isFocused)
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
                    .frame(width: 56)
                    .onSubmit(commit)
                    .onChange(of: isFocused) { _, focused in
                        if !focused { commit() }
                    }
                    .onAppear { isFocused = true }
            } else {
                Button {
                    draft = editText
                    isEditing = true
                } label: {
                    Text(text)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Type a value")
            }
        }
        .font(.subheadline.monospacedDigit())
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.primary.opacity(0.08), in: Capsule())
    }

    private func commit() {
        guard isEditing else { return }
        isEditing = false
        if let value = Double(draft.replacingOccurrences(of: ",", with: ".")) { onCommit(value) }
    }
}

/// A section title with its reset in a "…" menu, out of the way of the rows.
struct SettingsSectionHeader: View {
    let title: String
    let resetTitle: String
    let canReset: Bool
    let reset: () -> Void

    init(_ title: String, resetTitle: String, canReset: Bool, reset: @escaping () -> Void) {
        self.title = title
        self.resetTitle = resetTitle
        self.canReset = canReset
        self.reset = reset
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Menu {
                Button(resetTitle, role: .destructive, action: reset)
                    .disabled(!canReset)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.large)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More for \(title)")
        }
        .settingsRow(resetTitle)
    }
}

private struct SettingsPinnedPreview<Preview: View>: ViewModifier {
    @ViewBuilder let preview: () -> Preview
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            // A phone on its side has no room to keep it on screen.
            if verticalSizeClass != .compact || !OmniaDevice.isPhone {
                preview()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background { OmniaPageBackground().ignoresSafeArea() }
            }
        }
    }
}

extension View {
    /// Rows that only show when another option is on.
    func settingsDependentRows() -> some View {
        padding(.leading, 14)
            .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Keeps a live preview on screen while the options scroll under it.
    func settingsPinnedPreview<Preview: View>(@ViewBuilder _ preview: @escaping () -> Preview) -> some View {
        modifier(SettingsPinnedPreview(preview: preview))
    }
}
