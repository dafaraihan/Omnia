//
//  MediaDetailView.swift
//  Omnia
//

import SwiftUI

struct MediaDetailView: View {
    let item: MediaItem
    @Environment(OmniaStore.self) private var store
    @Environment(LiveMetadataStore.self) private var metadata
    @Environment(\.dismiss) private var dismiss
    @State private var resolvedItem: MediaItem?
    @State private var showsSourceSelector = false
    @State private var showsSynopsis = false
    @State private var creditSection: CreditSection = .cast
    @State private var selectedSeasonNumber = 1
    @State private var selectedEpisode: MediaEpisode?

    private var displayItem: MediaItem { resolvedItem ?? item }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                detailHero
                detailInformation
            }
        }
        .background(pageBackground)
        #if os(macOS)
        // Match Home: the scroll container, not merely its first child,
        // owns the top safe area. The detail hero can therefore meet the
        // stable transparent toolbar instead of leaving a black band.
        .ignoresSafeArea(edges: .top)
        #endif
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .task(id: item.id) {
            let resolved = await metadata.details(for: item)
            resolvedItem = resolved
            selectedSeasonNumber = resolved.details?.seasons.first?.seasonNumber ?? 1
        }
        .sheet(isPresented: $showsSourceSelector) {
            PlaybackSourceSheet(item: displayItem, episode: selectedEpisode)
        }
        .sheet(isPresented: $showsSynopsis) {
            SynopsisSheet(title: displayItem.title, synopsis: displayItem.overview)
        }
    }

    private var detailHero: some View {
        ZStack(alignment: .bottomLeading) {
            FeaturedBackdrop(item: displayItem, artworkAlignment: .topTrailing)

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                CinematicHeroColumn {
                    detailIdentity
                    actions
                }
            }
            .padding(.leading, CinematicHeroLayout.horizontalInset)
            .padding(.bottom, 34)
        }
        #if os(iOS)
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.42), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, horizontalInset)
            .padding(.top, 10)
            .accessibilityLabel("Back")
        }
        #endif
        .frame(maxWidth: .infinity, minHeight: detailHeroHeight, maxHeight: detailHeroHeight)
        // The hero owns the top safe area on every platform. On macOS the
        // compact system Back control floats above this artwork; it must not
        // create a separate black titlebar band.
        .ignoresSafeArea(edges: .top)
    }

    private var detailIdentity: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let logoURL = displayItem.logoURL {
                TitleLogoView(
                    url: logoURL,
                    title: displayItem.title,
                    maximumWidth: CinematicHeroLayout.logoWidth,
                    maximumHeight: CinematicHeroLayout.logoHeight,
                    alignment: .center
                )
            } else {
                // Detail metadata may update with a transparent logo after
                // the first render. Reserve its canvas rather than showing a
                // flash of duplicate title text.
                Color.clear
                    .frame(
                        width: CinematicHeroLayout.logoWidth,
                        height: CinematicHeroLayout.logoHeight,
                        alignment: .center
                    )
                    .accessibilityHidden(true)
            }

            HeroMetadataLine(item: displayItem)

            Button {
                showsSynopsis = true
            } label: {
                JustifiedSynopsisText(
                    text: displayItem.overview,
                    lineLimit: synopsisLineLimit,
                    fontSize: CinematicHeroLayout.synopsisFontSize
                )
                    .frame(width: CinematicHeroLayout.synopsisWidth, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Synopsis")
            .accessibilityHint("Opens the full synopsis")

        }
    }

    private var detailInformation: some View {
        VStack(alignment: .leading, spacing: 34) {
            if !displayItem.genres.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Genres")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    FlowLayout(spacing: 8) {
                        ForEach(displayItem.genres, id: \.self) { genre in
                            Text(genre)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(.primary.opacity(0.08), in: Capsule())
                        }
                    }
                }
            }

            if let details = displayItem.details {
                TitleFactsView(details: details)

                if displayItem.kind == .series, !details.seasons.isEmpty {
                    EpisodeShelf(
                        seasons: details.seasons,
                        selectedSeasonNumber: $selectedSeasonNumber,
                        selectEpisode: { episode in
                            selectedEpisode = episode
                            showsSourceSelector = true
                        }
                    )
                }

                if !details.trailers.isEmpty {
                    VideoShelf(title: "Trailers", videos: details.trailers)
                }

                if !details.bonusContent.isEmpty {
                    VideoShelf(title: "Bonus Content", videos: details.bonusContent)
                }

                if !displayPeople(for: details).isEmpty {
                    peopleSection(details: details)
                }

                if !details.studioTitles.isEmpty {
                    detailShelf(title: studioShelfTitle(details), items: details.studioTitles)
                }

                if let collection = details.collection, !collection.members.isEmpty {
                    detailShelf(title: collection.name, items: collection.members)
                }

                if !details.recommendations.isEmpty {
                    detailShelf(title: "More Like This", items: details.recommendations)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, horizontalInset)
        .padding(.top, 32)
        .padding(.bottom, 72)
        .background(pageBackground)
    }

    private var actions: some View {
        HeroActionRow(
            width: CinematicHeroLayout.logoWidth,
            isSaved: store.isSaved(displayItem),
            libraryAction: { store.toggleSaved(displayItem) }
        ) {
            Button {
                showsSourceSelector = true
            } label: {
                HeroPrimaryActionLabel(title: playbackActionTitle)
            }
            .buttonStyle(.plain)
        }
    }

    private func peopleSection(details: MediaTitleDetails) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("People")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Picker("People", selection: $creditSection) {
                    ForEach(CreditSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.menu)
                .tint(.primary)
            }

            ShelfScrollView(
                items: displayPeople(for: details),
                spacing: 14,
                itemSpan: 126,
                accessibilityLabel: "People"
            ) { person in
                CreditCard(person: person)
            }
        }
    }

    private func detailShelf(title: String, items: [MediaItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title)
            ShelfScrollView(items: items, itemSpan: posterItemSpan, accessibilityLabel: title) { related in
                MediaPoster(item: related)
            }
        }
    }

    private func displayPeople(for details: MediaTitleDetails) -> [MediaCredit] {
        switch creditSection {
        case .cast:
            return details.cast
        case .directors:
            return details.crew.filter { $0.role?.compare("Director", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        case .writers:
            return details.crew.filter {
                guard let role = $0.role?.lowercased() else { return false }
                return role.contains("writer") || role.contains("screenplay") || role.contains("story")
            }
        case .editors:
            return details.crew.filter { $0.role?.localizedCaseInsensitiveContains("editor") == true }
        }
    }

    private func studioShelfTitle(_ details: MediaTitleDetails) -> String {
        guard let studio = details.studios.first?.name, !studio.isEmpty else { return "Similar Titles" }
        return "More from \(studio)"
    }

    private var playbackActionTitle: String {
        guard let saved = store.library.first(where: { $0.id == displayItem.id }),
              let position = saved.positionSeconds,
              position > 0
        else { return "Play" }
        return saved.progress == nil ? "Rewatch" : "Resume"
    }

    private var horizontalInset: CGFloat {
        #if os(iOS)
        20
        #else
        48
        #endif
    }

    private var posterItemSpan: CGFloat {
        #if os(iOS)
        148
        #else
        170
        #endif
    }

    private var pageBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    private var detailHeroHeight: CGFloat {
        #if os(iOS)
        700
        #else
        820
        #endif
    }

    private var synopsisLineLimit: Int {
        #if os(iOS)
        3
        #else
        3
        #endif
    }

    private var titleFontSize: CGFloat {
        #if os(iOS)
        30
        #else
        38
        #endif
    }
}

private enum CreditSection: String, CaseIterable, Identifiable {
    case cast, directors, writers, editors

    var id: String { rawValue }
    var title: String {
        switch self {
        case .cast: "Cast"
        case .directors: "Director"
        case .writers: "Writer"
        case .editors: "Editor"
        }
    }
}

/// A TV-specific shelf. The season menu changes the source episode list while
/// preserving the broad, artwork-led cards used by the Apple TV reference.
private struct EpisodeShelf: View {
    let seasons: [MediaSeason]
    @Binding var selectedSeasonNumber: Int
    let selectEpisode: (MediaEpisode) -> Void
    @State private var showsSeasonChoices = false

    private var selectedSeason: MediaSeason? {
        seasons.first(where: { $0.seasonNumber == selectedSeasonNumber }) ?? seasons.first
    }

    private var episodeCardSpan: CGFloat {
        #if os(iOS)
        264
        #else
        320
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                showsSeasonChoices.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text(selectedSeason?.title ?? "Season")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 28)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose \(selectedSeason?.title ?? "season")")
            .popover(isPresented: $showsSeasonChoices, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(seasons) { season in
                        Button {
                            selectedSeasonNumber = season.seasonNumber
                            showsSeasonChoices = false
                        } label: {
                            HStack(spacing: 12) {
                                Text(season.title)
                                Spacer(minLength: 0)
                                if season.seasonNumber == selectedSeasonNumber {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                }
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .frame(minWidth: 180)
            }

            if let selectedSeason {
                ShelfScrollView(
                    items: selectedSeason.episodes,
                    itemSpan: episodeCardSpan,
                    accessibilityLabel: selectedSeason.title
                ) { episode in
                    EpisodeCard(episode: episode) { selectEpisode(episode) }
                }
            }
        }
    }
}

private struct EpisodeCard: View {
    let episode: MediaEpisode
    let action: () -> Void
    @State private var isHovered = false
    @State private var isPressing = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
            AsyncImage(url: episode.stillURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                LinearGradient(
                    colors: [.indigo.opacity(0.84), .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: "play.rectangle.fill")
                        .font(.title)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(width: cardWidth, height: artworkHeight)
            .clipped()
            .overlay {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.34)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            .overlay {
                Image(systemName: "play.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(width: 42, height: 42)
                    .background(.white, in: Circle())
                    .opacity(isHovered || isPressing ? 1 : 0)
                    .animation(.easeInOut(duration: 0.14), value: isHovered || isPressing)
            }
            .clipShape(.rect(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text("EPISODE \(episode.episodeNumber)")
                    .font(.caption2.weight(.bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                Text(episode.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(episode.overview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 7) {
                    if let releaseDateText {
                        Text(releaseDateText)
                    }
                    if releaseDateText != nil, episode.runtimeMinutes != nil {
                        Text("•")
                    }
                    if let runtime = episode.runtimeMinutes {
                        Text(runtimeText(runtime))
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: cardWidth, alignment: .leading)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressing = true }
                .onEnded { _ in isPressing = false }
        )
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Episode \(episode.episodeNumber), \(episode.title)")
        .accessibilityValue(episode.overview)
    }

    private func runtimeText(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 { return "\(hours)h \(remainder)m" }
        return "\(minutes)m"
    }

    private var cardWidth: CGFloat {
        #if os(iOS)
        248
        #else
        304
        #endif
    }

    private var artworkHeight: CGFloat {
        #if os(iOS)
        140
        #else
        172
        #endif
    }

    private var releaseDateText: String? {
        guard let airDate = episode.airDate,
              let date = Self.sourceDateFormatter.date(from: airDate)
        else { return nil }
        return Self.displayDateFormatter.string(from: date)
    }

    private static let sourceDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "d MMM yyyy"
        return formatter
    }()
}

private struct VideoShelf: View {
    let title: String
    let videos: [MediaVideo]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title)
            ShelfScrollView(items: videos, itemSpan: videoCardSpan, accessibilityLabel: title) { video in
                Link(destination: video.watchURL) {
                    VideoCard(video: video)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play \(video.title) in YouTube")
            }
        }
    }

    private var videoCardSpan: CGFloat {
        #if os(iOS)
        264
        #else
        320
        #endif
    }
}

/// TMDB's official YouTube metadata contains a watch-page key, not a native
/// HLS/MP4 asset. A Link therefore opens the provider's official player rather
/// than attempting unsupported playback through AVPlayer.
private struct VideoCard: View {
    let video: MediaVideo

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: video.thumbnailURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                LinearGradient(colors: [.red.opacity(0.7), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .center, endPoint: .bottom)
            Image(systemName: "play.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 42, height: 42)
                .background(.white, in: Circle())
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(video.type.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.75))
                Text(video.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
            .padding(14)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
    }

    private var cardWidth: CGFloat {
        #if os(iOS)
        248
        #else
        304
        #endif
    }

    private var cardHeight: CGFloat {
        #if os(iOS)
        140
        #else
        172
        #endif
    }
}

private struct TitleFactsView: View {
    let details: MediaTitleDetails

    var body: some View {
        let facts = facts
        if !facts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Details")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 18)], alignment: .leading, spacing: 14) {
                    ForEach(facts, id: \.title) { fact in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(fact.title.uppercased())
                                .font(.caption2.weight(.bold))
                                .tracking(0.8)
                                .foregroundStyle(.secondary)
                            Text(fact.value)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
    }

    private var facts: [(title: String, value: String)] {
        var result: [(String, String)] = []
        if !details.studios.isEmpty { result.append(("Studio", details.studios.map(\.name).joined(separator: ", "))) }
        if let runtime = details.runtimeMinutes { result.append(("Runtime", "\(runtime) min")) }
        if let status = details.status { result.append(("Status", status)) }
        if let budget = details.budget, budget > 0 { result.append(("Budget", Self.currency.string(from: NSNumber(value: budget)) ?? "—")) }
        if let revenue = details.revenue, revenue > 0 { result.append(("Revenue", Self.currency.string(from: NSNumber(value: revenue)) ?? "—")) }
        return result
    }

    private static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

private struct CreditCard: View {
    let person: MediaCredit

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            AsyncImage(url: person.profileURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.primary.opacity(0.08))
            }
            .frame(width: 104, height: 104)
            .clipShape(Circle())

            Text(person.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if let subtitle = person.character ?? person.role {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 112, alignment: .leading)
    }
}

private struct SynopsisSheet: View {
    let title: String
    let synopsis: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(synopsis)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A compact wrapping layout for the small, immutable genre labels in a title
/// detail page. It avoids a horizontally scrolling metadata row on iPhone.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .greatestFiniteMagnitude
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let proposedX = x == 0 ? size.width : x + spacing + size.width
            if x > 0, proposedX > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            if x > 0 { x += spacing }
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }

        return .init(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let proposedX = x == bounds.minX ? x + size.width : x + spacing + size.width
            if x > bounds.minX, proposedX > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            if x > bounds.minX { x += spacing }
            subview.place(at: .init(x: x, y: y), proposal: .unspecified)
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }
    }
}
