import Foundation

nonisolated protocol ClockProviding: Sendable {
    var now: Date { get }
}

nonisolated struct SystemDateClock: ClockProviding {
    var now: Date { .now }
}
