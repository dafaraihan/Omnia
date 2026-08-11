//
//  OmniaApp.swift
//  Omnia
//
//  Created by Dafa Raihan on 28/07/26.
//

import SwiftUI

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
        // Apple documents hiddenTitleBar as hiding both the title and the
        // backing material of the titlebar. This lets hero artwork own the
        // top edge while keeping the native traffic-light and toolbar
        // controls available above the content.
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
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
            .task {
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
