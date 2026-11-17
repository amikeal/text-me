import XCTest
@testable import CubbyCore

final class ClassificationPipelineTests: XCTestCase {
    private let pipeline = ClassificationPipeline(calendar: TestClock.calendar)
    private let now = TestClock.mondayMorning

    private func quick(_ text: String) -> EntryClassification {
        pipeline.quick(text: text, capturedAt: now)
    }

    // MARK: Rules

    func testTerseDatedTaskIsTodoWithDeadline() {
        let result = quick("dentist thurs 3pm, ask about retainer")
        XCTAssertTrue(result.isTodo)
        XCTAssertFalse(result.isNote)
        XCTAssertEqual(result.deadline, TestClock.date(2026, 10, 15, 15, 0))
        XCTAssertTrue(result.deadlineHasTime)
        XCTAssertEqual(result.tier, .heuristic)
    }

    func testActionVerbIsTodo() {
        XCTAssertTrue(quick("email landlord about the lease").isTodo)
        XCTAssertTrue(quick("renew passport before March").isTodo)
        XCTAssertEqual(quick("renew passport before March").deadline, TestClock.date(2027, 3, 1))
    }

    func testTriggerPhraseIsTodo() {
        XCTAssertTrue(quick("need to find the warranty for the dishwasher").isTodo)
        XCTAssertTrue(quick("don’t forget sunscreen").isTodo)
    }

    func testExplicitCheckboxIsTodo() {
        XCTAssertTrue(quick("[ ] water plants").isTodo)
        XCTAssertTrue(quick("todo: water plants").isTodo)
    }

    func testListsWithAnActionOrManyShortItemsAreTodos() {
        let mixed = quick("milk, eggs, call mom")
        XCTAssertTrue(mixed.isTodo)
        XCTAssertTrue(mixed.isMultiItem)

        let shopping = quick("milk, eggs, bread")
        XCTAssertTrue(shopping.isTodo)
        XCTAssertTrue(shopping.isMultiItem)
    }

    func testTwoLongerCommaPartsAreOneItem() {
        XCTAssertFalse(quick("dentist thurs 3pm, ask about retainer").isMultiItem)
        XCTAssertTrue(quick("milk, eggs").isMultiItem)
        XCTAssertTrue(quick("sunscreen\ncharger\npassport").isMultiItem)
    }

    func testLabelledIdeasAreNotes() {
        for text in [
            "podcast idea: ask people about the one note they never deleted",
            "gift for Sam: the ceramic pour-over set",
            "book: The Overstory (Dana says read it)",
            "wifi: pinecone-guest",
        ] {
            let result = quick(text)
            XCTAssertFalse(result.isTodo, text)
            XCTAssertTrue(result.isNote, text)
            XCTAssertNil(result.deadline, text)
        }
    }

    func testQuestionStartingWithAVerbIsNotATodo() {
        XCTAssertFalse(quick("do you remember the name of that place?").isTodo)
    }

    func testLongNarrativeWithADateIsANoteWithoutDeadline() {
        let result = quick("today was rough, slept badly and the meeting ran long but at least the demo worked fine in the end")
        XCTAssertFalse(result.isTodo)
        XCTAssertTrue(result.isNote)
        XCTAssertNil(result.deadline)
    }

    // MARK: Links

    func testBareLinkIsNeitherTodoNorNote() {
        let result = quick("https://longreads.example/one-thing")
        XCTAssertTrue(result.isLinkOnly)
        XCTAssertTrue(result.hasLink)
        XCTAssertFalse(result.isTodo)
        XCTAssertFalse(result.isNote)
        XCTAssertEqual(result.urls.count, 1)
    }

    func testLinkWithInstructionIsTodoAndLink() {
        let result = quick("read this before friday https://example.com/a")
        XCTAssertTrue(result.hasLink)
        XCTAssertFalse(result.isLinkOnly)
        XCTAssertTrue(result.isTodo)
        XCTAssertEqual(result.deadline, TestClock.date(2026, 10, 16))
        XCTAssertFalse(result.deadlineHasTime)
    }

    func testDateInsideAUrlIsIgnored() {
        let result = quick("https://example.com/2026/11/20/post")
        XCTAssertNil(result.deadline)
    }

    // MARK: Merging the model's answer

    private func llm(todo: Bool, note: Bool = false, deadline: String = "", multi: Bool = false, title: String = "") -> LLMClassification {
        LLMClassification(isTodo: todo, isNote: note, deadline: deadline, isMultiItem: multi, shortTitle: title)
    }

    func testModelDeadlineFillsInWhenParserFindsNothing() {
        let result = pipeline.merge(text: "sort out the bank thing", capturedAt: now,
                                    llm: llm(todo: true, deadline: "2026-10-20T14:30", title: "Bank thing"))
        XCTAssertTrue(result.isTodo)
        XCTAssertEqual(result.deadline, TestClock.date(2026, 10, 20, 14, 30))
        XCTAssertTrue(result.deadlineHasTime)
        XCTAssertEqual(result.shortTitle, "Bank thing")
        XCTAssertEqual(result.tier, .foundationModels)
    }

    func testParserDeadlineBeatsModelDeadline() {
        let result = pipeline.merge(text: "dentist thurs 3pm", capturedAt: now,
                                    llm: llm(todo: true, deadline: "2026-10-16"))
        XCTAssertEqual(result.deadline, TestClock.date(2026, 10, 15, 15, 0))
    }

    func testImplausibleModelDeadlinesAreRejected() {
        let past = pipeline.merge(text: "sort out the bank thing", capturedAt: now, llm: llm(todo: true, deadline: "2020-01-01"))
        XCTAssertNil(past.deadline)
        let farFuture = pipeline.merge(text: "sort out the bank thing", capturedAt: now, llm: llm(todo: true, deadline: "2031-01-01"))
        XCTAssertNil(farFuture.deadline)
        let garbage = pipeline.merge(text: "sort out the bank thing", capturedAt: now, llm: llm(todo: true, deadline: "soon"))
        XCTAssertNil(garbage.deadline)
    }

    func testNonTodoNeverCarriesADeadline() {
        let result = pipeline.merge(text: "flight lands fri 5pm", capturedAt: now, llm: llm(todo: false, note: true, deadline: "2026-10-16T17:00"))
        XCTAssertFalse(result.isTodo)
        XCTAssertTrue(result.isNote)
        XCTAssertNil(result.deadline)
    }

    func testBareLinkStaysALinkWhateverTheModelSays() {
        let result = pipeline.merge(text: "https://longreads.example/one-thing", capturedAt: now, llm: llm(todo: true, note: true, multi: true))
        XCTAssertFalse(result.isTodo)
        XCTAssertFalse(result.isNote)
        XCTAssertFalse(result.isMultiItem)
        XCTAssertTrue(result.isLinkOnly)
    }

    func testEveryTextEntryIsAtLeastATodoOrANote() {
        let result = pipeline.merge(text: "hmm", capturedAt: now, llm: llm(todo: false, note: false))
        XCTAssertTrue(result.isNote)
    }
}

final class LinkDetectorTests: XCTestCase {
    func testFindsLinksInOrderWithoutDuplicates() {
        let urls = LinkDetector.urls(in: "see https://example.com/a?b=1, then www.test.org. again https://example.com/a?b=1")
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls.first?.host, "example.com")
        XCTAssertEqual(urls.last?.host, "www.test.org")
    }

    func testStrippingLinksLeavesTidyText() {
        XCTAssertEqual(LinkDetector.strippingURLs(from: "read this https://example.com/a later"), "read this later")
        XCTAssertEqual(LinkDetector.strippingURLs(from: "https://example.com/a"), "")
    }

    func testLinkOnly() {
        XCTAssertTrue(LinkDetector.isLinkOnly("  https://example.com/a  "))
        XCTAssertFalse(LinkDetector.isLinkOnly("look https://example.com/a"))
        XCTAssertFalse(LinkDetector.isLinkOnly("no links here"))
    }

    func testEmailAddressesAreNotLinks() {
        XCTAssertTrue(LinkDetector.urls(in: "email dana@example.com about friday").isEmpty)
    }
}
