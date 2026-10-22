import Foundation

/// A fixed Full HD preview. An HLS source carries an in-memory master with
/// only its 1920×1080 variant and the original audio renditions.
nonisolated struct HeroTrailerSource: Hashable, Sendable {
    let url: URL
    var playlist: Data? = nil
}
