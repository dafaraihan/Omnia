import SwiftUI

struct UpcomingSettingsView: View {
    @Environment(SettingsPreferencesStore.self) private var settings

    var body: some View {
        OmniaSettingsForm {
            Section {
                Toggle("Show on Home", isOn: settings.binding(\.showUpcoming))
                .settingsRow("Show on Home")
            } footer: {
                Text("Shows future episodes for series saved locally in Omnia.")
            }

            Section("Range") {
                SettingsDropdown(
                    "Days to look ahead",
                    selection: settings.binding(\.upcomingLookAhead),
                    options: Array(UpcomingLookAhead.allCases)
                ) { value in "\(value.rawValue) days" }
                .settingsRow("Days to look ahead")
                SettingsDropdown(
                    "Items",
                    selection: settings.binding(\.upcomingItemLimit),
                    options: Array(BoundedItemLimit.allCases)
                ) { limit in limit.value.map(String.init) ?? "No limit" }
                .settingsRow("Items")
            }
            .disabled(!settings.preferences.showUpcoming)

            if !settings.preferences.showUpcoming {
                Section {
                    Label("Upcoming is hidden from Home.", systemImage: "eye.slash")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .omniaNavigationTitle("Upcoming")
    }
}
