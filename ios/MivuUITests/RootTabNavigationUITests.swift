import XCTest

@MainActor final class RootTabNavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    func testFourTabsSelectTheirOwnRootsAndSettingsReturnsToTheOrigin() {
        let app = launch()
        for title in ["Today", "Diary", "Progress", "Coach", "Progress", "Diary"] {
            select(title, in: app)
            openSettings(in: app)
            let done = app.buttons["doneSettings"]
            XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
            assertRoot(title, in: app)
        }
    }

    func testProgressCoverageOpensTheDiaryTabAndProgressStillOpensProgress() {
        let app = launch()
        select("Progress", in: app)
        let diary = app.buttons["openDiaryForCoverage"]
        reveal(diary, in: app)
        XCTAssertTrue(diary.isHittable); diary.tap()
        assertRoot("Diary", in: app)
        XCTAssertTrue(app.tabBars.buttons["Diary"].isHittable,
            "Coverage must select the existing Diary tab, preserving the four root destinations")
        select("Progress", in: app)
        XCTAssertTrue(app.buttons["reportWeekly"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Diary"].exists,
            "Progress must not retain a second Diary screen in its navigation stack")
    }

    func testCoachDraftSurvivesProgressDetailAndSettingsReturn() {
        let app = launch()
        select("Coach", in: app)
        let input = app.textFields["coachInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText("Unsent navigation note")
        dismissKeyboard(in: app)
        XCTAssertEqual(input.value as? String, "Unsent navigation note")
        select("Diary", in: app)
        select("Progress", in: app)
        let weight = app.buttons["openWeight"]
        reveal(weight, in: app)
        XCTAssertTrue(weight.isHittable); weight.tap()
        XCTAssertTrue(app.navigationBars["Weight"].waitForExistence(timeout: 5))
        let back = app.navigationBars.buttons["Progress"]
        XCTAssertTrue(back.isHittable); back.tap()
        assertRoot("Progress", in: app)
        openSettings(in: app)
        app.buttons["doneSettings"].tap()
        assertRoot("Progress", in: app)
        select("Coach", in: app)
        XCTAssertEqual(app.textFields["coachInput"].value as? String, "Unsent navigation note")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--proof-english"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
        return app
    }

    private func select(_ title: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[title]
        XCTAssertTrue(tab.waitForExistence(timeout: 5)); XCTAssertTrue(tab.isHittable)
        tab.tap()
        assertRoot(title, in: app)
    }

    private func assertRoot(_ title: String, in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
        for name in ["Today", "Diary", "Progress", "Coach"] {
            let tab = app.tabBars.buttons[name]
            XCTAssertTrue(tab.exists)
            XCTAssertEqual(tab.isSelected, name == title,
                "The visible \(title) screen and selected \(name) tab must agree")
        }
    }

    private func openSettings(in app: XCUIApplication) {
        if !app.buttons["profileSettings"].isHittable, app.buttons["OverflowBarButtonItem"].exists {
            app.buttons["OverflowBarButtonItem"].tap()
        }
        let settings = app.buttons["profileSettings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5)); XCTAssertTrue(settings.isHittable)
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
    }

    private func dismissKeyboard(in app: XCUIApplication) {
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        let table = app.tables["coachViewport"]
        var previous: [CGRect] = []
        var settled: [CGRect] = []
        let layout = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frames = [app.frame, table.frame, keyboard.frame]
            let onScreenKeyboard = frames[0].intersection(frames[2])
            guard keyboard.exists, table.isHittable, !onScreenKeyboard.isNull,
                  onScreenKeyboard.height >= 44, frames[2].minY > frames[0].minY,
                  frames[1].height > 24, frames[1].maxY <= frames[2].minY else {
                previous = []; return false
            }
            defer { previous = frames }
            guard frames == previous else { return false }
            settled = frames
            return true
        }, object: app)
        let layoutResult = XCTWaiter.wait(for: [layout], timeout: 5)
        XCTAssertEqual(layoutResult, .completed, "Keyboard and visible timeline must finish laying out before the drag")
        guard layoutResult == .completed, settled.count == 3 else { return }
        let appFrame = settled[0], tableFrame = settled[1], keyboardFrame = settled[2]
        let visible = tableFrame.intersection(CGRect(x: appFrame.minX, y: appFrame.minY,
            width: appFrame.width, height: keyboardFrame.minY - appFrame.minY))
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: visible.midX - appFrame.minX, dy: visible.maxY - 12 - appFrame.minY))
        let end = origin.withOffset(CGVector(dx: visible.midX - appFrame.minX,
            dy: min(appFrame.maxY, keyboardFrame.maxY) - 4 - appFrame.minY))
        start.press(forDuration: 0.05, thenDragTo: end)
        // UIKit can retain an offscreen keyboard accessibility element after dismissal.
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"),
            object: app.tabBars.buttons["Diary"])
        let result = XCTWaiter.wait(for: [ready], timeout: 5)
        if result != .completed {
            let base = FileManager.default.temporaryDirectory.appendingPathComponent("navigation-keyboard-" + UUID().uuidString)
            do {
                try app.screenshot().pngRepresentation.write(to: base.appendingPathExtension("png"))
                try app.debugDescription.write(to: base.appendingPathExtension("txt"), atomically: true, encoding: .utf8)
                print("NAVIGATION_FAILURE_PATH " + base.path)
            } catch { XCTFail("Could not preserve navigation failure evidence: \(error)") }
        }
        XCTAssertEqual(result, .completed)
    }
}
