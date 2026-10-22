//
//  ContinueWatchingSceneStore.swift
//  Omnia
//

import CryptoKit
import Foundation
import Observation
#if os(macOS)
import AppKit
#endif

/// Settings › Layout › Continue Watching › Artwork › Paused Scene: the frame
/// each title was stopped on, kept as a JPEG on this device. The player saves
/// one when it closes; Continue Watching cards read it back by title ID.
@MainActor
@Observable
final class ContinueWatchingSceneStore {
    static let shared = ContinueWatchingSceneStore()

    /// The newest scene for each title, by the hash of its ID.
    private var scenes: [String: URL] = [:]
    private let directory = URL.applicationSupportDirectory
        .appending(path: "Omnia/Continue Watching Scenes", directoryHint: .isDirectory)

    private init() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        // Names are "<hash>-<time>.jpg"; the newest wins and older ones go.
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let key = file.lastPathComponent.split(separator: "-").first.map(String.init) else { continue }
            if let older = scenes[key] { try? FileManager.default.removeItem(at: older) }
            scenes[key] = file
        }
    }

    func sceneURL(for mediaID: String) -> URL? {
        scenes[Self.key(for: mediaID)]
    }

    /// Asks `write` to save the current frame to a new file, then makes it
    /// this title's scene. A new name each time, so cards don't show an image
    /// cached under the old one.
    @discardableResult
    func capture(for mediaID: String, write: (URL) -> Bool) -> Bool {
        let file = newFile(for: mediaID)
        guard write(file), FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return false }
        adopt(file, for: mediaID)
        return true
    }

    #if os(macOS)
    /// When the player can't save the frame on screen, a separate decoder
    /// opens the same stream and grabs the frame at `position`. It runs after
    /// the player has closed, so the card updates a moment later.
    func generate(for mediaID: String, source: PlaybackSource, at position: Double) async {
        let generator = MPVLocalFrameGenerator(maximumSize: NSSize(width: 960, height: 540))
        let frame = try? await generator.image(at: position, source: source)
        await generator.stop()
        guard let image = frame?.image,
              let tiff = image.tiffRepresentation,
              let jpeg = NSBitmapImageRep(data: tiff)?.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        else { return }
        let file = newFile(for: mediaID)
        guard (try? jpeg.write(to: file, options: .atomic)) != nil else { return }
        adopt(file, for: mediaID)
    }
    #endif

    private func newFile(for mediaID: String) -> URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = Int(Date.now.timeIntervalSince1970 * 1_000)
        return directory.appending(path: "\(Self.key(for: mediaID))-\(stamp).jpg", directoryHint: .notDirectory)
    }

    private func adopt(_ file: URL, for mediaID: String) {
        let key = Self.key(for: mediaID)
        if let older = scenes[key], older != file { try? FileManager.default.removeItem(at: older) }
        scenes[key] = file
    }

    private static func key(for mediaID: String) -> String {
        SHA256.hash(data: Data(mediaID.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
