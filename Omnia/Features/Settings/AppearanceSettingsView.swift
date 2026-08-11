import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(OmniaStore.self) private var store

    var body: some View {
        Form {
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
        }
        .navigationTitle("Appearance")
    }
}
