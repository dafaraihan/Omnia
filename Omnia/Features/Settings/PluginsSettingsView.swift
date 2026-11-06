//
//  PluginsSettingsView.swift
//  Omnia
//

import SwiftUI

/// Settings › Plugins: Nuvio-format plugin repositories. Each plugin is a
/// script that finds streams for a title; its sources appear after the
/// add-ons' in the source list.
struct PluginsSettingsView: View {
    @Environment(PluginStore.self) private var plugins
    @State private var repositoryInput = ""
    @State private var isAdding = false
    @State private var addError: String?
    @State private var tmdbKeyDraft = ""
    @State private var repositoryToRemove: PluginRepository?
    @State private var testing: Set<String> = []
    @State private var testResults: [String: String] = [:]
    @State private var settingsScraper: PluginScraper?

    let showsAdvanced: Bool

    init(showsAdvanced: Bool = false) {
        self.showsAdvanced = showsAdvanced
    }

    var body: some View {
        Group {
            if showsAdvanced {
                OmniaSettingsForm {
            Section {
                Toggle(isOn: Binding(get: { plugins.groupsByRepository }, set: { plugins.setGroupsByRepository($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Group Plugin Providers by Repository")
                        Text("In Streams, show one provider per repository instead of one per plugin.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .settingsRow("Group Plugin Providers by Repository")
                .disabled(!plugins.pluginsEnabled)
            }
                }
            } else {
                OmniaSettingsForm {
            Section {
                Toggle(isOn: Binding(get: { plugins.pluginsEnabled }, set: { plugins.setPluginsEnabled($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use Plugins")
                        Text("Plugins search for streams when you choose a source. Only install repositories you trust: their code runs on this device and can reach any website.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .settingsRow("Use Plugins")


            }

            Section {
                HStack {
                    TextField("Repository URL", text: $repositoryInput, prompt: Text(verbatim: "https://example.com/manifest.json"))
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .onSubmit(addRepository)
                    if isAdding {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Add", action: addRepository)
                            .disabled(repositoryInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if let addError {
                    Label(addError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Add Repository")
            } footer: {
                Text("A repository is a manifest.json that lists plugins, in the format Nuvio uses. Omnia checks installed repositories for updates every six hours.")
            }

            if plugins.repositories.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Repositories",
                        systemImage: "shippingbox",
                        description: Text("Add a plugin repository's address above.")
                    )
                }
            }

            ForEach(plugins.repositories) { repository in
                repositorySection(repository)
            }

            Section {
                HStack {
                    SecureField("TMDB API Key", text: $tmdbKeyDraft, prompt: Text(plugins.hasTMDBKey ? "Saved" : "Optional"))
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .onSubmit(saveTMDBKey)
                    Button(plugins.hasTMDBKey && tmdbKeyDraft.isEmpty ? "Remove" : "Save", action: saveTMDBKey)
                        .disabled(!plugins.hasTMDBKey && tmdbKeyDraft.isEmpty)
                }
            } header: {
                Text("TMDB")
            } footer: {
                Text("Many plugins look titles up on TMDB. Some include their own key; others need yours. It's kept in your Keychain and only given to plugins.")
            }

            Section {
                SettingsRouteLink(route: .advanced(.plugins), summary: nil)
            }
                }
            }
        }
        .omniaNavigationTitle(showsAdvanced ? "Advanced" : "Plugins")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                OmniaToolbarSymbol {
                Button("Refresh All", systemImage: "arrow.clockwise") {
                    Task { await plugins.refreshAll() }
                }
                .disabled(plugins.repositories.isEmpty || !plugins.refreshing.isEmpty)
                }
            }
        }
        .confirmationDialog(
            "Remove \(repositoryToRemove?.name ?? "Repository")?",
            isPresented: Binding(get: { repositoryToRemove != nil }, set: { if !$0 { repositoryToRemove = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let repositoryToRemove { plugins.removeRepository(repositoryToRemove) }
                repositoryToRemove = nil
            }
        } message: {
            Text("Its plugins and their settings are removed from Omnia.")
        }
        .sheet(item: $settingsScraper) { scraper in
            PluginSettingsSheet(scraper: scraper)
        }
    }

    // MARK: Sections

    private func repositorySection(_ repository: PluginRepository) -> some View {
        let scrapers = plugins.scrapers(in: repository)
        return Section {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(repositorySummary(repository, count: scrapers.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let description = repository.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let error = plugins.errors[repository.id] {
                        Label("Couldn't refresh: \(error)", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                if plugins.refreshing.contains(repository.id) {
                    ProgressView().controlSize(.small)
                }
            }
            ForEach(scrapers) { scraper in
                scraperRow(scraper)
            }
            HStack {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await plugins.refresh(repository) }
                }
                .disabled(plugins.refreshing.contains(repository.id))
                Spacer()
                Button("Remove…", systemImage: "trash", role: .destructive) {
                    repositoryToRemove = repository
                }
            }
            // Borderless on iOS too: in a Form a tap on the row fires every
            // button in it.
            .buttonStyle(.borderless)
        } header: {
            Text(repository.name)
        }
    }

    private func scraperRow(_ scraper: PluginScraper) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { scraper.isEnabled }, set: { plugins.setEnabled($0, for: scraper) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(scraper.name)
                    Text(scraperSummary(scraper))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !scraper.description.isEmpty {
                        Text(scraper.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    if !scraper.manifestEnabled {
                        Text("Turned off by the repository.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .settingsRow("Turned off by the repository.")
            .disabled(!scraper.manifestEnabled || !plugins.pluginsEnabled)

            HStack(spacing: 12) {
                if scraper.hasSettings {
                    Button("Settings…", systemImage: "slider.horizontal.3") { settingsScraper = scraper }
                }
                Button("Test", systemImage: "play.circle") { test(scraper) }
                    .disabled(testing.contains(scraper.id))
                if testing.contains(scraper.id) {
                    ProgressView().controlSize(.small)
                } else if let result = testResults[scraper.id] {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            #if os(iOS)
            .buttonStyle(.borderless)
            #endif
            .font(.callout)
            #if os(macOS)
            .buttonStyle(.borderless)
            #endif
        }
        .padding(.vertical, 2)
    }

    // MARK: Actions

    private func addRepository() {
        let input = repositoryInput
        guard !input.trimmingCharacters(in: .whitespaces).isEmpty, !isAdding else { return }
        isAdding = true
        addError = nil
        Task {
            do {
                try await plugins.addRepository(input)
                repositoryInput = ""
            } catch {
                addError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isAdding = false
        }
    }

    private func saveTMDBKey() {
        plugins.setTMDBAPIKey(tmdbKeyDraft)
        tmdbKeyDraft = ""
    }

    private func test(_ scraper: PluginScraper) {
        testing.insert(scraper.id)
        testResults[scraper.id] = nil
        Task {
            do {
                let outcome = try await plugins.test(scraper)
                let results = outcome.results
                let title = scraper.supports(type: "movie") ? "The Matrix" : "Game of Thrones S1 E1"
                testResults[scraper.id] = results.isEmpty
                    ? "Found nothing for \(title)." + (outcome.problem.map { " Last problem: \($0)" } ?? "")
                    : "Found \(results.count) \(results.count == 1 ? "stream" : "streams") for \(title)."
            } catch {
                testResults[scraper.id] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            testing.remove(scraper.id)
        }
    }

    // MARK: Text

    private func repositorySummary(_ repository: PluginRepository, count: Int) -> String {
        var parts: [String] = []
        if let version = repository.version { parts.append("Version \(version)") }
        if let author = repository.author, !author.isEmpty { parts.append("by \(author)") }
        parts.append(count == 1 ? "1 plugin" : "\(count) plugins")
        if let updated = repository.lastUpdated {
            parts.append("updated \(updated.formatted(.relative(presentation: .named)))")
        }
        // Only the host: a repository address can carry a private key.
        if let host = repository.manifestURL.host() { parts.append(host) }
        return parts.joined(separator: " · ")
    }

    private func scraperSummary(_ scraper: PluginScraper) -> String {
        var types: [String] = []
        for type in scraper.supportedTypes {
            let label = PluginScraper.normalizedType(type) == "tv" ? "Series" : type.capitalized
            if !types.contains(label) { types.append(label) }
        }
        var parts = ["Version \(scraper.version)", types.joined(separator: ", ")]
        if !scraper.contentLanguage.isEmpty {
            parts.append(scraper.contentLanguage.map { $0.uppercased() }.joined(separator: ", "))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// The settings a plugin describes with `onSettings()`.
private struct PluginSettingsSheet: View {
    let scraper: PluginScraper

    @Environment(PluginStore.self) private var plugins
    @Environment(\.dismiss) private var dismiss
    @State private var fields: [PluginSettingsField] = []
    @State private var text: [String: String] = [:]
    @State private var toggles: [String: Bool] = [:]
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Form {
                if isLoading {
                    OmniaLoadingRow("Loading Settings…")
                        .frame(maxWidth: .infinity)
                } else if let loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else if fields.isEmpty {
                    Text("This plugin has no settings.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(fields) { field in
                        fieldView(field)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(scraper.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(isLoading || fields.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
        .task { await load() }
    }

    @ViewBuilder
    private func fieldView(_ field: PluginSettingsField) -> some View {
        switch field.kind {
        case .header:
            Text(field.label).font(.headline)
        case .info:
            VStack(alignment: .leading, spacing: 2) {
                if !field.label.isEmpty { Text(field.label) }
                if let detail = field.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        case let .text(placeholder, isSecure):
            VStack(alignment: .leading, spacing: 2) {
                if isSecure {
                    SecureField(field.label, text: textBinding(field), prompt: placeholder.map { Text($0) })
                } else {
                    TextField(field.label, text: textBinding(field), prompt: placeholder.map { Text($0) })
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                }
                if let detail = field.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        case let .select(options):
            SettingsDropdown(
                field.label,
                selection: textBinding(field),
                options: options.map(\.value)
            ) { value in
                options.first { $0.value == value }?.label ?? value
            }
        case .toggle:
            Toggle(isOn: Binding(get: { toggles[field.key] ?? false }, set: { toggles[field.key] = $0 })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.label)
                    if let detail = field.detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func textBinding(_ field: PluginSettingsField) -> Binding<String> {
        Binding(get: { text[field.key] ?? "" }, set: { text[field.key] = $0 })
    }

    private func load() async {
        guard let configuration = plugins.configuration(for: scraper) else {
            loadError = "This plugin's code is missing. Refresh its repository."
            isLoading = false
            return
        }
        do {
            fields = try await PluginRuntime.settingsLayout(configuration)
            let saved = plugins.settingsValues(for: scraper)
            for field in fields where !field.key.isEmpty {
                switch field.kind {
                case .toggle:
                    toggles[field.key] = (saved[field.key] as? Bool) ?? field.defaultBool ?? false
                case .text, .select:
                    text[field.key] = (saved[field.key] as? String)
                        ?? (saved[field.key] as? NSNumber)?.stringValue
                        ?? field.defaultText ?? ""
                case .header, .info:
                    break
                }
            }
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    private func save() {
        var values = plugins.settingsValues(for: scraper)
        for (key, value) in text { values[key] = value }
        for (key, value) in toggles { values[key] = value }
        plugins.saveSettings(values, for: scraper)
    }
}
