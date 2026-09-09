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
        isAutoSkipEnabled ? nil : "Turn on Show Skip Intro to enable automatic skipping."
    }

    var isUpNextTimingEnabled: Bool { preferences.autoplayNextEpisode }
    var upNextTimingDisabledExplanation: String? {
        isUpNextTimingEnabled ? nil : "Turn on Autoplay Next Episode to choose when Up Next appears."
    }

    var isRetentionEnabled: Bool { preferences.rememberLastSelection }
    var retentionDisabledExplanation: String? {
        isRetentionEnabled ? nil : "Turn on Remember Last Selection to choose its retention period."
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

/// Settings use wide grouped cards on macOS so rows follow the detail column
/// instead of inheriting SwiftUI Form's centered readable-width cap. Mobile
/// platforms retain Form and their existing layout.
struct OmniaSettingsForm<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        #if os(macOS)
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
        .tint(.blue)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #else
        Form {
            content
        }
        #endif
    }
}

#if os(macOS)
enum MacSettingsContainerStyle: Equatable {
    case groupedCards
}

enum MacSettingsSymbolTreatment: Equatable {
    case whiteMonochrome
    case blueMonochrome

    var color: Color {
        switch self {
        case .whiteMonochrome: .white
        case .blueMonochrome: .blue
        }
    }
}

enum MacSettingsInteractionTreatment: Equatable {
    case neutralGray
}

enum MacSettingsPresentation {
    static let containerStyle: MacSettingsContainerStyle = .groupedCards
    static let hoverTreatment: MacSettingsInteractionTreatment = .neutralGray
    static let pressedTreatment: MacSettingsInteractionTreatment = .neutralGray

    static func symbolTreatment(isHovered: Bool, isPressed: Bool) -> MacSettingsSymbolTreatment {
        isHovered || isPressed ? .blueMonochrome : .whiteMonochrome
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
