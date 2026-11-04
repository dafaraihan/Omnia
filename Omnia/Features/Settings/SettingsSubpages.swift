import SwiftUI

/// Settings › Navigation: the sidebar or top bar, on iPad and Mac.
struct NavigationSettingsView: View {
    @Environment(SettingsPreferencesStore.self) private var settings
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        OmniaSettingsForm {
            Section {
                if showsNavigationStyle {
                    SettingsDropdown(
                        "Navigation Style",
                        selection: settings.binding(\.navigationStyle),
                        options: MacNavigationStyle.allCases,
                        systemImage: \.systemImage
                    ) { $0.title }
                    .settingsRow("Navigation Style")
                }

                if showsBarStyle {
                    SettingsDropdown(
                        barStyleTitle,
                        subtitle: settings.preferences.display.topBarStyle.detail,
                        selection: settings.binding(\.display.topBarStyle),
                        options: TopBarStyle.allCases
                    ) { $0.title }

                    if settings.preferences.display.topBarStyle.isNuvio {
Group {
                        Toggle(isOn: settings.binding(\.display.topBarGlow)) {
                            Text("Glass Glow")
                            Text("Adds soft light around the floating bar while you press or drag it.")
                        }
                        .settingsRow("Glass Glow")
                        SettingsDeferredSlider(title: "Top Bar Size", value: settings.binding(\.display.topBarSize.size), range: TopBarSizePreferences.range)
                        .settingsRow("Top Bar Size")
                        SettingsDeferredSlider(title: "Top Bar Height", value: settings.binding(\.display.topBarSize.height), range: TopBarSizePreferences.range)
                        .settingsRow("Top Bar Height")
                        SettingsDeferredSlider(title: "Top Bar Width", value: settings.binding(\.display.topBarSize.width), range: TopBarSizePreferences.range)
                        .settingsRow("Top Bar Width")
                    }
.settingsDependentRows()
}
                }

            } header: {
                SettingsSectionHeader("Bar", resetTitle: "Reset Top Bar Size", canReset: !(settings.preferences.display.topBarSize == TopBarSizePreferences())) {
                            settings.update { $0.display.topBarSize = TopBarSizePreferences() }

                }
            } footer: {
                Text("Choose a sidebar or a floating bar.")
            }
        }
        .omniaNavigationTitle("Navigation")
    }

    /// A narrow iOS window always uses a tab bar, so only a regular-width
    /// window offers Sidebar or Top Bar.
    private var showsNavigationStyle: Bool {
        #if os(macOS)
        true
        #else
        UIDevice.current.userInterfaceIdiom != .phone && horizontalSizeClass != .compact
        #endif
    }

    private var showsBarStyle: Bool {
        #if os(iOS)
        guard UIDevice.current.userInterfaceIdiom != .phone else { return false }
        #endif
        return !showsNavigationStyle || settings.preferences.navigationStyle == .topBar
    }

    /// iPhone's bar sits at the bottom, so it is a tab bar there.
    private var barStyleTitle: String {
        showsNavigationStyle ? "Top Bar Style" : "Tab Bar Style"
    }

}

private extension MacNavigationStyle {
    var title: String {
        switch self {
        case .sidebar: "Sidebar"
        case .topBar: "Top Bar"
        }
    }

    var systemImage: String {
        switch self {
        case .sidebar: "sidebar.left"
        case .topBar: "rectangle.topthird.inset.filled"
        }
    }
}

/// Settings › Player Controls: the size of the player's controls and menus,
/// and what it shows over the video.
struct PlayerControlsSettingsView: View {
    @Environment(SettingsPreferencesStore.self) private var settings
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
        OmniaSettingsForm {
            Section {
                Toggle("Show a Menu in the Preview", isOn: $showsMenuInPreview)
                sizeSlider("Controls Size", \.controls)
                .settingsRow("Controls Size")
                sizeSlider("Timeline Length", \.timelineLength, range: 0.5 ... 1)
                .settingsRow("Timeline Length")
                sizeSlider("Menu Size", \.menuSize)
                .settingsRow("Menu Size")
                sizeSlider("Menu Width", \.menuWidth)
                .settingsRow("Menu Width")
                sizeSlider("Menu Height", \.menuHeight)
                .settingsRow("Menu Height")
            } header: {
                SettingsSectionHeader("Size", resetTitle: "Reset Player Size", canReset: !(settings.preferences.display.playerSize == PlayerSizePreferences())) {
                    settings.update { $0.display.playerSize = PlayerSizePreferences() }

                }
            }

            Section {
                Toggle(isOn: settings.binding(\.playbackBehavior.showLoadingOverlay)) {
                    Text("Loading Overlay")
                    Text("Shows the title's artwork until the first frame appears.")
                }
                .settingsRow("Loading Overlay")
                Toggle("Show Loading Status", isOn: settings.binding(\.playbackBehavior.showLoadingStatus))
                .settingsRow("Show Loading Status")
                    .disabled(!settings.preferences.playbackBehavior.showLoadingOverlay)
                Toggle(isOn: settings.binding(\.playbackBehavior.showPauseOverlay)) {
                    Text("Pause Overlay")
                    Text("Shows the title's details after five seconds paused.")
                }
                .settingsRow("Pause Overlay")
                SettingsRouteLink(route: .privacy, summary: "Content Warnings")
            } header: {
                Text("Overlays")
            }

            Section {
                // The same setting as Liquid Glass › Player Controls.
                Toggle("Liquid Glass on Player Controls", isOn: settings.binding(\.display.liquidGlass.playerControls))
                .settingsRow("Liquid Glass on Player Controls")
            } header: {
                Text("Glass")
            }
        }
        .settingsPinnedPreview {
            MacSubtitlePlaybackPreview(
                style: settings.preferences.playbackSubtitleStyle,
                height: previewHeight,
                showsMenu: showsMenuInPreview
            )
            .environment(\.displayPreferences, previewDisplay)
        }
        .omniaNavigationTitle("Player Controls")
    }

    private var previewHeight: CGFloat {
        OmniaDevice.isPhone ? 220 : 380
    }
}

/// Settings › Notifications.
struct NotificationsSettingsView: View {
    @Environment(SettingsPreferencesStore.self) private var settings
    @State private var remindersDenied = false

    var body: some View {
        OmniaSettingsForm {
            Section {
                Toggle(isOn: Binding(
                    get: { settings.preferences.display.episodeNotifications },
                    set: { setReminders($0) }
                )) {
                    Text("New Episode Reminders")
                    Text("A notification on the day a new episode of a saved or in-progress series airs.")
                }
                .settingsRow("New Episode Reminders")
            } footer: {
                if remindersDenied {
                    Text("Notifications are off for Omnia. Turn them on in your device's Settings, then try again.")
                }
            }
        }
        .omniaNavigationTitle("Notifications")
    }

    private func setReminders(_ enabled: Bool) {
        Task {
            if enabled {
                let granted = await EpisodeNotifications.requestAuthorization()
                remindersDenied = !granted
                settings.update { $0.display.episodeNotifications = granted }
            } else {
                remindersDenied = false
                settings.update { $0.display.episodeNotifications = false }
                await EpisodeNotifications.cancelAll()
            }
        }
    }
}

/// Settings › Privacy & Security.
struct PrivacySecuritySettingsView: View {
    @Environment(SettingsPreferencesStore.self) private var settings

    var body: some View {
        let lock = DeviceLock.shared
        OmniaSettingsForm {
            Section {
                Toggle(isOn: Binding(
                    get: { lock.locksSettings },
                    set: { enabled in Task { await lock.setLocksSettings(enabled) } }
                )) {
                    Text("Lock Settings")
                    Text("Ask for \(lock.methodName) before opening Settings.")
                }
                .settingsRow("Lock Settings")
                .disabled(!lock.isAvailable)
                Toggle(isOn: Binding(
                    get: { lock.locksProfiles },
                    set: { enabled in Task { await lock.setLocksProfiles(enabled) } }
                )) {
                    Text("Lock Profile Switching")
                    Text("Ask for \(lock.methodName) before changing profile.")
                }
                .settingsRow("Lock Profile Switching")
                .disabled(!lock.isAvailable)
            } header: {
                Text("App Lock")
            } footer: {
                // Stays on this device; it isn't part of the account's sync.
                Text(lock.isAvailable ? "Kept on this device only." : "Set up a device passcode to use App Lock.")
            }

            Section {
                Toggle(isOn: settings.binding(\.playbackBehavior.showContentWarnings)) {
                    Text("Content Warnings")
                    Text("Shows IMDb's parents guide for a few seconds when a title starts. Sends the title's IMDb ID to api.tiffara.com, as Nuvio does.")
                }
                .settingsRow("Content Warnings")
            } header: {
                Text("Player")
            }
        }
        .omniaNavigationTitle("Privacy & Security")
    }
}

/// Settings › Battery & Performance.
struct BatteryPerformanceSettingsView: View {
    @Environment(SettingsPreferencesStore.self) private var settings

    private var behavior: PlaybackBehaviorPreferences { settings.preferences.playbackBehavior }

    var body: some View {
        OmniaSettingsForm {
            Section {
                SettingsDropdown(
                    "Low Power Mode",
                    subtitle: "Turns off hero trailers and Omnia's glass to save battery.",
                    selection: settings.binding(\.display.lowPowerMode),
                    options: LowPowerMode.allCases
                ) { $0.title }
                .settingsRow("Low Power Mode")
            } header: {
                Text("Battery")
            }

            #if OMNIA_MPV || os(macOS)
            Section {
                #if OMNIA_MPV
                SettingsDropdown(
                    "Decoder",
                    selection: settings.binding(\.playbackBehavior.decoderPriority),
                    options: Array(DecoderPriority.allCases)
                ) { priority in priority.title }
                .settingsRow("Decoder")
                #endif
                #if os(macOS)
                Toggle(isOn: settings.binding(\.playbackBehavior.metalRendering)) {
                    Text("Metal Rendering")
                    Text("Draws video with gpu-next on Metal, as Nuvio does, for sharper scaling and HDR tone mapping. If Metal can't start, the player uses OpenGL and notes why in Diagnostics. Applies from the next video.")
                }
                .settingsRow("Metal Rendering")
                #endif
            } header: {
                Text("Video")
            } footer: {
                #if OMNIA_MPV
                Text("\(behavior.decoderPriority.detail) Applies from the next title you play.")
                #endif
            }
            #endif

            #if os(macOS)
            Section {
                Toggle("Hover Preview", isOn: settings.binding(\.display.hoverPreviewEnabled))
                .settingsRow("Hover Preview")
                if settings.preferences.display.hoverPreviewEnabled {
Group {
                    SettingsDropdown(
                        "Hover Preview Delay",
                        selection: settings.binding(\.display.hoverPreviewDelay),
                        options: HoverPreviewDelay.allCases
                    ) { $0.title }
                    .settingsRow("Hover Preview Delay")
                }
.settingsDependentRows()
}
            } header: {
                Text("Browsing")
            } footer: {
                Text("Resting the pointer on a poster previews it.")
            }
            #endif
        }
        .omniaNavigationTitle("Battery & Performance")
    }
}
