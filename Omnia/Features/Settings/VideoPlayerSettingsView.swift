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
        OmniaSettingsForm {
            Section {
                NavigationLink {
                    SettingsDestinationView(route: .streamSelection)
                } label: {
                    LabeledContent("Stream Selection", value: streamSelectionSummary)
                }
                .settingsLinkRow()
                Toggle("Play Continue Watching Directly", isOn: settings.binding(\.directContinueWatchingPlayback))
                Toggle(isOn: settings.binding(\.compatibleFormatsOnly)) {
                    Text("Show Only Compatible Formats")
                    Text("Hides web pages and sources Omnia can't play from the source list.")
                }
                NavigationLink {
                    SettingsDestinationView(route: .playbackResolver)
                } label: {
                    LabeledContent("Local Playback Resolver", value: resolverSummary)
                }
                .settingsLinkRow()
                NavigationLink {
                    SettingsDestinationView(route: .playbackDiagnostics)
                } label: {
                    LabeledContent("Diagnostics", value: "Recent playback failures")
                }
                .settingsLinkRow()
            } header: {
                Text("Sources")
            }

            Section {
                Toggle("Autoplay Next Episode", isOn: settings.binding(\.autoplayNextEpisode))
                if settings.preferences.autoplayNextEpisode {
                    Toggle(isOn: settings.binding(\.playbackBehavior.nextEpisodeFallbackToAnySource)) {
                        Text("Fall Back to Any Source")
                        Text("When no source from the same release is found, play the first available one.")
                    }
                    .disabled(!behavior.preferBingeGroup)
                }
                SettingsDropdown(
                    "Show Up Next",
                    selection: settings.binding(\.playbackBehavior.nextEpisodeThresholdMode),
                    options: Array(NextEpisodeThresholdMode.allCases)
                ) { mode in mode.title }
                switch behavior.nextEpisodeThresholdMode {
                case .percentage:
                    SettingsDropdown(
                        "Threshold",
                        selection: settings.binding(\.playbackBehavior.nextEpisodeThresholdPercent),
                        options: Array(PlaybackBehaviorPreferences.thresholdPercentOptions)
                    ) { value in "\(value.formatted(.number.precision(.fractionLength(0 ... 1))))% watched" }
                case .minutesBeforeEnd:
                    SettingsDropdown(
                        "Threshold",
                        selection: settings.binding(\.playbackBehavior.nextEpisodeThresholdMinutes),
                        options: Array(PlaybackBehaviorPreferences.thresholdMinuteOptions)
                    ) { value in minutesTitle(value) }
                }
                Toggle(isOn: settings.binding(\.playbackBehavior.preloadNextEpisodeSources)) {
                    Text("Preload Next Episode Sources")
                    Text("Looks up the next episode's sources shortly before Up Next appears.")
                }
            } header: {
                Text("Next Episode")
            } footer: {
                Text("The threshold is used when a title has no credits timestamp. With one, Up Next appears when the credits start, after any post-credits scene.")
            }

            Section {
                Toggle(isOn: settings.binding(\.showSkipIntro)) {
                    Text("Skip Intro, Recap and Credits")
                    Text("Shows a Skip button using timestamps from IntroDB.")
                }
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
            } footer: {
                Text("Omnia only reads timestamp data. It does not upload playback activity or edit IntroDB records.")
            }

            Section {
                LabeledContent("Default player", value: "Omnia (in-app)")
                #if os(macOS)
                LabeledContent("Playback engine", value: "libmpv")
                SettingsDropdown(
                    "Decoder",
                    selection: settings.binding(\.playbackBehavior.decoderPriority),
                    options: Array(DecoderPriority.allCases)
                ) { priority in priority.title }
                Toggle(isOn: settings.binding(\.playbackBehavior.metalRendering)) {
                    Text("Metal Rendering")
                    Text("Draws video with gpu-next on Metal, as Nuvio does, for sharper scaling and HDR tone mapping. If Metal can't start, the player uses OpenGL and notes why in Diagnostics. Applies from the next video.")
                }
                #else
                LabeledContent("Playback engine", value: "AVPlayer")
                #endif
            } header: {
                Text("Player")
            } footer: {
                #if os(macOS)
                Text("\(behavior.decoderPriority.detail) Applies from the next title you play.")
                #else
                Text("Playback always stays inside Omnia.")
                #endif
            }

            Section("Overlays") {
                Toggle(isOn: settings.binding(\.playbackBehavior.showLoadingOverlay)) {
                    Text("Loading Overlay")
                    Text("Shows the title's artwork until the first frame appears.")
                }
                Toggle("Show Loading Status", isOn: settings.binding(\.playbackBehavior.showLoadingStatus))
                    .disabled(!behavior.showLoadingOverlay)
                Toggle(isOn: settings.binding(\.playbackBehavior.showPauseOverlay)) {
                    Text("Pause Overlay")
                    Text("Shows the title's details after five seconds paused.")
                }
                Toggle(isOn: settings.binding(\.playbackBehavior.showContentWarnings)) {
                    Text("Content Warnings")
                    Text("Shows IMDb's parents guide (sex, violence, language, drugs, frightening scenes) for a few seconds when a title starts. Sends the title's IMDb ID to api.tiffara.com, as Nuvio does.")
                }
            }

            #if os(macOS)
            Section("Full Screen") {
                Toggle(isOn: settings.binding(\.playbackBehavior.usesWholeScreen)) {
                    Text("Use Whole Screen")
                    Text("Video also covers the strip beside the camera notch. Full screen then stays in the current Space instead of opening its own. Applies from the next video.")
                }
            }
            #endif

            Section("Audio") {
                LanguagePicker("Preferred audio", selection: settings.binding(\.preferredAudioLanguage), includesNone: false)
                LanguagePicker("Audio fallback", selection: settings.binding(\.audioFallbackLanguage), includesNone: true)
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
            }

            Section {
                Toggle(isOn: settings.binding(\.playbackBehavior.stripSDHSubtitles)) {
                    Text("Strip SDH Text")
                    Text("Removes sound descriptions and speaker names, like [door creaks].")
                }
                Toggle(isOn: settings.binding(\.playbackBehavior.useForcedSubtitles)) {
                    Text("Use Forced Subtitles")
                    Text("When the audio is in your subtitle language, shows only forced subtitles, such as signs and foreign dialogue.")
                }
                Toggle(isOn: settings.binding(\.playbackBehavior.showOnlyPreferredSubtitleLanguages)) {
                    Text("Only Preferred Languages")
                    Text("Add-on subtitles in other languages aren't added to the player.")
                }
                #if os(macOS)
                Toggle(isOn: settings.binding(\.playbackBehavior.autoSyncsSubtitles)) {
                    Text("Auto Sync Subtitles")
                    Text("When an add-on subtitle starts, Omnia listens to the speech for up to three minutes and lines the subtitle up with it. Subtitles inside the video are left as they are.")
                }
                SubtitleDoubleSlider(
                    title: "Subtitle Delay",
                    value: Binding(
                        get: { settings.preferences.playbackSubtitleStyle.delaySeconds },
                        // Tenth-of-a-second steps, like the player's own control.
                        set: { value in
                            settings.update { $0.playbackSubtitleStyle.delaySeconds = (value * 10).rounded() / 10 }
                        }
                    ),
                    range: -10 ... 10,
                    valueLabel: { String(format: "%+.1f s", $0) }
                )
                Button("Reset Delay") {
                    settings.update { $0.playbackSubtitleStyle.delaySeconds = 0 }
                }
                .disabled(settings.preferences.playbackSubtitleStyle.delaySeconds == 0)
                #endif
                // Languages and SDH live with the subtitle style, in one place.
                NavigationLink("Subtitle Languages and Style") {
                    SettingsDestinationView(route: .subtitle)
                }
                .settingsLinkRow()
            } header: {
                Text("Subtitles")
            } footer: {
                Text("Subtitles from add-ons such as OpenSubtitles are added to the player's list as they arrive. The delay applies to every video; a delay set in the player's Sync panel is kept for that title only, and a positive delay shows subtitles later.")
            }
        }
        .omniaNavigationTitle("Playback")
    }

    private var streamSelectionSummary: String {
        if behavior.reuseLastLink && behavior.autoSelectionMode == .manual { return "Reuse Last Link" }
        return behavior.autoSelectionMode.title
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
struct StreamSelectionSettingsView: View {
    @Environment(SettingsPreferencesStore.self) private var settings
    @Environment(OmniaStore.self) private var store
    @Environment(PluginStore.self) private var plugins
    @State private var confirmsForget = false

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
        OmniaSettingsForm {
            StreamSortingSections()

            Section {
                Toggle(isOn: settings.binding(\.playbackBehavior.reuseLastLink)) {
                    Text("Reuse Last Link")
                    Text("Plays the stream you last watched for a movie or episode again, without asking the add-ons.")
                }
                SettingsDropdown(
                    "Keep Links For",
                    selection: settings.binding(\.playbackBehavior.lastLinkCacheHours),
                    options: Array(PlaybackBehaviorPreferences.lastLinkCacheHourOptions)
                ) { hours in hoursTitle(hours) }
                .disabled(!behavior.reuseLastLink)
            } header: {
                Text("Last Link")
            } footer: {
                Text("Links that expire or fail to play are never reused.")
            }

            Section {
                SettingsDropdown(
                    "Auto-play",
                    selection: settings.binding(\.playbackBehavior.autoSelectionMode),
                    options: Array(AutoStreamSelectionMode.allCases)
                ) { mode in mode.title }
                if behavior.autoSelectionMode == .regexMatch {
                    TextField("Regex Pattern", text: settings.binding(\.playbackBehavior.autoSelectionRegex), prompt: Text("(2160p|4k|1080p)"))
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
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
                if behavior.autoSelectionMode != .manual {
                    SettingsDropdown(
                        "Wait for Add-ons",
                        selection: settings.binding(\.playbackBehavior.selectionTimeoutSeconds),
                        options: Array(StreamSelectionTimeout.options)
                    ) { seconds in StreamSelectionTimeout.title(seconds) }
                    SettingsDropdown(
                        "Pick From",
                        selection: settings.binding(\.playbackBehavior.selectionScope),
                        options: Array(AutoStreamSelectionScope.allCases)
                    ) { scope in scope.title }
                }
            } header: {
                Text("Auto Stream Selection")
            } footer: {
                Text(modeFooter)
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
                    Text("Automatic selection only picks from these add-ons. The source list still shows all of them.")
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
                Toggle(isOn: settings.binding(\.playbackBehavior.reuseBingeGroup)) {
                    Text("Remember Release Per Show")
                    Text("Keeps using that release group when you come back to a show later, even in Manual mode.")
                }
                .disabled(!behavior.preferBingeGroup)
            } header: {
                Text("Binge Group")
            } footer: {
                Text("Add-ons mark sources from the same release with a binge group, as in Stremio.")
            }

            Section {
                Button("Forget Saved Links and Releases", role: .destructive) {
                    confirmsForget = true
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
        .omniaNavigationTitle("Stream Selection")
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

private struct LanguagePicker: View {
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
