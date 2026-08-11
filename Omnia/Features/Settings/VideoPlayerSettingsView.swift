import SwiftUI

struct VideoPlayerSettingsView: View {
    @Environment(SettingsPreferencesStore.self) private var settings

    private var model: VideoPlayerSettingsModel {
        VideoPlayerSettingsModel(preferences: settings.preferences)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Show Skip Intro", isOn: settings.binding(\.showSkipIntro))
                Toggle("Skip automatically", isOn: settings.binding(\.autoSkipIntro))
                    .disabled(!model.isAutoSkipEnabled)
                if let explanation = model.autoSkipDisabledExplanation {
                    Text(explanation).font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("Intro timestamps") {
                    Link("IntroDB", destination: URL(string: "https://introdb.app/docs/terms")!)
                }
            } header: {
                Text("Skip Intro")
            } footer: {
                Text("Omnia only reads timestamp data. It does not upload playback activity or edit IntroDB records.")
            }

            Section("Up Next") {
                Toggle("Autoplay Next Episode", isOn: settings.binding(\.autoplayNextEpisode))
                Picker("Show Up Next", selection: settings.binding(\.upNextLeadTime)) {
                    ForEach(UpNextLeadTime.allCases, id: \.self) { value in
                        Text("\(value.rawValue) seconds remaining").tag(value)
                    }
                }
                .disabled(!model.isUpNextTimingEnabled)
                if let explanation = model.upNextTimingDisabledExplanation {
                    Text(explanation).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Default player", value: "Omnia (in-app)")
                #if os(macOS)
                LabeledContent("Playback engine", value: "libmpv")
                #else
                LabeledContent("Playback engine", value: "AVPlayer")
                #endif
            } header: {
                Text("Playback Destination")
            } footer: {
                Text("Playback always stays inside Omnia.")
            }

            Section("Source Selection") {
                Toggle("Remember Last Selection", isOn: settings.binding(\.rememberLastSelection))
                Picker("Keep preference for", selection: settings.binding(\.sourceSelectionRetention)) {
                    ForEach(SourceSelectionRetention.allCases, id: \.self) { value in
                        Text(value.title).tag(value)
                    }
                }
                .disabled(!model.isRetentionEnabled)
                if let explanation = model.retentionDisabledExplanation {
                    Text(explanation).font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Autoplay First Compatible Source", isOn: settings.binding(\.autoplayFirstCompatibleSource))
                    .disabled(!settings.preferences.rememberLastSelection)
                Toggle("Play Continue Watching Directly", isOn: settings.binding(\.directContinueWatchingPlayback))
                Toggle("Show Only Compatible Formats", isOn: settings.binding(\.compatibleFormatsOnly))
                NavigationLink(value: SettingsRoute.playbackResolver) {
                    LabeledContent("Playback Resolver", value: resolverSummary)
                }
            }

            Section("Audio") {
                LanguagePicker("Preferred audio", selection: settings.binding(\.preferredAudioLanguage), includesNone: false)
                LanguagePicker("Audio fallback", selection: settings.binding(\.audioFallbackLanguage), includesNone: true)
                Picker("Anime audio", selection: settings.binding(\.animeAudioPreference)) {
                    Text("Follow preferred audio").tag(AnimeAudioPreference.followPreferred)
                    Text("Sub (Japanese audio)").tag(AnimeAudioPreference.sub)
                    Text("Dub").tag(AnimeAudioPreference.dub)
                }
            }

            Section("Subtitles") {
                LanguagePicker("Preferred subtitles", selection: settings.binding(\.preferredSubtitleLanguage), includesNone: true)
                LanguagePicker("Subtitle fallback", selection: settings.binding(\.subtitleFallbackLanguage), includesNone: true)
                Toggle("Prefer SDH Captions", isOn: Binding(
                    get: { settings.preferences.sdhPreference == .prefer },
                    set: { newValue in
                        settings.update {
                            $0.sdhPreference = newValue ? .prefer : .followSystem
                        }
                    }
                ))
                NavigationLink("Subtitle", value: SettingsRoute.subtitle)
            }
        }
        .navigationTitle("Video Player")
    }

    private var resolverSummary: String {
        PlaybackResolverCredentialStore.hasAuthorizationToken ? "Configured locally" : "Not configured"
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
        Picker(title, selection: $selection) {
            Text("Follow System").tag(PreferredLanguage.followSystem)
            if includesNone { Text("Off / No preference").tag(PreferredLanguage.none) }
            Text("English").tag(PreferredLanguage.language("en"))
            Text("Indonesian").tag(PreferredLanguage.language("id"))
            Text("Japanese").tag(PreferredLanguage.language("ja"))
            Text("Spanish").tag(PreferredLanguage.language("es"))
        }
    }
}

private extension SourceSelectionRetention {
    var title: String {
        switch self {
        case .hours24: "24 hours"
        case .days3: "3 days"
        case .week1: "1 week"
        }
    }
}
