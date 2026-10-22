//
//  TitleDetailPages.swift
//  Omnia
//

import SwiftUI

// The pages a title page's sections open, as in Nuvio Enhanced: a person,
// a production company or network, and the full More Like This, Similar and
// Collection lists.

/// A person's page (Nuvio's PersonDetailScreen): photo, facts, biography and
/// the titles they acted in or worked on.
struct PersonDetailView: View {
    let personID: String
    let name: String
    var photoURL: URL?
    var prefersCrew = false
    @Environment(LiveMetadataStore.self) private var metadata
    @Environment(\.displayPreferences) private var display
    @State private var page: PersonPage?
    @State private var errorMessage: String?
    @State private var showsCrew = false
    @State private var showsFullBiography = false

    private var credits: [PersonPage.Credit] {
        guard let page else { return [] }
        return showsCrew ? page.crew : page.cast
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                header
                if let page {
                    if let biography = page.biography {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Biography")
                            Text(biography)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .lineLimit(showsFullBiography ? nil : 6)
                            Button(showsFullBiography ? "Show Less" : "Show More") {
                                showsFullBiography.toggle()
                            }
                            .buttonStyle(.link)
                        }
                    }
                    if credits.isEmpty {
                        ContentUnavailableView("No Titles", systemImage: "film")
                            .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeader(title: showsCrew ? "Behind the Camera" : "Known For")
                            LazyVGrid(
                                columns: MediaBrowseMetrics.posterGridColumns(display),
                                alignment: .leading,
                                spacing: MediaBrowseMetrics.gridRowSpacing
                            ) {
                                ForEach(credits) { credit in
                                    VStack(alignment: .leading, spacing: 3) {
                                        MediaPoster(item: credit.item, fillsAvailableWidth: true)
                                        if let role = credit.role {
                                            Text(role)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("Person Unavailable", systemImage: "person.crop.circle.badge.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Try Again") { Task { await load() } }
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 220)
                }
            }
            .padding(.horizontal, MediaBrowseMetrics.pageInset)
            .padding(.vertical, 24)
        }
        .omniaNavigationTitle(page?.name ?? name)
        .toolbar {
            if let page, !page.cast.isEmpty, !page.crew.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker(selection: $showsCrew) {
                            Text("Acting").tag(false)
                            Text("Crew").tag(true)
                        } label: {
                            Label("Credits", systemImage: "person.2")
                        }
                        .pickerStyle(.menu)
                    } label: {
                        Label("Filter and Sort", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .help("Filter and Sort")
                }
            }
        }
        .task(id: personID) { await load() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 22) {
            CachedArtworkImage(url: page?.profileURL ?? photoURL, size: CGSize(width: 150, height: 225)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.primary.opacity(0.08))
                }
            }
            .frame(width: 150, height: 225)
            .clipShape(.rect(cornerRadius: display.posterCornerRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text(page?.name ?? name)
                    .font(.largeTitle.weight(.bold))
                if let department = page?.knownForDepartment {
                    Text(department)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                ForEach(facts, id: \.label) { fact in
                    LabeledContent(fact.label, value: fact.value)
                        .font(.subheadline)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var facts: [(label: String, value: String)] {
        guard let page else { return [] }
        var facts: [(label: String, value: String)] = []
        if let birthday = page.birthday.flatMap(TitleFactFormat.date) {
            let age = page.deathday == nil ? page.birthday.flatMap(TitleFactFormat.age).map { " (age \($0))" } ?? "" : ""
            facts.append(("Born", birthday + age))
        }
        if let place = page.placeOfBirth { facts.append(("Place of Birth", place)) }
        if let deathday = page.deathday.flatMap(TitleFactFormat.date) { facts.append(("Died", deathday)) }
        return facts
    }

    private func load() async {
        errorMessage = nil
        do {
            let loaded = try await metadata.person(id: personID)
            page = loaded
            showsCrew = prefersCrew ? !loaded.crew.isEmpty : loaded.cast.isEmpty && !loaded.crew.isEmpty
        } catch {
            errorMessage = "Omnia couldn't load this person. Check your connection and try again."
        }
    }
}

/// A production company's or TV network's titles (Nuvio's
/// TmdbEntityBrowseScreen). More load automatically at the bottom.
struct EntityTitlesView: View {
    let kind: MetadataEntityKind
    let entityID: String
    let name: String
    var logoURL: URL?
    let initialType: MediaType
    @Environment(LiveMetadataStore.self) private var metadata
    @State private var type: MediaType?

    private var currentType: MediaType {
        kind == .network ? .series : type ?? initialType
    }

    var body: some View {
        PagedTitleGrid(requestKey: "\(kind.rawValue)|\(entityID)|\(currentType.rawValue)") { page in
            try await metadata.entityPage(kind: kind, id: entityID, type: currentType, page: page)
        } header: {
            if let logoURL {
                CachedArtworkImage(url: logoURL, size: CGSize(width: 220, height: 70), contentMode: .fit) { phase in
                    phase.image?.resizable().scaledToFit()
                }
                .frame(maxWidth: 220, maxHeight: 70, alignment: .leading)
                .padding(14)
                .background(.white.opacity(0.92), in: .rect(cornerRadius: 14, style: .continuous))
            }
        }
        .omniaNavigationTitle(name)
        .toolbar {
            // Networks only list series.
            if kind == .company {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker(selection: typeBinding) {
                            Text("Movies").tag(MediaType.movie)
                            Text("Series").tag(MediaType.series)
                        } label: {
                            Label("Type", systemImage: "film.stack")
                        }
                        .pickerStyle(.menu)
                    } label: {
                        Label("Filter and Sort", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .help("Filter and Sort")
                }
            }
        }
    }

    private var typeBinding: Binding<MediaType> {
        Binding(get: { currentType }, set: { type = $0 })
    }
}

/// Every More Like This or Similar title behind a section's header.
struct RelatedTitlesView: View {
    let kind: MetadataRelatedKind
    let tmdbID: String
    let type: MediaType
    let title: String
    @Environment(LiveMetadataStore.self) private var metadata

    var body: some View {
        PagedTitleGrid(requestKey: "\(kind.rawValue)|\(tmdbID)|\(type.rawValue)") { page in
            try await metadata.relatedPage(kind: kind, tmdbID: tmdbID, type: type, page: page)
        } header: {
            EmptyView()
        }
        .omniaNavigationTitle(title)
    }
}

/// A section's titles already on the page, such as a collection.
struct TitleListView: View {
    let title: String
    let items: [MediaItem]
    @Environment(\.displayPreferences) private var display

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: MediaBrowseMetrics.posterGridColumns(display),
                alignment: .leading,
                spacing: MediaBrowseMetrics.gridRowSpacing
            ) {
                ForEach(items) { item in
                    MediaPoster(item: item, fillsAvailableWidth: true)
                }
            }
            .padding(.horizontal, MediaBrowseMetrics.pageInset)
            .padding(.vertical, 24)
        }
        .omniaNavigationTitle(title)
    }
}

/// A poster grid that loads the next page on its own at the bottom, with
/// no page numbers.
private struct PagedTitleGrid<Header: View>: View {
    let requestKey: String
    let load: (Int) async throws -> TitleListPage
    @ViewBuilder let header: () -> Header
    @Environment(\.displayPreferences) private var display
    @State private var items: [MediaItem] = []
    @State private var nextPage = 1
    @State private var hasReachedEnd = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                header()
                if isLoading && items.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else if let errorMessage, items.isEmpty {
                    ContentUnavailableView {
                        Label("Titles Unavailable", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Try Again") { Task { await loadNextPage() } }
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else if items.isEmpty && hasReachedEnd {
                    ContentUnavailableView("No Titles Found", systemImage: "film")
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    LazyVGrid(
                        columns: MediaBrowseMetrics.posterGridColumns(display),
                        alignment: .leading,
                        spacing: MediaBrowseMetrics.gridRowSpacing
                    ) {
                        ForEach(items) { item in
                            MediaPoster(item: item, fillsAvailableWidth: true)
                        }
                    }
                    if !hasReachedEnd {
                        Color.clear
                            .frame(height: 1)
                            .task(id: items.count) {
                                await Task { await loadNextPage() }.value
                            }
                    }
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    }
                }
            }
            .padding(.horizontal, MediaBrowseMetrics.pageInset)
            .padding(.vertical, 24)
        }
        .task(id: requestKey) {
            items = []
            nextPage = 1
            hasReachedEnd = false
            errorMessage = nil
            isLoading = false
            await loadNextPage()
        }
    }

    private func loadNextPage() async {
        guard !isLoading, !hasReachedEnd else { return }
        let key = requestKey
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await load(nextPage)
            guard key == requestKey else { return }
            let known = Set(items.map(\.id))
            items += page.items.filter { !known.contains($0.id) }
            nextPage += 1
            hasReachedEnd = !page.hasMore || page.items.isEmpty
        } catch {
            guard key == requestKey else { return }
            errorMessage = "Omnia couldn't load these titles. Check your connection and try again."
            if !items.isEmpty { hasReachedEnd = true }
        }
    }
}

/// Formats shared by the title page's Details section and person pages.
nonisolated enum TitleFactFormat {
    private static func day(_ text: String) -> Date? {
        try? Date(String(text.prefix(10)), strategy: Date.ISO8601FormatStyle().year().month().day().dateSeparator(.dash))
    }

    static func date(_ text: String) -> String? {
        day(text)?.formatted(date: .long, time: .omitted)
    }

    static func age(_ birthday: String) -> Int? {
        day(birthday).flatMap { Calendar.current.dateComponents([.year], from: $0, to: .now).year }
    }

    static func country(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }

    static func language(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    static func usd(_ amount: Int) -> String {
        amount.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}
