import Foundation

/// Short labels for deadline chips: "Today 3:00 PM", "Tomorrow", "Thu 3:00 PM", "Mar 1".
public enum DeadlineLabel {
    public static func text(
        for date: Date,
        hasTime: Bool,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let today = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: date)
        let dayOffset = calendar.dateComponents([.day], from: today, to: target).day ?? 0

        let day: String
        switch dayOffset {
        case 0:
            day = "Today"
        case 1:
            day = "Tomorrow"
        case -1:
            day = "Yesterday"
        case 2...6:
            day = format(date, template: "EEE", calendar: calendar, locale: locale)
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            day = format(date, template: sameYear ? "MMMd" : "yMMMd", calendar: calendar, locale: locale)
        }

        guard hasTime else { return day }
        return day + " " + format(date, template: "jmm", calendar: calendar, locale: locale)
    }

    /// True when the deadline has passed: the moment itself, or the whole day if no time was given.
    public static func isOverdue(_ date: Date, hasTime: Bool, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        if hasTime { return date < now }
        return calendar.startOfDay(for: date) < calendar.startOfDay(for: now)
    }

    private static func format(_ date: Date, template: String, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}
