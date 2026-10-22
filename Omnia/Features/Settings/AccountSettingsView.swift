import SwiftUI

/// Settings › General › Account: the watching profile front and centre,
/// what it has watched, the other profiles, and the Omnia account that
/// keeps them in sync.
struct AccountSettingsView: View {
    @Environment(OmniaAccount.self) private var account
    @Environment(OmniaStore.self) private var store
    @Environment(ProfileStore.self) private var profiles
    @Environment(ProfileDataSync.self) private var profileData
    @Environment(CredentialVaultSync.self) private var credentialVault
    @Environment(\.displayPreferences) private var display
    @State private var confirmation = SettingsConfirmation<DestructiveAction>()
    @State private var isSigningIn = false
    @State private var editingProfile: EditorTarget?
    @State private var appeared = false

    private enum DestructiveAction: Equatable {
        case signOut
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                if let profile = profiles.activeProfile {
                    hero(profile)
                    stats
                }
                profilesCard
                accountCard
            }
            .frame(maxWidth: 640)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
        }
        .omniaNavigationTitle("Account")
        .onAppear {
            withAnimation(.smooth(duration: 0.6)) { appeared = true }
        }
        .sheet(isPresented: $isSigningIn) {
            ScrollView {
                AuthPanel(onSignedIn: { isSigningIn = false })
                    .padding(36)
                    .frame(maxWidth: .infinity)
            }
            .frame(minWidth: 460, minHeight: 600)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        account.cancelCode()
                        isSigningIn = false
                    }
                }
            }
        }
        .sheet(item: $editingProfile) { target in
            ProfileEditorView(target: target)
        }
        .confirmationDialog(
            "Sign Out of Omnia?",
            isPresented: confirmationPresentation,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                guard confirmation.confirm() == .signOut else { return }
                Task { await account.signOut() }
            }
            Button("Cancel", role: .cancel) { confirmation.cancel() }
        } message: {
            Text(credentialVault.hasPendingChanges
                ? "This Mac will return to welcome with no active profiles, library, settings, credentials or Live TV sources. Your account data stays in the cloud. Recent profile changes must sync before sign-out can finish. Unsynced credentials stay encrypted for this account."
                : "This Mac will return to welcome with no active profiles, library, settings, credentials or Live TV sources. Recent profile changes must sync before sign-out can finish. Sign in again to restore your account data.")
        }
    }

    // MARK: Hero

    private func hero(_ profile: ViewerProfile) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(display.accentColor.opacity(0.45))
                    .frame(width: 180, height: 180)
                    .blur(radius: 50)
                    .scaleEffect(appeared ? 1 : 0.6)
                ProfileAvatarView(profile: profile, size: 128)
                    .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
                    .scaleEffect(appeared ? 1 : 0.85)
            }
            .frame(height: 150)
            VStack(spacing: 6) {
                Text(profile.name)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                HStack(spacing: 8) {
                    if profiles.isMain(profile.id) {
                        Label("Main Profile", systemImage: "crown.fill")
                    } else {
                        Label("Profile", systemImage: "person.fill")
                    }
                    if let email = account.user?.email {
                        Text("·")
                        Text(email)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Button("Edit Profile", systemImage: "pencil") {
                editingProfile = .edit(profile)
            }
            .buttonStyle(.glass)
        }
        .opacity(appeared ? 1 : 0)
    }

    // MARK: Stats

    private var stats: some View {
        HStack(spacing: 0) {
            stat(value: "\(store.library.count)", label: "Watchlist", symbol: "bookmark.fill")
            divider
            stat(value: "\(inProgressCount)", label: "In Progress", symbol: "play.circle.fill")
            divider
            stat(value: "\(watchedCount)", label: "Watched", symbol: "checkmark.circle.fill")
            divider
            stat(value: timeWatched, label: "Time Watched", symbol: "clock.fill")
        }
        .padding(.vertical, 18)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
    }

    /// The library with each title once: add-ons and the metadata service
    /// can save one title under several ids.
    private var titleSnapshots: [LocalMediaSnapshot] {
        var kept: [LocalMediaSnapshot] = []
        var seen = Set<String>()
        for snapshot in store.localMediaSnapshots {
            let keys = snapshot.item.identityKeys.union([snapshot.item.id])
            guard seen.isDisjoint(with: keys) else { continue }
            seen.formUnion(keys)
            kept.append(snapshot)
        }
        return kept
    }

    /// Titles in Continue Watching: a resume point, counted once per title
    /// whatever the episode or source.
    private var inProgressCount: Int {
        titleSnapshots.filter { snapshot in
            snapshot.progress != nil && snapshot.watchState.movieWatched != true
        }.count
    }

    /// Titles watched: a finished movie, or a show with at least one
    /// watched episode, each counted once (Dafa, 2026-10-22).
    private var watchedCount: Int {
        titleSnapshots.filter { snapshot in
            snapshot.watchState.movieWatched == true
                || snapshot.watchState.episodeStates.values.contains(true)
        }.count
    }

    /// Playback time counted while watching on this profile, or, when the
    /// library shows more, an estimate from it: finished movies' running
    /// time, watched episodes at the show's episode length, and how far
    /// into each title playback got.
    private var watchedSeconds: Double {
        let estimate = titleSnapshots.reduce(0.0) { total, snapshot in
            let state = snapshot.watchState
            let length = snapshot.durationSeconds ?? 0
            let position = snapshot.progress == nil ? 0 : (snapshot.positionSeconds ?? 0)
            if snapshot.item.kind == .movie {
                return total + (state.movieWatched == true ? max(length, position) : position)
            }
            let episodes = Double(state.episodeStates.values.filter { $0 }.count)
            return total + episodes * length + position
        }
        return max(profileData.activeWatchSeconds, estimate)
    }

    private var timeWatched: String {
        let minutes = Int(watchedSeconds / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = watchedSeconds / 3600
        return hours < 10
            ? "\(hours.formatted(.number.precision(.fractionLength(1))))h"
            : "\(Int(hours))h"
    }

    private func stat(value: String, label: String, symbol: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(display.accentColor)
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Rectangle().fill(.separator).frame(width: 1, height: 44)
    }

    // MARK: Profiles

    /// Nuvio's way: a glance at every profile and one Switch Profile
    /// button that opens Who's Watching.
    private var profilesCard: some View {
        card(title: "Profiles", detail: "\(profiles.profiles.count) of \(ViewerProfile.maximumCount)") {
            HStack(spacing: 16) {
                HStack(spacing: -12) {
                    ForEach(Array(profiles.profiles.enumerated()), id: \.element.id) { index, profile in
                        ProfileAvatarView(
                            profile: profile,
                            size: 44,
                            isSelected: profile.id == profiles.activeProfile?.id
                        )
                        .background(Circle().fill(.background).padding(-2))
                        .zIndex(Double(profiles.profiles.count - index))
                        .help(profile.name)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(profiles.activeProfile.map { "Watching as \($0.name)" } ?? "No profile")
                        .font(.callout.weight(.semibold))
                    Text(profiles.canAddProfile ? "Add, edit or switch profiles." : "All five profiles are in use.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button {
                    ProfileSwitchCenter.shared.openPicker(using: profiles)
                } label: {
                    Label("Switch Profile", systemImage: "person.2.circle")
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
            Divider()
            Toggle(isOn: Binding(
                get: { profiles.rememberLastProfile },
                set: { profiles.rememberLastProfile = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remember Last Profile")
                    Text(profiles.rememberLastProfile
                        ? "Omnia opens straight into the last profile used."
                        : "Omnia asks Who's Watching each time it opens.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            if let active = profiles.activeProfile, !profiles.isMain(active.id) {
                Text(sharingSummary(active))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sharingSummary(_ profile: ViewerProfile) -> String {
        guard profile.usesMainSettings || profile.usesMainAddons || profile.usesMainPlugins else {
            return "\(profile.name) has its own settings. Turn on Use Main Profile Settings in Edit Profile to share the main profile's."
        }
        return "\(profile.name) uses the main profile's settings."
    }

    // MARK: Account

    private var accountCard: some View {
        card(title: "Omnia Account", detail: nil) {
            if let user = account.user {
                HStack(spacing: 12) {
                    Image(systemName: syncSymbol)
                        .font(.system(size: 22))
                        .foregroundStyle(profileData.problem == nil ? AnyShapeStyle(OmniaBrandColors.gradient) : AnyShapeStyle(.orange))
                        .symbolEffect(.rotate, isActive: profileData.isSyncing)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.email ?? "Signed in")
                            .font(.body.weight(.medium))
                        Text(syncDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Sync Now") {
                        Task { await credentialVault.sync(); await profileData.sync() }
                    }
                    .disabled(profileData.isSyncing || credentialVault.isSyncing)
                }
                credentialSyncStatus
                Text("Your account also backs up provider keys, profile PIN protection, media-server connections and Live TV sources in an encrypted vault. Signing in restores them into this device's secure storage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Sign Out", role: .destructive) { confirmation.request(.signOut) }
                    .disabled(account.isWorking)
            } else {
                HStack(spacing: 14) {
                    Image(systemName: "icloud.and.arrow.up")
                        .font(.system(size: 26))
                        .foregroundStyle(OmniaBrandColors.gradient)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Keep everything in sync")
                            .font(.body.weight(.semibold))
                        Text("Sign in to back up this device's setup and restore saved profiles, provider keys, media servers and Live TV sources. Omnia's backend manages vault encryption.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Button("Sign In or Create Account") {
                    account.errorMessage = nil
                    isSigningIn = true
                }
                .buttonStyle(.glassProminent)
                .tint(OmniaBrandColors.violet)
                .disabled(!account.isConfigured)
                if !account.isConfigured {
                    Text("Accounts are unavailable in this build of Omnia.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let errorMessage = account.errorMessage, !isSigningIn {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var credentialSyncStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            if credentialVault.isSyncing {
                ProgressView("Syncing saved credentials…")
            } else if let problem = credentialVault.problem {
                Label(problem, systemImage: "exclamationmark.icloud")
                    .font(.caption)
                Button("Retry Credential Sync") { Task { await credentialVault.sync() } }
            } else if credentialVault.hasPendingChanges {
                Label("Credential changes are saved on this device and waiting to sync", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
            } else if let date = credentialVault.lastSyncedAt {
                Label("Credentials synced \(date.formatted(.relative(presentation: .named)))", systemImage: "lock.icloud")
                    .font(.caption)
            } else {
                Label("Credential backup has not completed yet", systemImage: "lock.icloud")
                    .font(.caption)
            }
            ForEach(credentialVault.conflictIDs, id: \.self) { id in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(credentialVault.label(for: id)) changed on another device.")
                        .font(.callout)
                    HStack {
                        Button("Keep Account Copy") { credentialVault.resolve(id: id, keepDevice: false) }
                        Button("Keep This Device's Change") { credentialVault.resolve(id: id, keepDevice: true) }
                    }
                    .disabled(credentialVault.isSyncing)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var syncSymbol: String {
        if profileData.isSyncing { return "arrow.triangle.2.circlepath" }
        return profileData.problem == nil ? "checkmark.icloud.fill" : "exclamationmark.icloud.fill"
    }

    private var syncDescription: String {
        if profileData.isSyncing { return "Syncing…" }
        if let problem = profileData.problem ?? profiles.syncProblem { return problem }
        guard let date = profileData.lastSyncedAt else { return "Syncs when something changes" }
        return "Synced \(date.formatted(.relative(presentation: .named)))"
    }

    // MARK: Pieces

    private func card<Content: View>(
        title: String,
        detail: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.title3.weight(.semibold))
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
    }

    private var confirmationPresentation: Binding<Bool> {
        Binding(
            get: { confirmation.pending != nil },
            set: { isPresented in
                if !isPresented { confirmation.cancel() }
            }
        )
    }
}
