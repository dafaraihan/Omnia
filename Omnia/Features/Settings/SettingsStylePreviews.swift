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

/// Small drawings of Continue Watching cards, after Nuvio's
/// ContinueWatchingStylePreview.
struct ContinueWatchingStylePreview: View {
    let style: ContinueWatchingStyle
    @Environment(\.displayPreferences) private var display

    var body: some View {
        switch style {
        case .wide:
            HStack(spacing: 0) {
                Rectangle()
                    .fill(.primary.opacity(0.22))
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 0) {
                    bar(width: 0.7, height: 8, opacity: 0.20)
                    Spacer(minLength: 4)
                    bar(width: 0.5, height: 6, opacity: 0.14)
                    Spacer(minLength: 4)
                    progress(0.6, height: 4)
                }
                .padding(5)
            }
            .frame(width: 104, height: 60)
            .background(.primary.opacity(0.10))
            .clipShape(.rect(cornerRadius: 6, style: .continuous))
        case .poster:
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.primary.opacity(0.22))
                    .frame(width: 56, height: 72)
                    .overlay(alignment: .bottom) {
                        progress(0.45, height: 4)
                            .frame(width: 36)
                            .padding(4)
                            .background(.background, in: Capsule())
                            .padding(5)
                    }
                bar(width: 0.85, height: 6, opacity: 0.18)
                    .frame(width: 56)
            }
        }
    }

    private func bar(width: CGFloat, height: CGFloat, opacity: Double) -> some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 2)
                .fill(.primary.opacity(opacity))
                .frame(width: geometry.size.width * width, height: height)
        }
        .frame(height: height)
    }

    private func progress(_ value: Double, height: CGFloat) -> some View {
        GeometryReader { geometry in
            Capsule()
                .fill(.primary.opacity(0.16))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(display.accentStyle)
                        .frame(width: geometry.size.width * value)
                }
        }
        .frame(height: height)
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
