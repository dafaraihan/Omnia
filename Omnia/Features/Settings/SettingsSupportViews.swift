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
        #if os(macOS)
        if isRoot {
            rootCards
        } else {
            pageCards
        }
        #else
        Form {
            content
        }
        .modifier(AmoledFormBackground(isActive: usesAmoledBackground))
        .tint(resolvedTint)
        #endif
    }

    private var resolvedTint: Color { tint ?? display.accentColor }

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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
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
                                }
                            }

                            section.footer
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MacSettingsLayout.minimumOuterMargin)
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

    @State private var draft: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            Slider(
                value: Binding(
                    get: { draft ?? value },
                    set: { newValue in
                        draft = newValue
                        onDraft(newValue)
                    }
                ),
                in: range
            ) {
                Text(title)
            } minimumValueLabel: {
                if let minimumLabel { Text(minimumLabel).font(.caption) }
            } maximumValueLabel: {
                if let maximumLabel { Text(maximumLabel).font(.caption) }
            } onEditingChanged: { isEditing in
                guard !isEditing, let draft else { return }
                value = draft
                self.draft = nil
                onDraft(nil)
            }
        }
    }
}
