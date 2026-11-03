//
//  OmniaApp.swift
//  Omnia
//
//  Created by Dafa Raihan on 28/07/26.
//

import Network
import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct OmniaApp: App {
    @State private var store: OmniaStore
    @State private var account: OmniaAccount
    @State private var metadata = LiveMetadataStore()
    @State private var playback: PlaybackSession
    @State private var settings: SettingsPreferencesStore
    @State private var addonCatalogs: AddonCatalogStore
    @State private var homeLayout: HomeLayoutStore
    @State private var collections: CollectionsStore
    @State private var plugins: PluginStore
    @State private var profiles: ProfileStore
    @State private var profileData: ProfileDataSync
    @State private var credentialVault: CredentialVaultSync
    @State private var isPrepared = false
    @State private var dismissedSignedOutNotice = false
    @State private var showsSignIn = false
    @State private var pendingAddonInstall: URL?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let addonCatalogs = AddonCatalogStore()
        _addonCatalogs = State(initialValue: addonCatalogs)
        let playback = PlaybackSession()
        _playback = State(initialValue: playback)
        let store = OmniaStore()
        let account = OmniaAccount()
        let settings = SettingsPreferencesStore()
        let homeLayout = HomeLayoutStore()
        let collections = CollectionsStore()
        let plugins = PluginStore()
        let profiles = ProfileStore()
        let credentialVault = CredentialVaultSync(account: account, profiles: profiles)
        let profileData = ProfileDataSync(
            store: store, settings: settings, homeLayout: homeLayout, collections: collections,
            plugins: plugins, profiles: profiles, account: account
        )
        if account.hasSavedSession {
            UserDefaults.standard.set(true, forKey: OnboardingView.completedKey)
        }
        account.willChangeIdentity = { [weak credentialVault, weak profileData] next in
            profileData?.invalidateSession()
            try credentialVault?.prepareIdentityChange(to: next)
        }
        account.didRecoverIdentity = { [weak credentialVault] in
            await credentialVault?.identityChanged()
        }
        account.willSignOut = { [weak profileData, weak profiles, weak account, weak credentialVault] in
            guard let profileData, let profiles, let account else { throw CancellationError() }
            await profiles.sync(with: account)
            guard profiles.syncProblem == nil else { throw CancellationError() }
            try await profileData.flushForSignOut()
            await credentialVault?.sync()
        }
        account.didSignOut = { [weak profileData, weak profiles, weak store] in
            guard let profileData, let profiles, let store else { throw CancellationError() }
            playback.stop(persisting: false)
            addonCatalogs.resetAfterSignOut()
            try PlaybackResolverCredentialStore.deleteAuthorizationToken()
            try profiles.resetAfterSignOut()
            await profileData.resetAfterSignOut()
            try await store.resetLibraryAfterSignOut()
            SearchHistoryStore.shared.clear()
            ContinueWatchingSceneStore.shared.removeAll()
            PlaybackFailureLog.shared.removeAll()
            StreamLinkCacheStore().removeAll()
            SearchHistoryStore.shared.isEnabled = true
            EpisodeShuffleStore.shared.resetAfterSignOut()
            for key in [
                HomeView.continueWatchingVisibilityKey, HomeShelfPreferences.storageKey,
                "library-sort", "playback-completion-threshold", "subtitle-delay-by-title",
                "subtitle-delay-by-title-order", StreamLinkCacheStore.storageKey,
                "binge-group-cache-v1", LocalResolverSettingsStore.storageKey,
                PlaybackResolverSettings.endpointKey, PlaybackResolverSettings.approvedAddonIDsKey,
                PlaybackResolverSettings.approvedStreamHostsKey
            ] { UserDefaults.standard.removeObject(forKey: key) }
            UserDefaults.standard.set(false, forKey: OnboardingView.completedKey)
        }
        _credentialVault = State(initialValue: credentialVault)
        _store = State(initialValue: store)
        _account = State(initialValue: account)
        _settings = State(initialValue: settings)
        _homeLayout = State(initialValue: homeLayout)
        _collections = State(initialValue: collections)
        _plugins = State(initialValue: plugins)
        _profiles = State(initialValue: profiles)
        _profileData = State(initialValue: profileData)
        #if os(macOS)
        UniformScrollers.install()
        #endif
        // Artwork downloads go through the shared cache. The default is small
        // enough that artwork downloaded again on every launch; this keeps
        // it on disk between sessions. Decoded images are kept by
        // RemoteArtworkCache, so the in-memory copy of the raw bytes is small.
        URLCache.shared = URLCache(
            memoryCapacity: 16 * 1_024 * 1_024,
            diskCapacity: 1_024 * 1_024 * 1_024
        )
        // Many ISPs (Indonesia's included) block streaming sites by answering
        // their DNS lookups falsely, which breaks plugins and add-ons with
        // "hostname not found" or TLS errors. Lookups go over encrypted DNS
        // (Cloudflare) unless the system already uses an encrypted resolver.
        // This covers URLSession and getaddrinfo for the whole app.
        if let resolver = URL(string: "https://cloudflare-dns.com/dns-query") {
            NWParameters.PrivacyContext.default.requireEncryptedNameResolution(
                true,
                fallbackResolver: .https(resolver, serverAddresses: [
                    .hostPort(host: "1.1.1.1", port: 443),
                    .hostPort(host: "1.0.0.1", port: 443),
                    .hostPort(host: "2606:4700:4700::1111", port: 443)
                ])
            )
        }
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            rootContent
        }
        // WindowChrome keeps the titlebar transparent and extends content
        // beneath it. Retaining the standard window style lets SwiftUI render
        // navigation titles as native toolbar titles instead of custom pills.
        .windowToolbarStyle(.unified(showsTitle: true))
        // Opens filling the screen (not full screen), every launch, rather
        // than the small default or a size macOS remembered.
        .defaultWindowPlacement { _, context in
            WindowPlacement(size: context.defaultDisplay.visibleRect.size)
        }
        .restorationBehavior(.disabled)
        .commands {
            OmniaCommands(playback: playback, profiles: profiles)
        }
        #else
        WindowGroup {
            rootContent
        }
        #endif
    }

    private var rootContent: some View {
        OmniaRootView()
            .id(account.sessionGeneration)
            .environment(store)
            .environment(account)
            .environment(metadata)
            .environment(playback)
            .environment(settings)
            .environment(addonCatalogs)
            .environment(homeLayout)
            .environment(collections)
            .environment(plugins)
            .environment(profiles)
            .environment(profileData)
            .environment(credentialVault)
            .environment(\.showsMediaCardLabels, settings.preferences.showMediaCardLabels)
            .environment(\.displayPreferences, settings.preferences.display)
            .alert("You've Been Signed Out", isPresented: Binding(
                get: { isPrepared && credentialVault.sessionEnded && !dismissedSignedOutNotice && !showsSignIn },
                set: { if !$0 { dismissedSignedOutNotice = true } }
            )) {
                Button("Sign In") { showsSignIn = true }
                Button("Not Now", role: .cancel) { dismissedSignedOutNotice = true }
            } message: {
                Text("Your profiles, settings and credentials are still on this \(OmniaDevice.name), but they aren't syncing. Sign in again to pick up where you left off.")
            }
            .sheet(isPresented: $showsSignIn) {
                AccountSignInSheet { showsSignIn = false }
            }
            .alert("Install This Add-on?", isPresented: Binding(
                get: { pendingAddonInstall != nil },
                set: { if !$0 { pendingAddonInstall = nil } }
            ), presenting: pendingAddonInstall) { url in
                Button("Install") {
                    pendingAddonInstall = nil
                    Task { try? await store.installAddon(manifestURL: url) }
                }
                Button("Cancel", role: .cancel) { pendingAddonInstall = nil }
            } message: { url in
                Text("A link asked Omnia to install an add-on from \(url.host() ?? "an unknown address"). Only continue if you trust it: add-ons see what you browse and supply what you play.")
            }
            .task {
                guard !isPrepared else { return }
                if account.localResetPending {
                    playback.stop(persisting: false)
                    await account.finishLocalSignOut()
                    guard !account.localResetPending else { return }
                }
                await store.prepareInstalledAddons()
                if !profiles.profiles.isEmpty {
                    Task {
                        await store.installDefaultAddonsIfNeeded()
                        await store.refreshInstalledManifests()
                    }
                }
                profiles.account = account
                await store.prepareLocalMedia()
                await useActiveProfileLibrary()
                await profileData.activate()
                await account.restoreSession()
                isPrepared = true
                TrackerAccountStore.shared.refreshUsernamesIfStale()
                metadata.configure(metadataRouting: store.metadataRouting)
                await metadata.loadDefaultCatalogs()
            }
            // Each profile keeps its own library, progress, settings,
            // add-ons and plugins; its sharing switches can change too.
            .onChange(of: account.localResetPending) { _, pending in
                if pending { playback.stop(persisting: false) }
            }
            .onChange(of: profiles.activeProfile) { _, _ in
                Task {
                    await useActiveProfileLibrary()
                    await profileData.activate()
                    if account.user == nil, !profiles.profiles.isEmpty {
                        await store.installDefaultAddonsIfNeeded()
                    }
                }
            }
            .task(id: "\(isPrepared)-\(account.user?.id.uuidString ?? "guest")") {
                guard isPrepared else { return }
                guard !account.localResetPending else { return }
                let userID = account.user?.id
                if userID != nil { await profiles.sync(with: account) }
                guard !Task.isCancelled, account.user?.id == userID else { return }
                await credentialVault.identityChanged()
                guard !Task.isCancelled, account.user?.id == userID else { return }
                if userID != nil { await profileData.sync() }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, isPrepared else { return }
                TrackerAccountStore.shared.refreshUsernamesIfStale()
                Task { await credentialVault.sync() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .credentialVaultDidChange)) { _ in
                credentialVault.localChanged()
            }
            .modifier(ProfileDataChanges(
                store: store, settings: settings, homeLayout: homeLayout,
                collections: collections, plugins: plugins, profileData: profileData
            ))
            .onChange(of: store.metadataRouting) { _, routing in
                metadata.configure(metadataRouting: routing)
                Task { await metadata.loadDefaultCatalogs() }
            }
            .onChange(of: settings.preferences.integrations.anime, initial: true) { _, enrichment in
                metadata.animeEnrichment = enrichment
            }
            .onOpenURL { url in
                if TrackerAccountStore.shared.handleCallback(url) {
                    // AniList's sign-in returning to omnia://anilist.
                } else if let manifestURL = AddonInstallCallback.manifestURL(from: url) {
                    // Any web page can open this link, and an add-on sees what you
                    // browse and supplies what plays, so it needs a person's yes.
                    pendingAddonInstall = manifestURL
                } else {
                    account.handle(callback: url)
                }
            }
            #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                playback.flushProgress()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                Task { await metadata.refreshCatalogsIfStale() }
                Task { await credentialVault.sync(); await profileData.sync() }
                addonCatalogs.refreshIfStale()
            }
            #endif
    }

    private func useActiveProfileLibrary() async {
        guard let active = profiles.activeProfile else { return }
        await store.useLibrary(for: active.id, ownsDefaultLibrary: active.id == profiles.defaultLibraryOwnerID)
    }
}

#if os(macOS)
@MainActor
private struct OmniaCommands: Commands {
    @FocusedBinding(\.appDestination) private var appDestination
    let playback: PlaybackSession
    let profiles: ProfileStore

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                appDestination = .settings
            }
            .keyboardShortcut(",", modifiers: .command)
            .disabled(appDestination == nil)
        }

        CommandGroup(after: .appSettings) {
            Button("Switch Profile…") {
                ProfileSwitchCenter.shared.openPicker(using: profiles)
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(playback.isPresentingPlayer)
        }

        CommandGroup(after: .windowArrangement) {
            Button("Toggle Player Full Screen") {
                playback.toggleFullScreen()
            }
            .keyboardShortcut("f", modifiers: [])
            .disabled(!playback.isPresentingPlayer)
        }
    }
}
#endif

/// Tells profile sync whenever a store that belongs to a profile changes.
private struct ProfileDataChanges: ViewModifier {
    let store: OmniaStore
    let settings: SettingsPreferencesStore
    let homeLayout: HomeLayoutStore
    let collections: CollectionsStore
    let plugins: PluginStore
    let profileData: ProfileDataSync

    func body(content: Content) -> some View {
        content
            .onChange(of: settings.preferences) { _, _ in profileData.localChange(.settings) }
            .onChange(of: store.appearance) { _, _ in profileData.localChange(.settings) }
            .onChange(of: store.metadataRouting) { _, _ in profileData.localChange(.settings) }
            .onChange(of: homeLayout.preferences) { _, _ in profileData.localChange(.homeLayout) }
            .onChange(of: collections.revision) { _, _ in profileData.localChange(.collections) }
            .onChange(of: store.installedAddons) { _, _ in profileData.localChange(.addons) }
            .onChange(of: store.disabledAddonCatalogIDs) { _, _ in profileData.localChange(.addons) }
            .onChange(of: plugins.revision) { _, _ in profileData.localChange(.plugins) }
            .onChange(of: store.libraryRevision) { _, _ in profileData.localChange(.library) }
    }
}

private enum AddonInstallCallback {
    static func manifestURL(from url: URL) -> URL? {
        guard url.scheme?.lowercased() == "omnia", url.host == "addon-install",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = components.queryItems?.first(where: { $0.name == "manifest" })?.value
        else { return nil }
        return AddonManifestAddress.manifestURL(from: value)
    }
}
