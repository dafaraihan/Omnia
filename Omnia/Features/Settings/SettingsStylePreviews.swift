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

/// Uses the same presentation as Home; no separate schematic can drift from it.
struct ContinueWatchingStylePreview: View {
    let style: ContinueWatchingStyle
    var isThumbnail = true
    @Environment(\.displayPreferences) private var display

    private var previewDisplay: DisplayPreferences {
        var value = display
        value.continueWatchingStyle = style
        // Preview data has no captured scene or remote artwork.
        value.continueWatchingArtwork = .artwork
        return value
    }

    private var item: MediaItem {
        MediaItem(
            id: "settings-continue-watching-preview", title: "Continue Watching Preview",
            year: "2026", kind: .series, overview: "", genres: [], symbol: "tv",
            artworkColors: MediaItem.placeholderArtworkColors,
            progress: 0.6, positionSeconds: 1620, durationSeconds: 2700,
            resumeSeasonNumber: 1, resumeEpisodeNumber: 3, resumeEpisodeTitle: "Episode Preview"
        )
    }

    var body: some View {
        Group {
            if isThumbnail {
                let width = ContinueWatchingCard.width(for: previewDisplay)
                let height = style == .poster ? width * 1.5 + 56 : width / 1.77 + (style == .wide ? 56 : 0)
                let scale = min(104 / width, 90 / height)
                ContinueWatchingCard(item: item, requestPlayback: {}, isPreview: true)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: width * scale, height: height * scale, alignment: .topLeading)
            } else {
                ScrollView(.horizontal) {
                    ContinueWatchingCard(item: item, requestPlayback: {}, isPreview: true)
                        .padding(12)
                }
                .scrollIndicators(.hidden)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .environment(\.displayPreferences, previewDisplay)
        .allowsHitTesting(!isThumbnail)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(style.title) preview")
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

extension ContinueWatchingStyle {
    /// Nuvio's line under each style.
    var detail: String {
        switch self {
        case .card: "TV-style landscape card"
        case .wide: "Info-dense horizontal card"
        case .poster: "Artwork-first poster card"
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
