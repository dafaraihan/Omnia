import SwiftUI

/// Nuvio's style pickers: a row of tiles, each with a small drawing of the
/// card style, its name and a line on what it's for. The chosen tile takes
/// the accent.
struct SettingsStyleTilePicker<Option: Hashable & Identifiable, Preview: View>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    let detail: (Option) -> String
    @ViewBuilder let preview: (Option) -> Preview

    @Environment(\.displayPreferences) private var display

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(options) { option in
                tile(option)
            }
        }
        .padding(.vertical, 4)
    }

    private func tile(_ option: Option) -> some View {
        let isSelected = option == selection
        return Button {
            selection = option
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    preview(option)
                        .frame(maxWidth: .infinity)
                        .frame(height: 96)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(display.accentColor)
                        .opacity(isSelected ? 1 : 0)
                }
                Text(title(option))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isSelected ? display.accentColor : .primary)
                Text(detail(option))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? display.accentColor.opacity(0.08) : Color.primary.opacity(0.04))
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title(option))
        .accessibilityHint(detail(option))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The real card, drawing a title the viewer is watching, or else one from
/// their catalogs, so the settings above show as they will on Home.
struct ContinueWatchingLivePreview: View {
    @Environment(\.displayPreferences) private var display
    @Environment(OmniaStore.self) private var store
    @Environment(LiveMetadataStore.self) private var metadata
    @Environment(AddonCatalogStore.self) private var addonCatalogs

    private var watching: MediaItem? {
        store.localMediaSnapshots
            .filter { $0.progress != nil }
            .max { ($0.lastPlayedAt ?? .distantPast) < ($1.lastPlayedAt ?? .distantPast) }?
            .item
    }

    /// The first title with artwork from what Home already loaded.
    private var catalogItem: MediaItem? {
        let enabled = AddonCatalogStore.catalogs(in: store).filter {
            store.isCatalogEnabled(for: $0.addon, catalog: $0.catalog)
        }
        let candidates = enabled.flatMap { addonCatalogs.rows[$0.key]?.items ?? [] }
            + metadata.topSeries + metadata.topMovies + metadata.seriesCatalog + metadata.movieCatalog
        return candidates.first { $0.backdropURL != nil && $0.artworkURL != nil }
            ?? candidates.first { $0.artworkURL != nil }
    }

    private var item: MediaItem {
        if let watching { return watching }
        var sample = catalogItem ?? MediaItem(
            id: "settings-continue-watching-preview", title: "Your Title",
            year: "2026", kind: .series, overview: "", genres: [], symbol: "tv",
            artworkColors: MediaItem.placeholderArtworkColors,
            progress: nil
        )
        sample.progress = 0.6
        sample.positionSeconds = 1620
        sample.durationSeconds = 2700
        if sample.kind == .series {
            sample.resumeSeasonNumber = 1
            sample.resumeEpisodeNumber = 3
        }
        return sample
    }

    private var previewDisplay: DisplayPreferences {
        var value = display
        // Only a title really being watched has a paused scene to show.
        if watching == nil { value.continueWatchingArtwork = .artwork }
        return value
    }

    var body: some View {
        ScrollView(.horizontal) {
            ContinueWatchingCard(item: item, requestPlayback: {}, isPreview: true)
                .padding(24)
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.center, for: .alignment)
        .scrollClipDisabled()
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.displayPreferences, previewDisplay)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Continue Watching card live preview")
    }
}

/// Small drawings of the title page's episode cards, after Nuvio's
/// MetaEpisodeCardStylePreview.
struct EpisodeCardLayoutPreview: View {
    let layout: EpisodeCardLayout
    @Environment(\.displayPreferences) private var display

    var body: some View {
        switch layout {
        case .horizontal:
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.primary.opacity(0.16))
                VStack(spacing: 0) {
                    Spacer()
                    Rectangle()
                        .fill(.black.opacity(0.36))
                        .frame(height: 26)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.primary.opacity(0.22))
                                .frame(width: 64, height: 6)
                                .padding(.leading, 8)
                        }
                }
                RoundedRectangle(cornerRadius: 3)
                    .fill(.primary.opacity(0.26))
                    .frame(width: 36, height: 7)
                    .padding(6)
            }
            .frame(width: 128, height: 80)
            .clipShape(.rect(cornerRadius: 8, style: .continuous))
        case .list:
            HStack(spacing: 0) {
                Rectangle()
                    .fill(.primary.opacity(0.22))
                    .frame(width: 48)
                VStack(alignment: .leading, spacing: 5) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.primary.opacity(0.20))
                        .frame(width: 62, height: 8)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.primary.opacity(0.16))
                        .frame(width: 40, height: 6)
                    Capsule()
                        .fill(display.accentColor.opacity(0.55))
                        .frame(width: 72, height: 4)
                    Spacer(minLength: 0)
                }
                .padding(6)
                Spacer(minLength: 0)
            }
            .frame(width: 132, height: 78)
            .background(.primary.opacity(0.10))
            .clipShape(.rect(cornerRadius: 8, style: .continuous))
        }
    }
}

extension EpisodeCardLayout {
    /// Nuvio's line under each layout.
    var detail: String {
        switch self {
        case .horizontal: "Backdrop-style row cards"
        case .list: "Detail-first stacked cards"
        }
    }
}
