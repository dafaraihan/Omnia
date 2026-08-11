//
//  PlaybackViews.swift
//  Omnia
//

import SwiftUI

struct PlaybackSourceSheet: View {
    let item: MediaItem
    var episode: MediaEpisode? = nil

    @Environment(OmniaStore.self) private var store
    @Environment(LiveMetadataStore.self) private var metadata
    @Environment(PlaybackSession.self) private var playback
    @Environment(SettingsPreferencesStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @AppStorage("resume-playback") private var resumePlayback = true
    @State private var candidates: [AddonStreamCandidate] = []
    @State private var resolution: PlaybackSourceResolution?
    @State private var isResolving = true
    @State private var selectedAddonID: String?
    @State private var resolvingCandidateID: String?
    @State private var resolverFailures: [String: String] = [:]

    var body: some View {
        NavigationStack {
            Group {
                if isResolving {
                    ProgressView("Finding sources…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if candidates.isEmpty {
                    ContentUnavailableView(
                        "No Sources Found",
                        systemImage: "play.slash",
                        description: Text(emptyStateDescription)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        sourceFilters
                        Divider()
                        List {
                            if !sourceSections.direct.isEmpty {
                                Section {
                                    ForEach(sourceSections.direct) { candidate in
                                        playbackButton(candidate)
                                    }
                                } header: {
                                    Text("Direct HTTPS Sources")
                                } footer: {
                                    Text("Omnia opens these with libmpv on macOS. HLS, MP4, and Matroska streams are handed directly to the player; a stream can still fail when its server refuses the request or the media is malformed.")
                                }
                            }

                            if !sourceSections.resolverRequired.isEmpty {
                                Section {
                                    ForEach(sourceSections.resolverRequired) { candidate in
                                        resolverRequiredRow(candidate)
                                    }
                                } header: {
                                    Text("Requires a Configured Resolver")
                                } footer: {
                                    Text("These add-ons supplied a torrent info hash and file index. Omnia retains the exact source data until a configured resolver turns it into a final HTTPS media URL for the player.")
                                }
                            }

                            if !sourceSections.external.isEmpty {
                                Section {
                                    ForEach(sourceSections.external) { candidate in
                                        unavailableRow(candidate)
                                    }
                                } header: {
                                    Text("External Pages")
                                } footer: {
                                    Text("These add-on results are webpages, not media streams. Omnia shows them for completeness but does not open or resolve them locally.")
                                }
                            }

                            if !sourceSections.unavailable.isEmpty {
                                Section {
                                    ForEach(sourceSections.unavailable) { candidate in
                                        unavailableRow(candidate)
                                    }
                                } header: {
                                    Text("Unavailable Sources")
                                }
                            }

                            Section("Source Handling") {
                                Label("Direct HTTPS streams play in Omnia", systemImage: "play.rectangle")
                                Text("Torrent-backed streams retain their add-on-provided info hash and file index until a configured resolver returns an authorized HTTPS stream for Omnia.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .listStyle(.inset)
                    }
                }
            }
            .navigationTitle("Choose Source")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: "\(item.id)::\(episode?.id ?? "title")") {
                isResolving = true
                let enrichedItem = await metadata.details(for: item)
                let lookupItem = item.mergingSourceIdentifiers(from: enrichedItem)
                let result = await PlaybackSourceResolver.resolve(
                    for: lookupItem,
                    episode: episode,
                    addons: store.installedAddons
                )
                resolution = result
                candidates = result.candidates
                isResolving = false
                startAutomaticallyIfAllowed()
            }
        }
        #if os(macOS)
        // `List` has no useful intrinsic height in an automatically sized
        // macOS sheet. Without an explicit content size AppKit may collapse
        // the list to zero points, leaving only the navigation title and
        // Cancel button even when the resolver returned source rows.
        .frame(minWidth: 620, minHeight: 480)
        #endif
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

    private var enabledStreamAddons: [InstalledAddon] {
        store.installedAddons.filter { $0.isEnabled && $0.manifest.supportsStreams }
    }

    private var filteredCandidates: [AddonStreamCandidate] {
        guard let selectedAddonID else { return candidates }
        return candidates.filter { $0.addonID == selectedAddonID }
    }

    private var sourceFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                sourceFilter(
                    title: "All",
                    count: candidates.count,
                    isSelected: selectedAddonID == nil
                ) {
                    selectedAddonID = nil
                }

                ForEach(enabledStreamAddons) { addon in
                    sourceFilter(
                        title: addon.manifest.name,
                        count: candidates.filter { $0.addonID == addon.id }.count,
                        isSelected: selectedAddonID == addon.id
                    ) {
                        selectedAddonID = addon.id
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .accessibilityLabel("Add-on source filters")
    }

    private func sourceFilter(
        title: String,
        count: Int,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                Text("\(count)")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(isSelected ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count) sources")
    }

    @ViewBuilder
    private func playbackButton(_ candidate: AddonStreamCandidate) -> some View {
        if let source = candidate.nativePlaybackSource {
            Button {
                beginPlayback(source, candidate: candidate)
            } label: {
                candidateRow(candidate, symbol: "play.circle.fill", tint: .accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Starts native playback")
        }
    }

    @ViewBuilder
    private func resolverRequiredRow(_ candidate: AddonStreamCandidate) -> some View {
        let status = resolverStatus(for: candidate)
        Group {
            if status == nil {
                Button {
                    resolveAndStart(candidate)
                } label: {
                    candidateRow(
                        candidate,
                        symbol: resolvingCandidateID == candidate.id ? "hourglass" : "play.circle.fill",
                        tint: .accentColor,
                        status: resolvingCandidateID == candidate.id ? "Resolving authorized HTTPS stream…" : "Ready to resolve"
                    )
                }
                .buttonStyle(.plain)
                .disabled(resolvingCandidateID != nil)
                .accessibilityHint("Requests an authorized HTTPS stream from your configured resolver")
            } else {
                candidateRow(candidate, symbol: "lock.slash", tint: .secondary, status: status)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Configure or authorize a resolver before this source can play")
            }
        }
    }

    private func unavailableRow(_ candidate: AddonStreamCandidate) -> some View {
        let reason: String
        switch PlaybackSourceRowState(candidate: candidate).action {
        case let .unavailable(message):
            reason = message
        case .playDirect, .resolve:
            reason = "Unavailable"
        }

        return candidateRow(
            candidate,
            symbol: "exclamationmark.triangle",
            tint: .secondary,
            status: reason
        )
            .accessibilityElement(children: .combine)
    }

    private func candidateRow(
        _ candidate: AddonStreamCandidate,
        symbol: String,
        tint: Color,
        status: String? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                Text(candidate.displayDescription ?? candidate.addonName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(candidate.sourceTypeLabel)
                    if let technicalSummary = candidate.technicalSummary {
                        Text("·")
                        Text(technicalSummary)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                if let sourceIndexDetail = candidate.sourceIndexDetail {
                    Text(sourceIndexDetail)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                if let status {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(status == "Ready to resolve" ? .green : .orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if case .nativeHTTPS = candidate.delivery {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
        .contentShape(.rect)
    }

    private func resolverStatus(for candidate: AddonStreamCandidate) -> String? {
        if let failure = resolverFailures[candidate.id] { return failure }
        do {
            let configuration = try PlaybackResolverSettings.configuration()
            guard configuration.approvedAddonIDs.contains(candidate.addonID) else {
                return PlaybackResolverError.candidateNotApproved.localizedDescription
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func resolveAndStart(_ candidate: AddonStreamCandidate) {
        resolvingCandidateID = candidate.id
        resolverFailures[candidate.id] = nil
        Task {
            do {
                let configuration = try PlaybackResolverSettings.configuration()
                let source = try await AuthorizedPlaybackResolver.resolve(candidate, configuration: configuration)
                guard !Task.isCancelled else { return }
                beginPlayback(source, candidate: candidate)
            } catch {
                resolverFailures[candidate.id] = error.localizedDescription
                resolvingCandidateID = nil
            }
        }
    }

    /// The source picker is itself a transient presentation.  Starting the
    /// root-level player in the same update transaction as dismissing it lets
    /// AppKit occasionally apply the sheet's old presentation state after
    /// `PlaybackSession` has requested the player.  Dismiss first, then start
    /// from the next main-actor turn so the shared player presentation wins.
    private func beginPlayback(_ source: PlaybackSource, candidate: AddonStreamCandidate? = nil) {
        let item = item
        let episode = episode
        let resumeAt = resumePlayback ? item.positionSeconds : nil
        dismiss()

        Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            playback.start(
                item: item,
                episode: episode,
                source: source,
                resumeAt: resumeAt,
                preferences: settings.preferences
            ) { position, duration in
                store.recordPlayback(
                    for: item,
                    episode: episode,
                    positionSeconds: position,
                    durationSeconds: duration
                )
            }
            if settings.preferences.rememberLastSelection, let candidate {
                try? RememberedSourceStore().remember(
                    mediaKey: mediaKey,
                    addonID: candidate.addonID,
                    bingeGroup: candidate.bingeGroup,
                    displayNameFingerprint: candidate.displayNameFingerprint,
                    retention: settings.preferences.sourceSelectionRetention
                )
            }
        }
    }

    private var adapter: PlaybackAdapter {
        #if os(macOS)
        .libmpv
        #else
        .avPlayer
        #endif
    }

    private var mediaKey: MediaPlaybackKey {
        if let episode {
            return MediaPlaybackKey(rawValue: "\(item.id):\(episode.seasonNumber):\(episode.episodeNumber)")
        }
        return MediaPlaybackKey(rawValue: item.id)
    }

    private func startAutomaticallyIfAllowed() {
        let directCandidates = candidates.filter { $0.nativePlaybackSource != nil }
        let remembered = settings.preferences.rememberLastSelection
            ? RememberedSourceStore().source(
                for: mediaKey,
                enabledAddonIDs: Set(store.installedAddons.filter(\.isEnabled).map(\.id))
            )
            : nil
        let decision = PlaybackPolicy.choose(
            from: directCandidates,
            adapter: adapter,
            compatibleOnly: settings.preferences.compatibleFormatsOnly,
            autoplayFirst: settings.preferences.autoplayFirstCompatibleSource,
            remembered: remembered,
            now: .now
        )
        if case let .play(candidate) = decision, let source = candidate.nativePlaybackSource {
            beginPlayback(source, candidate: candidate)
        }
    }

}

struct PlaybackExperienceView: View {
    @Environment(PlaybackSession.self) private var playback
    @Environment(SettingsPreferencesStore.self) private var settings
    @State private var isScrubbing = false
    @State private var showsChrome = true
    @State private var chromeHideTask: Task<Void, Never>?
    @State private var segments: [SkipSegment] = []
    @State private var visibleSkipSegment: SkipSegment?
    @State private var showsUpNext = false
    @State private var showsNextSourceSheet = false
    @State private var didHandleEnd = false
    @State private var automation = PlaybackAutomationController(policy: .init(
        showSkipIntro: true,
        autoSkipIntro: false,
        autoplayNextEpisode: false,
        upNextLeadSeconds: 30
    ))

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let playbackError = playback.playbackError {
                ContentUnavailableView(
                    "Playback Failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(playbackError)
                )
                .foregroundStyle(.white)
            } else if let player = playback.player {
                NativePlayerView(player: player)
                    .ignoresSafeArea()
            } else {
                ContentUnavailableView("Playback Unavailable", systemImage: "play.slash")
                    .foregroundStyle(.white)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            revealChrome()
        }
        .overlay {
            PlaybackChrome(isScrubbing: $isScrubbing) {
                playback.stop()
            }
            .opacity(showsChrome ? 1 : 0)
            .allowsHitTesting(showsChrome)
            .animation(.easeInOut(duration: 0.2), value: showsChrome)
        }
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing, spacing: 10) {
                if let visibleSkipSegment {
                    Button("Skip Intro", systemImage: "forward.end.fill") {
                        playback.seek(to: visibleSkipSegment.endSeconds)
                        self.visibleSkipSegment = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
                    .accessibilityHint("Seeks to the end of the detected intro")
                }
                if showsUpNext, let nextEpisode = playback.nextEpisode {
                    Button("Up Next: S\(nextEpisode.seasonNumber) E\(nextEpisode.episodeNumber)", systemImage: "forward.fill") {
                        showsNextSourceSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Choose an in-app source for the next episode")
                }
            }
            .padding(28)
        }
        .onAppear { revealChrome() }
        .onDisappear { chromeHideTask?.cancel() }
        .task(id: playbackAutomationKey) {
            configureAutomation()
            await loadIntroSegments()
        }
        .onChange(of: playback.positionSeconds) { _, _ in updateAutomation() }
        .sheet(isPresented: $showsNextSourceSheet) {
            if let item = playback.mediaItem, let nextEpisode = playback.nextEpisode {
                PlaybackSourceSheet(item: item, episode: nextEpisode)
            }
        }
        #if os(macOS)
        .onHover { isHovering in
            isHovering ? revealChrome() : hideChrome(after: 2.2)
        }
        #endif
        #if os(iOS)
        // On iOS the full-screen cover disappearing means the user dismissed
        // the player. AppKit can transiently recreate the hosted view while
        // entering/exiting a full-screen space, so macOS stops only through
        // Omnia's explicit Close control instead.
        .onDisappear {
            playback.stop()
        }
        #endif
    }

    private var playbackAutomationKey: String {
        "\(playback.mediaItem?.id ?? "none"):\(playback.episode?.id ?? "title"):\(settings.preferences.showSkipIntro):\(settings.preferences.autoSkipIntro):\(settings.preferences.autoplayNextEpisode):\(settings.preferences.upNextLeadTime.rawValue)"
    }

    private func configureAutomation() {
        automation = PlaybackAutomationController(policy: .init(
            showSkipIntro: settings.preferences.showSkipIntro,
            autoSkipIntro: settings.preferences.autoSkipIntro,
            autoplayNextEpisode: settings.preferences.autoplayNextEpisode,
            upNextLeadSeconds: Double(settings.preferences.upNextLeadTime.rawValue)
        ))
        visibleSkipSegment = nil
        showsUpNext = false
        didHandleEnd = false
    }

    private func loadIntroSegments() async {
        guard settings.preferences.showSkipIntro,
              let item = playback.mediaItem,
              let episode = playback.episode,
              let imdbID = item.externalIDs["imdb"] ?? item.externalIDs["imdb_id"]
        else {
            segments = []
            return
        }
        do {
            segments = try await IntroDBClient().segments(
                imdbID: imdbID,
                season: episode.seasonNumber,
                episode: episode.episodeNumber
            )
            updateAutomation()
        } catch is CancellationError {
            return
        } catch {
            segments = []
        }
    }

    private func updateAutomation() {
        switch automation.update(
            position: playback.positionSeconds,
            duration: playback.durationSeconds,
            segments: segments,
            hasNextEpisode: playback.nextEpisode != nil
        ) {
        case let .presentSkip(segment): visibleSkipSegment = segment
        case .dismissSkip: visibleSkipSegment = nil
        case let .seek(position):
            playback.seek(to: position)
            visibleSkipSegment = nil
        case .presentUpNext: showsUpNext = true
        case .none, .resolveNextEpisode, .stopAtEnd: break
        }

        guard !didHandleEnd,
              let duration = playback.durationSeconds,
              duration - playback.positionSeconds <= 0.5,
              duration - playback.positionSeconds >= 0 else { return }
        didHandleEnd = true
        if automation.playbackEnded(hasNextEpisode: playback.nextEpisode != nil) == .resolveNextEpisode {
            showsNextSourceSheet = true
        }
    }

    private func revealChrome() {
        chromeHideTask?.cancel()
        showsChrome = true
        guard !isScrubbing else { return }
        hideChrome(after: 3.2)
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
/// renderer: its exit button and transport surface appear and dismiss together
/// instead of being unrelated, permanently visible SwiftUI controls.
private struct PlaybackChrome: View {
    @Binding var isScrubbing: Bool
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close player")
                .accessibilityHint("Stops playback and returns to Omnia")
                Spacer()
            }
            .padding(.top, 18)
            .padding(.leading, 18)

            Spacer()

            PlaybackControlSurface(isScrubbing: $isScrubbing)
                .padding(.bottom, 28)
        }
        .ignoresSafeArea()
    }
}

/// Omnia's compact transport surface uses SF Symbols, Slider, Menu, and a
/// system material—Apple resources throughout—while matching the deliberate,
/// low-profile player layout in the supplied reference.
private struct PlaybackControlSurface: View {
    @Environment(PlaybackSession.self) private var playback
    @Binding var isScrubbing: Bool

    private var duration: Double { playback.durationSeconds ?? 0 }
    private var position: Double { min(max(playback.positionSeconds, 0), duration) }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                Image(systemName: playback.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 20)
                    .accessibilityHidden(true)

                Slider(
                    value: Binding(
                        get: { playback.volume },
                        set: { playback.setVolume($0) }
                    ),
                    in: 0...1
                )
                .frame(width: 128)
                .accessibilityLabel("Volume")

                Spacer(minLength: 8)

                controlButton("gobackward.10", label: "Back 10 seconds") {
                    playback.seek(by: -10)
                }

                controlButton(playback.isPaused ? "play.fill" : "pause.fill", label: playback.isPaused ? "Play" : "Pause", prominent: true) {
                    playback.togglePause()
                }

                controlButton("goforward.10", label: "Forward 10 seconds") {
                    playback.seek(by: 10)
                }

                Spacer(minLength: 8)

                Menu {
                    Button {
                        playback.selectSubtitleTrack(nil)
                    } label: {
                        Label("Off", systemImage: playback.subtitleTracks.contains(where: \.isSelected) ? "circle" : "checkmark")
                    }
                    switch PlaybackTrackAvailability(
                        isLoading: playback.areTracksLoading,
                        tracks: playback.subtitleTracks
                    ) {
                    case .loading:
                        ProgressView("Tracks still loading")
                    case .empty:
                        Text("No embedded subtitles")
                    case .available:
                        Divider()
                        ForEach(playback.subtitleTracks) { track in
                            Button {
                                playback.selectSubtitleTrack(track.id)
                            } label: {
                                Label(track.displayName, systemImage: track.isSelected ? "checkmark" : "circle")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "captions.bubble")
                        .font(.body.weight(.semibold))
                        .frame(width: 32, height: 36)
                        .contentShape(.rect)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Subtitles")

                Menu {
                    switch PlaybackTrackAvailability(
                        isLoading: playback.areTracksLoading,
                        tracks: playback.audioTracks
                    ) {
                    case .loading:
                        ProgressView("Tracks still loading")
                    case .empty:
                        Text("No audio tracks")
                    case .available:
                        ForEach(playback.audioTracks) { track in
                            Button {
                                playback.selectAudioTrack(track.id)
                            } label: {
                                Label(track.displayName, systemImage: track.isSelected ? "checkmark" : "circle")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "waveform")
                        .font(.body.weight(.semibold))
                        .frame(width: 32, height: 36)
                        .contentShape(.rect)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Audio track")

                Menu {
                    ForEach([0.5, 0.75, 1, 1.25, 1.5, 2], id: \.self) { rate in
                        Button(playbackRateTitle(rate)) { playback.setPlaybackRate(rate) }
                    }
                } label: {
                    Text(playbackRateTitle(playback.playbackRate))
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 28, minHeight: 32)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Playback speed")

                controlButton("rectangle.inset.filled", label: "Toggle full screen") {
                    playback.toggleFullScreen()
                }
            }

            Slider(
                value: Binding(
                    get: { duration > 0 ? position : 0 },
                    set: { playback.seek(to: $0) }
                ),
                in: 0...max(duration, 0.001),
                onEditingChanged: { isScrubbing = $0 }
            )
            .tint(.white)
            .accessibilityLabel("Playback position")
            .disabled(duration <= 0)

            HStack {
                Text(timeText(position))
                Spacer()
                Text(timeText(duration))
            }
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(maxWidth: 660)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 24)
    }

    private func controlButton(
        _ symbol: String,
        label: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(prominent ? .title3.weight(.semibold) : .body.weight(.semibold))
                .frame(width: prominent ? 42 : 32, height: 36)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func playbackRateTitle(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))x" : String(format: "%.2gx", value)
    }

    private func timeText(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0:00" }
        let total = Int(value.rounded(.down))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
