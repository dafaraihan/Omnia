import SwiftUI

struct UpcomingSettingsView: View {
    @Environment(SettingsPreferencesStore.self) private var settings
    @State private var remindersDenied = false

    var body: some View {
        OmniaSettingsForm {
            Section {
                Toggle("Show on Home", isOn: settings.binding(\.showUpcoming))
            } footer: {
                Text("Shows future episodes for series saved locally in Omnia.")
            }

            Section {
                Toggle(isOn: Binding(
                    get: { settings.preferences.display.episodeNotifications },
                    set: { setReminders($0) }
                )) {
                    Text("New Episode Reminders")
                    Text("A notification on the day a new episode of a saved or in-progress series airs.")
                }
            } footer: {
                if remindersDenied {
                    Text("Notifications are off for Omnia. Turn them on in your device's Settings, then try again.")
                }
            }

            Section("Range") {
                SettingsDropdown(
                    "Days to look ahead",
                    selection: settings.binding(\.upcomingLookAhead),
                    options: Array(UpcomingLookAhead.allCases)
                ) { value in "\(value.rawValue) days" }
                SettingsDropdown(
                    "Items",
                    selection: settings.binding(\.upcomingItemLimit),
                    options: Array(BoundedItemLimit.allCases)
                ) { limit in limit.value.map(String.init) ?? "No limit" }
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
