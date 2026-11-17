import BackgroundTasks
import Foundation

/// Best-effort background refresh. iOS decides if and when this runs, so nothing time-critical
/// depends on it: reminders are scheduled as local notifications at capture time instead.
enum BackgroundRefresh {
    /// Must match `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
    static var identifier: String {
        (Bundle.main.bundleIdentifier ?? "cubby") + ".refresh"
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
