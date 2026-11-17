import Foundation
import UserNotifications
import CubbyCore

/// Deadline reminders and the weekly digest, all as local notifications.
///
/// Reminders are scheduled the moment a deadline is known, so they fire on time without the app
/// running. The digest's wording is computed whenever the app is in the foreground or refreshed.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private static let deadlineCategory = "CUBBY_DEADLINE"
    private static let doneAction = "CUBBY_DONE"
    private static let digestIdentifier = "cubby-weekly-digest"
    /// Day-only deadlines remind at this hour.
    private static let dayReminderHour = 9

    private let center = UNUserNotificationCenter.current()

    /// Called when the user taps "Mark Done" on a reminder.
    var onMarkDone: ((UUID) -> Void)?
    /// Called when the user opens a notification. The string is a `cubby://` host such as "todos".
    var onOpen: ((String) -> Void)?

    /// Call once at launch, before the app finishes launching.
    func configure() {
        center.delegate = self
        let done = UNNotificationAction(identifier: Self.doneAction, title: "Mark Done", options: [])
        let category = UNNotificationCategory(identifier: Self.deadlineCategory, actions: [done], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Asks for permission the first time a reminder is actually needed, never before.
    private func ensureAuthorized() async -> Bool {
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return await requestAuthorization()
        default:
            return false
        }
    }

    // MARK: - Deadlines

    /// Replaces the reminder for one entry. Takes plain values, not the entry, because the entry
    /// can be deleted while this waits.
    func syncDeadline(id: UUID, title: String, deadline: Date?, hasTime: Bool, isOpenTodo: Bool) async {
        let identifier = Self.identifier(for: id)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        guard isOpenTodo, let deadline else { return }
        let fireDate = Self.fireDate(for: deadline, hasTime: hasTime)
        guard fireDate > Date() else { return }
        guard await ensureAuthorized() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = hasTime ? "It's time." : "Due today."
        content.sound = .default
        content.categoryIdentifier = Self.deadlineCategory
        content.userInfo = ["entryID": id.uuidString, "open": "todos"]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    func cancelDeadline(id: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier(for: id)])
    }

    private static func identifier(for id: UUID) -> String {
        "cubby-deadline-" + id.uuidString
    }

    private static func fireDate(for deadline: Date, hasTime: Bool) -> Date {
        if hasTime { return deadline }
        return Calendar.current.date(bySettingHour: dayReminderHour, minute: 0, second: 0, of: deadline) ?? deadline
    }

    // MARK: - Weekly digest

    /// Replaces the repeating weekly digest. It never prompts for permission on its own.
    func syncDigest(_ digest: DigestComposer.Digest?, enabled: Bool, weekday: Int, hour: Int) async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.digestIdentifier])
        guard enabled, let digest else { return }
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = digest.title
        content.body = digest.body
        content.sound = .default
        content.userInfo = ["open": "todos"]

        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: Self.digestIdentifier, content: content, trigger: trigger))
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        let entryID = (userInfo["entryID"] as? String).flatMap { UUID(uuidString: $0) }
        let destination = userInfo["open"] as? String

        Task { @MainActor in
            if action == Self.doneAction {
                if let entryID { self.onMarkDone?(entryID) }
            } else if action == UNNotificationDefaultActionIdentifier, let destination {
                self.onOpen?(destination)
            }
            completionHandler()
        }
    }
}
