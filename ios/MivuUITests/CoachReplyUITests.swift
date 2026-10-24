import XCTest

@MainActor final class CoachReplyUITests: XCTestCase {
    func testSwipeReplyQuotesPipSendsAndQuoteSeeksOriginal() {
        let app = launch()
        let source = send("Synthetic reply source", in: app)
        _ = send("Synthetic later message", in: app)
        let sourceRow = exchange(source, in: app)
        sourceRow.swipeRight()
        let action = app.buttons["Reply"]
        if action.waitForExistence(timeout: 2), action.isHittable { action.tap() }
        XCTAssertTrue(app.otherElements["coachReplyBar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Replying to Pip"].exists)
        let proof = XCTAttachment(screenshot: app.screenshot()); proof.name = "Composer reply quote"; proof.lifetime = .keepAlways; add(proof)
        let reply = send("About that answer", in: app)
        XCTAssertFalse(app.otherElements["coachReplyBar"].exists, "Sending clears the composer quote")
        let quote = app.buttons["coachQuote-" + reply]
        XCTAssertTrue(quote.waitForExistence(timeout: 5))
        XCTAssertTrue(quote.label.hasPrefix("Reply to Pip: "), quote.label)
        XCTAssertGreaterThanOrEqual(quote.frame.height, 44)
        let bubble = XCTAttachment(screenshot: app.screenshot()); bubble.name = "Sent message with quote"; bubble.lifetime = .keepAlways; add(bubble)

        app.terminate(); app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        XCTAssertTrue(quote.waitForExistence(timeout: 10), "The quote is saved with the message")
        quote.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Selected source message"), object: sourceRow)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed)
        let sent = XCTAttachment(screenshot: app.screenshot()); sent.name = "Sent quote highlights original"; sent.lifetime = .keepAlways; add(sent)
    }

    func testLongPressReplyToOwnMessageAndCancel() {
        let app = launch()
        let own = send("Synthetic own message", in: app)
        app.staticTexts["coachText-" + own].press(forDuration: 1)
        let reply = app.buttons["Reply"]
        XCTAssertTrue(reply.waitForExistence(timeout: 5)); reply.tap()
        XCTAssertTrue(app.staticTexts["Replying to you"].waitForExistence(timeout: 5))
        let cancel = app.buttons["coachReplyCancel"]
        XCTAssertGreaterThanOrEqual(cancel.frame.width, 44); XCTAssertGreaterThanOrEqual(cancel.frame.height, 44)
        cancel.tap()
        XCTAssertFalse(app.otherElements["coachReplyBar"].waitForExistence(timeout: 1))
    }

    func testDiaryDayAskPipQuotesDay() {
        let app = launchDiary()
        XCTAssertTrue(app.selectDiaryDate("2026-10-12"))
        app.buttons["diaryAskPip"].tap()
        let quote = app.otherElements["coachReplyBar"]
        XCTAssertTrue(quote.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["coachReplyCancel"].exists)
        XCTAssertTrue(quote.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Monday, 12 Oct")).firstMatch.exists)
    }

    func testUnrecordedDayAskPipPrefillsDate() {
        let app = launchDiary()
        XCTAssertTrue(app.selectDiaryDate(XCUIApplication.diaryLabel(Date())))
        app.buttons["diaryAskPip"].tap()
        let input = app.textFields["coachInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        let prefilled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value BEGINSWITH %@", "For "), object: input)
        XCTAssertEqual(XCTWaiter.wait(for: [prefilled], timeout: 10), .completed)
    }

    private func launchDiary() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-navigation-start-today", "--diary-history-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["logMeal"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Diary"].tap()
        return app
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-inference-fixture", "--proof-english"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        return app
    }
    /// Sends text, waits for Pip's answer and returns the turn's ID.
    private func send(_ text: String, in app: XCUIApplication) -> String {
        let input = app.textFields["coachInput"]; XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText(text); app.buttons["coachSend"].tap()
        let sent = app.staticTexts.matching(NSPredicate(format: "label == %@ AND identifier BEGINSWITH %@", text, "coachText-")).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 5))
        let id = String(sent.identifier.dropFirst("coachText-".count))
        let answer = exchange(id, in: app).descendants(matching: .any).matching(identifier: "coachReply").firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 15), "Pip answers: \(text)")
        return id
    }
    private func exchange(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["coachExchange-" + id].firstMatch
    }
}
