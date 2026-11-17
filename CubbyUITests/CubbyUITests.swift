import XCTest

/// Drives the real app in the simulator with demo data (in-memory, rules-only sorting).
final class CubbyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(startScreen: String) {
        app = XCUIApplication()
        app.launchArguments = ["-cubbyDemo", "-cubbyRulesOnly", "-startScreen", startScreen, "-appearance", "system"]
        app.launch()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func text(_ label: String) -> XCUIElement {
        app.staticTexts[label].firstMatch
    }

    /// True once the element is the first responder. Checks focus rather than the on-screen
    /// keyboard, which CI simulators often don't show.
    private func waitForFocus(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: element)
        return XCTWaiter().wait(for: [focused], timeout: timeout) == .completed
    }

    // MARK: - Blank page (the default)

    func testBlankPageOpensReadyToTypeAndSavesIntoTheTimeline() {
        launch(startScreen: "capture")

        let field = element("captureField")
        XCTAssertTrue(field.waitForExistence(timeout: 10), "capture field")
        XCTAssertTrue(waitForFocus(field), "the blank page should open ready to type")

        app.typeText("buy stamps tomorrow")
        app.buttons["Save"].tap()

        element("timelinePill").tap()
        XCTAssertTrue(text("buy stamps tomorrow").waitForExistence(timeout: 5), "saved entry appears in the timeline")
        XCTAssertTrue(text("Due Tomorrow").exists, "a deadline chip for tomorrow")
    }

    func testSettingsOpenFromTheBlankPage() {
        launch(startScreen: "capture")
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(text("Open to").exists || app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Open to'")).firstMatch.exists)
    }

    // MARK: - Timeline

    func testTimelineStartFocusesTheComposer() {
        launch(startScreen: "timeline")
        let composer = element("composerField")
        XCTAssertTrue(composer.waitForExistence(timeout: 10), "composer")
        XCTAssertTrue(waitForFocus(composer), "the timeline start should open ready to type")
        XCTAssertTrue(text("milk, eggs, call mom").exists, "recent entries are visible above the keyboard")
    }

    func testFiltersShowOnlyMatchingEntries() {
        launch(startScreen: "timeline")
        XCTAssertTrue(element("filter-todos").waitForExistence(timeout: 10))

        element("filter-todos").tap()
        XCTAssertTrue(text("dentist thurs 3pm, ask about retainer").waitForExistence(timeout: 5))
        XCTAssertFalse(text("gift for Sam: the ceramic pour-over set").exists, "a note is not a to-do")

        element("filter-notes").tap()
        XCTAssertTrue(text("gift for Sam: the ceramic pour-over set").waitForExistence(timeout: 5))
        XCTAssertFalse(text("dentist thurs 3pm, ask about retainer").exists, "a to-do is not a note")
    }

    func testCompletingAToDo() {
        launch(startScreen: "timeline")
        XCTAssertTrue(element("filter-todos").waitForExistence(timeout: 10))
        element("filter-todos").tap()

        // The demo data has one completed to-do already.
        XCTAssertTrue(app.buttons["Show 1 completed"].waitForExistence(timeout: 5))
        app.buttons["Mark done"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Show 2 completed"].waitForExistence(timeout: 5))
    }

    func testLongPressCorrectsTheSorting() {
        launch(startScreen: "timeline")
        let gift = text("gift for Sam: the ceramic pour-over set")
        XCTAssertTrue(gift.waitForExistence(timeout: 10))

        gift.press(forDuration: 1.2)
        let makeTodo = app.buttons["Make It a To-do"]
        XCTAssertTrue(makeTodo.waitForExistence(timeout: 5))
        makeTodo.tap()

        element("filter-todos").tap()
        XCTAssertTrue(text("gift for Sam: the ceramic pour-over set").waitForExistence(timeout: 5))
    }

    func testSearchFindsAnEntry() {
        launch(startScreen: "timeline")
        XCTAssertTrue(app.buttons["Search"].waitForExistence(timeout: 10))
        app.buttons["Search"].tap()

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("passport")
        XCTAssertTrue(text("renew passport before March").waitForExistence(timeout: 5))
    }
}
