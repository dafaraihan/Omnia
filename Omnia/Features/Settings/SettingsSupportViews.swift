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

#if os(macOS)
enum MacSettingsLayout {
    static let maximumContentWidth: CGFloat = 680
    static let minimumOuterMargin: CGFloat = 24

    static func contentWidth(for availableWidth: CGFloat) -> CGFloat {
        max(
            0,
            min(
                maximumContentWidth,
                availableWidth - (minimumOuterMargin * 2)
            )
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
            content
                .formStyle(.grouped)
                .frame(width: MacSettingsLayout.contentWidth(for: geometry.size.width))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, MacSettingsLayout.minimumOuterMargin)
        }
    }
}
#endif
