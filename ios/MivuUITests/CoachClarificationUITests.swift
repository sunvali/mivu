import XCTest

@MainActor final class CoachClarificationUITests: XCTestCase {
    func testChipTapResumesOriginalRequest() {
        let app = launch()
        send("Synthetic meal", in: app); send("Synthetic review", in: app)
        send("clarify-candidates", in: app)
        let chips = app.buttons.matching(identifier: "coachQuestionChip")
        XCTAssertTrue(chips.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(chips.count, 2)
        XCTAssertGreaterThanOrEqual(chips.firstMatch.frame.height, 44)
        XCTAssertTrue(chips.firstMatch.label.contains(", "), chips.firstMatch.label)
        let before = app.descendants(matching: .any).matching(identifier: "coachReceiptQuantity").count
        chips.firstMatch.tap()
        XCTAssertTrue(chips.firstMatch.waitForNonExistence(timeout: 20), "Chips leave the answered exchange")
        let receipt = app.descendants(matching: .any).matching(identifier: "coachReceiptQuantity")
        let added = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count > %d", before), object: receipt)
        XCTAssertEqual(XCTWaiter.wait(for: [added], timeout: 20), .completed, "A receipt card follows the tap")
    }

    func testChipsAtLargestDynamicType() {
        let app = launch(largeType: true)
        send("Synthetic meal", in: app); send("Synthetic review", in: app); send("clarify-candidates", in: app)
        let chip = app.buttons["coachQuestionChip"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(chip.frame.height, 44)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Chips at AX5"; shot.lifetime = .keepAlways; add(shot)
    }

    func testConfirmRemoveDeletesMeal() {
        let app = launch()
        send("Synthetic meal", in: app)
        send("clarify-confirm", in: app)
        let remove = app.buttons["coachConfirmRemove"], keep = app.buttons["coachConfirmKeep"]
        XCTAssertTrue(remove.waitForExistence(timeout: 10)); XCTAssertTrue(keep.exists)
        XCTAssertGreaterThanOrEqual(remove.frame.height, 44)
        remove.tap()
        XCTAssertTrue(remove.waitForNonExistence(timeout: 20), "Buttons leave once answered")
        let quote = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'coachQuote-'")).firstMatch
        XCTAssertTrue(quote.waitForExistence(timeout: 5))
        XCTAssertFalse(quote.label.contains("Remove it"), "The answer quotes the meal, not itself: \(quote.label)")
        app.tabBars.buttons["Today"].tap()
        XCTAssertFalse(app.buttons["mealRow"].firstMatch.waitForExistence(timeout: 3), "The confirmed meal is gone")
    }

    private func launch(largeType: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-inference-fixture", "--proof-english"]
        if largeType { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        return app
    }
    private func send(_ text: String, in app: XCUIApplication) {
        let count = app.descendants(matching: .any).matching(identifier: "coachReply").count
        let input = app.textFields["coachInput"]; XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText(text); app.buttons["coachSend"].tap()
        let answered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count > %d", count), object: app.descendants(matching: .any).matching(identifier: "coachReply"))
        XCTAssertEqual(XCTWaiter.wait(for: [answered], timeout: 20), .completed, "Pip answers: \(text)")
    }
}
