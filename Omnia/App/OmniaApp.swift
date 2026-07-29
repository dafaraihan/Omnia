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
            .task {
                await account.restoreSession()
                await metadata.loadDefaultCatalogs()
            }
            .onOpenURL { account.handle(callback: $0) }
    }
}
