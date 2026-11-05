import SwiftUI

/// Settings › Landscape Card Style. Any card shown landscape reads these:
/// Continue Watching, landscape collections, and posters shown as backdrops.
struct LandscapeCardSettingsView: View {
    @Environment(SettingsPreferencesStore.self) private var settings
    @Environment(CollectionsStore.self) private var collections

    private var display: DisplayPreferences { settings.preferences.display }

    private var landscapeFolders: [HomeCollectionFolder] {
        collections.collections.flatMap(\.folders).filter { $0.tileShape == .landscape || $0.tileShape == .wide }
    }

    var body: some View {
        OmniaSettingsForm {
            Section {
                SettingsDropdown(
                    "Size",
                    selection: settings.binding(\.display.continueWatchingCard.size),
                    options: Array(ContinueWatchingCardPreferences.Size.allCases)
                ) { $0.title }
                .settingsRow("Size")
                SettingsDropdown(
                    "Corners",
                    selection: settings.binding(\.display.continueWatchingCard.corners),
                    options: Array(ContinueWatchingCardPreferences.Corners.allCases)
                ) { $0.title }
                .settingsRow("Corners")
            } header: {
                Text("All Landscape Cards")
            } footer: {
                Text("Portrait cards follow Poster Card Style.")
            }

            Section {
                SettingsStyleTilePicker(
                    options: ContinueWatchingStyle.allCases,
                    selection: settings.binding(\.display.continueWatchingStyle),
                    title: \.title,
                    detail: \.detail
                ) { style in
                    ContinueWatchingStylePreview(style: style)
                }
                if display.continueWatchingStyle != .card {
                    Toggle(isOn: settings.binding(\.display.continueWatchingShowsLabels)) {
                        Text("Show Labels")
                        Text("The title under each card.")
                    }
                    .settingsRow("Show Labels")
                }
            } header: {
                Text("Continue Watching")
            }

            Section {
                SettingsDropdown(
                    "Folder Names",
                    selection: settings.binding(\.display.collectionCard.titles),
                    options: Array(CollectionCardPreferences.Titles.allCases)
                ) { $0.title }
                .settingsRow("Folder Names")
            } header: {
                Text("Collections")
            } footer: {
                Text("Collections keep the shape they were imported with.")
            }

            if display.cardDepth.isEnabled {
                Section {
                    Toggle("Continue Watching", isOn: depthBinding(.continueWatching))
                    Toggle("Collections", isOn: depthBinding(.collections))
                } header: {
                    Text("Apply Card Depth To")
                } footer: {
                    Text("Depth and hover glow are set in Poster Card Style.")
                }
            }
        }
        .settingsPinnedPreview {
            LandscapeCardsLivePreview(folders: Array(landscapeFolders.prefix(1)))
        }
        .omniaNavigationTitle("Landscape Card Style")
    }

    private func depthBinding(_ surface: CardDepthPreferences.Surface) -> Binding<Bool> {
        Binding(
            get: { !settings.preferences.display.cardDepth.disabledSurfaces.contains(surface) },
            set: { isOn in
                settings.update {
                    if isOn {
                        $0.display.cardDepth.disabledSurfaces.remove(surface)
                    } else {
                        $0.display.cardDepth.disabledSurfaces.insert(surface)
                    }
                }
            }
        )
    }
}

/// A real Continue Watching card and a landscape collection card.
private struct LandscapeCardsLivePreview: View {
    let folders: [HomeCollectionFolder]
    @Environment(\.displayPreferences) private var display
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) {
                ContinueWatchingLivePreview(style: display.continueWatchingStyle)
                    .fixedSize()
                CollectionCardPreview(folders: folders, sampleShape: .landscape)
                    .fixedSize()
            }
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.center, for: .alignment)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: display.continueWatchingCard)
    }
}
