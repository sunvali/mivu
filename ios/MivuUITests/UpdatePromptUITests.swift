import XCTest

final class UpdatePromptUITests: XCTestCase {
    private func launch(_ fixture: String, id: String = UUID().uuidString) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", id, "--proof-english", "--coach-navigation-start-today", fixture]
        app.launch()
        return app
    }

    func testUpdateCardDismisses() {
        let id = UUID().uuidString
        var app = launch("--update-available-fixture", id: id)
        let card = app.descendants(matching: .any)["updateCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["updateCardStore"].exists)
        app.buttons["updateCardDismiss"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        app.terminate()
        app = launch("--update-available-fixture", id: id)
        XCTAssertTrue(app.buttons["profileSettings"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.descendants(matching: .any)["updateCard"].firstMatch.exists)
    }

    func testSettingsShowsUpdateRow() {
        let app = launch("--update-available-fixture")
        XCTAssertTrue(app.buttons["profileSettings"].waitForExistence(timeout: 15)); app.buttons["profileSettings"].tap()
        let row = app.descendants(matching: .any)["updateAvailable"].firstMatch, list = app.collectionViews.firstMatch
        for _ in 0..<8 where !row.isHittable { list.swipeUp() }
        XCTAssertTrue(row.isHittable)
    }

    func testRequiredUpdateBlocksAndOffersExport() {
        let app = launch("--update-required-fixture")
        XCTAssertTrue(app.descendants(matching: .any)["updateRequired"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["updateRequiredStore"].isHittable)
        XCTAssertTrue(app.buttons["updateRequiredExport"].isHittable)
        XCTAssertFalse(app.buttons["profileSettings"].isHittable)
    }

    func testWhatsNewShowsUntilGotIt() {
        let app = launch("--whats-new-fixture")
        let card = app.descendants(matching: .any)["whatsNewCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Synthetic highlight one."].exists)
        app.buttons["whatsNewDone"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
    }
}
