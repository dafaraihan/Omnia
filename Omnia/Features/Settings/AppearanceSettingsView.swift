import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(OmniaStore.self) private var store
    @Environment(SettingsPreferencesStore.self) private var settings

    var body: some View {
        OmniaSettingsForm {
            Section {
                Picker(
                    "Appearance",
                    selection: Binding(
                        get: { store.appearance },
                        set: { store.appearance = $0 }
                    )
                ) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.inline)
            } footer: {
                Text("Match System follows the appearance selected for this device.")
            }

            Section {
                Toggle(
                    "Show Details Under Posters",
                    isOn: settings.binding(\.showMediaCardLabels)
                )
            } header: {
                Text("Media Cards")
            } footer: {
                Text("Shows each title, release year, and primary genre below standard posters.")
            }

            #if os(macOS)
            Section {
                Picker(
                    "Navigation Style",
                    selection: settings.binding(\.navigationStyle)
                ) {
                    ForEach(MacNavigationStyle.allCases) { style in
                        Label(style.title, systemImage: style.systemImage)
                            .tag(style)
                    }
                }
                .pickerStyle(.inline)
            } header: {
                Text("Navigation")
            } footer: {
                Text("Choose whether Omnia’s main sections appear in a sidebar or a floating top tab bar.")
            }
            #endif
        }
        .omniaNavigationTitle("Appearance")
    }
}

#if os(macOS)
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
#endif
