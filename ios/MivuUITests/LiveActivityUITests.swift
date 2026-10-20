import XCTest

final class LiveActivityUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testDynamicIslandTogglesShowAndPersist() {
        let id = UUID().uuidString
        var app = openSettings(id)
        let main = app.switches["liveActivityToggle"]
        // Settings live in standard defaults, so start from the default whatever an earlier run left.
        if switchIsOn(main) { main.switches.firstMatch.tap() }
        XCTAssertFalse(switchIsOn(main))
        XCTAssertFalse(app.switches["liveActivityHideWhenLocked"].exists)

        main.switches.firstMatch.tap()
        let hide = app.switches["liveActivityHideWhenLocked"]
        XCTAssertTrue(hide.waitForExistence(timeout: 3))
        XCTAssertTrue(switchIsOn(main))
        XCTAssertTrue(switchIsOn(hide))
        XCTAssertGreaterThanOrEqual(main.frame.height, 44)

        app.terminate()
        app = openSettings(id)
        XCTAssertTrue(switchIsOn(app.switches["liveActivityToggle"]))
        XCTAssertTrue(switchIsOn(app.switches["liveActivityHideWhenLocked"]))
        app.switches["liveActivityToggle"].switches.firstMatch.tap()
        XCTAssertFalse(app.switches["liveActivityHideWhenLocked"].waitForExistence(timeout: 1))
    }

    private func openSettings(_ id: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", id, "--proof-english"]
        app.launch()
        XCTAssertTrue(app.buttons["profileSettings"].waitForExistence(timeout: 15))
        app.buttons["profileSettings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let toggle = app.switches["liveActivityToggle"]
        for _ in 0..<8 where !(toggle.exists && toggle.isHittable) { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(toggle.isHittable)
        return app
    }

    private func switchIsOn(_ element: XCUIElement) -> Bool { (element.value as? String) == "1" }
}
