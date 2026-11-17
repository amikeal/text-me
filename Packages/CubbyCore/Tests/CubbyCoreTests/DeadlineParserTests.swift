import XCTest
@testable import CubbyCore

/// A fixed calendar so results don't depend on the machine running the tests.
enum TestClock {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 1
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    /// Monday 12 October 2026, 9:00.
    static let mondayMorning = date(2026, 10, 12, 9, 0)
}

final class DeadlineParserTests: XCTestCase {
    private let parser = DeadlineParser(calendar: TestClock.calendar)
    private let reference = TestClock.mondayMorning

    private func parse(_ text: String, at reference: Date? = nil) -> ParsedDeadline? {
        parser.parse(text, reference: reference ?? self.reference)
    }

    private func assertDeadline(
        _ text: String,
        _ expected: Date,
        hasTime: Bool,
        at reference: Date? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let parsed = parse(text, at: reference) else {
            return XCTFail("No deadline found in \"\(text)\"", file: file, line: line)
        }
        XCTAssertEqual(parsed.date, expected, "date for \"\(text)\"", file: file, line: line)
        XCTAssertEqual(parsed.hasTime, hasTime, "hasTime for \"\(text)\"", file: file, line: line)
    }

    private func assertNoDeadline(_ text: String, at reference: Date? = nil, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(parse(text, at: reference), "unexpected deadline in \"\(text)\"", file: file, line: line)
    }

    // MARK: Weekdays

    func testAbbreviatedWeekdayWithTime() {
        assertDeadline("dentist thurs 3pm, ask about retainer", TestClock.date(2026, 10, 15, 15, 0), hasTime: true)
    }

    func testWeekdayWithoutTime() {
        assertDeadline("pay rent fri", TestClock.date(2026, 10, 16), hasTime: false)
    }

    func testNextWeekdaySkipsThisWeek() {
        assertDeadline("lunch with dana next friday", TestClock.date(2026, 10, 23), hasTime: false)
    }

    func testSameWeekdayWithoutTimeMeansNextWeek() {
        assertDeadline("standup notes mon", TestClock.date(2026, 10, 19), hasTime: false)
    }

    func testSameWeekdayWithLaterTimeMeansToday() {
        assertDeadline("call bank mon 3pm", TestClock.date(2026, 10, 12, 15, 0), hasTime: true)
    }

    func testAmbiguousWeekdayWordsNeedContext() {
        assertNoDeadline("sat down with Jim about the roof")
        assertNoDeadline("the sun is out finally")
        assertDeadline("dinner sat 7pm", TestClock.date(2026, 10, 17, 19, 0), hasTime: true)
        assertDeadline("call mom sun", TestClock.date(2026, 10, 18), hasTime: false)
    }

    func testWeekdayWithTwentyFourHourTime() {
        assertDeadline("review fri 15:30", TestClock.date(2026, 10, 16, 15, 30), hasTime: true)
    }

    // MARK: Relative words

    func testTomorrow() {
        assertDeadline("call mom tomorrow", TestClock.date(2026, 10, 13), hasTime: false)
        assertDeadline("tmrw 9am gym", TestClock.date(2026, 10, 13, 9, 0), hasTime: true)
        assertDeadline("tomorrow at 3 pick up keys", TestClock.date(2026, 10, 13, 15, 0), hasTime: true)
        assertDeadline("tomorrow morning email lee", TestClock.date(2026, 10, 13, 9, 0), hasTime: true)
    }

    func testTonightImpliesEvening() {
        assertDeadline("call mom tonight", TestClock.date(2026, 10, 12, 20, 0), hasTime: true)
    }

    func testIntervals() {
        assertDeadline("check in 2 weeks", TestClock.date(2026, 10, 26), hasTime: false)
        assertDeadline("move the laundry in 20 minutes", reference.addingTimeInterval(20 * 60), hasTime: true)
        assertDeadline("follow up in a few days", TestClock.date(2026, 10, 15), hasTime: false)
    }

    func testWeekAndMonthBoundaries() {
        assertDeadline("report by end of the month", TestClock.date(2026, 10, 31), hasTime: false)
        assertDeadline("clean garage this weekend", TestClock.date(2026, 10, 17), hasTime: false)
        assertDeadline("send invoice eow", TestClock.date(2026, 10, 16), hasTime: false)
        assertDeadline("revisit next week", TestClock.date(2026, 10, 19), hasTime: false)
    }

    // MARK: Calendar dates

    func testMonthAndDay() {
        assertDeadline("nov 20 party", TestClock.date(2026, 11, 20), hasTime: false)
        assertDeadline("taxes march 3rd", TestClock.date(2027, 3, 3), hasTime: false)
        assertDeadline("3 march taxes", TestClock.date(2027, 3, 3), hasTime: false)
        assertDeadline("may 5 recital", TestClock.date(2027, 5, 5), hasTime: false)
    }

    func testPastDateRollsToNextYear() {
        assertDeadline("sep 30 renewal", TestClock.date(2027, 9, 30), hasTime: false)
    }

    func testMonthOnlyWithCue() {
        assertDeadline("renew passport before March", TestClock.date(2027, 3, 1), hasTime: false)
        assertDeadline("book flights by end of november", TestClock.date(2026, 11, 30), hasTime: false)
    }

    func testIsoDate() {
        assertDeadline("submit by 2026-12-01", TestClock.date(2026, 12, 1), hasTime: false)
    }

    func testNumericDatesNeedACue() {
        assertDeadline("due 11/20", TestClock.date(2026, 11, 20), hasTime: false)
        assertNoDeadline("1/2 cup flour")
        assertNoDeadline("24/7 support line")
    }

    func testExplicitDateBeatsWeekday() {
        assertDeadline("tues nov 24 vet", TestClock.date(2026, 11, 24), hasTime: false)
    }

    // MARK: Times on their own

    func testClockTimeLaterToday() {
        assertDeadline("call the school at 2:30", TestClock.date(2026, 10, 12, 14, 30), hasTime: true)
        assertDeadline("pick up kids 6pm", TestClock.date(2026, 10, 12, 18, 0), hasTime: true)
    }

    func testPastClockTimeIsNotADeadline() {
        assertNoDeadline("woke up at 3am again")
    }

    func testEveningNoteAboutMorningMeansTomorrow() {
        let evening = TestClock.date(2026, 10, 12, 21, 0)
        assertDeadline("gym 7am", TestClock.date(2026, 10, 13, 7, 0), hasTime: true, at: evening)
    }

    // MARK: Things that are not dates

    func testNonDates() {
        assertNoDeadline("gift for Sam: the ceramic pour-over set")
        assertNoDeadline("2 may be enough")
        assertNoDeadline("look at 2 options for the couch")
        assertNoDeadline("john 3:16")
        assertNoDeadline("sun-dried tomatoes")
        assertNoDeadline("call the bank, this may take a while")
        assertDeadline("trip planning in may", TestClock.date(2027, 5, 1), hasTime: false)
    }
}
