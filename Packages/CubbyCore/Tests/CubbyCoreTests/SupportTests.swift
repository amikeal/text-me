import XCTest
@testable import CubbyCore

final class InboxQueueTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cubby-inbox-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testDrainReturnsCapturesOldestFirstAndEmptiesTheQueue() throws {
        let queue = InboxQueue(directory: directory)
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        try queue.enqueue(PendingCapture(text: "second", source: "shareExtension", createdAt: base.addingTimeInterval(10)))
        try queue.enqueue(PendingCapture(text: "first", source: "shareExtension", createdAt: base))
        try queue.enqueue(PendingCapture(text: "third", source: "shareExtension", createdAt: base.addingTimeInterval(20)))
        XCTAssertEqual(queue.count, 3)

        let drained = queue.drain()
        XCTAssertEqual(drained.map(\.text), ["first", "second", "third"])
        XCTAssertEqual(queue.count, 0)
        XCTAssertTrue(queue.drain().isEmpty)
    }

    func testCaptureSurvivesTheRoundTrip() throws {
        let queue = InboxQueue(directory: directory)
        let capture = PendingCapture(text: "https://example.com/a", source: "shareExtension", createdAt: Date(timeIntervalSince1970: 1_800_000_000.25))
        try queue.enqueue(capture)
        XCTAssertEqual(queue.drain(), [capture])
    }

    func testUnreadableFileIsDroppedNotRetriedForever() throws {
        let queue = InboxQueue(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("000-bad.json"))
        try queue.enqueue(PendingCapture(text: "good", source: "shareExtension"))

        XCTAssertEqual(queue.drain().map(\.text), ["good"])
        XCTAssertEqual(queue.count, 0)
    }

    func testDrainingAMissingDirectoryIsEmpty() {
        XCTAssertTrue(InboxQueue(directory: directory).drain().isEmpty)
    }
}

final class WidgetSnapshotTests: XCTestCase {
    func testSaveAndLoad() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cubby-snapshot-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let snapshot = WidgetSnapshot(openTodoCount: 4, nextTitle: "Dentist", nextDeadline: Date(timeIntervalSince1970: 1_800_000_000), nextDeadlineHasTime: true, updatedAt: Date(timeIntervalSince1970: 1_799_999_000))
        XCTAssertTrue(snapshot.save(to: url))
        XCTAssertEqual(WidgetSnapshot.load(from: url), snapshot)
    }

    func testLoadWithoutAFileIsNil() {
        XCTAssertNil(WidgetSnapshot.load(from: nil))
    }
}

final class DeadlineLabelTests: XCTestCase {
    private let calendar = TestClock.calendar
    private let locale = Locale(identifier: "en_US")
    private let now = TestClock.mondayMorning

    private func label(_ date: Date, hasTime: Bool) -> String {
        DeadlineLabel.text(for: date, hasTime: hasTime, now: now, calendar: calendar, locale: locale)
    }

    func testNearbyDaysUseWords() {
        XCTAssertEqual(label(TestClock.date(2026, 10, 12), hasTime: false), "Today")
        XCTAssertEqual(label(TestClock.date(2026, 10, 13), hasTime: false), "Tomorrow")
        XCTAssertEqual(label(TestClock.date(2026, 10, 11), hasTime: false), "Yesterday")
    }

    func testThisWeekUsesWeekdayAndTime() {
        let text = label(TestClock.date(2026, 10, 15, 15, 0), hasTime: true)
        XCTAssertTrue(text.hasPrefix("Thu"), text)
        XCTAssertTrue(text.contains("3:00"), text)
    }

    func testFartherDatesUseMonthAndDay() {
        XCTAssertEqual(label(TestClock.date(2026, 11, 20), hasTime: false), "Nov 20")
        XCTAssertTrue(label(TestClock.date(2027, 3, 1), hasTime: false).contains("2027"))
    }

    func testOverdue() {
        XCTAssertTrue(DeadlineLabel.isOverdue(TestClock.date(2026, 10, 12, 8, 0), hasTime: true, now: now, calendar: calendar))
        XCTAssertFalse(DeadlineLabel.isOverdue(TestClock.date(2026, 10, 12), hasTime: false, now: now, calendar: calendar))
        XCTAssertTrue(DeadlineLabel.isOverdue(TestClock.date(2026, 10, 11), hasTime: false, now: now, calendar: calendar))
    }
}

final class DigestComposerTests: XCTestCase {
    func testNothingToSayMeansNoDigest() {
        XCTAssertNil(DigestComposer.compose(DigestStats()))
    }

    func testCountsArePluralizedAndJoined() {
        let digest = DigestComposer.compose(DigestStats(openTodos: 4, dueThisWeek: 2, overdue: 1, linksThisWeek: 1, notesThisWeek: 3))
        XCTAssertEqual(digest?.title, "Your week in Cubby")
        XCTAssertEqual(digest?.body, "4 open to-dos · 1 overdue · 2 due this week · 1 link saved · 3 new notes")
    }
}
