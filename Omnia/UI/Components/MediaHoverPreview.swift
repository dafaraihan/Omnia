import SwiftUI

extension View {
    /// Nuvio's Hover Preview: resting the pointer on a poster for the chosen
    /// delay shows the backdrop, logo and synopsis beside it. Off by default,
    /// and only on the Mac, where there is a pointer.
    func mediaHoverPreview(_ item: MediaItem) -> some View {
        #if os(macOS)
        modifier(MediaHoverPreviewModifier(item: item))
        #else
        self
        #endif
    }
}

#if os(macOS)
private struct MediaHoverPreviewModifier: ViewModifier {
    let item: MediaItem
    @Environment(\.displayPreferences) private var display
    @State private var isPresented = false
    @State private var hoverTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        if display.hoverPreviewEnabled {
            content
                .onHover { hovering in
                    hoverTask?.cancel()
                    if hovering {
                        let delay = display.hoverPreviewDelay.rawValue
                        hoverTask = Task {
                            try? await Task.sleep(for: .seconds(delay))
                            guard !Task.isCancelled else { return }
                            isPresented = true
                        }
                    } else {
                        isPresented = false
                    }
                }
                .onDisappear {
                    hoverTask?.cancel()
                    isPresented = false
                }
                .popover(isPresented: $isPresented, arrowEdge: .trailing) {
                    MediaHoverPreviewCard(item: item)
                }
        } else {
            content
        }
    }
}

private struct MediaHoverPreviewCard: View {
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                MediaItem.placeholderArtworkColor
                CachedArtworkImage(url: item.backdropURL ?? item.artworkURL, size: CGSize(width: 320, height: 180)) { phase in
                    phase.image?.resizable().scaledToFill()
                }
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                if let logoURL = item.logoURL {
                    TitleLogoView(url: logoURL, title: item.title, maximumWidth: 170, maximumHeight: 52, alignment: .bottomLeading)
                        .padding(12)
                }
            }
            .frame(width: 320, height: 180)
            .clipShape(.rect(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                if let metadata = MediaPosterLabelContent(item: item).metadata {
                    Text(metadata)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !item.overview.isEmpty {
                Text(item.overview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 320, alignment: .leading)
        .padding(14)
        .allowsHitTesting(false)
    }
}
#endif
