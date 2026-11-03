import SwiftUI

// Nuvio's desktop streams page: the title's backdrop fills the window, the
// logo or episode sits on the left, and the sources are listed in a glass
// panel on the right, filtered by add-on and grouped under add-on headers.

/// The full-window frame around the source list.
struct StreamsPageLayout<Panel: View>: View {
    let item: MediaItem
    let episode: MediaEpisode?
    let resumeAt: Double?
    let background: StreamPagePreferences.Background
    let onClose: () -> Void
    @ViewBuilder let panel: () -> Panel

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width >= 900
            ZStack(alignment: .topLeading) {
                StreamsPageBackdrop(item: item, episode: episode, background: background)

                HStack(spacing: 0) {
                    if isWide {
                        StreamsInfoPanel(item: item, episode: episode, resumeAt: resumeAt)
                            .frame(width: proxy.size.width * 0.42)
                            .padding(.horizontal, 48)
                    }

                    panel()
                        .frame(maxWidth: isWide ? 640 : .infinity, maxHeight: .infinity)
                        .background(.black.opacity(0.34), in: .rect(cornerRadius: 26, style: .continuous))
                        #if os(macOS)
                        .glassEffect(.clear, in: .rect(cornerRadius: 26, style: .continuous))
                        #endif
                        .clipShape(.rect(cornerRadius: 26, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .strokeBorder(.white.opacity(0.08))
                        }
                        .padding(.top, 64)
                        .padding([.bottom, .trailing], 18)
                        .padding(.leading, isWide ? 0 : 18)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .frame(width: 36, height: 36)
                }
                #if os(macOS)
                .omniaRoundedGlassButton(cornerRadius: 18, role: .control)
                #else
                .buttonStyle(.plain)
                #endif
                .keyboardShortcut(.cancelAction)
                .help("Back")
                .accessibilityLabel("Back")
                #if os(macOS)
                // Beside the window's traffic lights, on their centre line.
                .padding(.leading, 86)
                .padding(.top, 8)
                #else
                .padding(.leading, 18)
                .padding(.top, 18)
                #endif
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

/// The sources over the video in the player: the panel alone on the right,
/// with the picture dimmed behind it and no artwork or title details.
struct StreamsPlayerPanelLayout<Panel: View>: View {
    let onClose: () -> Void
    @ViewBuilder let panel: () -> Panel

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .trailing) {
                Color.black.opacity(0.5)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                                .frame(width: 32, height: 32)
                        }
                        #if os(macOS)
                        .omniaRoundedGlassButton(cornerRadius: 16, role: .control)
                        #else
                        .buttonStyle(.plain)
                        #endif
                        .keyboardShortcut(.cancelAction)
                        .help("Close")
                        .accessibilityLabel("Close Sources")
                    }
                    .padding([.top, .trailing], 14)
                    panel()
                }
                .frame(width: min(560, proxy.size.width - 36))
                .frame(maxHeight: .infinity)
                .background(.black.opacity(0.45), in: .rect(cornerRadius: 26, style: .continuous))
                #if os(macOS)
                .glassEffect(.clear, in: .rect(cornerRadius: 26, style: .continuous))
                #endif
                .clipShape(.rect(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(.white.opacity(0.08))
                }
                .padding(18)
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

private struct StreamsPageBackdrop: View {
    let item: MediaItem
    let episode: MediaEpisode?
    let background: StreamPagePreferences.Background
    @State private var backdropSize = CGSize.zero

    var body: some View {
        ZStack {
            Color.black
            switch background {
            case .cinematic:
                HeroAccentBackground(item: item)
                    .opacity(0.9)
                if let url = item.backdropURL ?? episode?.stillURL ?? item.artworkURL {
                    Color.clear
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { backdropSize = $0 }
                    .overlay {
                        CachedArtworkImage(url: url, size: backdropSize, transaction: .init(animation: .easeOut(duration: 0.5))) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
                            }
                        }
                    }
                    .clipped()
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: 0.38),
                                .init(color: .black.opacity(0.35), location: 0.72),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
                }
                LinearGradient(
                    colors: [.black.opacity(0.05), .black.opacity(0.25), .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            case .normal:
                Color(white: 0.06)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct StreamsInfoPanel: View {
    let item: MediaItem
    let episode: MediaEpisode?
    let resumeAt: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 0)
            if let logoURL = item.logoURL {
                TitleLogoView(url: logoURL, title: item.title, maximumWidth: 360, maximumHeight: 120, alignment: .bottomLeading)
            } else {
                Text(item.title)
                    .font(.system(size: 42, weight: .bold))
                    .lineLimit(3)
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
            }

            if let episode {
                HStack(spacing: 10) {
                    Text("S\(episode.seasonNumber) · E\(episode.episodeNumber)")
                        .font(.callout.weight(.bold).monospacedDigit())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.tint, in: .capsule)
                        .foregroundStyle(.white)
                    if !episode.title.isEmpty {
                        Text(episode.title)
                            .font(.title3.weight(.semibold))
                            .lineLimit(2)
                    }
                }
                if !episode.overview.isEmpty {
                    Text(episode.overview)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(4)
                }
            } else if !metadataLine.isEmpty {
                Text(metadataLine)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
            }

            if let resumeText {
                Label(resumeText, systemImage: "clock.arrow.circlepath")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.12), in: .capsule)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.bottom, 72)
    }

    private var metadataLine: String {
        ([item.year] + item.genres.prefix(2)).filter { !$0.isEmpty && $0 != "—" }.joined(separator: " · ")
    }

    private var resumeText: String? {
        guard let resumeAt, resumeAt > 5 else { return nil }
        let total = Int(resumeAt)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        let time = hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
        return "Resume from \(time)"
    }
}

/// Nuvio's provider filter chip, with the add-on's logo when it has one.
struct StreamFilterChip: View {
    let title: String
    let count: Int?
    var logoURL: URL? = nil
    var systemImage: String? = nil
    let isSelected: Bool
    var isLoading = false
    /// Spoken instead of the title, for icon-only chips.
    var accessibilityText: String? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let logoURL {
                    CachedArtworkImage(url: logoURL, size: CGSize(width: 16, height: 16), contentMode: .fit) { phase in
                        phase.image?.resizable().scaledToFit()
                    }
                    .frame(width: 16, height: 16)
                    .clipShape(.rect(cornerRadius: 4))
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                if !title.isEmpty {
                    Text(title)
                        .lineLimit(1)
                }
                if isLoading {
                    ProgressView().controlSize(.mini)
                } else if let count {
                    Text("\(count)")
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                }
            }
            .font(.subheadline.weight(isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                Capsule()
                    .fill(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(isHovered ? 0.14 : 0.08)))
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.snappy(duration: 0.18), value: isSelected)
        .accessibilityLabel(accessibilityText ?? count.map { "\(title), \($0) sources" } ?? title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The add-on heading over its streams.
struct StreamSectionHeader: View {
    let title: String
    let count: Int
    var logoURL: URL? = nil
    let isPinned: Bool
    var isLoading = false

    var body: some View {
        HStack(spacing: 8) {
            if let logoURL {
                CachedArtworkImage(url: logoURL, size: CGSize(width: 18, height: 18), contentMode: .fit) { phase in
                    phase.image?.resizable().scaledToFit()
                }
                .frame(width: 18, height: 18)
                .clipShape(.rect(cornerRadius: 4))
            }
            Text(title)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Pinned")
            }
            Text("\(count)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
            if isLoading {
                ProgressView().controlSize(.mini)
            }
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
        .padding(.top, 10)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
    }
}

/// One stream, drawn like Nuvio's stream card: badges, a bold name, the
/// add-on's description, and optionally the add-on's logo on the right.
struct StreamCardView: View {
    let candidate: AddonStreamCandidate
    let badges: [StreamBadge]
    let preferences: StreamPagePreferences
    var addonLogoURL: URL? = nil
    var symbol: String = "play.fill"
    /// Source type and technical summary, under the description.
    var detail: String? = nil
    var status: String? = nil
    var isPinned = false
    var isEnabled = true

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isHovered && isEnabled ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                .frame(width: 32, height: 32)
                .background {
                    Circle().fill(isHovered && isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.08)))
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                if preferences.badgePlacement == .top, hasBadges {
                    badgeRow
                }

                HStack(spacing: 6) {
                    Text(candidate.displayName)
                        .font(.body.weight(.bold))
                        .lineLimit(2)
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.tint)
                    }
                }

                if let description = candidate.displayDescription {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if preferences.badgePlacement == .bottom, hasBadges {
                    badgeRow
                        .padding(.top, 1)
                }

                if let status {
                    Text(status)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(status.localizedCaseInsensitiveContains("ready") ? .green : .orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if preferences.showAddonLogo {
                VStack(spacing: 3) {
                    if let addonLogoURL {
                        CachedArtworkImage(url: addonLogoURL, size: CGSize(width: 28, height: 28), contentMode: .fit) { phase in
                            phase.image?.resizable().scaledToFit()
                        }
                        .frame(width: 28, height: 28)
                        .clipShape(.rect(cornerRadius: 6))
                    } else {
                        Image(systemName: "puzzlepiece.extension.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                    }
                    Text(candidate.addonName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: 76)
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isHovered && isEnabled ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(.white.opacity(0.05)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isHovered && isEnabled ? AnyShapeStyle(.tint.opacity(0.55)) : AnyShapeStyle(.white.opacity(0.06)))
        }
        .opacity(isEnabled ? 1 : 0.55)
        .contentShape(.rect(cornerRadius: 14))
        .onHover { isHovered = $0 }
        .animation(.snappy(duration: 0.16), value: isHovered)
    }

    private var hasBadges: Bool {
        !badges.isEmpty || (preferences.showSizeBadges && candidate.videoSize != nil)
    }

    private var badgeRow: some View {
        FlowLayout(spacing: 4) {
            ForEach(badges, id: \.self) { badge in
                StreamBadgeChip(badge: badge)
            }
            if preferences.showSizeBadges, let size = candidate.videoSize {
                Text("SIZE \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(.white.opacity(0.1), in: .rect(cornerRadius: 5))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.14))
                    }
            }
        }
    }
}

/// A Fusion badge: its image, or its name when the image can't load.
struct StreamBadgeChip: View {
    let badge: StreamBadge

    var body: some View {
        Group {
            if let url = badge.imageURL {
                CachedArtworkImage(url: url, size: CGSize(width: 92, height: 16), contentMode: .fit) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFit()
                    case .failure:
                        nameLabel
                    default:
                        Color.clear.frame(width: 34)
                    }
                }
                .frame(minWidth: 20, maxWidth: 92)
                .frame(height: 16)
            } else {
                nameLabel
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .frame(height: 20)
        .background {
            if let fill = badge.fillHex.flatMap(Color.init(badgeHex:)) {
                RoundedRectangle(cornerRadius: 5).fill(fill)
            }
        }
        .overlay {
            if let border = badge.borderHex.flatMap(Color.init(badgeHex:)) {
                RoundedRectangle(cornerRadius: 5).strokeBorder(border)
            }
        }
        .help(badge.name)
        .accessibilityLabel(badge.name)
    }

    private var nameLabel: some View {
        Text(badge.name)
            .font(.system(size: 10, weight: .bold))
            .lineLimit(1)
            .padding(.horizontal, 3)
    }
}

extension Color {
    /// `#RRGGBB`, or `#AARRGGBB` as Nuvio reads eight-digit badge colours.
    nonisolated init?(badgeHex: String) {
        var text = badgeHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard let value = UInt64(text, radix: 16) else { return nil }
        switch text.count {
        case 6:
            self.init(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255
            )
        case 8:
            self.init(
                .sRGB,
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255,
                opacity: Double((value >> 24) & 0xFF) / 255
            )
        default:
            return nil
        }
    }
}
