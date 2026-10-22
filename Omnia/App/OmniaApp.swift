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
    @State private var playback = PlaybackSession()
    @State private var settings: SettingsPreferencesStore
    @State private var addonCatalogs = AddonCatalogStore()
    @State private var homeLayout: HomeLayoutStore
    @State private var collections: CollectionsStore
    @State private var plugins: PluginStore
    @State private var profiles: ProfileStore
    @State private var profileData: ProfileDataSync

    init() {
        let store = OmniaStore()
        let account = OmniaAccount()
        let settings = SettingsPreferencesStore()
        let homeLayout = HomeLayoutStore()
        let collections = CollectionsStore()
        let plugins = PluginStore()
        let profiles = ProfileStore()
        _store = State(initialValue: store)
        _account = State(initialValue: account)
        _settings = State(initialValue: settings)
        _homeLayout = State(initialValue: homeLayout)
        _collections = State(initialValue: collections)
        _plugins = State(initialValue: plugins)
        _profiles = State(initialValue: profiles)
        _profileData = State(initialValue: ProfileDataSync(
            store: store, settings: settings, homeLayout: homeLayout, collections: collections,
            plugins: plugins, profiles: profiles, account: account
        ))
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
            .environment(\.showsMediaCardLabels, settings.preferences.showMediaCardLabels)
            .environment(\.displayPreferences, settings.preferences.display)
            .task {
                await store.prepareInstalledAddons()
                Task {
                    await store.installDefaultAddonsIfNeeded()
                    await store.refreshInstalledManifests()
                }
                profiles.account = account
                await store.prepareLocalMedia()
                await useActiveProfileLibrary()
                await profileData.activate()
                await account.restoreSession()
                if account.user != nil {
                    await profiles.sync(with: account)
                    await profileData.sync()
                }
                metadata.configure(metadataRouting: store.metadataRouting)
                await metadata.loadDefaultCatalogs()
            }
            // Each profile keeps its own library, progress, settings,
            // add-ons and plugins; its sharing switches can change too.
            .onChange(of: profiles.activeProfile) { _, _ in
                Task {
                    await useActiveProfileLibrary()
                    await profileData.activate()
                }
            }
            .onChange(of: account.user?.id) { _, id in
                guard id != nil else { return }
                Task {
                    await profiles.sync(with: account)
                    await profileData.sync()
                }
            }
            .modifier(ProfileDataChanges(
                store: store, settings: settings, homeLayout: homeLayout,
                collections: collections, plugins: plugins, profileData: profileData
            ))
            .onChange(of: store.metadataRouting) { _, routing in
                metadata.configure(metadataRouting: routing)
                Task { await metadata.loadDefaultCatalogs() }
            }
            .onOpenURL { url in
                if let manifestURL = AddonInstallCallback.manifestURL(from: url) {
                    Task { try? await store.installAddon(manifestURL: manifestURL) }
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
                Task { await profileData.sync() }
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
