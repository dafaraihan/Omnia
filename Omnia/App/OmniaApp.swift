//
//  OmniaApp.swift
//  Omnia
//
//  Created by Dafa Raihan on 28/07/26.
//

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
            .environment(\.showsMediaCardLabels, settings.preferences.showMediaCardLabels)
            .task {
                await store.prepareInstalledAddons()
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
              let value = components.queryItems?.first(where: { $0.name == "manifest" })?.value,
              let manifestURL = URL(string: value), manifestURL.scheme?.lowercased() == "https", manifestURL.host != nil
        else { return nil }
        return manifestURL
    }
}
