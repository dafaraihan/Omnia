import Foundation

struct SubtitleCue: Codable, Equatable, Sendable {
    let startSeconds: Double
    let endSeconds: Double
    let text: String
}
