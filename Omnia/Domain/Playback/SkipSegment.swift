import Foundation

struct SkipSegment: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case intro
        case recap
        case outro
    }

    let kind: Kind
    let startSeconds: Double
    let endSeconds: Double
    let confidence: Double?
}

struct IntroSegmentKey: Codable, Hashable, Sendable {
    let imdbID: String
    let season: Int
    let episode: Int
}
