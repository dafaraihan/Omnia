import SwiftUI

struct MediaPosterLabelContent: Equatable {
    let title: String
    let metadata: String?

    init(item: MediaItem) {
        title = item.title

        let rawYear = item.year.trimmingCharacters(in: .whitespacesAndNewlines)
        let year = rawYear == "—" ? "" : rawYear
        let genre = item.genres.first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let values = [year, genre].filter { !$0.isEmpty }
        metadata = values.isEmpty ? nil : values.joined(separator: " · ")
    }
}

private struct ShowsMediaCardLabelsKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var showsMediaCardLabels: Bool {
        get { self[ShowsMediaCardLabelsKey.self] }
        set { self[ShowsMediaCardLabelsKey.self] = newValue }
    }
}

struct MediaPosterLabel: View {
    let item: MediaItem

    private var content: MediaPosterLabelContent {
        MediaPosterLabelContent(item: item)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(content.title)
                .font(titleFont)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let metadata = content.metadata {
                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleFont: Font {
        switch content.title.count {
        case 56...:
            .caption2
        case 33...:
            .caption
        default:
            .subheadline
        }
    }
}
