import XCTest

@MainActor final class PipStickerUITests: XCTestCase {
    private func openSheet(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--proof-english"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["profileSettings"].waitForExistence(timeout: 15))
        app.buttons["profileSettings"].tap()
        let row = app.buttons["pipStickers"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["addPipToWhatsApp"].waitForExistence(timeout: 5))
        return app
    }

    func testStickerSheetOpensFromSettings() {
        let app = openSheet()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'pipSticker-'")).count, 12)
        XCTAssertTrue(app.buttons["addPipMovesToWhatsApp"].exists)
        app.buttons["addPipToWhatsApp"].tap()
        let alert = app.alerts["WhatsApp isn't installed"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.buttons["Get WhatsApp"].exists)
        alert.buttons["Cancel"].tap()
        XCTAssertFalse(alert.exists)
    }

    func testReduceMotionShowsStillStickers() {
        let app = openSheet(["-UIAccessibilityReduceMotionEnabled", "YES"])
        let hi = app.buttons["pipSticker-hi"]
        XCTAssertTrue(hi.exists)
        XCTAssertNotEqual(hi.value as? String, "animated")
    }
}
