import SwiftUI

struct UpcomingSettingsView: View {
    @Environment(SettingsPreferencesStore.self) private var settings

    var body: some View {
        OmniaSettingsForm {
            Section {
                Toggle("Show on Home", isOn: settings.binding(\.showUpcoming))
            } footer: {
                Text("Shows future episodes for series saved locally in Omnia.")
            }

            Section("Range") {
                Picker("Days to look ahead", selection: settings.binding(\.upcomingLookAhead)) {
                    ForEach(UpcomingLookAhead.allCases, id: \.self) { value in
                        Text("\(value.rawValue) days").tag(value)
                    }
                }
                Picker("Items", selection: settings.binding(\.upcomingItemLimit)) {
                    ForEach(BoundedItemLimit.allCases, id: \.self) { limit in
                        Text(limit.value.map(String.init) ?? "No limit").tag(limit)
                    }
                }
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
