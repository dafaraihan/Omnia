//
//  TraktDetailSections.swift
//  Omnia
//

import SwiftUI

/// More Like This from Trakt, when Account › Tracking › More Like This
/// Source is Trakt, as in Nuvio. Trakt names the titles; the add-ons draw
/// them.
struct TraktRelatedShelf<Fallback: View>: View {
    let item: MediaItem
    /// Shown while Trakt answers, and when it has nothing.
    @ViewBuilder let fallback: () -> Fallback

    @Environment(OmniaStore.self) private var store
    @Environment(\.displayPreferences) private var display
    @State private var related: [MediaItem]?

    var body: some View {
        Group {
            if let related, !related.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "More Like This") {
                        Text("Trakt")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 6)
                    }
                    ShelfScrollView(
                        items: related,
                        itemSpan: MediaBrowseMetrics.posterItemSpan(display),
                        accessibilityLabel: "More Like This"
                    ) { title in
                        MediaPoster(item: title)
                    }
                }
            } else {
                fallback()
            }
        }
        .task(id: item.id) { await load() }
    }

    private func load() async {
        related = nil
        guard let clientID = TraktExtrasClient.clientID,
              let entries = try? await TraktExtrasClient.related(to: item, clientID: clientID),
              !Task.isCancelled
        else { return }
        let plain = entries.map(\.mediaItem)
        let addons = store.installedAddons
        let drawn = await withTaskGroup(of: (Int, MediaItem).self) { group in
            for (index, title) in plain.enumerated() {
                group.addTask { (index, await AddonMetadataResolver.resolve(title, addons: addons) ?? title) }
            }
            var resolved = plain
            for await (index, title) in group { resolved[index] = title }
            return resolved
        }
        guard !Task.isCancelled else { return }
        // Titles no add-on could draw would show as blank cards.
        related = drawn.filter { $0.artworkURL != nil }
    }
}

/// Trakt's comments and reviews on a title page, as Nuvio's Trakt Comments.
/// Spoilers stay hidden until tapped.
struct TraktCommentsSection: View {
    let item: MediaItem

    @State private var comments: [TraktComment] = []
    @State private var revealed: Set<Int> = []
    @State private var isExpanded = false

    var body: some View {
        Group {
            if !comments.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Trakt Comments")
                    ForEach(isExpanded ? comments : Array(comments.prefix(4))) { comment in
                        commentRow(comment)
                    }
                    if comments.count > 4 {
                        Button(isExpanded ? "Show Fewer" : "Show All \(comments.count)") {
                            withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .task(id: item.id) { await load() }
    }

    private func commentRow(_ comment: TraktComment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(comment.username)
                    .font(.subheadline.weight(.semibold))
                if comment.isReview {
                    Text("Review")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.primary.opacity(0.1), in: Capsule())
                }
                if let rating = comment.rating {
                    Label("\(rating)/10", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if comment.likes > 0 {
                    Label("\(comment.likes)", systemImage: "hand.thumbsup")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("\(comment.likes) likes")
                }
            }
            if comment.isSpoiler, !revealed.contains(comment.id) {
                Button {
                    revealed.insert(comment.id)
                } label: {
                    Label("Contains spoilers. Show anyway", systemImage: "eye.slash")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
            } else {
                Text(comment.text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(isExpanded ? nil : 6)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .frame(maxWidth: 760, alignment: .leading)
        .background(.primary.opacity(0.05), in: .rect(cornerRadius: 14, style: .continuous))
    }

    private func load() async {
        comments = []
        revealed = []
        guard let clientID = TraktExtrasClient.clientID,
              let loaded = try? await TraktExtrasClient.comments(on: item, clientID: clientID),
              !Task.isCancelled
        else { return }
        comments = loaded
    }
}
