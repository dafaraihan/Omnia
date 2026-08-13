import Foundation

@main
struct LocalTorrentDescriptorSmoke {
    static func main() throws {
        let descriptor = try LocalTorrentPlaybackDescriptor(
            infoHash: String(repeating: "A", count: 64),
            fileIndex: 100_000,
            displayName: "Movie.mkv",
            expectedByteCount: nil,
            sources: [
                "tracker:https://tracker.example/announce",
                "tracker:udp://tracker.example:6969/announce",
                "tracker:http://insecure.example/announce",
                "tracker:https://user:password@tracker.example/private",
                "tracker:https://tracker.example/fragment#unsafe",
                "tracker:https://tracker.example/announce",
            ]
        )

        precondition(descriptor.infoHash == String(repeating: "a", count: 64))
        precondition(descriptor.trackers.map(\.absoluteString) == [
            "https://tracker.example/announce",
            "udp://tracker.example:6969/announce",
        ])
        precondition(descriptor.magnetURL.absoluteString.contains("tr=https://tracker.example/announce"))

        precondition(throwsError {
            _ = try LocalTorrentPlaybackDescriptor(
                infoHash: String(repeating: "a", count: 40),
                fileIndex: 100_001,
                displayName: "Movie",
                expectedByteCount: nil
            )
        })
        precondition(throwsError {
            _ = try LocalTorrentPlaybackDescriptor(
                infoHash: String(repeating: "a", count: 40),
                fileIndex: nil,
                displayName: String(repeating: "é", count: 257),
                expectedByteCount: nil
            )
        })
    }

    private static func throwsError(_ body: () throws -> Void) -> Bool {
        do {
            try body()
            return false
        } catch {
            return true
        }
    }
}
