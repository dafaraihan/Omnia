import Foundation

nonisolated struct SkipSegment: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case intro
        case recap
        case outro
        /// IntroDB's outro for a movie.
        case movieCredits = "movie-credits"
        /// A scene after the credits; never skipped, only skipped to.
        case postCredits = "post-credits"

        var skipTitle: String {
            switch self {
            case .intro: "Skip Intro"
            case .recap: "Skip Recap"
            case .outro: "Skip Outro"
            case .movieCredits: "Skip Credits"
            case .postCredits: "Skip"
            }
        }

        var settingsTitle: String {
            switch self {
            case .intro: "Intro"
            case .recap: "Recap"
            case .outro: "Outro"
            case .movieCredits: "Movie Credits"
            case .postCredits: "Post-Credits Scene"
            }
        }

        var isEnding: Bool { self == .outro || self == .movieCredits }
    }

    let kind: Kind
    let startSeconds: Double
    let endSeconds: Double
    let confidence: Double?
}
