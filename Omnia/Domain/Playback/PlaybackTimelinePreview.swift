import Foundation

nonisolated struct PlaybackStoryboardCrop: Hashable, Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

nonisolated struct PlaybackStoryboardTile: Hashable, Sendable {
    let startTime: Double
    let endTime: Double
    let imageURL: URL
    let crop: PlaybackStoryboardCrop?

    func contains(_ timestamp: Double) -> Bool {
        startTime <= timestamp && timestamp < endTime
    }
}

nonisolated struct PlaybackStoryboardDescriptor: Hashable, Sendable {
    let allowedOriginURL: URL
    let tiles: [PlaybackStoryboardTile]
}

nonisolated enum PlaybackTimelinePreviewDescriptor: Hashable, Sendable {
    case storyboard(PlaybackStoryboardDescriptor)
}

nonisolated struct PlaybackTimelinePreviewConfiguration: Equatable, Sendable {
    static let maximumBytes = 8 * 1_024 * 1_024

    let debounce: Duration
    let maximumFrameCount: Int
    let maximumBytes: Int

    init(isLowPowerModeEnabled: Bool) {
        debounce = isLowPowerModeEnabled ? .milliseconds(500) : .milliseconds(250)
        maximumFrameCount = isLowPowerModeEnabled ? 8 : 24
        maximumBytes = Self.maximumBytes
    }
}

nonisolated struct PlaybackTimelinePreviewCache<Key: Hashable, Value> {
    private struct Entry {
        let value: Value
        let byteCount: Int
        var access: UInt64
    }

    private let maximumCount: Int
    private let maximumBytes: Int
    private var entries: [Key: Entry] = [:]
    private var access: UInt64 = 0
    private var byteCount = 0

    init(maximumCount: Int, maximumBytes: Int) {
        self.maximumCount = max(maximumCount, 1)
        self.maximumBytes = max(maximumBytes, 1)
    }

    mutating func value(for key: Key) -> Value? {
        guard var entry = entries[key] else { return nil }
        access &+= 1
        entry.access = access
        entries[key] = entry
        return entry.value
    }

    mutating func insert(_ value: Value, for key: Key, byteCount: Int) {
        guard byteCount > 0, byteCount <= maximumBytes else { return }
        if let old = entries.removeValue(forKey: key) {
            self.byteCount -= old.byteCount
        }
        access &+= 1
        entries[key] = Entry(value: value, byteCount: byteCount, access: access)
        self.byteCount += byteCount
        while entries.count > maximumCount || self.byteCount > maximumBytes {
            guard let oldest = entries.min(by: { $0.value.access < $1.value.access }) else { break }
            self.byteCount -= oldest.value.byteCount
            entries.removeValue(forKey: oldest.key)
        }
    }

    mutating func removeAll() {
        entries.removeAll(keepingCapacity: false)
        byteCount = 0
    }
}
