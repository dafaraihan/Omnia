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
        }
        .omniaNavigationTitle("Appearance")
    }
}
