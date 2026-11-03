//
//  PlaybackViews.swift
//  Omnia
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct PlaybackSourceHandoff {
    static func preparedItem(original: MediaItem, enriched: MediaItem) -> MediaItem {
        original.mergingSourceIdentifiers(from: enriched)
    }
}

struct PlaybackSourceSheet: View {
    let item: MediaItem
    var episode: MediaEpisode? = nil
    var resumeAt: Double? = nil
    /// Opened for the next episode from the player. Nuvio's next-episode
    /// rules then replace the library rules, and `nextEpisodeRequest` nil
    /// shows the list.
    var isNextEpisode = false
    var nextEpisodeRequest: StreamAutoPlayRequest? = nil
    /// Opened over the video: just the sources, without the title's
    /// artwork and details (Dafa, 2026-10-22).
    var presentedInPlayer = false
    var onClose: (() -> Void)? = nil

    @Environment(OmniaStore.self) private var store
    @Environment(LiveMetadataStore.self) private var metadata
    @Environment(PlaybackSession.self) private var playback
    @Environment(SettingsPreferencesStore.self) private var settings
    @Environment(PluginStore.self) private var plugins
    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [AddonStreamCandidate] = []
    @State private var resolution: PlaybackSourceResolution?
    @State private var preparedPlaybackItem: MediaItem?
    @State private var isResolving = true
    @State private var pendingSourceCount = 0
    @State private var selectionID: UUID?
    @State private var isHandingOffPlayback = false
    @State private var retryingAddonIDs: Set<String> = []
    @State private var selectedAddonID: String?
    @State private var resolvingCandidateID: String?
    @State private var resolverFailures: [String: String] = [:]
    @State private var localResolverSettings = LocalResolverSettingsStore()
    @State private var pendingLocalTorrentCandidate: AddonStreamCandidate?
    @State private var localTorrentProgress: [String: Double] = [:]
    @State private var autoSelection: StreamAutoSelectionRun?
    /// Shown while a source is being chosen automatically.
    @State private var autoSelectionStatus: String?
    @State private var lastLinkTask: Task<Void, Never>?
    @State private var choosesManually = false
    /// The title with its artwork and logo, for the page's backdrop.
    @State private var pageItem: MediaItem?
    @State private var searchText = ""
    #if os(macOS)
    @State private var localTorrentEngine: OMLocalTorrentEngine?
    @State private var localTorrentTask: Task<Void, Never>?
    @State private var discMaterializer: DiscMaterializer?
    @State private var discPreparationTask: Task<Void, Never>?
    @State private var preparingDiscCandidateID: String?
    @State private var discPreparationStates: [String: DiscPreparationState] = [:]
    #endif

    var body: some View {
        sourcePage
            .task(id: mediaKey) {
                let selectionID = playback.beginSourceSelection()
                self.selectionID = selectionID
                isHandingOffPlayback = false
                isResolving = true
                pendingSourceCount = 0
                candidates = []
                resolution = nil
                preparedPlaybackItem = nil
                selectedAddonID = nil
                searchText = ""
                resolverFailures = [:]
                choosesManually = false
                autoSelection?.cancel()
                autoSelection = nil
                autoSelectionStatus = nil
                let enrichedItem = await metadata.details(for: item)
                guard !Task.isCancelled, playback.isCurrentSourceSelection(selectionID) else { return }
                pageItem = enrichedItem
                let lookupItem = PlaybackSourceHandoff.preparedItem(
                    original: item,
                    enriched: enrichedItem
                )
                preparedPlaybackItem = lookupItem
                if await playLastLinkIfAllowed(selectionID: selectionID) { return }
                guard !Task.isCancelled, playback.isCurrentSourceSelection(selectionID) else { return }
                startAutomaticSelection()
                if let preloaded = playback.takePreloadedSources(for: mediaKey) {
                    resolution = preloaded
                    candidates = ranked(preloaded.candidates)
                    pendingSourceCount = 0
                    isResolving = false
                    autoSelection?.receive(candidates, isComplete: true)
                    return
                }
                let result = await PlaybackSourceResolver.resolve(
                    for: lookupItem,
                    episode: episode,
                    addons: store.installedAddons,
                    plugins: plugins.plan(for: lookupItem, episode: episode),
                    servers: MediaServerStore.shared.streamPlan(),
                    timeout: settings.preferences.addonTimeout
                ) { partial, pending in
                    // Show what has arrived instead of waiting for the
                    // slowest add-on, like Nuvio.
                    guard !Task.isCancelled, playback.isCurrentSourceSelection(selectionID),
                          !partial.candidates.isEmpty else { return }
                    resolution = partial
                    candidates = ranked(partial.candidates)
                    pendingSourceCount = pending
                    isResolving = false
                    autoSelection?.receive(candidates, isComplete: false)
                }
                guard !Task.isCancelled, playback.isCurrentSourceSelection(selectionID) else { return }
                resolution = result
                candidates = ranked(result.candidates)
                pendingSourceCount = 0
                isResolving = false
                autoSelection?.receive(candidates, isComplete: true)
            }
            .confirmationDialog(
                "Allow Local Peer Playback?",
                isPresented: localTorrentConsentPresentation,
                titleVisibility: .visible
            ) {
                Button("Allow and Download") {
                    guard let candidate = pendingLocalTorrentCandidate else { return }
                    pendingLocalTorrentCandidate = nil
                    localResolverSettings.acceptConsent()
                    downloadLocalTorrent(candidate)
                }
                Button("Cancel", role: .cancel) {
                    pendingLocalTorrentCandidate = nil
                }
            } message: {
                Text(LocalTorrentConsent.disclosure)
            }
            .onDisappear {
                autoSelection?.cancel()
                autoSelection = nil
                lastLinkTask?.cancel()
                if !isHandingOffPlayback, let selectionID {
                    playback.cancelSourceSelection(selectionID)
                }
                #if os(macOS)
                localTorrentEngine?.cancel()
                localTorrentEngine = nil
                localTorrentTask?.cancel()
                localTorrentTask = nil
                discPreparationTask?.cancel()
                discPreparationTask = nil
                discMaterializer = nil
                #endif
            }
    }

    /// Nuvio's streams page: the backdrop and the title's logo or episode
    /// on the left, the sources in a glass panel on the right.
    @ViewBuilder
    private var sourcePage: some View {
        #if os(macOS)
        if presentedInPlayer {
            StreamsPlayerPanelLayout(onClose: { closePresentation() }) {
                sourcePanel
            }
            .tint(settings.preferences.display.accentColor)
        } else {
            streamsPage
        }
        #else
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Cancel") { closePresentation() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            sourcePanel
        }
        .tint(settings.preferences.display.accentColor)
        .modifier(StreamSheetSizing())
        #endif
    }

    #if os(macOS)
    private var streamsPage: some View {
        StreamsPageLayout(
            item: pageItem ?? item,
            episode: episode,
            resumeAt: resumeAt,
            background: streamPreferences.background,
            onClose: { closePresentation() }
        ) {
            sourcePanel
        }
        .tint(settings.preferences.display.accentColor)
    }
    #endif

    private var streamPreferences: StreamPagePreferences {
        settings.preferences.streams
    }

    private var sourcePanel: some View {
        VStack(spacing: 0) {
            panelHeader

            if let autoSelectionStatus {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(autoSelectionStatus)
                        .font(.callout.weight(.medium))
                        .lineLimit(2)
                    Spacer(minLength: 12)
                    Button("Choose Manually", action: chooseManually)
                        .buttonStyle(.borderless)
                        .fontWeight(.semibold)
                        .accessibilityHint("Stops automatic selection so you can pick a source")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.tint.opacity(0.16), in: .rect(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
                .transition(.opacity)
            }

            if isResolving {
                OmniaLoadingRow("Finding sources…")
                    .frame(maxHeight: .infinity)
            } else if candidates.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ContentUnavailableView(
                            "No Sources Found",
                            systemImage: "play.slash",
                            description: Text(emptyStateDescription)
                        )
                        .frame(maxWidth: .infinity)
                        if !addonStatusResults.isEmpty {
                            addonStatusList
                        }
                    }
                    .padding(18)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                sourceFilters
                if streamPreferences.showsSearchBar {
                    searchField
                }
                sourceList
            }
        }
        .animation(.snappy(duration: 0.2), value: autoSelectionStatus)
    }

    private var panelHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Streams")
                    .font(.title2.weight(.bold))
                Text(headerSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            if pendingSourceCount > 0 {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(pendingSourceCount == 1
                         ? "Checking 1 more"
                         : "Checking \(pendingSourceCount) more")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white.opacity(0.08), in: .capsule)
                .accessibilityLabel(pendingSourceCount == 1
                                    ? "Still checking 1 more source"
                                    : "Still checking \(pendingSourceCount) more sources")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var headerSubtitle: String {
        let title = (pageItem ?? item).title
        guard let episode else { return title }
        return "\(title) · S\(episode.seasonNumber) · E\(episode.episodeNumber)"
    }

    /// Nuvio Enhanced's stream search: every word must appear somewhere in
    /// the stream's name, description, file name or add-on.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search streams", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.07), in: .rect(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }

    private var searchTerms: [String] {
        guard streamPreferences.showsSearchBar else { return [] }
        return searchText.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private var emptyStateDescription: String {
        if let resolution {
            return resolution.emptyStateDescription
        }
        if let episode {
            return "No enabled add-on returned a stream for S\(episode.seasonNumber), E\(episode.episodeNumber)."
        }
        return "Enable a trusted add-on that supplies a stream for this title."
    }

    private var sourceSections: PlaybackSourceSections {
        PlaybackSourceSections(candidates: filteredCandidates)
    }

    /// Show Only Compatible Formats hides web pages and sources Omnia can't
    /// open, so the list holds only what plays in the app.
    private var hidesIncompatibleSources: Bool {
        settings.preferences.compatibleFormatsOnly
    }

    private var hiddenIncompatibleCount: Int {
        sourceSections.external.count + sourceSections.unavailable.count
    }

    private var addonStatusResults: [AddonSourceResolution] {
        resolution?.addonResults.filter { $0.state != .loaded } ?? []
    }

    private var addonStatusList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add-on Status")
                .font(.subheadline.weight(.bold))
                .padding(.top, 10)
            ForEach(addonStatusResults) { result in
                addonStatusRow(result)
                    .padding(12)
                    .background(.white.opacity(0.05), in: .rect(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func addonStatusRow(_ result: AddonSourceResolution) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: result.state == .failed ? "wifi.exclamationmark" : "tray")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(result.addonName)
                    .font(.body.weight(.semibold))
                Text(result.statusDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button("Retry") {
                retryAddon(result.addonID)
            }
            .disabled(retryingAddonIDs.contains(result.addonID))
            .accessibilityLabel("Retry \(result.addonName)")
        }
    }

    private func retryAddon(_ addonID: String) {
        if PluginStreamResolver.isPluginSource(addonID) {
            retryPlugin(addonID)
            return
        }
        if MediaServerIdentifier.isServerSource(addonID) {
            retryServer(addonID)
            return
        }
        guard let resolution,
              !retryingAddonIDs.contains(addonID),
              let addon = enabledStreamAddons.first(where: { $0.id == addonID })
        else { return }

        retryingAddonIDs.insert(addonID)
        Task {
            let result = await PlaybackSourceResolver.resolve(
                addon: addon,
                mediaTypes: item.streamMediaTypes,
                identifiers: resolution.attemptedIdentifiers,
                timeout: settings.preferences.addonTimeout,
                transport: HTTPTransport()
            )
            guard !Task.isCancelled else { return }
            let updated = resolution.replacingAddonResult(result)
            self.resolution = updated
            candidates = ranked(updated.candidates)
            retryingAddonIDs.remove(addonID)
        }
    }

    private func retryPlugin(_ sourceID: String) {
        guard resolution != nil, !retryingAddonIDs.contains(sourceID) else { return }
        let plan = plugins.plan(forSourceID: sourceID)
        guard !plan.entries.isEmpty else { return }
        let lookupItem = preparedPlaybackItem ?? item
        retryingAddonIDs.insert(sourceID)
        Task {
            let results = await PluginStreamResolver.resolve(plan, for: lookupItem, episode: episode)
            guard !Task.isCancelled, var updated = resolution else { return }
            for result in results { updated = updated.replacingAddonResult(result) }
            self.resolution = updated
            candidates = ranked(updated.candidates)
            retryingAddonIDs.remove(sourceID)
        }
    }

    private func retryServer(_ sourceID: String) {
        guard resolution != nil, !retryingAddonIDs.contains(sourceID),
              let entry = MediaServerStore.shared.streamPlan(forSourceID: sourceID).entries.first
        else { return }
        let lookupItem = preparedPlaybackItem ?? item
        retryingAddonIDs.insert(sourceID)
        Task {
            let result = await MediaServerStreamResolver.resolve(entry, item: lookupItem, episode: episode)
            guard !Task.isCancelled, let current = resolution else { return }
            let updated = current.replacingAddonResult(result)
            self.resolution = updated
            candidates = ranked(updated.candidates)
            retryingAddonIDs.remove(sourceID)
        }
    }

    /// Media servers that answered for this title.
    private var serverSources: [AddonSourceResolution] {
        (resolution?.addonResults ?? []).filter { MediaServerIdentifier.isServerSource($0.addonID) }
    }

    private var enabledStreamAddons: [InstalledAddon] {
        store.installedAddons.filter { $0.isEnabled && $0.manifest.supportsStreams }
    }

    private var filteredCandidates: [AddonStreamCandidate] {
        guard let selectedAddonID else { return candidates }
        if let repository = pluginRepositories.first(where: { $0.filterID == selectedAddonID }) {
            return candidates.filter { repository.sourceIDs.contains($0.addonID) }
        }
        return candidates.filter { $0.addonID == selectedAddonID }
    }

    /// Plugin providers get a filter each, like add-ons, as in Nuvio: one per
    /// repository, or one per plugin when Group by Repository is off.
    private var pluginRepositories: [(filterID: String, name: String, sourceIDs: Set<String>)] {
        guard plugins.pluginsEnabled else { return [] }
        guard plugins.groupsByRepository else {
            return plugins.scrapers.filter(\.isEnabled).map { scraper in
                let sourceID = PluginStreamResolver.sourceID(for: scraper)
                return (sourceID, scraper.name, [sourceID])
            }
        }
        return plugins.repositories.compactMap { repository in
            let sourceIDs = Set(
                plugins.scrapers
                    .filter { $0.repositoryURL == repository.manifestURL && $0.isEnabled }
                    .map(PluginStreamResolver.sourceID(for:))
            )
            guard !sourceIDs.isEmpty else { return nil }
            return ("plugin-repository:" + repository.id, repository.name, sourceIDs)
        }
    }

    /// Nuvio's provider row: refresh, All, then one chip per add-on and
    /// plugin repository.
    private var sourceFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                StreamFilterChip(
                    title: "",
                    count: nil,
                    systemImage: "arrow.clockwise",
                    isSelected: false,
                    isLoading: !retryingAddonIDs.isEmpty,
                    accessibilityText: "Refresh sources",
                    action: refreshAllSources
                )
                .disabled(resolution == nil || !retryingAddonIDs.isEmpty)
                .help("Refresh")

                StreamFilterChip(
                    title: "All",
                    count: candidates.count,
                    isSelected: selectedAddonID == nil
                ) {
                    selectedAddonID = nil
                }

                ForEach(enabledStreamAddons) { addon in
                    StreamFilterChip(
                        title: addon.displayName,
                        count: candidates.filter { $0.addonID == addon.id }.count,
                        logoURL: addon.manifest.presentationLogoURL,
                        isSelected: selectedAddonID == addon.id,
                        isLoading: retryingAddonIDs.contains(addon.id)
                    ) {
                        selectedAddonID = addon.id
                    }
                }

                ForEach(pluginRepositories, id: \.filterID) { repository in
                    StreamFilterChip(
                        title: repository.name,
                        count: candidates.filter { repository.sourceIDs.contains($0.addonID) }.count,
                        systemImage: "puzzlepiece.extension",
                        isSelected: selectedAddonID == repository.filterID
                    ) {
                        selectedAddonID = repository.filterID
                    }
                }

                ForEach(serverSources, id: \.addonID) { source in
                    StreamFilterChip(
                        title: source.addonName,
                        count: candidates.filter { $0.addonID == source.addonID }.count,
                        systemImage: "server.rack",
                        isSelected: selectedAddonID == source.addonID,
                        isLoading: retryingAddonIDs.contains(source.addonID)
                    ) {
                        selectedAddonID = source.addonID
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
        }
        .padding(.bottom, 6)
        .accessibilityLabel("Add-on source filters")
    }

    /// Asks every add-on and plugin again, without restarting automatic
    /// selection or Reuse Last Link.
    private func refreshAllSources() {
        guard let resolution else { return }
        for result in resolution.addonResults {
            retryAddon(result.addonID)
        }
    }

    private struct StreamSourceGroup: Identifiable {
        let id: String
        let title: String
        let logoURL: URL?
        let isPinned: Bool
        var candidates: [AddonStreamCandidate]
    }

    private enum StreamRowKind {
        case direct, resolverRequired, unavailable
    }

    private var sourceList: some View {
        let sections = sourceSections
        let groups = sourceGroups(from: sections)
        let directIDs = Set(sections.direct.map(\.id))
        let resolverIDs = Set(sections.resolverRequired.map(\.id))
        // A single add-on needs no headings; All and plugin repositories,
        // which hold several sources, are grouped like Nuvio.
        let showsHeaders = selectedAddonID == nil
            || pluginRepositories.contains { $0.filterID == selectedAddonID && $0.sourceIDs.count > 1 }

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if groups.isEmpty, !searchTerms.isEmpty {
                    Text("No streams match \u{201C}\(searchText)\u{201D}.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }

                ForEach(groups) { group in
                    if showsHeaders {
                        StreamSectionHeader(
                            title: group.title,
                            count: group.candidates.count,
                            logoURL: group.logoURL,
                            isPinned: group.isPinned,
                            isLoading: retryingAddonIDs.contains(group.id)
                                || group.candidates.contains { retryingAddonIDs.contains($0.addonID) }
                        )
                        .contentShape(.rect)
                        .contextMenu { pinButton(sourceID: group.id, name: group.title) }
                    }
                    ForEach(group.candidates) { candidate in
                        let kind: StreamRowKind = directIDs.contains(candidate.id)
                            ? .direct
                            : resolverIDs.contains(candidate.id) ? .resolverRequired : .unavailable
                        streamRow(candidate, kind: kind)
                            .contextMenu { pinButton(sourceID: group.id, name: group.title) }
                    }
                }

                if !sections.resolverRequired.isEmpty {
                    Text("Peer-to-peer sources are resolved locally into Omnia's bounded cache, then the completed file or a validated single BDMV tree opens with libmpv. Peer activity never starts through autoplay.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }

                if hidesIncompatibleSources, hiddenIncompatibleCount > 0 {
                    Text(hiddenIncompatibleCount == 1
                         ? "1 source that can't play in Omnia is hidden. Turn off Show Only Compatible Formats in Settings to see it."
                         : "\(hiddenIncompatibleCount) sources that can't play in Omnia are hidden. Turn off Show Only Compatible Formats in Settings to see them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }

                // Sources come first; add-ons and plugins that found
                // nothing are listed after them.
                if !addonStatusResults.isEmpty {
                    addonStatusList
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
    }

    @ViewBuilder
    private func streamRow(_ candidate: AddonStreamCandidate, kind: StreamRowKind) -> some View {
        switch kind {
        case .direct: playbackButton(candidate)
        case .resolverRequired: resolverRequiredRow(candidate)
        case .unavailable: unavailableRow(candidate)
        }
    }

    /// The visible streams grouped by add-on in result order, with pinned
    /// add-ons first in the order they were pinned (Nuvio Enhanced).
    private func sourceGroups(from sections: PlaybackSourceSections) -> [StreamSourceGroup] {
        var ordered = sections.direct + sections.resolverRequired
        if !hidesIncompatibleSources {
            ordered += sections.external + sections.unavailable
        }
        let terms = searchTerms
        if !terms.isEmpty {
            ordered = ordered.filter { candidate in
                let text = [
                    candidate.displayName,
                    candidate.displayDescription ?? "",
                    candidate.filename ?? "",
                    candidate.addonName
                ].joined(separator: " ")
                return terms.allSatisfy { text.localizedCaseInsensitiveContains($0) }
            }
        }

        let preferences = streamPreferences
        // With Group by Repository on, a repository's plugins share one
        // section, as Nuvio shows one provider per repository.
        let pluginGroups = Dictionary(
            pluginRepositories.flatMap { provider in provider.sourceIDs.map { ($0, provider) } },
            uniquingKeysWith: { first, _ in first }
        )
        var groups: [StreamSourceGroup] = []
        var indexByID: [String: Int] = [:]
        for candidate in ordered {
            let provider = plugins.groupsByRepository ? pluginGroups[candidate.addonID] : nil
            let groupID = provider?.filterID ?? candidate.addonID
            if let index = indexByID[groupID] {
                groups[index].candidates.append(candidate)
            } else {
                indexByID[groupID] = groups.count
                let addon = enabledStreamAddons.first { $0.id == candidate.addonID }
                groups.append(StreamSourceGroup(
                    id: groupID,
                    title: provider?.name ?? addon?.displayName ?? candidate.addonName,
                    logoURL: addon?.manifest.presentationLogoURL,
                    isPinned: preferences.isPinned(groupID),
                    candidates: [candidate]
                ))
            }
        }
        let pinOrder = Dictionary(
            preferences.pinnedSourceIDs.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let pinned = groups.filter(\.isPinned).sorted { (pinOrder[$0.id] ?? 0) < (pinOrder[$1.id] ?? 0) }
        return pinned + groups.filter { !$0.isPinned }
    }

    private func pinButton(sourceID: String, name: String) -> some View {
        let isPinned = streamPreferences.isPinned(sourceID)
        return Button(
            isPinned ? "Unpin \(name)" : "Pin \(name) to Top",
            systemImage: isPinned ? "pin.slash" : "pin"
        ) {
            settings.update { $0.streams.togglePin(sourceID) }
        }
    }

    private func addonLogoURL(for addonID: String) -> URL? {
        enabledStreamAddons.first { $0.id == addonID }?.manifest.presentationLogoURL
    }

    @ViewBuilder
    private func playbackButton(_ candidate: AddonStreamCandidate) -> some View {
        if let source = candidate.nativePlaybackSource {
            #if os(macOS)
            let rowState = PlaybackSourceRowState(candidate: candidate)
            let preparationState = discPreparationStates[candidate.id]
            let preparationStatus = preparationState.map {
                DiscPreparationPresentation(state: $0).status
            } ?? rowState.idleStatus
            HStack(spacing: 8) {
                Button {
                    switch rowState.action {
                    case .playDirect:
                        beginDirectPlayback(source, candidate: candidate)
                    case .prepareDisc:
                        prepareHTTPSDisc(candidate)
                    case .resolve, .unavailable:
                        break
                    }
                } label: {
                    candidateRow(
                        candidate,
                        symbol: rowState.action == .prepareDisc
                            ? "opticaldisc.fill"
                            : "play.fill",
                        status: preparationStatus
                    )
                }
                .buttonStyle(.plain)
                .disabled(
                    rowState.isPrimaryActionDisabled(
                        isLocalPreparationActive: isLocalPreparationActive
                    )
                )
                .accessibilityHint(
                    rowState.action == .prepareDisc
                        ? "Downloads the disc into Omnia's local cache, then starts playback"
                        : "Starts native playback"
                )

                if rowState.allowsExplicitDiscPreparation,
                   rowState.action == .playDirect {
                    Menu {
                        Button("Prepare as Blu-ray Disc", systemImage: "opticaldisc") {
                            prepareHTTPSDisc(candidate)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .frame(width: 28, height: 28)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .disabled(isLocalPreparationActive)
                    .accessibilityLabel("More source actions")
                }
            }
            #else
            Button {
                beginPlayback(source, candidate: candidate)
            } label: {
                candidateRow(candidate, symbol: "play.fill")
            }
            .buttonStyle(.plain)
            .accessibilityHint("Starts native playback")
            #endif
        }
    }

    private func resolverRequiredRow(_ candidate: AddonStreamCandidate) -> some View {
        let status = localTorrentStatus(for: candidate)
        return Button {
            requestLocalTorrent(candidate)
        } label: {
            candidateRow(
                candidate,
                symbol: resolvingCandidateID == candidate.id ? "arrow.down" : "play.fill",
                status: status
            )
        }
        .buttonStyle(.plain)
        .disabled(isLocalPreparationActive || !localTorrentIsAvailable)
        .accessibilityHint("Downloads the selected torrent file locally, then starts native playback")
    }

    private func unavailableRow(_ candidate: AddonStreamCandidate) -> some View {
        let reason: String
        switch PlaybackSourceRowState(candidate: candidate).action {
        case let .unavailable(message):
            reason = message
        case .playDirect, .prepareDisc, .resolve:
            reason = "Unavailable"
        }

        return candidateRow(
            candidate,
            symbol: "exclamationmark.triangle",
            status: reason,
            isEnabled: false
        )
            .accessibilityElement(children: .combine)
    }

    private func candidateRow(
        _ candidate: AddonStreamCandidate,
        symbol: String,
        status: String? = nil,
        isEnabled: Bool = true
    ) -> some View {
        StreamCardView(
            candidate: candidate,
            badges: StreamBadgeStore.shared.badges(for: candidate),
            preferences: streamPreferences,
            addonLogoURL: addonLogoURL(for: candidate.addonID),
            symbol: symbol,
            detail: [candidate.sourceTypeLabel, candidate.technicalSummary]
                .compactMap { $0 }
                .joined(separator: " · "),
            status: status,
            isPinned: streamPreferences.isPinned(candidate.addonID),
            isEnabled: isEnabled
        )
    }

    private var localTorrentConsentPresentation: Binding<Bool> {
        Binding(
            get: { pendingLocalTorrentCandidate != nil },
            set: { if !$0 { pendingLocalTorrentCandidate = nil } }
        )
    }

    private var localTorrentIsAvailable: Bool {
        #if os(macOS)
        OMLocalTorrentEngine.isAvailable
        #else
        false
        #endif
    }

    private var isLocalPreparationActive: Bool {
        #if os(macOS)
        resolvingCandidateID != nil
            || preparingDiscCandidateID != nil
        #else
        resolvingCandidateID != nil
        #endif
    }

    private func localTorrentStatus(for candidate: AddonStreamCandidate) -> String {
        if let failure = resolverFailures[candidate.id] { return failure }
        if resolvingCandidateID == candidate.id {
            let progress = localTorrentProgress[candidate.id] ?? 0
            return "Downloading locally… \(Int(progress * 100))%"
        }
        #if os(macOS)
        if !OMLocalTorrentEngine.isAvailable {
            return "The reviewed local torrent engine is not included in this build"
        }
        return localResolverSettings.preferences.hasCurrentConsent
            ? "Ready to download locally"
            : "Peer consent required"
        #else
        return "Mobile local resolving awaits separate review"
        #endif
    }

    private func requestLocalTorrent(_ candidate: AddonStreamCandidate) {
        guard localTorrentIsAvailable, !isLocalPreparationActive else { return }
        if localResolverSettings.preferences.hasCurrentConsent {
            downloadLocalTorrent(candidate)
        } else {
            pendingLocalTorrentCandidate = candidate
        }
    }

    private func downloadLocalTorrent(_ candidate: AddonStreamCandidate) {
        #if os(macOS)
        guard !isLocalPreparationActive else { return }
        resolvingCandidateID = candidate.id
        resolverFailures[candidate.id] = nil
        localTorrentProgress[candidate.id] = 0
        localTorrentTask = Task { @MainActor in
            var lease: UUID?
            do {
                let acquiredLease = try await LocalPlaybackJobCoordinator.shared.acquire()
                lease = acquiredLease
                let descriptor = try LocalTorrentPlaybackDescriptor(candidate: candidate)
                let preferences = localResolverSettings.preferences
                let policy = LocalTorrentStoragePolicy(
                    maximumCacheBytes: preferences.cacheQuota.bytes,
                    minimumFreeBytes: LocalTorrentStoragePolicy.default.minimumFreeBytes,
                    maximumItemBytes: preferences.cacheQuota.bytes
                )
                // Torrent metadata arrives only after peer discovery. Reserve
                // the full configured item allowance so a metadata-discovered
                // BDMV cannot exceed the cache quota based on an add-on's
                // selected-file size hint.
                let cacheDescriptor = try LocalTorrentPlaybackDescriptor(
                    infoHash: descriptor.infoHash,
                    fileIndex: descriptor.fileIndex,
                    displayName: descriptor.displayName,
                    expectedByteCount: nil
                )
                let reservation = try await LocalPlaybackJobCoordinator.shared.prepare(
                    descriptor: cacheDescriptor,
                    policy: policy,
                    lease: acquiredLease
                )
                try Task.checkCancellation()
                let mediaDirectory = reservation.itemDirectory
                    .appendingPathComponent("Media", isDirectory: true)
                let engine = OMLocalTorrentEngine(
                    cacheDirectory: mediaDirectory,
                    maximumDownloadBytes: policy.maximumItemBytes,
                    minimumFreeBytes: policy.minimumFreeBytes,
                    downloadLimitBytesPerSecond: Int64(
                        preferences.downloadLimitKilobytesPerSecond
                    ) * 1_024,
                    uploadLimitBytesPerSecond: Int64(
                        preferences.uploadLimitKilobytesPerSecond
                    ) * 1_024
                )
                localTorrentEngine = engine
                try await LocalPlaybackJobCoordinator.shared.commitPreparation(
                    acquiredLease
                )
                let fileURL = try await engine.download(
                    magnetURL: descriptor.magnetURL,
                    fileIndex: descriptor.fileIndex.map(NSNumber.init(value:)),
                    progress: { progress, _, _ in
                        localTorrentProgress[candidate.id] = progress
                    }
                )
                try Task.checkCancellation()
                guard resolvingCandidateID == candidate.id else {
                    throw CancellationError()
                }
                let playbackInput: PlaybackInput
                if engine.completedMediaKind == .bluRayDirectory {
                    let disc = try TorrentDiscFinalizer.finalizeBluRayDirectory(
                        fileURL,
                        declaredBytes: engine.completedBytes,
                        cacheRoot: reservation.cacheRoot,
                        jobID: UUID()
                    )
                    let request = try await LocalPlaybackJobCoordinator.shared.discPlaybackRequest(
                        disc: disc,
                        cacheRoot: reservation.cacheRoot,
                        lease: acquiredLease
                    )
                    let protection = try await LocalPlaybackJobCoordinator.shared.protectForPlayback(
                        acquiredLease
                    )
                    playbackInput = .disc(
                        source: PlaybackSource(localCandidate: candidate, fileURL: fileURL),
                        request: request,
                        protection: protection
                    )
                } else {
                    let protection = try await LocalPlaybackJobCoordinator.shared.protectForPlayback(
                        acquiredLease
                    )
                    playbackInput = .cachedStream(
                        source: PlaybackSource(localCandidate: candidate, fileURL: fileURL),
                        protection: protection
                    )
                }
                lease = nil
                localTorrentEngine = nil
                localTorrentTask = nil
                resolvingCandidateID = nil
                localTorrentProgress[candidate.id] = nil
                beginPlayback(
                    playbackInput,
                    candidate: candidate
                )
            } catch {
                if let lease {
                    await LocalPlaybackJobCoordinator.shared.release(lease)
                }
                localTorrentEngine?.cancel()
                localTorrentEngine = nil
                localTorrentTask = nil
                if error is CancellationError {
                    resolvingCandidateID = nil
                    localTorrentProgress[candidate.id] = nil
                    return
                }
                resolverFailures[candidate.id] = error.localizedDescription
                resolvingCandidateID = nil
            }
        }
        #endif
    }

    #if os(macOS)
    private func prepareHTTPSDisc(_ candidate: AddonStreamCandidate) {
        guard case let .nativeHTTPS(url) = candidate.delivery,
              let sourceMetadata = candidate.nativePlaybackSource,
              !isLocalPreparationActive
        else { return }

        preparingDiscCandidateID = candidate.id
        discPreparationStates[candidate.id] = .detecting
        discPreparationTask = Task { @MainActor in
            var lease: UUID?
            var jobMaterializer: DiscMaterializer?
            do {
                let acquiredLease = try await LocalPlaybackJobCoordinator.shared.acquire()
                lease = acquiredLease
                let preferences = localResolverSettings.preferences
                let source = try await HTTPSDiscByteSource.prepare(
                    url: url,
                    maximumBytes: preferences.cacheQuota.bytes,
                    requestHeaders: candidate.requestHeaders
                )
                try Task.checkCancellation()

                let jobID = UUID()
                let compactID = jobID.uuidString
                    .replacingOccurrences(of: "-", with: "")
                    .lowercased()
                let infoHash = compactID + String(compactID.prefix(8))
                let policy = LocalTorrentStoragePolicy(
                    maximumCacheBytes: preferences.cacheQuota.bytes,
                    minimumFreeBytes: LocalTorrentStoragePolicy.default.minimumFreeBytes,
                    maximumItemBytes: preferences.cacheQuota.bytes
                )
                let descriptor = try LocalTorrentPlaybackDescriptor(
                    infoHash: infoHash,
                    fileIndex: nil,
                    displayName: "Blu-ray disc image",
                    expectedByteCount: source.expectedByteCount
                )
                let reservation = try await LocalPlaybackJobCoordinator.shared.prepare(
                    descriptor: descriptor,
                    policy: policy,
                    lease: acquiredLease
                )
                try Task.checkCancellation()

                let file = TorrentMediaFile(
                    index: 0,
                    relativePath: "Disc.iso",
                    size: source.expectedByteCount
                )
                let materializer = DiscMaterializer(
                    reservationRoot: reservation.itemDirectory,
                    reservedBytes: source.expectedByteCount,
                    retainsIncompleteJobs: preferences.retainsIncompleteJobs,
                    jobID: jobID
                )
                jobMaterializer = materializer
                discMaterializer = materializer
                try await LocalPlaybackJobCoordinator.shared.commitPreparation(
                    acquiredLease
                )
                let events = await materializer.materialize(.iso(file), source: source)
                var preparedDisc: MaterializedDisc?
                for try await event in events {
                    try Task.checkCancellation()
                    switch event {
                    case let .progress(completedBytes, totalBytes):
                        discPreparationStates[candidate.id] = .materializing(
                            completedBytes: completedBytes,
                            totalBytes: totalBytes
                        )
                    case let .ready(disc):
                        preparedDisc = disc
                    }
                }
                guard let preparedDisc else {
                    throw DiscPlaybackRequestError.incompleteMaterialization
                }
                let request = try await LocalPlaybackJobCoordinator.shared.discPlaybackRequest(
                    disc: preparedDisc,
                    cacheRoot: reservation.cacheRoot,
                    lease: acquiredLease
                )
                try Task.checkCancellation()

                let protection = try await LocalPlaybackJobCoordinator.shared.protectForPlayback(
                    acquiredLease
                )
                lease = nil
                discPreparationStates[candidate.id] = .ready
                preparingDiscCandidateID = nil
                discMaterializer = nil
                discPreparationTask = nil
                beginPlayback(
                    .disc(
                        source: sourceMetadata,
                        request: request,
                        protection: protection
                    ),
                    candidate: candidate
                )
            } catch is CancellationError {
                if let lease {
                    await LocalPlaybackJobCoordinator.shared.cancelDiscPreparation(
                        jobMaterializer,
                        lease: lease
                    )
                }
                preparingDiscCandidateID = nil
                discMaterializer = nil
                discPreparationTask = nil
            } catch let error as HTTPSDiscByteSourceError where error == .cancelled {
                if let lease {
                    await LocalPlaybackJobCoordinator.shared.cancelDiscPreparation(
                        jobMaterializer,
                        lease: lease
                    )
                }
                preparingDiscCandidateID = nil
                discMaterializer = nil
                discPreparationTask = nil
            } catch {
                if let lease {
                    await LocalPlaybackJobCoordinator.shared.cancelDiscPreparation(
                        jobMaterializer,
                        lease: lease
                    )
                }
                discPreparationStates[candidate.id] = .failed(
                    discPreparationFailure(for: error)
                )
                preparingDiscCandidateID = nil
                discMaterializer = nil
                discPreparationTask = nil
            }
        }
    }

    private func discPreparationFailure(for error: Error) -> DiscPreparationFailure {
        if let error = error as? HTTPSDiscByteSourceError {
            switch error {
            case .httpsRequired, .credentialedURL, .redirectRejected:
                return .unsafeSource
            case .sourceTooLarge:
                return .storageFull
            case .invalidContentLength, .invalidResponse, .fileSizeMismatch,
                 .cancelled, .transportFailure:
                return .network
            }
        }
        if let error = error as? LocalTorrentStoragePolicy.StorageError {
            switch error {
            case .itemTooLarge, .insufficientSpace:
                return .storageFull
            case .invalidPolicy:
                return .unsafeSource
            }
        }
        if let error = error as? LocalPlaybackJobCoordinator.JobError {
            switch error {
            case .busy:
                return .busy
            case .invalidLease:
                return .unsafeSource
            }
        }
        if let error = error as? LocalTorrentCacheManager.CacheError {
            switch error {
            case .cacheUnavailable, .evictionFailed:
                return .storageFull
            case .unsafeCacheEntry:
                return .unsafeSource
            }
        }
        if let error = error as? DiscMaterializationError {
            switch error {
            case .insufficientReservation, .storageFailure:
                return .storageFull
            case .unsafeReservation:
                return .unsafeSource
            case .byteCountMismatch:
                return .network
            }
        }
        if let error = error as? DiscPlaybackRequestError {
            switch error {
            case .unsupportedDisc:
                return .unsupportedDisc
            case .outsideCache, .incompleteMaterialization, .unsafeDevice:
                return .unsafeSource
            }
        }
        return .network
    }
    #endif

    /// The source picker is itself a transient presentation.  Starting the
    /// root-level player in the same update transaction as dismissing it lets
    /// AppKit occasionally apply the sheet's old presentation state after
    /// `PlaybackSession` has requested the player.  Dismiss first, then start
    /// from the next main-actor turn so the shared player presentation wins.
    private func beginPlayback(_ source: PlaybackSource, candidate: AddonStreamCandidate? = nil) {
        beginPlayback(.stream(source), candidate: candidate)
    }

    private func beginDirectPlayback(
        _ source: PlaybackSource,
        candidate: AddonStreamCandidate
    ) {
        #if os(macOS)
        let torrentTask = localTorrentTask
        let preparationTask = discPreparationTask
        let materializer = discMaterializer
        localTorrentEngine?.cancel()
        torrentTask?.cancel()
        preparationTask?.cancel()
        Task { @MainActor in
            await materializer?.cancelAndWait()
            await torrentTask?.value
            await preparationTask?.value
            guard !Task.isCancelled else { return }
            beginPlayback(source, candidate: candidate)
        }
        #else
        beginPlayback(source, candidate: candidate)
        #endif
    }

    private func beginPlayback(_ input: PlaybackInput, candidate: AddonStreamCandidate? = nil) {
        guard let selectionID, playback.isCurrentSourceSelection(selectionID), !isHandingOffPlayback else {
            releaseUnusedInput(input)
            return
        }
        let item = preparedPlaybackItem ?? item
        let progressItem = self.item
        let episode = episode
        let resumeAt = resumeAt
        let mediaKey = mediaKey
        isHandingOffPlayback = true
        autoSelection?.cancel()
        autoSelectionStatus = nil
        closePresentation(preservingSelection: true)

        Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, playback.claimSourceSelection(selectionID) else {
                releaseUnusedInput(input)
                return
            }
            // A streamed source that fails can be fetched again or replaced
            // from this list; local files and discs can't.
            if case .stream = input {
                playback.recoveryContext = PlaybackRecoveryContext(
                    item: item,
                    progressItem: progressItem,
                    episode: episode,
                    resumeAt: resumeAt,
                    linkKey: mediaKey,
                    candidates: candidates.filter { $0.nativePlaybackSource != nil }
                )
            } else {
                playback.recoveryContext = nil
            }
            PlaybackLauncher.start(
                input: input,
                candidate: candidate,
                item: item,
                progressItem: progressItem,
                episode: episode,
                resumeAt: resumeAt,
                linkKey: mediaKey,
                playback: playback,
                settings: settings,
                store: store
            )
        }
    }

    private func releaseUnusedInput(_ input: PlaybackInput) {
        #if os(macOS)
        if let protection = input.cacheProtection {
            Task { await LocalPlaybackJobCoordinator.shared.unprotect(protection) }
        }
        #endif
    }

    private func closePresentation(preservingSelection: Bool = false) {
        if !preservingSelection, let selectionID {
            playback.cancelSourceSelection(selectionID)
        }
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    /// Sources in the user's Stream Sorting order, best first; the list,
    /// auto-play and recovery all use it.
    private func ranked(_ sources: [AddonStreamCandidate]) -> [AddonStreamCandidate] {
        StreamRanking.rank(sources, preferences: settings.preferences.playbackBehavior.streamSorting)
    }

    private var mediaKey: MediaPlaybackKey {
        PlaybackLauncher.linkKey(item: item, episode: episode)
    }

    /// Nuvio's Reuse Last Link: the stream played last for this movie or
    /// episode starts again without asking the add-ons. A moment is left to
    /// choose another source instead.
    private func playLastLinkIfAllowed(selectionID: UUID) async -> Bool {
        let behavior = settings.preferences.playbackBehavior
        guard !isNextEpisode, behavior.reuseLastLink else { return false }
        let enabledSourceIDs = Set(store.installedAddons.filter(\.isEnabled).map(\.id))
            .union(plugins.pluginsEnabled
                ? plugins.scrapers.filter(\.isEnabled).map(PluginStreamResolver.sourceID(for:))
                : [])
        guard let cached = StreamLinkCacheStore().candidate(
            for: mediaKey,
            maximumAgeHours: behavior.lastLinkCacheHours,
            enabledSourceIDs: enabledSourceIDs
        ), let source = cached.nativePlaybackSource else { return false }
        withAnimation { autoSelectionStatus = "Playing your last source, \(cached.addonName)…" }
        let task = Task<Void, Never> { try? await Task.sleep(for: .seconds(1.2)) }
        lastLinkTask = task
        await task.value
        if Task.isCancelled || !playback.isCurrentSourceSelection(selectionID) { return true }
        // Choose Manually cancelled the wait: show the list instead.
        if task.isCancelled { return false }
        beginPlayback(source, candidate: cached)
        return true
    }

    /// Starts Nuvio's Auto Stream Selection for this lookup, if it applies.
    private func startAutomaticSelection() {
        let behavior = settings.preferences.playbackBehavior
        let request: StreamAutoPlayRequest?
        if isNextEpisode {
            request = nextEpisodeRequest
        } else {
            let remembered = episode == nil ? nil : BingeGroupCacheStore().bingeGroup(forSeries: item.id)
            request = behavior.selectionRequest(rememberedBingeGroup: remembered)
        }
        guard let request, !choosesManually else { return }
        autoSelection = StreamAutoSelectionRun(request: request) { outcome in
            withAnimation { autoSelectionStatus = nil }
            if case let .play(candidate) = outcome, let source = candidate.nativePlaybackSource {
                beginPlayback(source, candidate: candidate)
            }
        }
        withAnimation {
            autoSelectionStatus = request.bingeGroupOnly
                ? "Looking for the same release as last time…"
                : "Choosing a source automatically…"
        }
    }

    private func chooseManually() {
        choosesManually = true
        lastLinkTask?.cancel()
        autoSelection?.cancel()
        withAnimation { autoSelectionStatus = nil }
    }

}

extension MediaEpisode {
    /// Nuvio only plays a next episode that has aired; a missing or
    /// unreadable date counts as aired.
    var hasAired: Bool {
        guard let airDate, airDate.count >= 10 else { return true }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: String(airDate.prefix(10))) else { return true }
        return date <= Date()
    }
}

/// Starts a chosen source and records what Nuvio remembers about it: the
/// link for Reuse Last Link and the series' binge group.
enum PlaybackLauncher {
    static func linkKey(item: MediaItem, episode: MediaEpisode?) -> MediaPlaybackKey {
        if let episode {
            return MediaPlaybackKey(rawValue: "\(item.id):\(episode.seasonNumber):\(episode.episodeNumber)")
        }
        return MediaPlaybackKey(rawValue: item.id)
    }

    static func start(
        input: PlaybackInput,
        candidate: AddonStreamCandidate?,
        item: MediaItem,
        progressItem: MediaItem,
        episode: MediaEpisode?,
        resumeAt: Double?,
        linkKey: MediaPlaybackKey,
        playback: PlaybackSession,
        settings: SettingsPreferencesStore,
        store: OmniaStore
    ) {
        playback.setSubtitlePreferencesHandler { update in
            settings.update {
                $0.playbackSubtitleStyle = update.style
                if let isEnabled = update.isEnabled {
                    $0.subtitlesEnabled = isEnabled
                }
                if let preferredLanguage = update.preferredLanguage {
                    $0.preferredSubtitleLanguage = preferredLanguage
                }
            }
        }
        let display = settings.preferences.display
        let seriesEpisodes = (item.details ?? progressItem.details)?.seasons.flatMap(\.episodes) ?? []
        // Shuffle (Nuvio): while it is on for the show, the next episode and
        // Next Up are a random pick instead of the following episode.
        let shuffle = EpisodeShuffleStore.shared
        let shuffledNext = episode.flatMap { current in
            shuffle.isActive(for: progressItem, display: display)
                ? shuffle.pick(
                    for: progressItem.id,
                    episodes: seriesEpisodes,
                    watchState: store.watchState(for: progressItem),
                    includeWatched: shuffle.settings(for: progressItem.id).includeWatched,
                    excluding: current
                )
                : nil
        }
        let nextUp = episode.map { _ in
            OmniaStore.NextUpRequest(
                episodes: seriesEpisodes,
                fromFurthest: display.nextUpFromFurthestEpisode,
                includesUnaired: display.showsUnairedNextUp,
                shuffledNext: shuffledNext
            )
        }
        playback.start(
            item: item,
            episode: episode,
            input: input,
            resumeAt: resumeAt,
            preferences: settings.preferences
        ) { position, duration in
            store.recordPlayback(
                for: progressItem,
                episode: episode,
                positionSeconds: position,
                durationSeconds: duration,
                nextUp: nextUp
            )
        }
        playback.shuffledNextEpisode = shuffledNext
        playback.setCurrentSource(candidate, linkKey: candidate == nil ? nil : linkKey)
        playback.loadAddonSubtitles(
            addons: store.installedAddons,
            item: item,
            episode: episode,
            videoSize: candidate?.videoSize,
            preferences: settings.preferences
        )
        guard let candidate else { return }
        if settings.preferences.playbackBehavior.reuseLastLink {
            StreamLinkCacheStore().save(candidate, for: linkKey)
        }
        if episode != nil, let bingeGroup = candidate.bingeGroup {
            BingeGroupCacheStore().save(bingeGroup, forSeries: progressItem.id)
        }
    }
}

struct PlaybackTimelinePresentation: Equatable {
    let elapsedText: String
    let remainingText: String

    init(positionSeconds: Double, durationSeconds: Double?) {
        let duration = durationSeconds.flatMap { value in
            value.isFinite && value > 0 ? value : nil
        } ?? 0
        let position = min(max(positionSeconds.isFinite ? positionSeconds : 0, 0), duration)
        elapsedText = Self.timeText(position)
        remainingText = "−\(Self.timeText(max(duration - position, 0)))"
    }

    static func timeText(_ value: Double) -> String {
        let total = Int(value.rounded(.down))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

struct PlaybackChromeMetadata: Equatable {
    let title: String
    let context: String

    init(item: MediaItem?, episode: MediaEpisode?) {
        title = item?.title ?? "Now Playing"
        if let episode {
            context = "\(episode.title) - Season \(episode.seasonNumber) Episode \(episode.episodeNumber)"
        } else {
            context = item?.year ?? ""
        }
    }
}

struct PlaybackExperienceView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
    @FocusState private var hasKeyboardFocus: Bool
    #endif
    @Environment(PlaybackSession.self) private var playback
    @Environment(SettingsPreferencesStore.self) private var settings
    @Environment(OmniaStore.self) private var store
    @Environment(PluginStore.self) private var plugins
    @Environment(LiveMetadataStore.self) private var metadata
    @State private var isScrubbing = false
    @State private var showsChrome = true
    @State private var chromeHideTask: Task<Void, Never>?
    @State private var segments: [SkipSegment] = []
    @State private var visibleSkipSegment: SkipSegment?
    /// Nuvio hides the skip prompt after 10 seconds while the controls are
    /// hidden; it comes back with the controls.
    @State private var skipPromptExpired = false
    @State private var skipPromptTask: Task<Void, Never>?
    @State private var skipNotice: String?
    @State private var showsUpNext = false
    /// Up Next reached during an outro waits for the outro to end, so the
    /// two prompts never show together.
    @State private var deferredUpNext = false
    @State private var nextSourceRequest: PlaybackRequest?
    @State private var nextSourceAutoSelection: StreamAutoPlayRequest?
    @State private var didHandleEnd = false
    @State private var nextEpisodeAutoPlay: NextEpisodeAutoPlay?
    @State private var nextEpisodeTask: Task<Void, Never>?
    @State private var preloadTask: Task<Void, Never>?
    @State private var showsPauseOverlay = false
    @State private var pauseOverlayTask: Task<Void, Never>?
    @State private var automation = PlaybackAutomationController(policy: .init(
        skipEnabled: true,
        autoSkipKinds: [],
        thresholdMode: .percentage,
        thresholdPercent: 99,
        thresholdMinutes: 2,
        preloadLeadSeconds: nil
    ))

    /// Nuvio's next-episode countdown: "Playing via {source}" then 3, 2, 1.
    struct NextEpisodeAutoPlay: Equatable {
        let episode: MediaEpisode
        var candidate: AddonStreamCandidate?
        var secondsLeft: Int
    }

    /// The video: libmpv's surface, or AVPlayer's when iOS fell back to it.
    @ViewBuilder
    private var playerSurface: some View {
        if let player = playback.trailerPlayer {
            #if os(macOS)
            TrailerPlaybackSurface(player: player, fillsFrame: playback.aspectRatioMode == .fill)
            #else
            Color.clear
            #endif
        } else {

        #if os(iOS) && !OMNIA_MPV
        // The AVKit layer below owns both inline rendering and PiP.
        if playback.player != nil { Color.clear }
        #else
        if let player = playback.player {
            NativePlayerView(player: player)
        }
        #endif
        #if OMNIA_MPV && !os(macOS)
        if playback.player == nil, playback.fallbackPlayer != nil {
            Color.clear
        }
        #endif
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            #if os(iOS)
            IOSPictureInPictureHost(
                controller: playback.pictureInPictureController,
                fillsFrame: playback.aspectRatioMode == .fill
            )
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            #endif
            if playback.isRecoveringSource {
                // A failed source is being fetched again or replaced; the
                // error shows only if that doesn't work.
                OmniaLoadingRow("Reconnecting to the source…")
                    .controlSize(.large)
                    .tint(.white)
                    .foregroundStyle(.white)
            } else if let playbackError = playback.playbackError {
                ContentUnavailableView(
                    "Playback Failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(playbackError)
                )
                .foregroundStyle(.white)
            } else if playback.hasPlayer {
                playerSurface
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .zIndex(0)
            } else {
                ContentUnavailableView("Playback Unavailable", systemImage: "play.slash")
                    .foregroundStyle(.white)
            }
        }
        .overlay(alignment: .top) {
            if let notice = playback.recoveryNotice {
                Label(notice, systemImage: "arrow.triangle.2.circlepath")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .omniaGlass(.playerControls, base: .clear, in: Capsule())
                    .padding(.top, 28)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.snappy, value: playback.recoveryNotice)
        .overlay(alignment: .topLeading) {
            ContentWarningOverlay(
                item: playback.mediaItem,
                playbackKey: "\(playback.mediaItem?.id ?? "")|\(playback.episode?.id ?? "")",
                hasStarted: playback.hasRenderedVideoFrame,
                isEnabled: playback.purpose == .title && settings.preferences.playbackBehavior.showContentWarnings
            )
            .padding(.leading, 40)
            .padding(.top, 72)
        }
        .contentShape(Rectangle())
        #if os(iOS)
        .background {
            IOSSystemVolumeHost(controller: playback.outputVolumeController)
                .frame(width: 160, height: 44)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        // Touch: double tap a side to skip 10 seconds, drag up or down on
        // the left for brightness and on the right for volume, and drag
        // sideways to seek, as in most phone players.
        .overlay {
            PlaybackTouchGestures(
                isEnabled: !holdsChromeHidden,
                toggleChrome: {
                    if showsChrome { concealChrome() } else if !holdsChromeHidden { revealChrome() }
                }
            )
        }
        #else
        .onTapGesture {
            // One click shows the controls, the next hides them. While the
            // loading overlay or a Skip prompt is up a click leaves them
            // hidden (Dafa, 2026-10-22).
            if showsChrome {
                concealChrome()
            } else if !holdsChromeHidden {
                revealChrome()
            }
        }
        #endif
        .overlay {
            if showsLoadingOverlay, let item = playback.mediaItem {
                PlaybackLoadingOverlay(
                    item: item,
                    episode: playback.episode,
                    status: behavior.showLoadingStatus ? loadingStatus : nil
                )
                .allowsHitTesting(false)
                .transition(.opacity)
            } else if showsPauseOverlay, let item = playback.mediaItem {
                PlaybackPauseOverlay(item: item, episode: playback.episode, clearsControls: showsChrome)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showsLoadingOverlay)
        .animation(.easeInOut(duration: 0.35), value: showsPauseOverlay)
        .overlay {
            if playback.isPictureInPictureActive {
                VStack(spacing: 12) {
                    Image(systemName: "pip")
                        .font(.system(size: 54, weight: .light))
                    Text("Playing in Picture in Picture")
                        .font(.title3.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.55))
                .allowsHitTesting(false)
                .accessibilityElement(children: .combine)
            }
        }
        .overlay {
            if showsChrome && !showsLoadingOverlay {
                PlaybackChrome(
                    isScrubbing: $isScrubbing,
                    close: { playback.stop() },
                    hasNextEpisode: playback.nextEpisode != nil,
                    showUpNext: showUpNext,
                    playEpisode: presentEpisode,
                    showSources: presentSources
                )
                .id(
                    MacPlaybackChromeCoordinateSpaceIdentity(
                        isExclusiveFullScreen: playback.isFullScreenActive
                    )
                )
                // Settles into place rather than only fading.
                .transition(reduceMotion ? .opacity : .scale(scale: 1.02).combined(with: .opacity))
                .zIndex(10)
            }
        }
        // Skip and Up Next are their own overlay, apart from the player
        // controls, like the pause overlay. With the controls showing it
        // sits above them.
        .overlay(alignment: .bottomTrailing) {
            if showsPromptOverlay {
                PlaybackPromptOverlay(
                    skipTitle: showsChrome || showsContextualSkip ? visibleSkipSegment.map { _ in skipTitle } : nil,
                    skip: skipIntro,
                    upNext: upNextPrompt,
                    playNext: showUpNext,
                    cancel: cancelUpNextAction
                )
                .id(
                    MacPlaybackChromeCoordinateSpaceIdentity(
                        isExclusiveFullScreen: playback.isFullScreenActive
                    )
                )
                .padding(.trailing, 30)
                .padding(.bottom, showsChrome ? 150 : 40)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
                .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showsPromptOverlay)
        .overlay(alignment: .topTrailing) {
            if let skipNotice {
                Label(skipNotice, systemImage: "forward.end.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .omniaGlass(.playerControls, base: .clear, in: Capsule())
                    .padding(28)
                    .transition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.9), value: showsChrome)
        .animation(.easeInOut(duration: 0.2), value: skipNotice)
        .onAppear { revealChrome() }
        .onDisappear {
            chromeHideTask?.cancel()
            skipPromptTask?.cancel()
            nextEpisodeTask?.cancel()
            preloadTask?.cancel()
            pauseOverlayTask?.cancel()
        }
        .task(id: playbackAutomationKey) {
            configureAutomation()
            await loadSkipSegments()
        }
        .task(id: playback.mediaItem?.id) { await loadMissingEpisodes() }
        .onChange(of: playback.positionSeconds) { _, _ in updateAutomation() }
        .onChange(of: playback.isPaused) { _, isPaused in schedulePauseOverlay(isPaused: isPaused) }
        .onChange(of: playback.playbackError) { _, error in
            // A stream that fails is never offered again by Reuse Last Link.
            if error != nil, let key = playback.currentLinkKey {
                StreamLinkCacheStore().remove(key)
            }
            if let error, playback.purpose == .title {
                Task { await PlaybackRecovery.recover(from: error, playback: playback, store: store, settings: settings) }
            }
        }
        .onChange(of: isScrubbing) { _, isInteracting in
            if isInteracting {
                chromeHideTask?.cancel()
                showsChrome = true
            } else {
                hideChrome(after: 3.2)
            }
        }
        .onChange(of: showsChrome) { _, isVisible in
            if isVisible, visibleSkipSegment != nil {
                restartSkipPromptTimer()
            }
        }
        .omniaStreamsPage(isPresented: showsNextSourceSheet) {
            if let request = nextSourceRequest {
                PlaybackSourceSheet(
                    item: request.item,
                    episode: request.episode,
                    resumeAt: request.resumeAt,
                    isNextEpisode: true,
                    nextEpisodeRequest: nextSourceAutoSelection,
                    presentedInPlayer: true,
                    onClose: { nextSourceRequest = nil }
                )
                .id(request.id)
            }
        }
        #if os(macOS)
        .background {
            MacPlaybackKeyboardMonitor { perform($0) }
                .frame(width: 0, height: 0)
        }
        .onHover { isHovering in
            if !isHovering {
                hideChrome(after: 2.2)
            } else if !holdsChromeHidden {
                revealChrome()
            }
        }
        #endif
        #if os(iOS)
        // A keyboard attached to an iPad or iPhone drives the player as on the Mac.
        .focusable()
        .focused($hasKeyboardFocus)
        .focusEffectDisabled()
        .onAppear { hasKeyboardFocus = true }
        .onKeyPress(.leftArrow) { perform(.seekBackward10); return .handled }
        .onKeyPress(.rightArrow) { perform(.seekForward10); return .handled }
        .onKeyPress(.space) { perform(.togglePause); return .handled }
        .onKeyPress(.escape) { perform(.close); return .handled }
        // The controls stay hidden while loading, and an iPhone or iPad has
        // no Escape key: a source that never loads must still be closable.
        .overlay(alignment: .topLeading) {
            if showsLoadingOverlay {
                Button {
                    playback.stop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .omniaGlass(.playerControls, base: .clear, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(18)
                .accessibilityLabel("Close player")
                .accessibilityHint("Stops loading and returns to Omnia")
                .transition(.opacity)
            }
        }
        #endif
        #if os(iOS)
        // On iOS the full-screen cover disappearing means the user dismissed
        // the player. AppKit can transiently recreate the hosted view while
        // entering/exiting a full-screen space, so macOS stops only through
        // Omnia's explicit Close control instead.
        .onDisappear {
            if !playback.isPictureInPictureActive { playback.stop() }
        }
        #endif
    }

    private var behavior: PlaybackBehaviorPreferences {
        settings.preferences.playbackBehavior
    }

    private var playbackAutomationKey: String {
        [
            playback.mediaItem?.id ?? "none",
            playback.episode?.id ?? "title",
            "\(settings.preferences.showSkipIntro)",
            "\(settings.preferences.autoplayNextEpisode)",
            behavior.autoSkipSegments.map(\.rawValue).sorted().joined(separator: ","),
            behavior.nextEpisodeThresholdMode.rawValue,
            "\(behavior.nextEpisodeThresholdPercent)",
            "\(behavior.nextEpisodeThresholdMinutes)",
            "\(behavior.preloadNextEpisodeSources)",
            "\(behavior.selectionTimeoutSeconds)",
        ].joined(separator: ":")
    }

    private var showsNextSourceSheet: Binding<Bool> {
        Binding(
            get: { nextSourceRequest != nil },
            set: { if !$0 { nextSourceRequest = nil } }
        )
    }

    /// Nuvio's Loading Overlay: the title's artwork until the first frame.
    private var showsLoadingOverlay: Bool {
        behavior.showLoadingOverlay
            && playback.playbackError == nil
            && playback.hasPlayer
            && !playback.hasRenderedVideoFrame
    }

    /// Clicks and the pointer don't bring the controls up over the loading
    /// overlay or an on-screen Skip Intro or Outro.
    private var holdsChromeHidden: Bool {
        showsLoadingOverlay || showsContextualSkip
    }

    private var loadingStatus: String {
        if playback.areTracksLoading { return "Opening stream…" }
        if playback.durationSeconds == nil { return "Buffering…" }
        return "Starting playback…"
    }

    private func perform(_ action: MacPlaybackKeyboardAction) {
        switch action {
        case .seekBackward10:
            playback.seek(by: -10)
            revealChrome()
        case .seekForward10:
            playback.seek(by: 10)
            revealChrome()
        case .togglePause:
            playback.togglePause()
            revealChrome()
        case .close:
            #if os(macOS)
            // Esc leaves full screen first, as it does across macOS.
            if playback.isFullScreenActive {
                playback.setFullScreen(false)
                return
            }
            #endif
            playback.stop()
        }
    }


    /// Episodes for a show started from Continue Watching, which keeps no
    /// season list: from the add-on that lists it in add-on mode, else from
    /// the metadata service, as the title's page loads them.
    private func loadMissingEpisodes() async {
        guard playback.purpose == .title, let item = playback.mediaItem, item.kind != .movie, item.details == nil else { return }
        var resolved: MediaItem?
        if AddonCatalogStore.isAddonMode(store) {
            let addons = store.installedAddons
            resolved = await Task { await AddonMetadataResolver.resolve(item, addons: addons) }.value
        }
        if resolved?.details?.seasons.contains(where: { !$0.episodes.isEmpty }) != true {
            resolved = await metadata.details(for: item)
        }
        guard !Task.isCancelled, let resolved else { return }
        playback.fillMissingEpisodes(from: resolved)
    }

    /// Nuvio's Pause Overlay: the title's details, shown as soon as playback
    /// pauses (Dafa, 2026-10-21). A tap on the video hides the controls and
    /// leaves the overlay.
    private func schedulePauseOverlay(isPaused: Bool) {
        pauseOverlayTask?.cancel()
        guard isPaused,
              behavior.showPauseOverlay,
              playback.playbackError == nil,
              (playback.durationSeconds ?? 0) > 0 else {
            showsPauseOverlay = false
            return
        }
        showsPauseOverlay = true
    }

    private var showsContextualSkip: Bool {
        visibleSkipSegment != nil && !skipPromptExpired
    }

    private var skipTitle: String {
        visibleSkipSegment?.kind.skipTitle ?? "Skip Intro"
    }

    /// The prompt overlay shows while a prompt is up, except while a player
    /// panel is open or the timeline is being dragged.
    private var showsPromptOverlay: Bool {
        guard !(showsChrome && isScrubbing) else { return false }
        let showsSkip = visibleSkipSegment != nil && (showsChrome || showsContextualSkip)
        return showsSkip || upNextPrompt != nil
    }

    private var upNextPrompt: PlaybackUpNextPrompt? {
        guard showsUpNext, let nextEpisode = playback.nextEpisode else { return nil }
        let status: String?
        if let autoPlay = nextEpisodeAutoPlay {
            status = autoPlay.candidate.map { "Playing via \($0.addonName) in \(autoPlay.secondsLeft)" }
                ?? "Finding a source…"
        } else {
            status = nil
        }
        return PlaybackUpNextPrompt(episode: nextEpisode, status: status, isCountingDown: nextEpisodeAutoPlay != nil)
    }

    /// The player's Sources button: this title's sources, listed without
    /// automatic selection, resuming where playback is now.
    private func presentSources() {
        guard nextSourceRequest == nil, let item = playback.mediaItem else { return }
        cancelNextEpisodeAutoPlay()
        nextSourceAutoSelection = nil
        nextSourceRequest = PlaybackRequest(
            item: item,
            episode: playback.episode,
            resumeAt: playback.positionSeconds > 5 ? playback.positionSeconds : nil
        )
    }

    /// Picking an episode from the player's list is always a manual choice.
    private func presentEpisode(_ episode: MediaEpisode) {
        guard nextSourceRequest == nil, let item = playback.mediaItem else { return }
        cancelNextEpisodeAutoPlay()
        nextSourceAutoSelection = nil
        nextSourceRequest = PlaybackRequest(item: item, episode: episode, resumeAt: nil)
    }

    /// Up Next: plays the counted-down source now, or opens the next
    /// episode's sources with Nuvio's next-episode rules (a source from the
    /// same binge group plays by itself).
    private func showUpNext() {
        if let autoPlay = nextEpisodeAutoPlay, let candidate = autoPlay.candidate {
            playNextEpisode(autoPlay.episode, candidate: candidate)
            return
        }
        cancelNextEpisodeAutoPlay()
        openNextEpisodeSources(
            autoSelection: behavior.nextEpisodeRequest(
                currentBingeGroup: playback.currentCandidate?.bingeGroup,
                autoplayNextEpisode: false
            )
        )
    }

    private func openNextEpisodeSources(autoSelection: StreamAutoPlayRequest?) {
        guard nextSourceRequest == nil,
              let item = playback.mediaItem,
              let episode = playback.nextEpisode else { return }
        nextSourceAutoSelection = autoSelection
        nextSourceRequest = PlaybackRequest(item: item, episode: episode, resumeAt: nil)
    }

    private var cancelUpNextAction: (() -> Void)? {
        nextEpisodeAutoPlay == nil ? nil : { cancelNextEpisodeAutoPlay() }
    }

    private func skipIntro() {
        guard let visibleSkipSegment else { return }
        playback.seek(to: PlaybackAutomationController.skipTarget(for: visibleSkipSegment, in: segments))
        self.visibleSkipSegment = nil
        presentDeferredUpNext()
    }

    private var upNextTitle: String? {
        guard showsUpNext, let nextEpisode = playback.nextEpisode else { return nil }
        let number = "S\(nextEpisode.seasonNumber) E\(nextEpisode.episodeNumber)"
        if let autoPlay = nextEpisodeAutoPlay {
            if let candidate = autoPlay.candidate {
                return "Playing \(number) via \(candidate.addonName) in \(autoPlay.secondsLeft)"
            }
            return "Finding a source for \(number)…"
        }
        return "Up Next: \(number)"
    }

    private func configureAutomation() {
        let behavior = behavior
        let timeout = behavior.selectionTimeoutSeconds
        automation = PlaybackAutomationController(policy: .init(
            skipEnabled: settings.preferences.showSkipIntro,
            autoSkipKinds: behavior.autoSkipSegments,
            thresholdMode: behavior.nextEpisodeThresholdMode,
            thresholdPercent: behavior.nextEpisodeThresholdPercent,
            thresholdMinutes: behavior.nextEpisodeThresholdMinutes,
            // Nuvio preloads one selection timeout ahead of the card.
            preloadLeadSeconds: behavior.preloadNextEpisodeSources
                ? Double(timeout > 0 ? timeout : 10)
                : nil
        ))
        visibleSkipSegment = nil
        skipPromptExpired = false
        showsUpNext = false
        deferredUpNext = false
        didHandleEnd = false
        nextSourceRequest = nil
        cancelNextEpisodeAutoPlay()
        preloadTask?.cancel()
    }

    private func loadSkipSegments() async {
        guard playback.purpose == .title, settings.preferences.showSkipIntro,
              let item = playback.mediaItem,
              let imdbID = item.externalIDs["imdb"] ?? item.externalIDs["imdb_id"]
        else {
            segments = []
            return
        }
        do {
            if let episode = playback.episode {
                segments = try await IntroDBClient().segments(
                    imdbID: imdbID,
                    season: episode.seasonNumber,
                    episode: episode.episodeNumber
                )
            } else {
                segments = try await IntroDBClient().movieSegments(imdbID: imdbID)
            }
            updateAutomation()
        } catch is CancellationError {
            return
        } catch {
            segments = []
        }
    }

    private func updateAutomation() {
        guard playback.purpose == .title else { return }
        let hasNextEpisode = playback.nextEpisode != nil
        let effects = automation.update(
            position: playback.positionSeconds,
            duration: playback.durationSeconds,
            segments: segments,
            hasNextEpisode: hasNextEpisode,
            isPlaying: !playback.isPaused && !isScrubbing
        )
        for effect in effects { apply(effect) }

        guard !didHandleEnd,
              let duration = playback.durationSeconds,
              duration - playback.positionSeconds <= 0.5,
              duration - playback.positionSeconds >= 0 else { return }
        didHandleEnd = true
        if deferredUpNext {
            visibleSkipSegment = nil
            presentDeferredUpNext()
        }
        if let effect = automation.playbackEnded(hasNextEpisode: hasNextEpisode) {
            apply(effect)
        }
    }

    private func apply(_ effect: PlaybackAutomationController.Effect) {
        switch effect {
        case let .presentSkip(segment):
            visibleSkipSegment = segment
            restartSkipPromptTimer()
            dismissChromeForContextualAction()
            // An outro that starts after Up Next took its place.
            if segment.kind.isEnding, showsUpNext {
                showsUpNext = false
                cancelNextEpisodeAutoPlay()
                deferredUpNext = true
            }
        case .dismissSkip:
            visibleSkipSegment = nil
            skipPromptTask?.cancel()
            presentDeferredUpNext()
        case let .autoSkip(segment, position):
            playback.seek(to: position)
            visibleSkipSegment = nil
            showSkipNotice("Skipped \(segment.kind.settingsTitle)")
            presentDeferredUpNext()
        case .presentUpNext:
            if visibleSkipSegment?.kind.isEnding == true {
                deferredUpNext = true
            } else {
                presentUpNext()
            }
        case .preloadNextEpisode:
            preloadNextEpisodeSources()
        }
    }

    private func presentUpNext() {
        deferredUpNext = false
        showsUpNext = true
        dismissChromeForContextualAction()
        if settings.preferences.autoplayNextEpisode {
            startNextEpisodeAutoPlay()
        }
    }

    private func presentDeferredUpNext() {
        guard deferredUpNext else { return }
        presentUpNext()
    }

    private func restartSkipPromptTimer() {
        skipPromptExpired = false
        skipPromptTask?.cancel()
        skipPromptTask = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            skipPromptExpired = true
        }
    }

    private func showSkipNotice(_ text: String) {
        skipNotice = text
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            if skipNotice == text { skipNotice = nil }
        }
    }

    /// Nuvio's Auto-play Next Episode: chooses the next episode's source in
    /// the background while the credits run, counts down 3, 2, 1 and then
    /// switches. With no source chosen, the source list opens instead.
    private func startNextEpisodeAutoPlay() {
        guard nextEpisodeAutoPlay == nil,
              nextSourceRequest == nil,
              let item = playback.mediaItem,
              let episode = playback.nextEpisode,
              episode.hasAired
        else { return }
        guard let request = behavior.nextEpisodeRequest(
            currentBingeGroup: playback.currentCandidate?.bingeGroup,
            autoplayNextEpisode: true
        ) else {
            openNextEpisodeSources(autoSelection: nil)
            return
        }
        nextEpisodeAutoPlay = NextEpisodeAutoPlay(episode: episode, candidate: nil, secondsLeft: 3)
        let key = PlaybackLauncher.linkKey(item: item, episode: episode)
        let addons = store.installedAddons
        let pluginPlan = plugins.plan(for: item, episode: episode)
        let serverPlan = MediaServerStore.shared.streamPlan()
        let timeout = settings.preferences.addonTimeout
        let sorting = settings.preferences.playbackBehavior.streamSorting
        nextEpisodeTask?.cancel()
        nextEpisodeTask = Task {
            var outcome: StreamAutoPlayTracker.Outcome?
            let run = StreamAutoSelectionRun(request: request) { outcome = $0 }
            if let preloaded = playback.takePreloadedSources(for: key) {
                run.receive(StreamRanking.rank(preloaded.candidates, preferences: sorting), isComplete: true)
            } else {
                let lookup = Task {
                    let result = await PlaybackSourceResolver.resolve(
                        for: item,
                        episode: episode,
                        addons: addons,
                        plugins: pluginPlan,
                        servers: serverPlan,
                        timeout: timeout
                    ) { partial, _ in
                        run.receive(StreamRanking.rank(partial.candidates, preferences: sorting), isComplete: false)
                    }
                    guard !Task.isCancelled else { return }
                    run.receive(StreamRanking.rank(result.candidates, preferences: sorting), isComplete: true)
                }
                // Nuvio gives up after two minutes and shows the list.
                let deadline = Date().addingTimeInterval(120)
                while outcome == nil, !Task.isCancelled, Date() < deadline {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                lookup.cancel()
            }
            guard !Task.isCancelled, nextEpisodeAutoPlay?.episode == episode else {
                run.cancel()
                return
            }
            guard case let .play(candidate) = outcome else {
                run.cancel()
                nextEpisodeAutoPlay = nil
                openNextEpisodeSources(autoSelection: nil)
                return
            }
            nextEpisodeAutoPlay?.candidate = candidate
            for secondsLeft in stride(from: 3, through: 1, by: -1) {
                nextEpisodeAutoPlay?.secondsLeft = secondsLeft
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, nextEpisodeAutoPlay != nil else { return }
            }
            playNextEpisode(episode, candidate: candidate)
        }
    }

    private func cancelNextEpisodeAutoPlay() {
        nextEpisodeTask?.cancel()
        nextEpisodeTask = nil
        nextEpisodeAutoPlay = nil
    }

    private func playNextEpisode(_ episode: MediaEpisode, candidate: AddonStreamCandidate) {
        nextEpisodeTask?.cancel()
        nextEpisodeTask = nil
        nextEpisodeAutoPlay = nil
        guard let item = playback.mediaItem, let source = candidate.nativePlaybackSource else { return }
        PlaybackLauncher.start(
            input: .stream(source),
            candidate: candidate,
            item: item,
            progressItem: item,
            episode: episode,
            resumeAt: nil,
            linkKey: PlaybackLauncher.linkKey(item: item, episode: episode),
            playback: playback,
            settings: settings,
            store: store
        )
    }

    /// Nuvio's Preload Next Episode Sources: the lookup runs ahead of Up
    /// Next, so the list or the automatic choice is ready when it appears.
    private func preloadNextEpisodeSources() {
        guard let item = playback.mediaItem,
              let episode = playback.nextEpisode,
              episode.hasAired else { return }
        let key = PlaybackLauncher.linkKey(item: item, episode: episode)
        let addons = store.installedAddons
        let pluginPlan = plugins.plan(for: item, episode: episode)
        let serverPlan = MediaServerStore.shared.streamPlan()
        let timeout = settings.preferences.addonTimeout
        preloadTask?.cancel()
        preloadTask = Task {
            let result = await PlaybackSourceResolver.resolve(
                for: item,
                episode: episode,
                addons: addons,
                plugins: pluginPlan,
                servers: serverPlan,
                timeout: timeout
            )
            guard !Task.isCancelled else { return }
            playback.storePreloadedSources(result, for: key)
        }
    }

    private func revealChrome() {
        chromeHideTask?.cancel()
        showsChrome = true
        guard !isScrubbing else { return }
        hideChrome(after: 3.2)
    }

    private func concealChrome() {
        guard !isScrubbing else { return }
        chromeHideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { showsChrome = false }
    }

    private func dismissChromeForContextualAction() {
        guard !isScrubbing else { return }
        chromeHideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { showsChrome = false }
    }

    private func hideChrome(after delay: TimeInterval) {
        chromeHideTask?.cancel()
        chromeHideTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !isScrubbing else { return }
                withAnimation(.easeInOut(duration: 0.2)) { showsChrome = false }
            }
        }
    }
}

/// Fusion-style playback chrome is one coordinated overlay above the libmpv
/// renderer. Contextual episode actions stay available when the main transport
/// surface dismisses so they never obstruct or depend on transient chrome.
private struct PlaybackChrome: View {
    @Binding var isScrubbing: Bool
    let close: () -> Void
    let hasNextEpisode: Bool
    let showUpNext: () -> Void
    let playEpisode: (MediaEpisode) -> Void
    let showSources: () -> Void

    var body: some View {
        // One set of controls on every platform: the Mac's, laid out for
        // the screen it's on.
        MacPlaybackChrome(
            isInteracting: $isScrubbing,
            close: close,
            hasNextEpisode: hasNextEpisode,
            showUpNext: showUpNext,
            playEpisode: playEpisode,
            showSources: showSources
        )
        #if os(macOS)
        .ignoresSafeArea()
        #endif
    }
}

/// The title's backdrop, logo and episode while a stream opens.
private struct PlaybackLoadingOverlay: View {
    let item: MediaItem
    let episode: MediaEpisode?
    let status: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathes = false

    private var isPhone: Bool {
        OmniaDevice.isPhone
    }

    var body: some View {
        ZStack {
            Color.black
            // The artwork fills the overlay without sizing it, so the
            // title stays centred in the window whatever the image's shape.
            if let backdrop = item.backdropURL ?? item.artworkURL {
                Color.clear
                    .overlay {
                        RemoteArtworkImage(url: backdrop)
                            .background {
                                MediaItem.placeholderArtworkColor
                            }
                    }
                    .clipped()
                    .opacity(0.45)
                    .blur(radius: 6)
            }
            LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: isPhone ? 10 : 18) {
                Group {
                    if let logo = item.logoURL {
                        TitleLogoView(url: logo, title: item.title, maximumWidth: isPhone ? 240 : 420, maximumHeight: isPhone ? 80 : 140, alignment: .center)
                    } else {
                        Text(item.title)
                            .font(isPhone ? .title2.weight(.bold) : .largeTitle.weight(.bold))
                            .multilineTextAlignment(.center)
                    }
                }
                // Nuvio's loading pulse: the title grows and shrinks gently
                // until the first frame arrives.
                .scaleEffect(breathes ? 1.08 : 0.94)
                .opacity(breathes ? 1 : 0.8)
                if let episode {
                    Text("S\(episode.seasonNumber) E\(episode.episodeNumber) · \(episode.title)")
                        .font(isPhone ? .subheadline : .headline)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    if let status {
                        Text(status)
                            .font(isPhone ? .caption : .callout)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: isPhone ? 320 : 560)
            .padding(isPhone ? 24 : 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                breathes = true
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The title's details over a paused picture.
/// The next episode Up Next offers, and the countdown when one is running.
struct PlaybackUpNextPrompt: Equatable {
    let episode: MediaEpisode
    let status: String?
    let isCountingDown: Bool
}

/// Skip Intro or Outro, and Up Next with its countdown, as an overlay of
/// their own rather than buttons in the controls row.
private struct PlaybackPromptOverlay: View {
    let skipTitle: String?
    let skip: () -> Void
    let upNext: PlaybackUpNextPrompt?
    let playNext: () -> Void
    let cancel: (() -> Void)?

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if let skipTitle {
                Button(action: skip) {
                    Label(skipTitle, systemImage: "forward.end.fill")
                        .font(.headline.weight(.semibold))
                        .padding(.horizontal, 20)
                        .frame(minHeight: 46)
                        .contentShape(Capsule())
                }
                .omniaCapsuleGlassButton(element: .playerControls)
                .keyboardShortcut(.return, modifiers: [])
                .accessibilityHint("Seeks past the detected segment")
            }
            if let upNext {
                upNextCard(upNext)
            }
        }
        .foregroundStyle(.white)
    }

    private func upNextCard(_ prompt: PlaybackUpNextPrompt) -> some View {
        HStack(alignment: .center, spacing: 14) {
            CachedArtworkImage(url: prompt.episode.stillURL, size: CGSize(width: 136, height: 77)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    ZStack {
                        Color.white.opacity(0.08)
                        Image(systemName: "film")
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .frame(width: 136, height: 77)
            .clipShape(.rect(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Up Next")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.65))
                    .textCase(.uppercase)
                Text(MacPlaybackEpisodePresentation.title(prompt.episode))
                    .font(.headline)
                    .lineLimit(1)
                Text("Season \(prompt.episode.seasonNumber), Episode \(prompt.episode.episodeNumber)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                if let status = prompt.status {
                    Text(status)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .contentTransition(.numericText(countsDown: true))
                }
                HStack(spacing: 8) {
                    Button(action: playNext) {
                        Label(prompt.isCountingDown ? "Play Now" : "Play", systemImage: "play.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 32)
                            .contentShape(Capsule())
                    }
                    .omniaCapsuleGlassButton(element: .playerControls)
                    .accessibilityHint("Plays the next episode")
                    if let cancel {
                        Button(action: cancel) {
                            Text("Cancel")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .frame(minHeight: 32)
                                .contentShape(Capsule())
                        }
                        .omniaCapsuleGlassButton(element: .playerControls)
                        .accessibilityHint("Stops the next episode from starting automatically")
                    }
                }
                .padding(.top, 4)
            }
            .frame(width: 230, alignment: .leading)
        }
        .padding(12)
        .omniaGlass(.playerControls, base: .clear, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Up Next")
    }
}

private struct PlaybackPauseOverlay: View {
    let item: MediaItem
    let episode: MediaEpisode?
    /// Sits higher while the controls are up, so it never runs under them.
    var clearsControls = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    /// A phone, either way up: a short corner note instead of a block that
    /// covers the picture.
    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact || verticalSizeClass == .compact
        #else
        false
        #endif
    }

    private var overview: String {
        let episodeOverview = episode?.overview.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return episodeOverview.isEmpty ? item.overview : episodeOverview
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [.black.opacity(0.85), .black.opacity(0.35), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .ignoresSafeArea()
            VStack(alignment: .leading, spacing: isCompact ? 5 : 10) {
                Text("You're watching")
                    .font(isCompact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                if let logo = item.logoURL {
                    TitleLogoView(
                        url: logo,
                        title: item.title,
                        maximumWidth: isCompact ? 170 : 320,
                        maximumHeight: isCompact ? 56 : 110,
                        alignment: .leading
                    )
                } else {
                    Text(item.title)
                        .font(isCompact ? .title3.weight(.bold) : .largeTitle.weight(.bold))
                        .lineLimit(2)
                }
                if let episode {
                    Text("S\(episode.seasonNumber) E\(episode.episodeNumber) · \(episode.title)")
                        .font(isCompact ? .footnote.weight(.semibold) : .title3.weight(.semibold))
                        .lineLimit(1)
                }
                if !overview.isEmpty {
                    Text(overview)
                        .font(isCompact ? .caption : .body)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(isCompact ? 2 : 5)
                        .frame(maxWidth: isCompact ? 300 : 520, alignment: .leading)
                }
            }
            .foregroundStyle(.white)
            .padding(.leading, isCompact ? 24 : 56)
            .padding(.trailing, isCompact ? 24 : 0)
            .padding(.bottom, clearsControls ? (isCompact ? 150 : 170) : (isCompact ? 40 : 120))
            .animation(.easeInOut(duration: 0.2), value: clearsControls)
        }
        // The text keeps clear of the notch and home indicator; only the
        // shade runs to the edges.
        #if os(macOS)
        .ignoresSafeArea()
        #endif
        .accessibilityElement(children: .combine)
    }
}

#if os(iOS)
/// The player's touch gestures on iPhone and iPad.
private struct PlaybackTouchGestures: View {
    let isEnabled: Bool
    let toggleChrome: () -> Void

    @Environment(PlaybackSession.self) private var playback
    @State private var feedback: Feedback?
    @State private var feedbackTask: Task<Void, Never>?
    @State private var drag: DragMode?
    @State private var screen: UIScreen?

    private enum DragMode {
        case brightness(start: Double)
        case volume(start: Double)
        case seek(start: Double)
    }

    private enum Feedback: Equatable {
        case seek(Int)
        case brightness(Double)
        case volume(Double)
        case scrub(target: Double, delta: Double)
    }

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture(count: 2)
                        .onEnded { value in
                            guard isEnabled else { return }
                            skip(forward: value.location.x > geometry.size.width / 2)
                        }
                        .exclusively(before: TapGesture().onEnded { toggleChrome() })
                )
                .simultaneousGesture(dragGesture(in: geometry.size))
                .overlay(alignment: .top) {
                    feedbackView.padding(.top, 64)
                }
                .background {
                    IOSPlayerScreenReader { screen = $0 }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .onDisappear { feedbackTask?.cancel() }
        }
    }

    /// Repeated double taps add up, as in most players.
    private func skip(forward: Bool) {
        let step = forward ? 10 : -10
        playback.seek(by: Double(step))
        var total = step
        if case let .seek(previous) = feedback, previous.signum() == step.signum() {
            total += previous
        }
        show(.seek(total))
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard isEnabled else { return }
                if drag == nil {
                    if abs(value.translation.width) > abs(value.translation.height) {
                        guard playback.durationSeconds != nil else { return }
                        drag = .seek(start: playback.positionSeconds)
                    } else if value.startLocation.x < size.width / 2 {
                        guard let screen else { return }
                        drag = .brightness(start: Double(screen.brightness))
                    } else {
                        drag = .volume(start: playback.volume)
                    }
                }
                let lift = -value.translation.height / (size.height * 0.8)
                switch drag {
                case let .brightness(start):
                    let level = clamp(start + lift)
                    screen?.brightness = CGFloat(level)
                    show(.brightness(level), hides: false)
                case let .volume(start):
                    let level = clamp(start + lift)
                    playback.setVolume(level)
                    show(.volume(playback.volume), hides: false)
                case let .seek(start):
                    // A drag across the whole screen covers three minutes.
                    let duration = playback.durationSeconds ?? 0
                    let target = min(max(start + value.translation.width / size.width * 180, 0), duration)
                    show(.scrub(target: target, delta: target - start), hides: false)
                case nil:
                    break
                }
            }
            .onEnded { _ in
                if case let .scrub(target, _) = feedback { playback.seek(to: target) }
                drag = nil
                show(feedback)
            }
    }

    private func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }

    private func show(_ value: Feedback?, hides: Bool = true) {
        feedbackTask?.cancel()
        feedback = value
        guard hides else { return }
        feedbackTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { feedback = nil }
        }
    }

    @ViewBuilder
    private var feedbackView: some View {
        if let feedback {
            Group {
                switch feedback {
                case let .seek(seconds):
                    Label("\(seconds > 0 ? "+" : "−")\(abs(seconds)) s", systemImage: seconds > 0 ? "goforward" : "gobackward")
                case let .brightness(level):
                    meter(symbol: "sun.max.fill", value: level)
                case let .volume(level):
                    meter(symbol: level == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", value: level)
                case let .scrub(target, delta):
                    Text("\(Self.time(target))  (\(delta >= 0 ? "+" : "−")\(Self.time(abs(delta))))")
                        .monospacedDigit()
                }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .omniaGlass(.playerControls, base: .clear, in: Capsule())
            .allowsHitTesting(false)
            .transition(.opacity)
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private func meter(symbol: String, value: Double) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
            ProgressView(value: value)
                .frame(width: 90)
                .tint(.white)
            Text(value, format: .percent.precision(.fractionLength(0)))
                .monospacedDigit()
                .frame(minWidth: 42, alignment: .trailing)
        }
    }

    private static func time(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remainder = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%d:%02d", minutes, remainder)
    }
}
#endif

#if os(iOS)
/// iPhone's sheet stops at two heights; iPad's is sized by omniaStreamsPage.
private struct StreamSheetSizing: ViewModifier {
    func body(content: Content) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            content
        } else {
            content.presentationDetents([.medium, .large])
        }
    }
}
#endif
