import Foundation
import Observation

/// Which screen is showing, and requests that cross screens (deep links, notifications, search).
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    enum Screen: Equatable {
        case capture
        case timeline
    }

    var screen: Screen
    var filter: EntryFilter = .all
    /// Bumped to ask whichever composer is on screen to take the keyboard.
    var focusRequest = 0
    /// Set to scroll the timeline to one entry, for example from search.
    var scrollTarget: UUID?

    private init() {
        AppSettings.registerDefaults()
        screen = AppSettings.startScreen == .capture ? .capture : .timeline
    }

    /// Back to whatever the user chose to open to, ready to type.
    func resetToStart() {
        screen = AppSettings.startScreen == .capture ? .capture : .timeline
        filter = .all
        focusRequest += 1
    }

    func showTimeline(filter: EntryFilter = .all) {
        self.filter = filter
        screen = .timeline
    }

    /// Handles `cubby://compose`, `cubby://todos` and `cubby://timeline`.
    func handle(url: URL) {
        guard url.scheme?.lowercased() == "cubby" else { return }
        switch url.host?.lowercased() {
        case "compose":
            resetToStart()
        case "todos":
            showTimeline(filter: .todos)
        case "timeline":
            showTimeline()
        default:
            break
        }
    }
}
