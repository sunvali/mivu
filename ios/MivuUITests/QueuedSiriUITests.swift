import XCTest

/// Siri text saved while locked waits for Send or Discard; nothing reaches the Coach on its own.
@MainActor final class QueuedSiriUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--siri-queue-fixture", "--proof-english"]
        app.launch()
        let coach = app.tabBars.buttons["Coach"]
        XCTAssertTrue(coach.waitForExistence(timeout: 15))
        coach.tap()
        return app
    }

    func testQueuedSiriMessageCanBeDiscarded() {
        let app = launch()
        let card = app.otherElements["queuedSiri"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["“Synthetic queued toast”"].exists)
        let discard = app.buttons["discardQueuedSiri"]
        XCTAssertGreaterThanOrEqual(discard.frame.height, 44)
        discard.tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Synthetic queued toast"].exists)
    }

    func testQueuedSiriMessageIsSentOnlyAfterSend() {
        let app = launch()
        XCTAssertTrue(app.otherElements["queuedSiri"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Synthetic queued toast"].exists, "Not in the conversation before Send")
        let send = app.buttons["sendQueuedSiri"]
        XCTAssertGreaterThanOrEqual(send.frame.height, 44)
        send.tap()
        XCTAssertTrue(app.staticTexts["Synthetic queued toast"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.otherElements["queuedSiri"].exists)
    }
}
