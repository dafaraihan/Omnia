import SwiftUI

struct VideoPlayerSettingsView: View {
    @Environment(SettingsPreferencesStore.self) private var settings
    @State private var localResolverSettings = LocalResolverSettingsStore()

    private var model: VideoPlayerSettingsModel {
        VideoPlayerSettingsModel(preferences: settings.preferences)
    }

    private var behavior: PlaybackBehaviorPreferences {
        settings.preferences.playbackBehavior
    }



    var body: some View {
        Group {
            OmniaSettingsForm {
            #if OMNIA_MPV
            Section {
                SettingsDropdown(
                    "Engine",
                    selection: settings.binding(\.playbackBehavior.engine),
                    options: Array(PlaybackEngineKind.allCases)
                ) { engine in engine.title }
                .settingsRow("Engine")
            } header: {
                Text("Engine")
            } footer: {
                Text("\(settings.preferences.playbackBehavior.engine.detail) Controls and settings are the same with either. Applies from the next title you play.")
            }
            #endif
            Section {
                Toggle("Autoplay Next Episode", isOn: settings.binding(\.autoplayNextEpisode))
                .settingsRow("Autoplay Next Episode")
                Toggle(isOn: settings.binding(\.showSkipIntro)) {
                    Text("Skip Intro, Recap and Credits")
                    Text("Shows a Skip button using timestamps from IntroDB.")
                }
                .settingsRow("Skip Intro, Recap and Credits")
                Toggle("Play Continue Watching Directly", isOn: settings.binding(\.directContinueWatchingPlayback))
                .settingsRow("Play Continue Watching Directly")
            } header: {
                Text("Playback")
            }
            Section {
                SettingsRouteLink(route: .playerControls, summary: nil)
                SettingsRouteLink(route: .subtitle, summary: settings.preferences.subtitlesEnabled ? "On" : "Off")
                SettingsRouteLink(route: .streams, summary: settings.preferences.playbackBehavior.autoSelectionMode.title)
            }

            Section {
                SettingsDropdown(
                    "Show Up Next",
                    selection: settings.binding(\.playbackBehavior.nextEpisodeThresholdMode),
                    options: Array(NextEpisodeThresholdMode.allCases)
                ) { mode in mode.title }
                .settingsRow("Show Up Next")
                switch behavior.nextEpisodeThresholdMode {
                case .percentage:
                    SettingsDropdown(
                        "Threshold",
                        selection: settings.binding(\.playbackBehavior.nextEpisodeThresholdPercent),
                        options: Array(PlaybackBehaviorPreferences.thresholdPercentOptions)
                    ) { value in "\(value.formatted(.number.precision(.fractionLength(0 ... 1))))% watched" }
                    .settingsRow("Threshold")
                case .minutesBeforeEnd:
                    SettingsDropdown(
                        "Threshold",
                        selection: settings.binding(\.playbackBehavior.nextEpisodeThresholdMinutes),
                        options: Array(PlaybackBehaviorPreferences.thresholdMinuteOptions)
                    ) { value in minutesTitle(value) }
                    .settingsRow("Threshold")
                }
                Toggle(isOn: settings.binding(\.playbackBehavior.preloadNextEpisodeSources)) {
                    Text("Preload Next Episode Sources")
                    Text("Looks up the next episode's sources shortly before Up Next appears.")
                }
                .settingsRow("Preload Next Episode Sources")
                if settings.preferences.autoplayNextEpisode {
Group {
                    Toggle(isOn: settings.binding(\.playbackBehavior.nextEpisodeFallbackToAnySource)) {
                        Text("Fall Back to Any Source")
                        Text("When no source from the same release is found, play the first available one.")
                    }
                    .settingsRow("Fall Back to Any Source")
                    .disabled(!behavior.preferBingeGroup)
                }
.settingsDependentRows()
}
            } header: {
                Text("Up Next")
            } footer: {
                Text("The threshold is used when a title has no credits timestamp.")
            }
            Section {
                ForEach(PlaybackBehaviorPreferences.autoSkipKinds, id: \.self) { kind in
                    Toggle("Skip \(kind.settingsTitle) Automatically", isOn: autoSkipBinding(kind))
                }
                .disabled(!model.isAutoSkipEnabled)
                if let explanation = model.autoSkipDisabledExplanation {
                    Text(explanation).font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("Timestamps") {
                    Link("IntroDB", destination: URL(string: "https://introdb.app/docs/terms")!)
                }
            } header: {
                Text("Skip Segments")
            }
            Section {
                LanguagePicker("Preferred audio", selection: settings.binding(\.preferredAudioLanguage), includesNone: false)
                .settingsRow("Preferred audio")
                LanguagePicker("Audio fallback", selection: settings.binding(\.audioFallbackLanguage), includesNone: true)
                .settingsRow("Audio fallback")
                SettingsDropdown(
                    "Anime audio",
                    selection: settings.binding(\.animeAudioPreference),
                    options: AnimeAudioPreference.allCases
                ) { value in
                    switch value {
                    case .followPreferred: "Follow preferred audio"
                    case .sub: "Sub (Japanese audio)"
                    case .dub: "Dub"
                    }
                }
                .settingsRow("Anime audio")
            } header: {
                Text("Audio")
            }
            Section {
                Toggle(isOn: settings.binding(\.compatibleFormatsOnly)) {
                    Text("Show Only Compatible Formats")
                    Text("Hides web pages and sources Omnia can't play from the source list.")
                }
                .settingsRow("Show Only Compatible Formats")
                #if os(macOS)
                Toggle(isOn: settings.binding(\.playbackBehavior.usesWholeScreen)) {
                    Text("Use Whole Screen")
                    Text("Video also covers the strip beside the camera notch. Full screen then stays in the current Space instead of opening its own. Applies from the next video.")
                }
                .settingsRow("Use Whole Screen")
                #endif
            } header: {
                Text("Video")
            }
            Section {
                NavigationLink {
                    SettingsDestinationView(route: .playbackResolver)
                } label: {
                    LabeledContent("Cache and Sharing", value: resolverSummary)
                }
                .settingsLinkRow()
                NavigationLink {
                    SettingsDestinationView(route: .playbackDiagnostics)
                } label: {
                    LabeledContent("Diagnostics", value: "Recent playback failures")
                }
                .settingsLinkRow()
                LabeledContent("Default player", value: "Omnia (in-app)")
                #if !OMNIA_MPV
                LabeledContent("Playback engine", value: "AVPlayer")
                #endif
            } header: {
                Text("More")
            }
                }
        }
        .omniaNavigationTitle("Player")
    }

    private var resolverSummary: String {
        localResolverSettings.preferences.hasCurrentConsent ? "Ready on this \(OmniaDevice.name)" : "Consent required"
    }

    private func minutesTitle(_ value: Double) -> String {
        if value == 0 { return "At the end" }
        let text = value.formatted(.number.precision(.fractionLength(0 ... 1)))
        return value == 1 ? "1 minute before end" : "\(text) minutes before end"
    }

    private func autoSkipBinding(_ kind: SkipSegment.Kind) -> Binding<Bool> {
        Binding(
            get: { settings.preferences.playbackBehavior.autoSkipSegments.contains(kind) },
            set: { isOn in
                settings.update {
                    if isOn {
                        $0.playbackBehavior.autoSkipSegments.insert(kind)
                    } else {
                        $0.playbackBehavior.autoSkipSegments.remove(kind)
                    }
                }
            }
        )
    }
}

/// Settings › Video Player › Stream Selection: how sources are sorted and
/// filtered, then Nuvio's Reuse Last Link, Auto Stream Selection and binge
/// groups.
/// Streams › Selection: how Omnia picks a source.
struct StreamSelectionSections: View {
    @Binding var confirmsForget: Bool
    @Environment(SettingsPreferencesStore.self) private var settings
    @Environment(OmniaStore.self) private var store
    @Environment(PluginStore.self) private var plugins

    private var behavior: PlaybackBehaviorPreferences {
        settings.preferences.playbackBehavior
    }

    private var streamAddons: [InstalledAddon] {
        store.installedAddons.filter { $0.isEnabled && $0.manifest.supportsStreams }
    }

    private var enabledPlugins: [PluginScraper] {
        plugins.pluginsEnabled ? plugins.scrapers.filter(\.isEnabled) : []
    }

    var body: some View {
        Group {
            StreamSortingSections()
            Section {
                SettingsDropdown(
                    "Auto-play",
                    selection: settings.binding(\.playbackBehavior.autoSelectionMode),
                    options: Array(AutoStreamSelectionMode.allCases)
                ) { mode in mode.title }
                .settingsRow("Auto-play")
                if behavior.autoSelectionMode == .regexMatch {
Group {
                    TextField("Regex Pattern", text: settings.binding(\.playbackBehavior.autoSelectionRegex), prompt: Text("(2160p|4k|1080p)"))
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    Menu("Insert a Preset") {
                        ForEach(StreamRegexPreset.all) { preset in
                            Button(preset.title) {
                                settings.update { $0.playbackBehavior.autoSelectionRegex = preset.pattern }
                            }
                        }
                    }
                    if let problem = regexProblem {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
.settingsDependentRows()
}
                if behavior.autoSelectionMode != .manual {
Group {
                    SettingsDropdown(
                        "Wait for Add-ons",
                        selection: settings.binding(\.playbackBehavior.selectionTimeoutSeconds),
                        options: Array(StreamSelectionTimeout.options)
                    ) { seconds in StreamSelectionTimeout.title(seconds) }
                    .settingsRow("Wait for Add-ons")
                    SettingsDropdown(
                        "Pick From",
                        selection: settings.binding(\.playbackBehavior.selectionScope),
                        options: Array(AutoStreamSelectionScope.allCases)
                    ) { scope in scope.title }
                    .settingsRow("Pick From")
                }
.settingsDependentRows()
}
            } header: {
                Text("Auto Stream Selection")
            } footer: {
                Text(modeFooter)
            }

            Section {
                Toggle(isOn: settings.binding(\.playbackBehavior.reuseLastLink)) {
                    Text("Reuse Last Link")
                    Text("Plays the stream you last watched for a movie or episode again, without asking the add-ons.")
                }
                .settingsRow("Reuse Last Link")
                SettingsDropdown(
                    "Keep Links For",
                    selection: settings.binding(\.playbackBehavior.lastLinkCacheHours),
                    options: Array(PlaybackBehaviorPreferences.lastLinkCacheHourOptions)
                ) { hours in hoursTitle(hours) }
                .settingsRow("Keep Links For")
                .disabled(!behavior.reuseLastLink)
            } header: {
                Text("Last Link")
            } footer: {
                Text("Links that expire or fail to play are never reused.")
            }

            if behavior.autoSelectionMode != .manual, behavior.selectionScope != .pluginsOnly, !streamAddons.isEmpty {
                Section {
                    ForEach(streamAddons) { addon in
                        Toggle(addon.displayName, isOn: allowedBinding(
                            id: addon.id,
                            allIDs: Set(streamAddons.map(\.id)),
                            keyPath: \.playbackBehavior.allowedAddonIDs
                        ))
                    }
                } header: {
                    Text("Allowed Add-ons")
                } footer: {
                    Text("Automatic selection only picks from these add-ons.")
                }
            }

            if behavior.autoSelectionMode != .manual, behavior.selectionScope != .addonsOnly, !enabledPlugins.isEmpty {
                Section {
                    ForEach(enabledPlugins) { scraper in
                        Toggle(scraper.name, isOn: allowedBinding(
                            id: PluginStreamResolver.sourceID(for: scraper),
                            allIDs: Set(enabledPlugins.map(PluginStreamResolver.sourceID(for:))),
                            keyPath: \.playbackBehavior.allowedPluginIDs
                        ))
                    }
                } header: {
                    Text("Allowed Plugins")
                }
            }

            Section {
                Toggle(isOn: settings.binding(\.playbackBehavior.preferBingeGroup)) {
                    Text("Prefer Same Release")
                    Text("For the next episode, picks the source from the same release group as the one you're watching.")
                }
                .settingsRow("Prefer Same Release")
                Toggle(isOn: settings.binding(\.playbackBehavior.reuseBingeGroup)) {
                    Text("Remember Release Per Show")
                    Text("Keeps using that release group when you come back to a show later, even in Manual mode.")
                }
                .settingsRow("Remember Release Per Show")
                .disabled(!behavior.preferBingeGroup)
            } header: {
                Text("Binge Group")
            } footer: {
                Text("Add-ons mark sources from the same release with a binge group.")
            }

            Section {
                Button("Forget Saved Links and Releases", role: .destructive) {
                    confirmsForget = true
                }
                .settingsRow("Forget Saved Links and Releases")
            }
        }
    }

    private var regexProblem: String? {
        let pattern = behavior.autoSelectionRegex.trimmingCharacters(in: .whitespacesAndNewlines)
        if pattern.isEmpty { return "Enter a pattern, or nothing plays automatically." }
        return behavior.compiledRegex == nil ? "This pattern isn't a valid regular expression." : nil
    }

    private var modeFooter: String {
        switch behavior.autoSelectionMode {
        case .manual:
            "You choose every source. Choose Manually also stops any automatic choice while sources load."
        case .firstSource:
            "Plays the first playable source, in add-on order, once the wait is over."
        case .regexMatch:
            "Plays the first source whose name, description, file name or link matches the pattern. Letter case is ignored."
        }
    }

    private func hoursTitle(_ hours: Int) -> String {
        switch hours {
        case 1: "1 hour"
        case 24: "1 day"
        case 48: "2 days"
        case 72: "3 days"
        case 168: "1 week"
        default: "\(hours) hours"
        }
    }

    /// An empty list allows everything, so turning one off from "all"
    /// stores every other one, and turning them all back on clears it.
    private func allowedBinding(
        id: String,
        allIDs: Set<String>,
        keyPath: WritableKeyPath<SettingsPreferences, Set<String>>
    ) -> Binding<Bool> {
        Binding(
            get: {
                let allowed = settings.preferences[keyPath: keyPath]
                return allowed.isEmpty || allowed.contains(id)
            },
            set: { isOn in
                settings.update {
                    var allowed = $0[keyPath: keyPath].intersection(allIDs)
                    if allowed.isEmpty { allowed = allIDs }
                    if isOn { allowed.insert(id) } else { allowed.remove(id) }
                    $0[keyPath: keyPath] = allowed == allIDs ? [] : allowed
                }
            }
        )
    }
}

struct LanguagePicker: View {
    let title: String
    @Binding var selection: PreferredLanguage
    let includesNone: Bool

    init(_ title: String, selection: Binding<PreferredLanguage>, includesNone: Bool) {
        self.title = title
        _selection = selection
        self.includesNone = includesNone
    }

    var body: some View {
        SettingsDropdown(
            title,
            selection: $selection,
            sections: [
                includesNone ? [.followSystem, PreferredLanguage.none] : [.followSystem],
                PlaybackLanguageCatalog.codes.map { PreferredLanguage.language($0) }
            ]
        ) { language in
            switch language {
            case .followSystem: "Follow System"
            case .none: "Off / No preference"
            case let .language(code): PlaybackLanguageCatalog.name(for: code)
            }
        }
    }
}
