//
//  PlaybackViews.swift
//  Omnia
//

import SwiftUI

struct PlaybackSourceSheet: View {
    let item: MediaItem
    var episode: MediaEpisode? = nil
    var resumeAt: Double? = nil
    var onClose: (() -> Void)? = nil

    @Environment(OmniaStore.self) private var store
    @Environment(LiveMetadataStore.self) private var metadata
    @Environment(PlaybackSession.self) private var playback
    @Environment(SettingsPreferencesStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [AddonStreamCandidate] = []
    @State private var resolution: PlaybackSourceResolution?
    @State private var isResolving = true
    @State private var selectionID: UUID?
    @State private var isHandingOffPlayback = false
    @State private var retryingAddonIDs: Set<String> = []
    @State private var selectedAddonID: String?
    @State private var resolvingCandidateID: String?
    @State private var resolverFailures: [String: String] = [:]
    @State private var localResolverSettings = LocalResolverSettingsStore()
    @State private var pendingLocalTorrentCandidate: AddonStreamCandidate?
    @State private var localTorrentProgress: [String: Double] = [:]
    #if os(macOS)
    @State private var localTorrentEngine: OMLocalTorrentEngine?
    @State private var localTorrentTask: Task<Void, Never>?
    @State private var discMaterializer: DiscMaterializer?
    @State private var discPreparationTask: Task<Void, Never>?
    @State private var preparingDiscCandidateID: String?
    @State private var discPreparationStates: [String: DiscPreparationState] = [:]
    #endif

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Choose Source")
                    .font(.headline)
                Spacer()
                Button("Cancel") { closePresentation() }
            }
            .padding(.horizontal, 20)
            .frame(height: 52)

            Divider()

            Group {
                if isResolving {
                    ProgressView("Finding sources…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if candidates.isEmpty {
                    VStack(spacing: 0) {
                        ContentUnavailableView(
                            "No Sources Found",
                            systemImage: "play.slash",
                            description: Text(emptyStateDescription)
                        )
                        .frame(maxWidth: .infinity)

                        if !addonStatusResults.isEmpty {
                            List {
                                Section("Add-on Status") {
                                    ForEach(addonStatusResults) { result in
                                        addonStatusRow(result)
                                    }
                                }
                            }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                            .background(.clear)
                            .frame(minHeight: 180)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        sourceFilters
                        Divider()
                        List {
                            if !addonStatusResults.isEmpty {
                                Section("Add-on Status") {
                                    ForEach(addonStatusResults) { result in
                                        addonStatusRow(result)
                                    }
                                }
                            }

                            if !sourceSections.direct.isEmpty {
                                Section {
                                    ForEach(sourceSections.direct) { candidate in
                                        playbackButton(candidate)
                                    }
                                }
                            }

                            if !sourceSections.resolverRequired.isEmpty {
                                Section {
                                    ForEach(sourceSections.resolverRequired) { candidate in
                                        resolverRequiredRow(candidate)
                                    }
                                } header: {
                                    Text("Local Peer-to-Peer Sources")
                                } footer: {
                                    Text("On macOS, Omnia resolves these locally into its bounded cache, then opens the completed file or a validated single BDMV tree with libmpv. Peer activity never starts through autoplay.")
                                }
                            }

                            if !sourceSections.external.isEmpty {
                                Section {
                                    ForEach(sourceSections.external) { candidate in
                                        unavailableRow(candidate)
                                    }
                                } header: {
                                    Text("External Pages")
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
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .background(.clear)
                    }
                }
            }
            .task(id: mediaKey) {
                let selectionID = playback.beginSourceSelection()
                self.selectionID = selectionID
                isHandingOffPlayback = false
                isResolving = true
                candidates = []
                resolution = nil
                selectedAddonID = nil
                resolverFailures = [:]
                let enrichedItem = await metadata.details(for: item)
                guard !Task.isCancelled, playback.isCurrentSourceSelection(selectionID) else { return }
                let lookupItem = item.mergingSourceIdentifiers(from: enrichedItem)
                let result = await PlaybackSourceResolver.resolve(
                    for: lookupItem,
                    episode: episode,
                    addons: store.installedAddons,
                    timeout: settings.preferences.addonTimeout
                )
                guard !Task.isCancelled, playback.isCurrentSourceSelection(selectionID) else { return }
                resolution = result
                candidates = result.candidates
                isResolving = false
                startAutomaticallyIfAllowed()
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
        #if os(macOS)
        // `List` has no useful intrinsic height in an automatically sized
        // macOS sheet. Without an explicit content size AppKit may collapse
        // the list to zero points, leaving only the navigation title and
        // Cancel button even when the resolver returned source rows.
        .frame(width: 700, height: 560)
        .omniaModalGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        #else
        .presentationDetents([.medium, .large])
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

    private var addonStatusResults: [AddonSourceResolution] {
        resolution?.addonResults.filter { $0.state != .loaded } ?? []
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
            candidates = updated.candidates
            retryingAddonIDs.remove(addonID)
        }
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
        }
        #if os(macOS)
        .omniaRoundedGlassButton(cornerRadius: 14, role: .control)
        #else
        .buttonStyle(.plain)
        #endif
        .accessibilityLabel("\(title), \(count) sources")
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
                            : "play.circle.fill",
                        tint: .accentColor,
                        status: preparationStatus,
                        showsDisclosure: false
                    )
                }
                .omniaMenuRowButton()
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
                candidateRow(candidate, symbol: "play.circle.fill", tint: .accentColor)
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
                symbol: resolvingCandidateID == candidate.id ? "arrow.down.circle" : "play.circle.fill",
                tint: .accentColor,
                status: status
            )
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .omniaMenuRowButton()
        #endif
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
            tint: .secondary,
            status: reason
        )
            .accessibilityElement(children: .combine)
    }

    private func candidateRow(
        _ candidate: AddonStreamCandidate,
        symbol: String,
        tint: Color,
        status: String? = nil,
        showsDisclosure: Bool = true
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
                        .foregroundStyle(status.localizedCaseInsensitiveContains("ready") ? .green : .orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if showsDisclosure, case .nativeHTTPS = candidate.delivery {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
        .contentShape(.rect)
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
        let item = item
        let episode = episode
        let resumeAt = resumeAt
        let mediaKey = mediaKey
        isHandingOffPlayback = true
        closePresentation(preservingSelection: true)

        Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, playback.claimSourceSelection(selectionID) else {
                releaseUnusedInput(input)
                return
            }
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
            playback.start(
                item: item,
                episode: episode,
                input: input,
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
        guard !Task.isCancelled,
              let selectionID,
              playback.isCurrentSourceSelection(selectionID),
              settings.preferences.rememberLastSelection else { return }
        #if os(macOS)
        let directCandidates = candidates.filter {
            $0.nativePlaybackSource != nil
                && PlaybackSourceRowState(candidate: $0).isEligibleForAutoplay
        }
        #else
        let directCandidates = candidates.filter { $0.nativePlaybackSource != nil }
        #endif
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
            context = "\(episode.title) · S\(episode.seasonNumber), E\(episode.episodeNumber)"
        } else {
            context = item?.year ?? ""
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
    @State private var nextSourceRequest: PlaybackRequest?
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
            PlaybackChrome(
                isScrubbing: $isScrubbing,
                close: { playback.stop() },
                showsSkipIntro: visibleSkipSegment != nil,
                skipIntro: {
                    guard let visibleSkipSegment else { return }
                    playback.seek(to: visibleSkipSegment.endSeconds)
                    self.visibleSkipSegment = nil
                },
                upNextTitle: upNextTitle,
                showUpNext: presentNextEpisode
            )
            .opacity(showsChrome ? 1 : 0)
            .allowsHitTesting(showsChrome)
            .animation(.easeInOut(duration: 0.2), value: showsChrome)
        }
        #if !os(macOS)
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
                        presentNextEpisode()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Choose an in-app source for the next episode")
                }
            }
            .padding(28)
        }
        #endif
        .onAppear { revealChrome() }
        .onDisappear { chromeHideTask?.cancel() }
        .task(id: playbackAutomationKey) {
            configureAutomation()
            await loadIntroSegments()
        }
        .onChange(of: playback.positionSeconds) { _, _ in updateAutomation() }
        .onChange(of: isScrubbing) { _, isInteracting in
            if isInteracting {
                chromeHideTask?.cancel()
                showsChrome = true
            } else {
                hideChrome(after: 3.2)
            }
        }
        .omniaGlassModal(isPresented: showsNextSourceSheet) {
            if let request = nextSourceRequest {
                PlaybackSourceSheet(
                    item: request.item,
                    episode: request.episode,
                    onClose: { nextSourceRequest = nil }
                )
                .id(request.id)
            }
        }
        #if os(macOS)
        .background {
            MacPlaybackKeyboardMonitor { action in
                switch action {
                case .seekBackward10:
                    playback.seek(by: -10)
                    revealChrome()
                case .seekForward10:
                    playback.seek(by: 10)
                    revealChrome()
                case .close:
                    playback.stop()
                }
            }
            .frame(width: 0, height: 0)
        }
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

    private var showsNextSourceSheet: Binding<Bool> {
        Binding(
            get: { nextSourceRequest != nil },
            set: { if !$0 { nextSourceRequest = nil } }
        )
    }

    private func presentNextEpisode() {
        guard nextSourceRequest == nil,
              let item = playback.mediaItem,
              let episode = playback.nextEpisode else { return }
        nextSourceRequest = PlaybackRequest(item: item, episode: episode, resumeAt: nil)
    }

    private var upNextTitle: String? {
        guard showsUpNext, let nextEpisode = playback.nextEpisode else { return nil }
        return "Up Next: S\(nextEpisode.seasonNumber) E\(nextEpisode.episodeNumber)"
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
        nextSourceRequest = nil
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
            presentNextEpisode()
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
    let showsSkipIntro: Bool
    let skipIntro: () -> Void
    let upNextTitle: String?
    let showUpNext: () -> Void

    var body: some View {
        #if os(macOS)
        MacPlaybackChrome(
            isInteracting: $isScrubbing,
            close: close,
            showsSkipIntro: showsSkipIntro,
            skipIntro: skipIntro,
            upNextTitle: upNextTitle,
            showUpNext: showUpNext
        )
            .ignoresSafeArea()
        #else
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
        #endif
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
