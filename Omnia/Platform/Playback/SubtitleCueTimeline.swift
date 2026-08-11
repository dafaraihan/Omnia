import Foundation

struct SubtitleCueTimeline: Sendable {
    private let orderedCues: [SubtitleCue]

    init(cues: [SubtitleCue]) {
        orderedCues = cues.sorted {
            $0.startSeconds == $1.startSeconds ? $0.endSeconds < $1.endSeconds : $0.startSeconds < $1.startSeconds
        }
    }

    func cues(at position: Double) -> [SubtitleCue] {
        guard position.isFinite else { return [] }
        return orderedCues.filter { $0.startSeconds <= position && position < $0.endSeconds }
    }
}
