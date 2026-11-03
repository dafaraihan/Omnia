import Foundation
import UserNotifications

/// Local reminders for upcoming episodes, so they need no server or push
/// entitlement. Rebuilt from the latest air dates each time Home loads them.
enum EpisodeNotifications {
    private static let prefix = "episode-"
    /// iOS keeps at most 64 pending notifications per app.
    private static let limit = 50

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) == true
    }

    static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
    }

    /// Air dates have no time, so the reminder comes at 9:00 on the day.
    static func schedule(_ episodes: [UpcomingEpisode], now: Date = .now, calendar: Calendar = .current) async {
        await cancelAll()
        guard await isAuthorized() else { return }
        let center = UNUserNotificationCenter.current()
        for episode in episodes.sorted(by: { $0.airDate < $1.airDate }).prefix(limit) {
            var components = calendar.dateComponents([.year, .month, .day], from: episode.airDate)
            components.hour = 9
            guard let fireDate = calendar.date(from: components), fireDate > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = episode.series.title
            content.body = "Season \(episode.episode.seasonNumber), episode \(episode.episode.episodeNumber) is out today: \(episode.episode.title)"
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: prefix + episode.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }
}
