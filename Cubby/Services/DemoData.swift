import Foundation

/// Sample entries for screenshots, demos and trying the app in the simulator.
///
/// Launch with the argument `-cubbyDemo` (Xcode: Product › Scheme › Edit Scheme › Run › Arguments).
/// Demo mode uses an in-memory store, so nothing real is touched and nothing is kept.
/// Other launch arguments that help: `-startScreen timeline`, `-appearance dark`.
enum DemoData {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-cubbyDemo")
    }

    @MainActor
    static func seed(into model: CubbyModel) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        func at(daysAgo: Int, _ hour: Int, _ minute: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        let samples: [(String, Date)] = [
            ("renew passport before March", at(daysAgo: 1, 14, 15)),
            ("book: The Overstory (Dana says read it)", at(daysAgo: 1, 16, 3)),
            ("https://www.apple.com/newsroom/", at(daysAgo: 1, 18, 40)),
            ("podcast idea: ask people about the one note they never deleted", at(daysAgo: 0, 8, 2)),
            ("dentist thurs 3pm, ask about retainer", at(daysAgo: 0, 8, 47)),
            ("gift for Sam: the ceramic pour-over set", at(daysAgo: 0, 9, 12)),
            ("milk, eggs, call mom", at(daysAgo: 0, 9, 30)),
        ]
        for (text, date) in samples {
            model.capture(text, source: .app, createdAt: date)
        }
        if let done = model.capture("email landlord about the lease", source: .app, createdAt: at(daysAgo: 2, 10, 5)) {
            model.toggleDone(done)
        }
    }
}
