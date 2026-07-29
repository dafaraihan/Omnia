//
//  NativePlayerView.swift
//  Omnia
//

import AVFoundation
import AVKit
import SwiftUI

/// Presents AVPlayer using the appropriate system player for each platform.
/// This keeps AirPlay and Picture in Picture behavior native rather than
/// recreating transport controls in SwiftUI.
struct NativePlayerView: View {
    let player: AVPlayer
    @AppStorage("picture-in-picture") private var allowsPictureInPicture = true

    var body: some View {
        #if os(iOS)
        NativePlayerController(player: player, allowsPictureInPicture: allowsPictureInPicture)
        #elseif os(macOS)
        NativePlayerHost(player: player)
        #endif
    }
}

#if os(iOS)
private struct NativePlayerController: UIViewControllerRepresentable {
    let player: AVPlayer
    let allowsPictureInPicture: Bool

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = allowsPictureInPicture
        controller.canStartPictureInPictureAutomaticallyFromInline = allowsPictureInPicture
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
        controller.allowsPictureInPicturePlayback = allowsPictureInPicture
        controller.canStartPictureInPictureAutomaticallyFromInline = allowsPictureInPicture
    }
}
#elseif os(macOS)
private struct NativePlayerHost: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}
#endif
