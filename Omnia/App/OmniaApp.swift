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
    @State private var store = OmniaStore()
    @State private var account = OmniaAccount()
    @State private var metadata = LiveMetadataStore()
    @State private var playback = PlaybackSession()
    @State private var settings = SettingsPreferencesStore()
    @State private var addonCatalogs = AddonCatalogStore()
    @State private var homeLayout = HomeLayoutStore()
    @State private var collections = CollectionsStore()
    @State private var plugins = PluginStore()

    init() {
        #if os(macOS)
        UniformScrollers.install()
        #endif
        // Posters and backdrops load through AsyncImage, which uses the
        // shared cache. The default is small enough that artwork downloaded
        // again on every launch; this keeps it on disk between sessions.
        URLCache.shared = URLCache(
            memoryCapacity: 64 * 1_024 * 1_024,
            diskCapacity: 512 * 1_024 * 1_024
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
        .commands {
            OmniaCommands(playback: playback)
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
            .environment(\.showsMediaCardLabels, settings.preferences.showMediaCardLabels)
            .environment(\.displayPreferences, settings.preferences.display)
            .task {
                await store.prepareInstalledAddons()
                Task { await store.refreshInstalledManifests() }
                await store.prepareLocalMedia()
                await account.restoreSession()
                metadata.configure(metadataRouting: store.metadataRouting)
                await metadata.loadDefaultCatalogs()
            }
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
                addonCatalogs.refreshIfStale()
            }
            #endif
    }
}

#if os(macOS)
@MainActor
private struct OmniaCommands: Commands {
    @FocusedBinding(\.appDestination) private var appDestination
    let playback: PlaybackSession

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                appDestination = .settings
            }
            .keyboardShortcut(",", modifiers: .command)
            .disabled(appDestination == nil)
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

private enum AddonInstallCallback {
    static func manifestURL(from url: URL) -> URL? {
        guard url.scheme?.lowercased() == "omnia", url.host == "addon-install",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = components.queryItems?.first(where: { $0.name == "manifest" })?.value
        else { return nil }
        return AddonManifestAddress.manifestURL(from: value)
    }
}
