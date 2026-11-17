import Foundation

/// A date (and optionally a clock time) found in a note.
public struct ParsedDeadline: Equatable, Sendable {
    public var date: Date
    /// False when only a day was given ("thurs"); `date` is then the start of that day.
    public var hasTime: Bool

    public init(date: Date, hasTime: Bool) {
        self.date = date
        self.hasTime = hasTime
    }
}

/// Finds the date a terse self-note refers to ("dentist thurs 3pm", "renew passport before March").
///
/// Everything is resolved relative to `reference` (when the note was written), so the same parser
/// serves live capture and offline evaluation of old notes. It is deliberately conservative:
/// a missed date costs less than a reminder nobody asked for.
public struct DeadlineParser: Sendable {
    public var calendar: Calendar
    /// When true, "3/4" reads as 3 April; otherwise as March 4.
    public var dayFirstNumericDates: Bool

    public init(calendar: Calendar = .current, dayFirstNumericDates: Bool = false) {
        self.calendar = calendar
        self.dayFirstNumericDates = dayFirstNumericDates
    }

    public func parse(_ text: String, reference: Date) -> ParsedDeadline? {
        let lower = text.lowercased()
        let explicitTime = Self.explicitTime(in: lower)
        let today = calendar.startOfDay(for: reference)

        if let day = dayHit(in: lower, reference: reference, hasExplicitTime: explicitTime != nil) {
            if let exact = day.exact {
                return ParsedDeadline(date: exact, hasTime: true)
            }
            let time = explicitTime ?? Self.looseTime(in: lower) ?? day.impliedTime
            var base = day.start
            if day.isSameWeekdayAsToday {
                // "thurs 3pm" written on a Thursday morning means today; otherwise next week.
                if let time, let candidate = at(time, on: today), candidate > reference {
                    base = today
                } else {
                    base = add(days: 7, to: today)
                }
            }
            if let time, let date = at(time, on: base) {
                return ParsedDeadline(date: date, hasTime: true)
            }
            return ParsedDeadline(date: base, hasTime: false)
        }

        // A clock time on its own ("call mom at 6pm").
        if let time = explicitTime, let candidate = at(time, on: today) {
            if candidate > reference {
                return ParsedDeadline(date: candidate, hasTime: true)
            }
            // Written in the evening about a morning time: it means tomorrow ("gym 7am").
            let referenceHour = calendar.component(.hour, from: reference)
            if referenceHour >= 17, (5...11).contains(time.hour),
               let tomorrow = at(time, on: add(days: 1, to: today)) {
                return ParsedDeadline(date: tomorrow, hasTime: true)
            }
        }
        return nil
    }

    // MARK: - Times

    struct TimeOfDay: Equatable {
        var hour: Int
        var minute: Int
    }

    private static let meridiemRx = Rx(#"\b(\d{1,2})(?::([0-5]\d))?\s*([ap])\.?m\b"#)
    private static let atTimeRx = Rx(#"(?:\bat|@)\s*(\d{1,2})(?::([0-5]\d))?(?![\d:/%])"#)
    private static let colonTimeRx = Rx(#"(?<![\d:/])\b([01]?\d|2[0-3]):([0-5]\d)\b(?![:\d])"#)
    private static let cuedNoonRx = Rx(#"\b(?:at|by|before|until|till|around)\s+noon\b"#)
    private static let noonRx = Rx(#"\bnoon\b"#)
    private static let midnightRx = Rx(#"\bmidnight\b"#)
    private static let dayPartRx = Rx(#"\b(morning|afternoon|evening|night)\b"#)

    /// Times clear enough to stand on their own: "3pm", "at 3:30", "by noon".
    static func explicitTime(in lower: String) -> TimeOfDay? {
        if let match = meridiemRx.first(in: lower),
           let hour = match.group(1).flatMap({ Int($0) }), (1...12).contains(hour) {
            let minute = match.group(2).flatMap { Int($0) } ?? 0
            let isPM = match.group(3) == "p"
            let hour24 = isPM ? (hour == 12 ? 12 : hour + 12) : (hour == 12 ? 0 : hour)
            return TimeOfDay(hour: hour24, minute: minute)
        }
        if let match = atTimeRx.first(in: lower),
           let hour = match.group(1).flatMap({ Int($0) }),
           let minute = match.group(2).flatMap({ Int($0) }),
           let resolved = assumeMeridiem(hour) {
            return TimeOfDay(hour: resolved, minute: minute)
        }
        if cuedNoonRx.isMatch(lower) {
            return TimeOfDay(hour: 12, minute: 0)
        }
        return nil
    }

    /// Times that only count when a day was also found: "at 3", "15:30", "morning".
    static func looseTime(in lower: String) -> TimeOfDay? {
        if let match = atTimeRx.first(in: lower),
           let hour = match.group(1).flatMap({ Int($0) }),
           let resolved = assumeMeridiem(hour) {
            let minute = match.group(2).flatMap { Int($0) } ?? 0
            return TimeOfDay(hour: resolved, minute: minute)
        }
        if let match = colonTimeRx.first(in: lower),
           let hour = match.group(1).flatMap({ Int($0) }),
           let minute = match.group(2).flatMap({ Int($0) }),
           let resolved = assumeMeridiem(hour) {
            return TimeOfDay(hour: resolved, minute: minute)
        }
        if noonRx.isMatch(lower) {
            return TimeOfDay(hour: 12, minute: 0)
        }
        if midnightRx.isMatch(lower) {
            return TimeOfDay(hour: 23, minute: 59)
        }
        if let match = dayPartRx.first(in: lower), let part = match.group(1) {
            return impliedTime(forDayPart: part)
        }
        return nil
    }

    /// "at 3" almost always means 3 in the afternoon; "at 9" usually means the morning.
    private static func assumeMeridiem(_ hour: Int) -> Int? {
        switch hour {
        case 0: return 0
        case 1...7: return hour + 12
        case 8...23: return hour
        default: return nil
        }
    }

    private static func impliedTime(forDayPart part: String) -> TimeOfDay? {
        switch part {
        case "morning": return TimeOfDay(hour: 9, minute: 0)
        case "afternoon": return TimeOfDay(hour: 15, minute: 0)
        case "evening": return TimeOfDay(hour: 18, minute: 0)
        case "night": return TimeOfDay(hour: 20, minute: 0)
        default: return nil
        }
    }

    // MARK: - Days

    private struct DayHit {
        var start: Date
        var location: Int
        /// Lower runs first: explicit dates beat relative words, which beat weekdays.
        var priority: Int
        var impliedTime: TimeOfDay?
        var exact: Date?
        var isSameWeekdayAsToday = false
    }

    private static let monthPattern =
        #"(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)"#

    private static let intervalRx = Rx(
        #"\bin\s+(\d{1,3}|an?|one|two|three|four|five|six|seven|eight|nine|ten|a\s+couple(?:\s+of)?|a\s+few)\s+(min(?:ute)?s?|hours?|hrs?|days?|weeks?|wks?|months?)\b"#
    )
    private static let isoRx = Rx(#"\b(\d{4})-(\d{2})-(\d{2})\b"#)
    private static let monthFirstRx = Rx(#"\b"# + monthPattern + #"\.?\s+(\d{1,2})(?:st|nd|rd|th)?\b(?:,?\s+(\d{4})\b)?"#)
    private static let dayFirstRx = Rx(#"\b(\d{1,2})(st|nd|rd|th)?\s+(of\s+)?"# + monthPattern + #"\b(?:,?\s+(\d{4})\b)?"#)
    private static let numericRx = Rx(#"(?<![\d/.])\b(\d{1,2})/(\d{1,2})(?:/(\d{4}|\d{2}))?\b(?![/\d])"#)
    private static let numericCueRx = Rx(#"\b(?:on|by|due|before|until|till|for)\s*$"#)
    private static let dayAfterTomorrowRx = Rx(#"\bday\s+after\s+(?:tomorrow|tmrw|tmr)\b"#)
    private static let tomorrowRx = Rx(#"\b(?:tomorrow|tmrw|tmr|tmw|tomo|2morrow|2moro)\b"#)
    private static let todayRx = Rx(#"\b(today|tonight|tonite|this\s+morning|this\s+afternoon|this\s+evening)\b"#)
    private static let nextWeekRx = Rx(#"\bnext\s+week\b"#)
    private static let weekendRx = Rx(#"\b(?:this|the|next)\s+weekend\b"#)
    private static let nextMonthRx = Rx(#"\bnext\s+month\b"#)
    private static let endOfWeekRx = Rx(#"\b(?:end\s+of\s+(?:the\s+)?week|eow)\b"#)
    private static let endOfMonthRx = Rx(#"\b(?:end\s+of\s+(?:the\s+)?month|eom)\b"#)
    private static let weekdayRx = Rx(
        #"\b(?:(next|this|on|by|before|until|till|due|every)\s+)?(monday|mon|tuesday|tues|tue|wednesday|weds|wed|thursday|thurs|thur|thu|friday|fri|saturday|sat|sunday|sun)\b"#
    )
    /// Short forms that are also ordinary words ("sat down", "the sun").
    private static let ambiguousWeekdays: Set<String> = ["sat", "sun", "wed"]
    private static let weekdayFollowRx = Rx(
        #"^\s*(?:$|[,.;:!?)/&+–—]|\d|@|at\s+\d|a\.?m\b|p\.?m\b|morning|afternoon|evening|night|noon)"#
    )
    private static let monthOnlyRx = Rx(
        #"\b(by|before|until|till|in|during|end\s+of|start\s+of|beginning\s+of|early|mid|late|this|next)\s+"#
            + monthPattern + #"\b(?!\.?\s*\d)"#
    )

    private func dayHit(in lower: String, reference: Date, hasExplicitTime: Bool) -> DayHit? {
        let today = calendar.startOfDay(for: reference)
        var hits: [DayHit] = []

        // "in 20 minutes", "in 2 weeks"
        if let match = Self.intervalRx.first(in: lower),
           let count = Self.count(from: match.group(1)), let unit = match.group(2) {
            if unit.hasPrefix("min") {
                hits.append(DayHit(start: today, location: match.location, priority: 0,
                                   exact: reference.addingTimeInterval(Double(count) * 60)))
            } else if unit.hasPrefix("h") {
                hits.append(DayHit(start: today, location: match.location, priority: 0,
                                   exact: reference.addingTimeInterval(Double(count) * 3600)))
            } else if unit.hasPrefix("d") {
                hits.append(DayHit(start: add(days: count, to: today), location: match.location, priority: 1))
            } else if unit.hasPrefix("w") {
                hits.append(DayHit(start: add(days: count * 7, to: today), location: match.location, priority: 1))
            } else if let date = calendar.date(byAdding: .month, value: count, to: today) {
                hits.append(DayHit(start: date, location: match.location, priority: 1))
            }
        }

        // 2026-11-20
        if let match = Self.isoRx.first(in: lower),
           let year = match.group(1).flatMap({ Int($0) }),
           let month = match.group(2).flatMap({ Int($0) }),
           let day = match.group(3).flatMap({ Int($0) }),
           let date = resolve(month: month, day: day, year: year, today: today) {
            hits.append(DayHit(start: date, location: match.location, priority: 1))
        }

        // "mar 3", "march 3rd, 2027"
        if let match = Self.monthFirstRx.first(in: lower),
           let month = Self.monthNumber(match.group(1)),
           let day = match.group(2).flatMap({ Int($0) }),
           let date = resolve(month: month, day: day, year: match.group(3).flatMap { Int($0) }, today: today) {
            hits.append(DayHit(start: date, location: match.location, priority: 1))
        }

        // "3 march", "1st of april"
        if let match = Self.dayFirstRx.first(in: lower),
           let day = match.group(1).flatMap({ Int($0) }),
           let month = Self.monthNumber(match.group(4)) {
            // "2 may be enough" is not a date; "2nd may" and "2 of may" are.
            let isBareMay = month == 5 && match.group(2) == nil && match.group(3) == nil
            if !isBareMay,
               let date = resolve(month: month, day: day, year: match.group(5).flatMap { Int($0) }, today: today) {
                hits.append(DayHit(start: date, location: match.location, priority: 1))
            }
        }

        // "11/20" only with a cue, a year or a clock time; otherwise "1/2 cup" would be a date.
        if let match = Self.numericRx.first(in: lower),
           let first = match.group(1).flatMap({ Int($0) }),
           let second = match.group(2).flatMap({ Int($0) }) {
            var year = match.group(3).flatMap { Int($0) }
            if let short = year, short < 100 { year = 2000 + short }
            let cued = Self.numericCueRx.isMatch(lower.prefix(toUTF16: match.location))
            if year != nil || cued || hasExplicitTime {
                var month = dayFirstNumericDates ? second : first
                var day = dayFirstNumericDates ? first : second
                if month > 12, day <= 12 { swap(&month, &day) }
                if let date = resolve(month: month, day: day, year: year, today: today) {
                    hits.append(DayHit(start: date, location: match.location, priority: 1))
                }
            }
        }

        // today, tonight, tomorrow
        if let match = Self.dayAfterTomorrowRx.first(in: lower) {
            hits.append(DayHit(start: add(days: 2, to: today), location: match.location, priority: 2))
        } else if let match = Self.tomorrowRx.first(in: lower) {
            hits.append(DayHit(start: add(days: 1, to: today), location: match.location, priority: 2))
        }
        if let match = Self.todayRx.first(in: lower), let word = match.group(1) {
            var implied: TimeOfDay?
            if word.hasPrefix("ton") { implied = TimeOfDay(hour: 20, minute: 0) }
            else if word.hasSuffix("morning") { implied = TimeOfDay(hour: 9, minute: 0) }
            else if word.hasSuffix("afternoon") { implied = TimeOfDay(hour: 15, minute: 0) }
            else if word.hasSuffix("evening") { implied = TimeOfDay(hour: 18, minute: 0) }
            hits.append(DayHit(start: today, location: match.location, priority: 2, impliedTime: implied))
        }

        // next week, weekend, end of week/month
        if let match = Self.nextWeekRx.first(in: lower) {
            hits.append(DayHit(start: add(days: 7, to: today), location: match.location, priority: 3))
        }
        if let match = Self.weekendRx.first(in: lower) {
            hits.append(DayHit(start: upcoming(weekday: 7, from: today, allowToday: true), location: match.location, priority: 3))
        }
        if let match = Self.endOfWeekRx.first(in: lower) {
            hits.append(DayHit(start: upcoming(weekday: 6, from: today, allowToday: true), location: match.location, priority: 3))
        }
        if let match = Self.endOfMonthRx.first(in: lower), let date = lastDayOfMonth(containing: today) {
            hits.append(DayHit(start: date, location: match.location, priority: 3))
        }
        if let match = Self.nextMonthRx.first(in: lower),
           let firstOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)),
           let date = calendar.date(byAdding: .month, value: 1, to: firstOfThisMonth) {
            hits.append(DayHit(start: date, location: match.location, priority: 3))
        }

        // "thurs", "next friday"
        for match in Self.weekdayRx.matches(in: lower) {
            guard let token = match.group(2), let target = Self.weekdayNumber(token) else { continue }
            let cue = match.group(1)
            if Self.ambiguousWeekdays.contains(token), cue == nil,
               !Self.weekdayFollowRx.isMatch(lower.suffix(fromUTF16: match.end)) {
                continue
            }
            let todayWeekday = calendar.component(.weekday, from: today)
            let delta = (target - todayWeekday + 7) % 7
            var hit = DayHit(start: add(days: delta, to: today), location: match.location, priority: 4)
            if cue == "next" {
                let soonest = add(days: delta == 0 ? 7 : delta, to: today)
                let sameWeek = calendar.isDate(soonest, equalTo: today, toGranularity: .weekOfYear)
                hit.start = sameWeek ? add(days: 7, to: soonest) : soonest
            } else if delta == 0, cue != "this" {
                hit.isSameWeekdayAsToday = true
            }
            hits.append(hit)
            break
        }

        // "before March", "end of June"
        if let match = Self.monthOnlyRx.first(in: lower),
           let cue = match.group(1), let month = Self.monthNumber(match.group(2)),
           !(month == 5 && cue == "this"), // "this may take a while"
           let date = resolve(monthOnly: month, cue: cue, today: today) {
            hits.append(DayHit(start: date, location: match.location, priority: 5))
        }

        return hits.min { left, right in
            left.priority != right.priority ? left.priority < right.priority : left.location < right.location
        }
    }

    // MARK: - Helpers

    private func at(_ time: TimeOfDay, on day: Date) -> Date? {
        calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day)
    }

    private func add(days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(Double(days) * 86_400)
    }

    /// The next date falling on `weekday` (1 = Sunday … 7 = Saturday).
    private func upcoming(weekday: Int, from today: Date, allowToday: Bool) -> Date {
        let current = calendar.component(.weekday, from: today)
        var delta = (weekday - current + 7) % 7
        if delta == 0, !allowToday { delta = 7 }
        return add(days: delta, to: today)
    }

    private func lastDayOfMonth(containing date: Date) -> Date? {
        guard let first = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let days = calendar.range(of: .day, in: .month, for: first)?.count else { return nil }
        return add(days: days - 1, to: first)
    }

    /// A concrete month and day. Without a year, the next time that date comes around.
    private func resolve(month: Int, day: Int, year: Int?, today: Date) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        var components = DateComponents()
        components.year = year ?? calendar.component(.year, from: today)
        components.month = month
        components.day = day
        guard var date = calendar.date(from: components),
              calendar.component(.month, from: date) == month else { return nil }
        if year == nil, date < today {
            components.year = (components.year ?? 0) + 1
            guard let next = calendar.date(from: components),
                  calendar.component(.month, from: next) == month else { return nil }
            date = next
        }
        return date
    }

    /// A month named without a day: "before March" is March 1, "end of June" is June 30.
    private func resolve(monthOnly month: Int, cue: String, today: Date) -> Date? {
        let normalizedCue = cue.split(separator: " ").joined(separator: " ")
        var year = calendar.component(.year, from: today)
        for _ in 0..<2 {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = 1
            guard let first = calendar.date(from: components) else { return nil }
            var date = first
            switch normalizedCue {
            case "end of": date = lastDayOfMonth(containing: first) ?? first
            case "mid": date = add(days: 14, to: first)
            case "late": date = add(days: 24, to: first)
            default: break
            }
            if date >= today { return date }
            year += 1
        }
        return nil
    }

    private static func count(from raw: String?) -> Int? {
        guard let raw else { return nil }
        if let number = Int(raw) { return number }
        let normalized = raw.split(separator: " ").joined(separator: " ")
        switch normalized {
        case "a", "an", "one": return 1
        case "two", "a couple", "a couple of": return 2
        case "three", "a few": return 3
        case "four": return 4
        case "five": return 5
        case "six": return 6
        case "seven": return 7
        case "eight": return 8
        case "nine": return 9
        case "ten": return 10
        default: return nil
        }
    }

    private static func monthNumber(_ raw: String?) -> Int? {
        guard let raw, raw.count >= 3 else { return nil }
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        guard let index = months.firstIndex(of: String(raw.prefix(3))) else { return nil }
        return index + 1
    }

    /// 1 = Sunday … 7 = Saturday, matching `Calendar`.
    private static func weekdayNumber(_ raw: String) -> Int? {
        let days = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        guard let index = days.firstIndex(of: String(raw.prefix(3))) else { return nil }
        return index + 1
    }
}
