import SwiftUI

/// Settings › Layout › Streams: Nuvio's stream page options (Fusion style
/// badges, badge position, add-on logo, background) plus Nuvio Enhanced's
/// search bar and pinned sources.
struct StreamsSettingsView: View {
    @Environment(SettingsPreferencesStore.self) private var settings
    @State private var badges = StreamBadgeStore.shared
    @State private var confirmsForget = false
    @State private var badgeURL = ""
    @State private var isImporting = false
    @State private var importingID: String?
    @State private var importError: String?

    private var streams: StreamPagePreferences { settings.preferences.streams }

    let showsAdvanced: Bool

    init(showsAdvanced: Bool = false) {
        self.showsAdvanced = showsAdvanced
    }

    var body: some View {
        Group {
            if showsAdvanced {
                OmniaSettingsForm {
            StreamSelectionSections(advanced: true, confirmsForget: $confirmsForget)
            Section {
                Toggle(isOn: settings.binding(\.streams.showSizeBadges)) {
                    Text("Size Badges")
                    Text("Shows each stream's file size on its card.")
                }
                .settingsRow("Size Badges")
                SettingsDropdown(
                    "Badge Position",
                    subtitle: "Where badges sit on a stream card.",
                    selection: settings.binding(\.streams.badgePlacement),
                    options: StreamPagePreferences.BadgePlacement.allCases
                ) { $0.title }
                .settingsRow("Badge Position")
            } header: {
                Text("Appearance: Badges")
            }

            Section {
                ForEach(badges.imports) { entry in
                    badgeImportRow(entry)
                }

                if badges.imports.count < StreamBadgeStore.importLimit {
                    HStack(spacing: 10) {
                        TextField("Badge URL", text: $badgeURL)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif
                            .onSubmit(importBadges)
                        if isImporting {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Import", action: importBadges)
                                .disabled(badgeURL.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }

                if let importError {
                    Text(importError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Appearance: Badge URLs")
            } footer: {
                Text("Import up to \(StreamBadgeStore.importLimit) Fusion badge lists. The active list adds a badge to every stream whose name or description matches one of its rules.")
            }

            Section {
                SettingsDropdown(
                    "Stream List Background",
                    subtitle: "Cinematic shows the title's backdrop behind the streams.",
                    selection: settings.binding(\.streams.background),
                    options: StreamPagePreferences.Background.allCases
                ) { $0.title }
                .settingsRow("Stream List Background")
                Toggle(isOn: settings.binding(\.streams.showAddonLogo)) {
                    Text("Add-on Logo")
                    Text("Shows the add-on's logo and name on each stream card.")
                }
                .settingsRow("Add-on Logo")
                Toggle(isOn: settings.binding(\.streams.showsSearchBar)) {
                    Text("Search Bar")
                    Text("Adds a field that filters streams by every word you type.")
                }
                .settingsRow("Search Bar")
            } header: {
                Text("Appearance: Stream List")
            }

            if !streams.pinnedSourceIDs.isEmpty {
                Section {
                    LabeledContent("Pinned Sources", value: "\(streams.pinnedSourceIDs.count)")
                    Button("Unpin All Sources", role: .destructive) {
                        settings.update { $0.streams.pinnedSourceIDs = [] }
                    }
                    .settingsRow("Unpin All Sources")
                } header: {
                    Text("Pinned")
                } footer: {
                    Text("Press and hold or right-click a stream to pin it.")
                }
            }
        
                }
            } else {
                OmniaSettingsForm {
            StreamSelectionSections(advanced: false, confirmsForget: $confirmsForget)
            Section {
                SettingsRouteLink(route: .advanced(.streams), summary: nil)
            }
                }
            }
        }
        .confirmationDialog(
            "Forget saved links and releases?",
            isPresented: $confirmsForget,
            titleVisibility: .visible
        ) {
            Button("Forget", role: .destructive) {
                StreamLinkCacheStore().removeAll()
                BingeGroupCacheStore().removeAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Titles will look up their sources again the next time you play them.")
        }
        .omniaNavigationTitle(showsAdvanced ? "Advanced" : "Streams")
    }

    private func badgeImportRow(_ entry: StreamBadgeImport) -> some View {
        let isActive = badges.activeImport?.id == entry.id
        return HStack(spacing: 12) {
            Button {
                badges.activate(entry)
            } label: {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isActive ? "Active" : "Use \(entry.displayHost)")

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayHost)
                    .fontWeight(.medium)
                Text(summary(for: entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if importingID == entry.id {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    refresh(entry)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
                .accessibilityLabel("Refresh \(entry.displayHost)")
                .disabled(importingID != nil || isImporting)
            }

            Button(role: .destructive) {
                badges.remove(entry)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove")
            .accessibilityLabel("Remove \(entry.displayHost)")
        }
    }

    private func summary(for entry: StreamBadgeImport) -> String {
        var parts = ["\(entry.enabledFilterCount) badges"]
        if entry.groupCount > 0 { parts.append("\(entry.groupCount) groups") }
        parts.append("Updated \(entry.importedAt.formatted(.relative(presentation: .named)))")
        return parts.joined(separator: " · ")
    }

    private func importBadges() {
        let text = badgeURL
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, !isImporting else { return }
        isImporting = true
        importError = nil
        Task {
            do {
                try await badges.importRules(from: text)
                badgeURL = ""
            } catch {
                importError = error.localizedDescription
            }
            isImporting = false
        }
    }

    private func refresh(_ entry: StreamBadgeImport) {
        importingID = entry.id
        importError = nil
        Task {
            do {
                try await badges.importRules(from: entry.sourceURL)
            } catch {
                importError = error.localizedDescription
            }
            importingID = nil
        }
    }
}
